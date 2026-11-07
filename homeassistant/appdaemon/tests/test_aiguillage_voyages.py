"""Tests hors Home Assistant d'`aiguillage_voyages` (P9-W, billets de train). L'IA et HA sont simulés."""

from datetime import datetime
import json
from pathlib import Path
import sqlite3
import sys
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import aiguillage_courrier as c  # noqa: E402
import aiguillage_voyages as v  # noqa: E402

MAINTENANT = datetime(2026, 11, 7, 10, 0, tzinfo=c.PARIS)


def trajet(date="2026-11-20", hd="08:00", ha="10:02", gd="Paris Gare de Lyon", ga="Lyon Part-Dieu",
           train="TGV INOUI 6611", voiture="12", place="45", date_arrivee=""):
    return {"date": date, "heure_depart": hd, "date_arrivee": date_arrivee, "heure_arrivee": ha, "gare_depart": gd,
            "gare_arrivee": ga, "train": train, "voiture": voiture, "place": place}


ALLER = trajet()
RETOUR = trajet(date="2026-11-23", hd="18:04", ha="20:00", gd="Lyon Part-Dieu", ga="Paris Gare de Lyon",
                train="TGV INOUI 6640", voiture="3", place="61")


def reponse(trajets, reference="ABC123", destination="Lyon", est_billet=True, annulation=False):
    texte = json.dumps({"est_billet": est_billet, "annulation": annulation, "destination": destination,
                        "reference": reference, "trajets": trajets})
    return SimpleNamespace(stop_reason="end_turn", content=[SimpleNamespace(type="text", text=texte)],
                           usage={"input_tokens": 3000, "output_tokens": 300})


class IA:
    def __init__(self, *reponses):
        self.reponses, self.appels = list(reponses), []

    @property
    def messages(self):
        return self

    def create(self, **kwargs):
        self.appels.append(kwargs)
        return self.reponses.pop(0)


class HA:
    def __init__(self):
        self.enr, self.fichiers, self.pieces_lues = {}, {}, []

    def lire(self, cle):
        return self.enr.get(cle)

    def ecrire(self, cle, valeur, version):
        actuel = self.enr.get(cle)
        if (actuel["version"] if actuel else 0) != version:
            return "conflit"
        self.enr[cle] = {"valeur": valeur, "version": version + 1, "supprime": False}
        return "ok"

    def piece(self, message_id, piece):
        self.pieces_lues.append((message_id, piece))
        return b"%PDF-1.7 billet"

    def deposer(self, nom, type_, octets):
        ident = f"sha-{len(self.fichiers)}"
        self.fichiers[ident] = (nom, type_, octets)
        return ident

    def taches(self):
        return [e["valeur"] for e in self.enr.values()]

    def rdv(self):
        return sorted((t for t in self.taches() if t["notes"].endswith(v.LIGNE_RDV)), key=lambda t: t["jour"])

    def reperes(self):
        return [t for t in self.taches() if t["notes"].endswith(v.LIGNE_INFO)]


def mail(ident="m1", de="noreply@sncf-connect.com", nom="SNCF Connect", sujet="Votre e-billet pour Lyon"):
    return {"id": ident, "fil": f"fil-{ident}", "de": de, "nom": nom, "sujet": sujet, "extrait": "",
            "date": "2026-11-07T09:00:00+00:00"}


PDF = {"partie": "2", "nom": "e-billet.pdf", "type": "application/pdf", "taille": 120_000, "piece": "att-1"}
LOGO = {"partie": "3", "nom": "logo.png", "type": "image/png", "taille": 4_000, "piece": "att-2"}


def base():
    db = sqlite3.connect(":memory:")
    db.row_factory = sqlite3.Row
    return db


# MARK: - Filtre

def test_candidat_par_domaine_ou_par_objet():
    assert v.candidat(mail())
    assert v.candidat(mail(de="confirmation@info.trainline.com", sujet="Vos billets"))
    assert v.candidat(mail(de="ami@exemple.fr", sujet="Votre réservation", nom="x") | {"extrait": "TGV 6611 voiture 4"})
    assert not v.candidat(mail(de="ami@exemple.fr", sujet="Dîner samedi ?"))
    assert not v.candidat(mail(de="promo@boutique.fr", sujet="Confirmation de commande") | {"extrait": "Vos chaussures"})


def test_ville_de_la_gare():
    assert v.ville("Paris Gare de Lyon") == "paris"
    assert v.ville("Aix-en-Provence TGV") == "aix"
    assert v.ville("Évry") == "evry"


# MARK: - Nettoyage de la réponse

def test_nettoyer_garde_les_trajets_valides_et_les_ordonne():
    brut = {"est_billet": True, "annulation": False, "destination": " Lyon ", "reference": "abc123",
            "trajets": [RETOUR, ALLER, trajet(date="20/11/2026"), trajet(gd=""), trajet(hd="8h", date="2026-11-21")]}
    e = v.nettoyer(brut)
    assert e["reference"] == "ABC123" and e["destination"] == "Lyon"
    assert [t["date"] for t in e["trajets"]] == ["2026-11-20", "2026-11-21", "2026-11-23"]
    assert e["trajets"][1]["heure_depart"] == ""            # heure mal formée effacée
    assert e["trajets"][0]["date_arrivee"] == "2026-11-20"  # arrivée le même jour par défaut


