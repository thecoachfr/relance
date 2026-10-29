"""Tests hors Home Assistant de `aiguillage_drive` (pièces jointes vers Google Drive depuis Courrier, 29/10/2026).
Aucun appel réseau : faux Drive, faux Gmail, faux HTTP. Garde-fous : aucune écriture dans Drive sans confirmation
qui corresponde à la proposition du NUC ; jamais le contenu d'une pièce jointe dans un résultat, un état ou le
journal ; aucun fichier temporaire ; client Drive limité à lister, lire des métadonnées et créer."""

import base64
from datetime import timedelta, timezone
import inspect
import json
from pathlib import Path
import re
import sys
from types import SimpleNamespace

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import aiguillage_agent as a  # noqa: E402
import aiguillage_assistant as s  # noqa: E402
import aiguillage_courrier as c  # noqa: E402
import aiguillage_drive as d  # noqa: E402
from test_aiguillage_agent import MAINTENANT, FauxClient, FauxService, _outil, _texte, base  # noqa: E402,F401

SECRET = b"%PDF-1.7 CONTENU SECRET DE LA FACTURE"

MESSAGE = {"id": "m1", "threadId": "f1", "payload": {
    "headers": [{"name": "Subject", "value": "Votre facture EDF d'octobre"}],
    "partId": "", "mimeType": "multipart/mixed", "body": {"size": 0}, "parts": [
        {"partId": "0", "mimeType": "multipart/alternative", "filename": "", "body": {"size": 0}, "parts": [
            {"partId": "0.0", "mimeType": "text/plain", "filename": "", "body": {"size": 120}},
            {"partId": "0.1", "mimeType": "image/png", "filename": "image001.png",
             "body": {"attachmentId": "att-logo", "size": 4000}}]},
        {"partId": "1", "mimeType": "application/pdf", "filename": "Facture_10-2026.pdf",
         "body": {"attachmentId": "att-a", "size": len(SECRET)}},
        {"partId": "2", "mimeType": "application/pdf", "filename": "Conditions.pdf",
         "body": {"attachmentId": "att-b", "size": 2000}},
        {"partId": "3", "mimeType": "application/pdf", "filename": "sans-id.pdf", "body": {"size": 10}},
    ]}}


class FauxGmail:
    def __init__(self, message=MESSAGE):
        self._message, self.lus = message, []

    def message(self, ident):
        if ident != self._message["id"]:
            raise c.Introuvable(ident)
        # L'id de pièce jointe de Gmail change d'une lecture à l'autre : l'exécution doit retrouver la partie.
        m = json.loads(json.dumps(self._message))
        for p in m["payload"]["parts"]:
            if p["body"].get("attachmentId"):
                p["body"]["attachmentId"] += "-relu"
        return m

    def contenu(self, ident, piece):
        self.lus.append(piece)
        return SECRET


class FauxDrive:
    DOSSIERS = {"d-fact": "Factures", "d-edf": "Factures/EDF", "d-trav": "Travaux"}

    def __init__(self, autorise=True):
        self._autorise = autorise
        self.ecritures = []           # (geste, …) : tout ce qui écrirait dans Drive
        self.enfants = {("root-id", "Travaux"): "d-trav"}

    def autorise(self):
        return self._autorise

    def racine(self):
        return "root-id"

    def dossiers(self, mots=None):
        return [{"id": k, "chemin": v} for k, v in self.DOSSIERS.items()
                if not mots or any(m.lower() in v.lower() for m in mots)]

    def dossier(self, ident):
        return {"id": ident, "chemin": self.DOSSIERS[ident]} if ident in self.DOSSIERS else None

    def enfant(self, parent, nom):
        return self.enfants.get((parent, nom))

    def creer_dossier(self, nom, parent):
        ident = f"nouveau-{nom}"
        self.ecritures.append(("dossier", nom, parent))
        self.enfants[(parent, nom)] = ident
        return ident

    def deposer(self, nom, type_, donnees, parent):
        self.ecritures.append(("fichier", nom, parent, len(donnees)))
        return {"id": f"f-{nom}", "lien": f"https://drive.google.com/file/d/f-{nom}/view"}


