"""Tests hors Home Assistant de `aiguillage_agent` (P9-N, lot N5). Aucun appel réseau : faux client Claude, base
SQLite de test, faux service `donnees_apps`."""

from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import sqlite3
import sys
from types import SimpleNamespace

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import aiguillage_agent as a  # noqa: E402
import aiguillage_courrier as c  # noqa: E402

MAINTENANT = datetime(2026, 10, 27, 14, 5, tzinfo=c.PARIS)


def _ms(d):
    return int(d.timestamp() * 1000)


@pytest.fixture
def base(tmp_path):
    chemin = tmp_path / "courrier.sqlite"
    db = c.ouvrir_base(str(chemin))
    lignes = [
        ("m1", "f1", MAINTENANT - timedelta(hours=2), "erika@seven-portage.fr", "Erika Martin", "Facture d'octobre",
         "a_traiter", "Erika (Seven Portage) envoie la facture d'octobre.", "Valider la facture", "2026-10-30",
         "Bonjour Alexandre, voici la facture. " + "x" * 3000),
        ("m2", "f2", MAINTENANT - timedelta(days=1), "noreply@enedis.fr", "Enedis", "Coupure programmée",
         "a_traiter", "Coupure de courant à Alfortville.", None, None, "Une coupure aura lieu."),
        ("m3", "f3", MAINTENANT - timedelta(days=3), "news@lemonde.fr", "Le Monde", "La lettre du soir",
         "lettre", "Lettre d'info du Monde.", None, None, "Édito"),
        ("m4", "f4", MAINTENANT - timedelta(days=20), "marie@exemple.fr", "Marie Dupont", "Dîner réglé",
         "fait", "Marie confirme le dîner.", None, None, "C'est noté, à samedi"),
    ]
    for ident, fil, quand, de, nom, sujet, cat, resume, demande, echeance, extrait in lignes:
        db.execute(
            "INSERT INTO messages (id, fil, date, date_ms, de, nom, a, sujet, extrait, libelles, categorie, "
            "categorie_tri, source, resume, demande, echeance, recu_le) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (ident, fil, quand.isoformat(), _ms(quand), de, nom, "alexandre.fau@gmail.com", sujet, extrait[:1500],
             "[]", cat, cat if cat != "fait" else "a_traiter", "ia", resume, demande, echeance, quand.isoformat()))
    db.commit()
    db.close()
    return str(chemin)


class FauxService:
    def __init__(self, statut="ok"):
        self.appels, self.statut = [], statut

    def __call__(self, domaine, action, data):
        self.appels.append((domaine, action, data))
        return {"statut": self.statut}


def outils(base, questions=("crée une tâche et reporte à demain",), service=None):
    return a.Outils(base, service or FauxService(), MAINTENANT, questions=list(questions))


# MARK: - Outils

def test_base_en_lecture_seule(base):
    db = a.ouvrir_lecture(base)
    try:
        assert db.execute("SELECT count(*) FROM messages").fetchone()[0] == 4
        with pytest.raises(sqlite3.OperationalError):
            db.execute("UPDATE messages SET categorie = 'fait'")
        with pytest.raises(sqlite3.OperationalError):
            db.execute("DELETE FROM messages")
    finally:
        db.close()


def test_chercher_mails_sans_extrait(base):
    o = outils(base)
    texte, erreur = o.executer("chercher_mails", {"requete": None, "expediteur": None, "categorie": "a_traiter",
                                                  "depuis_jours": None, "limite": None})
    assert not erreur
    res = json.loads(texte)
    assert [m["id"] for m in res["mails"]] == ["m1", "m2"]          # plus récent d'abord
    m1 = res["mails"][0]
    assert set(m1) == {"id", "date", "de", "adresse", "sujet", "categorie", "resume", "demande", "echeance", "fait"}
    assert "extrait" not in m1 and m1["date"] == "2026-10-27 12:05" and m1["fait"] is False


def test_chercher_mails_criteres(base):
    o = outils(base)

    def ids(**k):
        entree = {"requete": None, "expediteur": None, "categorie": None, "depuis_jours": None, "limite": None} | k
        return [m["id"] for m in json.loads(o.executer("chercher_mails", entree)[0])["mails"]]

    assert ids(requete="FACTURE octobre") == ["m1"]
    assert ids(requete="diner") == ["m4"]                           # sans accents
    assert ids(requete="alfortville coupure") == ["m2"]
    assert ids(expediteur="seven-portage") == ["m1"]
    assert ids(expediteur="enédis") == ["m2"]
    assert ids(depuis_jours=2) == ["m1", "m2"]
    assert ids(categorie="fait") == ["m4"]
    assert ids(limite=2) == ["m1", "m2"]
    assert len(ids(limite=500)) == 4                                # borné à 10
    assert ids(requete="introuvable") == []