def test_nettoyer_refuse_ce_qui_n_est_pas_un_billet():
    assert v.nettoyer({"est_billet": False, "trajets": [ALLER]}) is None
    assert v.nettoyer({"est_billet": True, "trajets": []}) is None
    assert v.nettoyer("pas un objet") is None


def test_duree_du_trajet():
    assert v.duree(ALLER | {"date_arrivee": "2026-11-20"}) == 122
    assert v.duree(trajet(hd="22:30", ha="07:10", date_arrivee="2026-11-21")) == 520   # train de nuit
    assert v.duree(trajet(hd="08:00", ha="")) is None
    assert v.duree(trajet(hd="08:00", ha="07:00")) is None


# MARK: - Un mail aller-retour

def test_aller_retour_dans_un_mail():
    ha, db = HA(), base()
    ia = IA(reponse([ALLER, RETOUR]))
    r, _ = v.traiter(mail(), "texte long", [PDF, LOGO], ia, db, ha, MAINTENANT, journal=lambda t: None)
    assert r["rendez_vous"] == 2 and r["repere"] == "créé"
    aller, retour = ha.rdv()
    assert aller["titre"] == "Train aller Paris Gare de Lyon → Lyon Part-Dieu"
    assert (aller["jour"], aller["heure"], aller["duree"]) == ("2026-11-20", "08:00", 122)
    assert retour["titre"] == "Train retour Lyon Part-Dieu → Paris Gare de Lyon"
    assert aller["lieu"] == {"nom": "Paris Gare de Lyon", "adresse": "Paris Gare de Lyon", "source": "courrier"}
    lignes = aller["notes"].split("\n")
    assert lignes[0] == "TGV INOUI 6611 · voiture 12 · place 45"
    assert "Arrivée à 10:02 · Lyon Part-Dieu" in lignes and "Dossier ABC123" in lignes
    assert "📍 Paris Gare de Lyon" in lignes and "📎 1 pièce jointe" in lignes and lignes[-1] == v.LIGNE_RDV
    # Le billet PDF est joint aux deux rendez-vous, déposé une seule fois ; le logo est ignoré.
    assert len(ha.fichiers) == 1 and ha.pieces_lues == [("m1", "att-1")]
    assert aller["pieces"] == retour["pieces"] and aller["pieces"][0]["source"] == "courrier"
    (repere,) = ha.reperes()
    assert repere["titre"] == "En voyage à Lyon"
    assert (repere["jour"], repere["fin"]) == ("2026-11-20", "2026-11-23")
    assert "heure" not in repere and repere["notes"].split("\n")[0] == "Du 20/11 au 23/11"
    # Texte complet et noms des pièces envoyés à l'IA.
    contenu = ia.appels[0]["messages"][0]["content"]
    assert "texte long" in contenu and "e-billet.pdf" in contenu


def test_meme_mail_relu_ne_cree_pas_de_doublon():
    ha, db = HA(), base()
    v.traiter(mail(), "", [], IA(reponse([ALLER, RETOUR])), db, ha, MAINTENANT, journal=lambda t: None)
    r, _ = v.traiter(mail("m2", sujet="Votre voyage approche"), "", [], IA(reponse([ALLER, RETOUR])), db, ha,
                     MAINTENANT, journal=lambda t: None)
    assert r["rendez_vous"] == 0 and r["repere"] == "inchangé"
    assert len(ha.rdv()) == 2 and len(ha.reperes()) == 1


# MARK: - Aller et retour dans deux mails

def test_retour_recu_apres_l_aller_complete_le_voyage():
    ha, db = HA(), base()
    v.traiter(mail(), "", [], IA(reponse([ALLER], reference="AAA111")), db, ha, MAINTENANT, journal=lambda t: None)
    (repere,) = ha.reperes()
    assert repere["jour"] == "2026-11-20" and "fin" not in repere
    # Alexandre corrige le titre du repère : sa correction est gardée.
    cle = next(k for k, e in ha.enr.items() if e["valeur"] is repere)
    ha.enr[cle]["valeur"] = dict(repere, titre="Week-end à Lyon")
    r, _ = v.traiter(mail("m2"), "", [PDF], IA(reponse([RETOUR], reference="BBB222", destination="Paris")), db, ha,
                     MAINTENANT, journal=lambda t: None)
    assert r["rendez_vous"] == 1 and r["repere"] == "élargi"
    (repere,) = ha.reperes()
    assert repere["titre"] == "Week-end à Lyon" and (repere["jour"], repere["fin"]) == ("2026-11-20", "2026-11-23")
    assert repere["notes"].startswith("Du 20/11 au 23/11\n")
    aller, retour = ha.rdv()
    assert retour["titre"].startswith("Train retour ") and "pieces" in retour and "pieces" not in aller