def outils(drive=None, gmail=None, base_=None):
    o = a.Outils(base_ or ":memory:", FauxService(), MAINTENANT, questions=["Enregistre la facture dans mon Drive"])
    return s.OutilsCourrier(o, drive=(lambda: drive) if drive else None, pieces=(lambda: gmail) if gmail else None)


def proposer(o, **champs):
    entree = {"id": "m1", "dossier_id": "d-edf", "nouveau_chemin": "", "fichiers": [], "candidats": ["d-fact"],
              **champs}
    return o.executer("proposer_enregistrement_drive", entree)


QUAND = MAINTENANT.astimezone(timezone.utc).isoformat()


def confirmation(bloc, **champs):
    return {"v": 1, "proposition": bloc["id"], "fichiers": [f["partie"] for f in bloc["fichiers"]],
            "dossier": {"id": bloc["dossier"]["id"], "chemin": bloc["dossier"]["chemin"]}, "appareil": "iPhone",
            "quand": QUAND, **champs}


# MARK: - Pièces jointes et proposition

def test_pieces_jointes_sans_contenu():
    p = d.pieces_jointes(MESSAGE)
    assert [x["nom"] for x in p] == ["image001.png", "Facture_10-2026.pdf", "Conditions.pdf"]   # sans id : ignoré
    assert p[1] == {"partie": "1", "nom": "Facture_10-2026.pdf", "type": "application/pdf", "taille": len(SECRET),
                    "piece": "att-a"}
    assert d.objet_du_message(MESSAGE) == "Votre facture EDF d'octobre"
    # La lecture du message ne demande que les métadonnées des parties (jamais `data`).
    assert "data" not in d.CHAMPS_PARTIES and "attachmentId" in d.CHAMPS_PARTIES


def test_sans_accord_drive_rien_n_est_propose():
    drive, gmail = FauxDrive(autorise=False), FauxGmail()
    o = outils(drive, gmail)
    texte, erreur = o.executer("chercher_dossiers_drive", {"mots": ["Factures"]})
    assert erreur and "pas autorisé" in texte and "accord" in texte
    texte, erreur = proposer(o)
    assert erreur and o.drive.blocs == [] and drive.ecritures == [] and gmail.lus == []
    # Sans autorisation Google du tout : pareil.
    texte, erreur = outils().executer("chercher_dossiers_drive", {"mots": []})
    assert erreur and "indisponible" in texte


def test_proposition_ne_touche_pas_a_drive():
    drive, gmail = FauxDrive(), FauxGmail()
    o = outils(drive, gmail)
    texte, erreur = o.executer("chercher_dossiers_drive", {"mots": ["EDF"]})
    assert not erreur and json.loads(texte)["dossiers"] == [{"id": "d-edf", "chemin": "Factures/EDF"}]
    texte, erreur = proposer(o)
    assert not erreur and "RIEN n'est enregistré" in json.loads(texte)["proposition"]
    bloc = o.drive.blocs[0]
    # Le logo de signature est écarté d'office ; ni contenu ni id de pièce jointe dans le bloc.
    assert [f["nom"] for f in bloc["fichiers"]] == ["Facture_10-2026.pdf", "Conditions.pdf"]
    assert bloc["dossier"] == {"id": "d-edf", "chemin": "Factures/EDF", "nouveau": False}
    assert bloc["candidats"] == [{"id": "d-fact", "chemin": "Factures", "nouveau": False}]
    assert bloc["objet"] == "Votre facture EDF d'octobre" and bloc["mail"] == "m1"
    assert "piece" not in json.dumps(bloc) and "att-" not in json.dumps(bloc)
    assert drive.ecritures == [] and gmail.lus == []        # aucune écriture Drive, aucun contenu lu
    v = d.valeur_proposition(bloc, MAINTENANT)
    assert v["v"] == 1 and v["fichiers"] == bloc["fichiers"] and "SECRET" not in json.dumps(v)