def test_lire_mail_avec_extrait_borne(base):
    o = outils(base)
    texte, erreur = o.executer("lire_mail", {"id": "m1"})
    m = json.loads(texte)
    assert not erreur and m["extrait"].startswith("Bonjour Alexandre") and len(m["extrait"]) == 1500
    assert m["a"] == "alexandre.fau@gmail.com"


def test_id_inconnu_refuse(base):
    o = outils(base)
    for nom, entree in (("lire_mail", {"id": "zz"}), ("creer_tache", {"id": "zz", "titre": None, "jour": None}),
                        ("reporter", {"id": "zz", "quand": "demain_matin"})):
        texte, erreur = o.executer(nom, entree)
        assert erreur and "inconnu" in texte
    assert o.executer("archiver", {"id": "m1"})[1] is True          # aucun autre outil


def test_creer_tache_meme_cle_que_l_app(base):
    service = FauxService()
    o = outils(base, service=service)
    texte, erreur = o.executer("creer_tache", {"id": "m1", "titre": None, "jour": None})
    assert not erreur and json.loads(texte)["tache"] == "créée"
    domaine, action, data = service.appels[0]
    attendu_cle, attendu = c.tache_du_mail(a.mail(a.ouvrir_lecture(base), "m1"), MAINTENANT)
    assert (domaine, action) == ("donnees_apps", "ecrire")
    assert data["espace"] == "aiguillage" and data["cle"] == attendu_cle and data["version_attendue"] == 0
    assert data["valeur"] == attendu and data["modifie_par"] == "agent"
    assert attendu_cle == str(__import__("uuid").uuid5(c.NAMESPACE_TACHES, "courrier:m1"))
    # Titre et jour donnés par Alexandre ; jour illisible refusé.
    o.executer("creer_tache", {"id": "m1", "titre": "Payer Erika", "jour": "2026-11-02"})
    assert service.appels[1][2]["valeur"]["titre"] == "Payer Erika"
    assert service.appels[1][2]["valeur"]["jour"] == "2026-11-02"
    assert o.executer("creer_tache", {"id": "m1", "titre": None, "jour": "lundi"})[1] is True


def test_creer_tache_deja_la_pas_d_ecrasement(base):
    o = outils(base, service=FauxService(statut="conflit"))
    texte, erreur = o.executer("creer_tache", {"id": "m1", "titre": None, "jour": None})
    assert not erreur and "déjà là" in json.loads(texte)["tache"]


def test_reporter_ecrit_plus_tard_comme_l_app(base):
    service = FauxService()
    o = outils(base, service=service)
    texte, erreur = o.executer("reporter", {"id": "m1", "quand": "demain_matin"})
    assert not erreur and json.loads(texte)["reporte_jusqua"] == "mercredi 28/10 à 09:00"
    _, _, data = service.appels[0]
    assert data["espace"] == "courrier" and data["cle"] == "plus_tard:m1"
    assert data["valeur"] == {"jusqua": "2026-10-28T09:00:00+01:00"}
    # Le NUC le relit comme un « Plus tard » de l'app.
    db = c.ouvrir_base(":memory:")
    db.execute("INSERT INTO messages (id, fil, date, date_ms, categorie, categorie_tri, source, recu_le) "
               "VALUES ('m1','f1','x',0,'a_traiter','a_traiter','ia','x')")
    assert c.appliquer_plus_tard(db, {"enregistrements": [{"cle": data["cle"], "valeur": data["valeur"]}]},
                                 MAINTENANT) == 1
    assert c.mis_de_cote(db, MAINTENANT) == {"m1"}
    # Ce soir (18 h), une date (9 h), une date et une heure.
    o.executer("reporter", {"id": "m1", "quand": "ce_soir"})
    assert service.appels[1][2]["valeur"]["jusqua"] == "2026-10-27T18:00:00+01:00"
    o.executer("reporter", {"id": "m1", "quand": "2026-11-03"})
    assert service.appels[2][2]["valeur"]["jusqua"] == "2026-11-03T09:00:00+01:00"
    o.executer("reporter", {"id": "m1", "quand": "2026-11-03T14:30"})
    assert service.appels[3][2]["valeur"]["jusqua"] == "2026-11-03T14:30:00+01:00"


def test_reporter_refus(base):
    o = outils(base)
    assert o.executer("reporter", {"id": "m3", "quand": "demain_matin"})[1] is True     # pas à traiter
    assert o.executer("reporter", {"id": "m1", "quand": "2026-10-01"})[1] is True       # passé
    assert o.executer("reporter", {"id": "m1", "quand": "bientôt"})[1] is True          # illisible
    tard = a.Outils(base, FauxService(), MAINTENANT.replace(hour=19), questions=["reporte"])
    texte, erreur = tard.executer("reporter", {"id": "m1", "quand": "ce_soir"})
    assert erreur and "18 h" in texte