def test_un_autre_voyage_reste_separe():
    ha, db = HA(), base()
    v.traiter(mail(), "", [], IA(reponse([ALLER])), db, ha, MAINTENANT, journal=lambda t: None)
    bordeaux = trajet(date="2026-12-05", gd="Paris Montparnasse", ga="Bordeaux Saint-Jean")
    v.traiter(mail("m2"), "", [], IA(reponse([bordeaux], reference="ZZZ", destination="Bordeaux")), db, ha, MAINTENANT,
              journal=lambda t: None)
    assert sorted(r["titre"] for r in ha.reperes()) == ["En voyage à Bordeaux", "En voyage à Lyon"]


def test_retour_trop_tardif_n_est_pas_rattache():
    ha, db = HA(), base()
    v.traiter(mail(), "", [], IA(reponse([ALLER], reference="")), db, ha, MAINTENANT, journal=lambda t: None)
    tard = RETOUR | {"date": "2027-02-01", "date_arrivee": ""}
    v.traiter(mail("m2"), "", [], IA(reponse([tard], reference="", destination="Paris")), db, ha, MAINTENANT,
              journal=lambda t: None)
    assert len(ha.reperes()) == 2


def test_repere_supprime_ou_fait_n_est_plus_touche():
    ha, db = HA(), base()
    v.traiter(mail(), "", [], IA(reponse([ALLER])), db, ha, MAINTENANT, journal=lambda t: None)
    cle = next(k for k, e in ha.enr.items() if e["valeur"]["notes"].endswith(v.LIGNE_INFO))
    ha.enr[cle]["supprime"] = True
    r, _ = v.traiter(mail("m2"), "", [], IA(reponse([RETOUR])), db, ha, MAINTENANT, journal=lambda t: None)
    assert r["repere"] == "supprimé, gardé tel quel"
    assert v.elargir_repere({"jour": "2026-11-20", "fait": True}, {"debut": "2026-11-20", "fin": "2026-11-23"}) is None


def test_rendez_vous_corrige_a_la_main_n_est_pas_ecrase():
    ha, db = HA(), base()
    v.traiter(mail(), "", [], IA(reponse([ALLER])), db, ha, MAINTENANT, journal=lambda t: None)
    cle = v.cle_trajet(v.nettoyer({"est_billet": True, "trajets": [ALLER]})["trajets"][0])
    ha.enr[cle]["valeur"]["titre"] = "Train pour Lyon (corrigé)"
    v.traiter(mail("m2"), "", [], IA(reponse([ALLER])), db, ha, MAINTENANT, journal=lambda t: None)
    assert ha.enr[cle]["valeur"]["titre"] == "Train pour Lyon (corrigé)"


# MARK: - Rien d'écrit

def test_annulation_et_publicite_n_ecrivent_rien():
    ha, db = HA(), base()
    r, _ = v.traiter(mail(), "", [], IA(reponse([ALLER], annulation=True)), db, ha, MAINTENANT, journal=lambda t: None)
    assert r["annulation"] and ha.enr == {}
    r, _ = v.traiter(mail(), "", [], IA(reponse([], est_billet=False)), db, ha, MAINTENANT, journal=lambda t: None)
    assert r is None and ha.enr == {}


def test_billet_illisible_le_rendez_vous_est_cree_quand_meme():
    class HAPanne(HA):
        def piece(self, message_id, piece):
            raise RuntimeError("Gmail")
    ha, db, journal = HAPanne(), base(), []
    r, _ = v.traiter(mail(), "", [PDF], IA(reponse([ALLER])), db, ha, MAINTENANT, journal=journal.append)
    assert r["rendez_vous"] == 1 and "pieces" not in ha.rdv()[0]
    assert any("non joint" in t for t in journal)


def test_pieces_du_billet():
    gros = PDF | {"taille": 20 * 1024 * 1024}
    wallet = {"partie": "4", "nom": "Billet.pkpass", "type": "application/octet-stream", "taille": 50_000, "piece": "p"}
    assert v.pieces_billet([LOGO, gros, PDF, wallet, PDF]) == [PDF, wallet]


# MARK: - Branchement dans la relève du courrier

def test_trier_appelle_voyages_et_survit_a_une_erreur(tmp_path):
    db = c.ouvrir_base(str(tmp_path / "c.sqlite"))
    brut = {"id": "m1", "threadId": "f1", "labelIds": ["INBOX", "UNREAD"], "snippet": "", "internalDate": "0",
            "payload": {"headers": [{"name": "From", "value": "SNCF <noreply@sncf-connect.com>"},
                                    {"name": "Subject", "value": "Votre e-billet"}]}}
    gmail = SimpleNamespace(message=lambda i: brut, fil=lambda f: {"messages": []})
    vus = []

    def voyages(f, b):
        vus.append((f["id"], b is brut))
        raise RuntimeError("panne")
    journal = []
    n = c.trier(gmail, db, None, ["m1"], {}, 15, MAINTENANT, {}, journal.append, verifier_fil=False, voyages=voyages)
    assert n == 1 and vus == [("m1", True)] and any("billet de train" in t for t in journal)