def test_proposition_choix_et_erreurs():
    drive, gmail = FauxDrive(), FauxGmail()
    o = outils(drive, gmail)
    _, erreur = proposer(o, fichiers=["facture_10-2026.PDF"], dossier_id="", nouveau_chemin=" Travaux / Alfortville/")
    assert not erreur
    assert [f["nom"] for f in o.drive.blocs[0]["fichiers"]] == ["Facture_10-2026.pdf"]
    assert o.drive.blocs[0]["dossier"] == {"id": None, "chemin": "Travaux/Alfortville", "nouveau": True}
    for champs, attendu in [({"dossier_id": ""}, "OU"), ({"nouveau_chemin": "X"}, "OU"),
                            ({"dossier_id": "inconnu"}, "dossier inconnu"), ({"id": "absent"}, "mail inconnu"),
                            ({"fichiers": ["autre.pdf"]}, "aucun de ces noms"),
                            ({"dossier_id": "", "nouveau_chemin": "a/../b"}, "chemin illisible")]:
        texte, erreur = proposer(o, **champs)
        assert erreur and attendu in texte, (champs, texte)
    assert len(o.drive.blocs) == 1 and drive.ecritures == []


def test_bloc_drive_dans_la_reponse_avec_le_mail_cite(base):
    drive, gmail = FauxDrive(), FauxGmail()
    o = outils(drive, gmail, base)
    o.vus["m1"] = {"id": "m1", "fil": "f1", "de": "EDF", "adresse": "edf@edf.fr", "objet": "Facture", "date": None,
                   "resume": None}
    proposer(o)
    blocs = s.blocs_reponse("Je te propose de les enregistrer dans Factures/EDF.", o)
    assert [b["type"] for b in blocs] == ["texte", "mails", "drive"]


# MARK: - Confirmation et exécution

def test_aucune_ecriture_sans_confirmation_correspondante():
    drive, gmail = FauxDrive(), FauxGmail()
    o = outils(drive, gmail)
    proposer(o)
    bloc = o.drive.blocs[0]
    prop = d.valeur_proposition(bloc, MAINTENANT)
    refus = [
        (None, confirmation(bloc)),                                         # pas de proposition du NUC
        (prop, None),                                                       # pas de confirmation
        (prop, confirmation(bloc, fichiers=["1", "9"])),                    # fichier non proposé
        (prop, confirmation(bloc, fichiers=[])),                            # rien de coché
        (prop, confirmation(bloc, dossier={"id": "d-trav"})),               # dossier jamais proposé
        (prop, confirmation(bloc, quand=(MAINTENANT - timedelta(minutes=11)).isoformat())),   # trop ancienne
        ({**prop, "propose_le": (MAINTENANT - timedelta(days=8)).isoformat()}, confirmation(bloc)),
        (prop, confirmation(bloc, dossier={"id": None, "chemin": "../.."})),
    ]
    for proposition, conf in refus:
        with pytest.raises(d.Refus):
            d.plan(proposition, conf, MAINTENANT)
    assert drive.ecritures == [] and gmail.lus == []
    # Moins de fichiers, un candidat proposé, ou un chemin tapé par Alexandre : accepté.
    p = d.plan(prop, confirmation(bloc, fichiers=["2"], dossier={"id": "d-fact"}), MAINTENANT)
    assert [f["nom"] for f in p["fichiers"]] == ["Conditions.pdf"] and p["dossier"]["chemin"] == "Factures"
    p = d.plan(prop, confirmation(bloc, dossier={"id": None, "chemin": "Impôts/2026"}), MAINTENANT)
    assert p["dossier"] == {"id": None, "chemin": "Impôts/2026", "nouveau": True}


def test_execution_dossier_existant_et_journal_sans_contenu():
    drive, gmail = FauxDrive(), FauxGmail()
    o = outils(drive, gmail)
    proposer(o)
    bloc = o.drive.blocs[0]
    p = d.plan(d.valeur_proposition(bloc, MAINTENANT), confirmation(bloc, fichiers=["1"]), MAINTENANT)
    r = d.executer(p, drive, gmail)
    assert gmail.lus == ["att-a-relu"]       # partie retrouvée par son numéro et son nom, id relu
    assert drive.ecritures == [("fichier", "Facture_10-2026.pdf", "d-edf", len(SECRET))]
    assert r["dossier"]["lien"] == "https://drive.google.com/drive/folders/d-edf" and r["crees"] == 0
    assert r["fichiers"][0]["lien"].startswith("https://drive.google.com/file/d/")
    v = d.valeur_resultat("ok", MAINTENANT, r)
    ligne = d.journal("iPhone", r)
    tout = json.dumps(v) + ligne
    assert "SECRET" not in tout and "PDF-1.7" not in tout
    assert "Facture" not in ligne and "EDF" not in ligne and "1 pièce(s) jointe(s)" in ligne
    assert "Factures" not in d.journal("iPad", raison="dossier non proposé")