def test_actions_seulement_si_demandees(base):
    service = FauxService()
    o = a.Outils(base, service, MAINTENANT, questions=["qu'est-ce que j'ai à traiter ?"])
    for nom, entree in (("creer_tache", {"id": "m1", "titre": None, "jour": None}),
                        ("reporter", {"id": "m1", "quand": "demain_matin"})):
        texte, erreur = o.executer(nom, entree)
        assert erreur and "pas demandé" in texte
    assert service.appels == []
    # La question précédente compte (« ? oui vas-y » après « ? fais-en une tâche »).
    o = a.Outils(base, service, MAINTENANT, questions=["oui vas-y", "fais-en une tâche"])
    assert o.executer("creer_tache", {"id": "m1", "titre": None, "jour": None})[1] is False


def test_date_du_jour(base):
    assert json.loads(outils(base).executer("date_du_jour", {})[0]) == {"date": "2026-10-27", "jour": "mardi",
                                                                         "heure": "14:05"}


def test_outils_stricts():
    assert a.NOMS_OUTILS == ("chercher_mails", "lire_mail", "creer_tache", "reporter", "date_du_jour")
    for o in a.OUTILS:
        schema = o["input_schema"]
        assert o["strict"] is True and schema["additionalProperties"] is False
        assert sorted(schema["required"]) == sorted(schema["properties"])


# MARK: - Boucle avec un faux client

def _usage(entree=1000, sortie=200, lecture=0, ecriture=0):
    return SimpleNamespace(input_tokens=entree, output_tokens=sortie, cache_read_input_tokens=lecture,
                           cache_creation_input_tokens=ecriture)


def _outil(ident, nom, entree):
    return SimpleNamespace(type="tool_use", id=ident, name=nom, input=entree)


def _texte(t):
    return SimpleNamespace(type="text", text=t)


class FauxClient:
    def __init__(self, reponses):
        self.reponses, self.requetes = list(reponses), []
        self.messages = self

    def create(self, **kw):
        self.requetes.append(json.loads(json.dumps(kw, default=lambda o: o.__dict__)))
        contenu, stop = self.reponses.pop(0)
        return SimpleNamespace(content=contenu, stop_reason=stop, usage=_usage())


def test_boucle_outils_puis_reponse(base):
    client = FauxClient([
        ([_outil("t1", "chercher_mails", {"requete": None, "expediteur": None, "categorie": "a_traiter",
                                          "depuis_jours": None, "limite": None})], "tool_use"),
        ([_texte("Deux mails à traiter :\n- **Erika** : facture")], "end_turn"),
    ])
    o = outils(base)
    memo = c.Memo("Fiches du mémo :\n- Seven Portage : société de portage")
    texte, cout, raison, tours = a.repondre(client, "qu'est-ce que j'ai à traiter ?", o, memo=memo,
                                            maintenant=MAINTENANT)
    assert raison is None and tours == 2 and texte.startswith("Deux mails")
    assert cout == pytest.approx(2 * (1000 * 2.0 + 200 * 10.0) / 1e6)
    assert o.appels == ["chercher_mails"]
    req = client.requetes[0]
    assert req["model"] == "claude-sonnet-5-5" and req["output_config"] == {"effort": "medium"}
    assert "thinking" not in req and "tool_choice" not in req
    # Système : consigne puis mémo, point de cache sur le mémo ; question datée.
    assert len(req["system"]) == 2 and "<memo>" in req["system"][1]["text"]
    assert req["system"][1]["cache_control"] == {"type": "ephemeral"} and "cache_control" not in req["system"][0]
    assert req["messages"][-1]["content"][0]["text"].startswith("[mardi 27/10/2026 14:05] qu'est-ce")
    # Second tour : résultat de l'outil, un seul point de cache mobile (sur le dernier message).
    req2 = client.requetes[1]
    resultat = req2["messages"][-1]["content"][0]
    assert resultat["type"] == "tool_result" and resultat["tool_use_id"] == "t1" and "is_error" not in resultat
    assert resultat["cache_control"] == {"type": "ephemeral"}
    assert all("cache_control" not in b for m in req2["messages"][:-1] if isinstance(m["content"], list)
               for b in m["content"])
    # Réponse pour Signal : sans gras, préfixée.
    assert a.mise_en_forme(texte) == "🤖 Deux mails à traiter :\n- Erika : facture"