def test_execution_nouveau_chemin_cree_les_dossiers_manquants():
    drive, gmail = FauxDrive(), FauxGmail()
    p = {"mail": "m1", "fichiers": [{"partie": "2", "nom": "Conditions.pdf"}],
         "dossier": {"id": None, "chemin": "Travaux/Alfortville", "nouveau": True}}
    r = d.executer(p, drive, gmail)
    # « Travaux » existe déjà : réutilisé ; « Alfortville » est créé dedans.
    assert drive.ecritures == [("dossier", "Alfortville", "d-trav"),
                               ("fichier", "Conditions.pdf", "nouveau-Alfortville", len(SECRET))]
    assert r["crees"] == 1 and r["dossier"]["id"] == "nouveau-Alfortville"
    with pytest.raises(d.Refus):     # pièce jointe disparue du mail : rien n'est déposé
        d.executer({**p, "fichiers": [{"partie": "7", "nom": "x.pdf"}]}, FauxDrive(), gmail)
    with pytest.raises(d.Refus):     # accord Drive retiré entre-temps
        d.executer(p, FauxDrive(autorise=False), gmail)


# MARK: - Client Drive (HTTP)

class FauxHttp:
    def __init__(self, reponses):
        self.reponses, self.appels = list(reponses), []

    def _r(self, methode, url, **kw):
        self.appels.append((methode, url, kw))
        code, corps, *entetes = self.reponses.pop(0)
        return SimpleNamespace(status_code=code, json=lambda: corps, text=json.dumps(corps),
                               headers=entetes[0] if entetes else {})

    def post(self, url, **kw):
        return self._r("post", url, **kw)

    def get(self, url, **kw):
        return self._r("get", url, **kw)

    def put(self, url, **kw):
        return self._r("put", url, **kw)


AUTH = {"client_id": "i", "client_secret": "x", "refresh_token": "r"}
JETON = {"access_token": "acces", "expires_in": 3600, "scope": f"{c.API_GMAIL} {d.PORTEE_DRIVE}"}


def test_jeton_portees_et_envoi_multipart():
    http = FauxHttp([(200, JETON), (200, {"id": "f1", "webViewLink": "https://drive.google.com/file/d/f1/view"})])
    drive = d.ClientDrive(s.JetonGoogle(AUTH, http=http))
    assert drive.autorise()
    r = drive.deposer("Facture.pdf", "application/pdf", SECRET, "d-edf")
    assert r == {"id": "f1", "lien": "https://drive.google.com/file/d/f1/view"}
    methode, url, kw = http.appels[-1]
    assert methode == "post" and url == d.API_ENVOI and kw["params"]["uploadType"] == "multipart"
    assert kw["headers"]["Content-Type"].startswith("multipart/related; boundary=")
    assert kw["headers"]["Authorization"] == "Bearer acces"
    assert b'"parents": ["d-edf"]' in kw["content"] and SECRET in kw["content"]
    # Consentement sans Drive : pas autorisé, et aucun appel à Drive.
    http = FauxHttp([(200, {**JETON, "scope": "https://www.googleapis.com/auth/gmail.modify"})])
    assert not d.ClientDrive(s.JetonGoogle(AUTH, http=http)).autorise() and len(http.appels) == 1


def test_envoi_resumable_au_dela_de_5_mo():
    gros = b"x" * (d.ENVOI_SIMPLE_MAX + 1)
    session = d.API_ENVOI + "?uploadType=resumable&upload_id=abc"
    http = FauxHttp([(200, JETON), (200, {}, {"Location": session}), (200, {"id": "f2"})])
    r = d.ClientDrive(s.JetonGoogle(AUTH, http=http)).deposer("Plans.pdf", "application/pdf", gros, "d-trav")
    assert r["lien"] == "https://drive.google.com/file/d/f2/view"
    (_, _, _), (m1, u1, k1), (m2, u2, k2) = http.appels
    assert m1 == "post" and k1["params"]["uploadType"] == "resumable" and k1["json"]["parents"] == ["d-trav"]
    assert k1["headers"]["X-Upload-Content-Length"] == str(len(gros))
    assert m2 == "put" and u2 == session and k2["content"] is gros
    # Une session qui ne pointe pas vers l'envoi de Drive est refusée (rien n'est envoyé ailleurs).
    http = FauxHttp([(200, JETON), (200, {}, {"Location": "https://ailleurs.example/x"})])
    with pytest.raises(c.ErreurGmail):
        d.ClientDrive(s.JetonGoogle(AUTH, http=http)).deposer("Plans.pdf", "application/pdf", gros, "d")
    assert [m for m, *_ in http.appels] == ["post", "post"]


def test_chemins_et_recherche_de_dossiers():
    http = FauxHttp([
        (200, JETON),
        (200, {"files": [{"id": "d-edf", "name": "EDF", "parents": ["d-fact"]}]}),     # files.list
        (200, {"id": "root-id"}),                                                     # racine
        (200, {"id": "d-fact", "name": "Factures", "parents": ["root-id"]}),           # parent
    ])
    drive = d.ClientDrive(s.JetonGoogle(AUTH, http=http))
    assert drive.dossiers(["L'EDF"]) == [{"id": "d-edf", "chemin": "Factures/EDF"}]
    q = http.appels[1][2]["params"]["q"]
    assert "mimeType = 'application/vnd.google-apps.folder'" in q and "trashed = false" in q
    assert "name contains 'L\\'EDF'" in q


def test_contenu_piece_jointe_decode_en_memoire():
    donnees = base64.urlsafe_b64encode(SECRET).decode().rstrip("=")
    http = FauxHttp([(200, JETON), (200, {"size": len(SECRET), "data": donnees})])
    assert d.PiecesGmail(s.JetonGoogle(AUTH, http=http)).contenu("m1", "att-a") == SECRET
    assert http.appels[-1][1].endswith("/messages/m1/attachments/att-a")


def test_drive_garde_fou():
    """Le client Drive ne fait que lister, lire des métadonnées et créer ; aucune suppression, corbeille,
    modification ni partage ; aucun fichier écrit sur le NUC (le contenu reste en mémoire)."""
    source = Path(d.__file__).read_text(encoding="utf-8")
    code = "\n".join(l for l in source.splitlines() if not l.strip().startswith("#"))
    code = re.sub(r'"""(.|\n)*?"""', "", code)
    for interdit in ('"delete"', "delete(", "trash\"", "/trash", "emptyTrash", "/permissions", '"patch"', "patch(",
                     "/copy", "tempfile", "open(", ".write(", "write_bytes", "self.log", "print("):
        assert interdit not in code, interdit
    assert '"trashed": True' not in code and "'trashed': True" not in code
    publiques = {n for n, _ in inspect.getmembers(d.ClientDrive, inspect.isfunction) if not n.startswith("_")}
    assert publiques == {"autorise", "racine", "chemin", "lister", "dossiers", "dossier", "enfant", "creer_dossier",
                         "deposer"}
    # Le seul PUT : les octets vers la session d'envoi de Drive.
    assert code.count('"put"') == 1 and "session.startswith(API_ENVOI)" in code
    publiques = {n for n, _ in inspect.getmembers(d.PiecesGmail, inspect.isfunction) if not n.startswith("_")}
    assert publiques == {"message", "contenu"}
    assert '"get"' in inspect.getsource(d.PiecesGmail.contenu) and '"post"' not in inspect.getsource(d.PiecesGmail)


def test_schemas_strict_sous_la_limite_des_unions():
    """L'API refuse (400) plus de 16 paramètres en union (anyOf) sur l'ensemble des outils strict : les outils Drive
    n'en ajoutent aucun (29/10, premier essai réel refusé à 18)."""
    def unions(x):
        if isinstance(x, dict):
            return ("anyOf" in x) + sum(unions(v) for v in x.values())
        return sum(unions(v) for v in x) if isinstance(x, list) else 0
    assert unions(d.OUTILS_DRIVE) == 0
    assert unions([t["input_schema"] for t in a.OUTILS + s.OUTILS_COURRIER if t.get("strict")]) <= 16


def test_portee_du_script_d_autorisation():
    script = (Path(__file__).resolve().parents[2] / "scripts" / "courrier_autoriser.py").read_text(encoding="utf-8")
    assert f'PORTEE_DRIVE = "{d.PORTEE_DRIVE}"' in script and "--tout" in script and "--drive" in script