def test_boucle_bornee(base):
    appel = ([_outil("t", "date_du_jour", {})], "tool_use")
    client = FauxClient([appel] * 20)
    texte, cout, raison, tours = a.repondre(client, "?", outils(base), maintenant=MAINTENANT, tours_max=8)
    assert texte is None and raison == "trop d'étapes" and tours == 8 and len(client.requetes) == 8
    assert a.echec(raison) == "🤖 ⚠️ Je n'ai pas pu répondre (trop d'étapes)."


def test_delai_total_borne(base):
    temps = iter([0, 0, 200])
    client = FauxClient([([_outil("t", "date_du_jour", {})], "tool_use")] * 5)
    texte, _, raison, tours = a.repondre(client, "?", outils(base), maintenant=MAINTENANT, delai=150,
                                         horloge=lambda: next(temps))
    assert texte is None and raison == "trop long" and tours == 1


def test_erreur_d_outil_renvoyee_au_modele(base):
    client = FauxClient([([_outil("t1", "lire_mail", {"id": "inconnu"})], "tool_use"),
                         ([_texte("Je ne trouve pas ce mail.")], "end_turn")])
    texte, _, raison, _ = a.repondre(client, "lis le mail", outils(base), maintenant=MAINTENANT)
    resultat = client.requetes[1]["messages"][-1]["content"][0]
    assert resultat["is_error"] is True and "inconnu" in resultat["content"] and texte == "Je ne trouve pas ce mail."


def test_refus_du_modele(base):
    client = FauxClient([([], "refusal")])
    assert a.repondre(client, "x", outils(base), maintenant=MAINTENANT)[2] == "refus du modèle"


# MARK: - Fil, budget, mise en forme, journal

def test_fil_de_conversation():
    vieux = (MAINTENANT - timedelta(minutes=45)).astimezone(timezone.utc).isoformat()
    recent = (MAINTENANT - timedelta(minutes=5)).astimezone(timezone.utc).isoformat()
    fil = [{"question": "vieux", "reponse": "r", "quand": vieux}] + \
          [{"question": f"q{i}", "reponse": f"r{i}", "quand": recent} for i in range(8)]
    gardes = a.fil_utile(fil, MAINTENANT)
    assert [e["question"] for e in gardes] == ["q2", "q3", "q4", "q5", "q6", "q7"]
    fil2 = a.ajouter_au_fil(gardes, "et celui d'hier ?", "Enedis…", MAINTENANT)
    assert len(fil2) == 6 and fil2[-1]["question"] == "et celui d'hier ?"
    msgs = a.messages_initiaux(fil2[-2:], "et l'autre ?", MAINTENANT)
    assert [m["role"] for m in msgs] == ["user", "assistant", "user", "assistant", "user"]
    assert msgs[1]["content"] == "r7" and msgs[-1]["content"].endswith("et l'autre ?")
    # 30 minutes plus tard, le fil est vide.
    assert a.fil_utile(fil2, MAINTENANT + timedelta(minutes=31)) == []


def test_budget():
    etat = {"mois": "2026-10", "cout_mois": 4.99}
    assert not a.budget_atteint(etat, 5, MAINTENANT)
    etat = c.compter(etat, 0.02, MAINTENANT)
    assert a.budget_atteint(etat, 5, MAINTENANT)
    assert "Budget du mois atteint (5.01 $ sur 5.00 $)" in a.message_budget(etat, 5)
    # Nouveau mois : compteur remis à zéro.
    assert not a.budget_atteint(etat, 5, MAINTENANT + timedelta(days=6))
    # Prix de Sonnet 5.5 avec le cache (lecture 0,20 $/M, écriture 2,50 $/M).
    assert c.cout(_usage(100, 300, 5000, 2000), "claude-sonnet-5-5") == pytest.approx(
        (100 * 2 + 300 * 10 + 5000 * 0.2 + 2000 * 2.5) / 1e6)


def test_troncature():
    texte = a.mise_en_forme("## Titre\n" + "mot " * 1000)
    assert len(texte) == 1500 and texte.startswith("🤖 Titre") and texte.endswith("…")
    assert a.mise_en_forme("court") == "🤖 court"


def test_journal_sans_contenu():
    ligne = a.journal("qu'est-ce que j'ai à traiter en ce moment, et surtout pour la facture d'Erika ???",
                      ["chercher_mails", "lire_mail"], 0.0123, 3, {"cout_mois": 0.5})
    question = ligne.split("« ")[1].split(" »")[0]
    assert len(question) == 60 and question.endswith("…") and "Erika" not in ligne
    assert "chercher_mails, lire_mail" in ligne and "0.0123 $" in ligne and "0.50 $" in ligne
    assert "échec : trop long" in a.journal("x", [], 0, 0, {}, "trop long")
