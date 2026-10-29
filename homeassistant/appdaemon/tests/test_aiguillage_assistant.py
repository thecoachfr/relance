"""Tests hors Home Assistant de `aiguillage_assistant` (assistant de l'app Courrier, 29/10/2026). Aucun appel réseau :
faux client Claude, faux Gmail, faux agenda, base SQLite de test (celle des tests de l'agent)."""

import base64
from datetime import date, datetime, timedelta, timezone
import email
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
from test_aiguillage_agent import MAINTENANT, FauxClient, FauxService, _outil, _texte, base  # noqa: E402,F401

QUAND = MAINTENANT.astimezone(timezone.utc).isoformat()


def question(**champs):
    return {"v": 1, "texte": "Prépare une réponse à Erika", "appareil": "iPad", "quand": QUAND, "mail": "m1",
            "mail_joint": True, "fil": [], **champs}


class FauxBrouillons:
    def __init__(self, erreur=None):
        self.crees, self.erreur = [], erreur

    def en_tetes(self, ident):
        if ident == "absent":
            raise c.Introuvable(ident)
        return {"fil": "f1", "de": "Erika Martin <erika@seven-portage.fr>", "repondre_a": "Compta <compta@seven-portage.fr>",
                "objet": "Facture d'octobre", "message_id": "<abc@seven>", "references": "<x@y>"}

    def creer(self, raw, fil=None):
        if self.erreur:
            raise self.erreur
        self.crees.append((raw, fil))
        return "r-42"


class FauxAgenda:
    def __init__(self, items=(), erreur=None):
        self.items, self.erreur, self.appels = list(items), erreur, []

    def evenements(self, debut, fin, limite=40):
        self.appels.append((debut, fin))
        if self.erreur:
            raise self.erreur
        return self.items


AGENDA = [
    {"id": "e2", "summary": "Dentiste", "start": {"dateTime": "2026-10-27T17:30:00+01:00"},
     "end": {"dateTime": "2026-10-27T18:00:00+01:00"}, "location": "  12 rue X,\n Alfortville ", "description": "secret"},
    {"id": "e1", "summary": "Anniversaire de Léa", "start": {"date": "2026-10-27"}, "end": {"date": "2026-10-28"}},
    {"id": "e3", "summary": "Annulé", "status": "cancelled", "start": {"dateTime": "2026-10-27T09:00:00+01:00"}},
]


def outils_courrier(base, brouillons=None, agenda=None, mail_cite=None, questions=("Prépare une réponse",)):
    o = a.Outils(base, FauxService(), MAINTENANT, questions=list(questions))
    return s.OutilsCourrier(o, brouillons=(lambda: brouillons) if brouillons else None,
                            agenda=(lambda: agenda) if agenda else None, mail_cite=mail_cite)


# MARK: - Question de l'app

def test_question_lue_et_bornee():
    q = s.lire_question(question(fil=[{"question": f"q{i}", "reponse": f"r{i}"} for i in range(5)] + [{"x": 1}]),
                        MAINTENANT)
    assert q["texte"] == "Prépare une réponse à Erika" and q["mail"] == "m1" and q["mail_joint"]
    assert [e["question"] for e in q["fil"]] == ["q3", "q4"]   # 3 derniers, l'échange mal formé ignoré
    # Trop ancienne (NUC arrêté pendant l'attente), vide, d'une autre forme : ignorée.
    vieille = (MAINTENANT - timedelta(minutes=6)).astimezone(timezone.utc).isoformat()
    assert s.lire_question(question(quand=vieille), MAINTENANT) is None
    assert s.lire_question(question(texte="   "), MAINTENANT) is None
    assert s.lire_question(question(v=2), MAINTENANT) is None
    assert s.lire_question(None, MAINTENANT) is None


def test_mail_cite_seulement_celui_de_la_question():
    v = {"v": 1, "id": "m1", "fil": "f1", "de": "Erika", "a": "moi", "objet": "Facture", "date": QUAND,
         "texte": "y" * 9000}
    m = s.lire_mail_cite(v, "m1")
    assert len(m["texte"]) == s.TEXTE_MAIL_MAX and m["objet"] == "Facture"
    assert s.lire_mail_cite(v, "m2") is None and s.lire_mail_cite(None, "m1") is None
    texte = s.question_pour_ia(s.lire_question(question(), MAINTENANT), MAINTENANT, m)
    assert texte.startswith("[mardi 27/10/2026 14:05] Prépare une réponse à Erika")
    assert '<mail_cite id="m1">' in texte and texte.rstrip().endswith("</mail_cite>")
    # Sans texte joint : seulement l'id du mail ouvert.
    sans = s.question_pour_ia(s.lire_question(question(mail_joint=False), MAINTENANT), MAINTENANT)
    assert "id m1" in sans and "mail_cite" not in sans


# MARK: - Outils de Courrier

def test_brouillon_cree_dans_gmail_jamais_envoye(base):
    faux = FauxBrouillons()
    o = outils_courrier(base, brouillons=faux)
    texte, erreur = o.executer("preparer_brouillon", {"id": "m1", "a": None, "objet": None,
                                                     "texte": "Bonjour Erika,\n\nC'est validé.\n\nAlexandre"})
    assert not erreur and "pas envoyé" in json.loads(texte)["brouillon"]
    (raw, fil), = faux.crees
    assert fil == "f1"
    msg = email.message_from_bytes(base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4)))
    # Réponse à « Répondre à », objet « Re: », dans la conversation.
    assert msg["To"] == "Compta <compta@seven-portage.fr>" and msg["Subject"] == "Re: Facture d'octobre"
    assert msg["In-Reply-To"] == "<abc@seven>" and msg["References"] == "<x@y> <abc@seven>"
    assert msg["From"] == c.ADRESSE_PERSO and "C'est validé." in msg.get_payload(decode=True).decode("utf-8")
    bloc, = o.blocs_brouillon
    assert bloc["brouillon_gmail"] == "r-42" and bloc["mail"] == "m1" and bloc["objet"] == "Re: Facture d'octobre"
    assert o.appels == ["preparer_brouillon"]


def test_brouillon_sans_gmail_ou_refuse(base):
    # Gmail refuse : le bloc part quand même, l'app créera le brouillon à l'ouverture.
    o = outils_courrier(base, brouillons=FauxBrouillons(erreur=c.ErreurGmail("HTTP 500")))
    texte, erreur = o.executer("preparer_brouillon", {"id": "m1", "a": None, "objet": None, "texte": "Oui"})
    assert not erreur and "l'app le créera" in json.loads(texte)["gmail"]
    assert o.blocs_brouillon[0]["brouillon_gmail"] is None
    # Nouveau mail sans destinataire : refusé ; texte vide : refusé.
    o = outils_courrier(base)
    assert o.executer("preparer_brouillon", {"id": None, "a": None, "objet": None, "texte": "Salut"})[1]
    assert o.executer("preparer_brouillon", {"id": None, "a": "x@y.fr", "objet": "Hello", "texte": " "})[1]
    texte, erreur = o.executer("preparer_brouillon", {"id": None, "a": "x@y.fr", "objet": "Hello", "texte": "Salut"})
    assert not erreur and o.blocs_brouillon[0]["fil"] is None


def test_proposer_actions_ne_fait_rien(base):
    service = FauxService()
    o = s.OutilsCourrier(a.Outils(base, service, MAINTENANT, questions=["archive tout"]))
    texte, erreur = o.executer("proposer_actions", {"intro": "Pubs à archiver", "actions": [
        {"id": "m3", "geste": "archiver", "raison": "Le Monde"}, {"id": "m3", "geste": "archiver", "raison": "doublon"},
        {"id": "m2", "geste": "supprimer", "raison": "?"}, {"id": "m2", "geste": "plus_tard", "raison": "Enedis"}]})
    assert not erreur and "RIEN n'est fait" in json.loads(texte)["proposition"]
    assert o.blocs_actions == [{"type": "actions", "intro": "Pubs à archiver", "actions": [
        {"mail": "m3", "geste": "archiver", "raison": "Le Monde"}, {"mail": "m2", "geste": "plus_tard", "raison": "Enedis"}]}]
    assert service.appels == []   # aucune écriture : c'est l'app qui agit après la confirmation d'Alexandre
    assert o.executer("proposer_actions", {"intro": "x", "actions": [{"id": "m1", "geste": "envoyer", "raison": ""}]})[1]


def test_outil_agenda(base):
    faux = FauxAgenda(AGENDA)
    o = outils_courrier(base, agenda=faux)
    r = json.loads(o.executer("agenda", {"jour": "2026-10-28", "jours": 30})[0])
    assert r["du"] == "2026-10-28" and r["jours"] == 14
    debut, fin = faux.appels[0]
    assert debut == datetime(2026, 10, 28, tzinfo=c.PARIS) and fin - debut == timedelta(days=14)
    assert [e["id"] for e in r["evenements"]] == ["e2", "e1"]
    assert "description" not in json.dumps(r) and "secret" not in json.dumps(r)
    assert o.executer("agenda", {"jour": "demain", "jours": None})[1]
    refuse = outils_courrier(base, agenda=FauxAgenda(erreur=s.PorteeManquante("403")))
    texte, erreur = refuse.executer("agenda", {"jour": None, "jours": None})
    assert erreur and "consentement" in texte
    assert outils_courrier(base).executer("agenda", {"jour": None, "jours": None})[1]


# MARK: - Agenda publié pour Programme

def test_agenda_du_jour_publie():
    evts = s.evenements_du_jour(FauxAgenda(AGENDA), date(2026, 10, 27))
    assert evts == [
        {"id": "e1", "titre": "Anniversaire de Léa", "debut": "2026-10-27", "fin": "2026-10-28", "lieu": None,
         "journee": True},
        {"id": "e2", "titre": "Dentiste", "debut": "2026-10-27T17:30:00+01:00", "fin": "2026-10-27T18:00:00+01:00",
         "lieu": "12 rue X, Alfortville", "journee": False}]
    v = s.valeur_agenda(evts, MAINTENANT)
    assert v["v"] == 1 and v["evenements"] == evts
    assert s.empreinte_agenda(evts) == s.empreinte_agenda(json.loads(json.dumps(evts)))
    cles = ["agenda:2026-10-25", "agenda:2026-10-26", "agenda:2026-10-27", "plus_tard:x"]
    assert s.cles_agenda_perimees(cles, MAINTENANT) == ["agenda:2026-10-25"]


class FauxHttp:
    def __init__(self, reponses):
        self.reponses, self.appels = list(reponses), []

    def _r(self, methode, url, **kw):
        self.appels.append((methode, url, kw))
        code, corps = self.reponses.pop(0)
        return SimpleNamespace(status_code=code, json=lambda: corps, text=json.dumps(corps))

    def post(self, url, **kw):
        return self._r("post", url, **kw)

    def get(self, url, **kw):
        return self._r("get", url, **kw)


def test_jeton_google_et_portee_manquante():
    jeton = {"access_token": "acces", "expires_in": 3600}
    http = FauxHttp([(200, jeton), (401, {}), (200, jeton), (200, {"items": AGENDA})])
    client = s.ClientAgenda(s.JetonGoogle({"client_id": "i", "client_secret": "x", "refresh_token": "r"}, http=http))
    assert len(client.evenements(MAINTENANT, MAINTENANT + timedelta(days=1))) == 2   # l'annulé est écarté
    assert [m for m, *_ in http.appels] == ["post", "get", "post", "get"]   # 401 : nouveau jeton, un seul nouvel essai
    assert http.appels[-1][2]["params"]["singleEvents"] == "true"
    refus = FauxHttp([(200, jeton), (403, {"error": {"errors": [{"reason": "insufficientPermissions"}]}})])
    with pytest.raises(s.PorteeManquante):
        s.ClientAgenda(s.JetonGoogle({"client_id": "i", "client_secret": "x", "refresh_token": "r"}, http=refus)) \
            .evenements(MAINTENANT, MAINTENANT)


def test_brouillons_garde_fou():
    """Seule écriture Gmail de l'assistant : `drafts.create`. Ni envoi, ni suppression, ni libellés, ni corbeille."""
    source = Path(s.__file__).read_text(encoding="utf-8")
    code = "\n".join(l for l in source.splitlines() if not l.strip().startswith("#"))
    code = re.sub(r'"""(.|\n)*?"""', "", code)
    for interdit in ("/send", "drafts/send", "/trash", "/untrash", "batchModify", "batchDelete", "/modify", "/import",
                     "/insert", "http.delete", "http.put", "http.patch", "delete(", "/messages/send"):
        assert interdit not in code, interdit
    publiques = {n for n, _ in inspect.getmembers(s.BrouillonsGmail, inspect.isfunction) if not n.startswith("_")}
    assert publiques == {"en_tetes", "creer"}
    assert '"post", f"{API_GMAIL}/drafts"' in inspect.getsource(s.BrouillonsGmail.creer)
    assert '"format": "metadata"' in inspect.getsource(s.BrouillonsGmail.en_tetes)
    publiques = {n for n, _ in inspect.getmembers(s.ClientAgenda, inspect.isfunction) if not n.startswith("_")}
    assert publiques == {"evenements"} and '"get", API_AGENDA' in inspect.getsource(s.ClientAgenda.evenements)


# MARK: - Réponse

def test_boucle_courrier_avec_mails_cites_et_blocs(base):
    client = FauxClient([
        ([_outil("t1", "chercher_mails", {"requete": None, "expediteur": "erika", "categorie": None,
                                          "depuis_jours": None, "limite": None}),
          _outil("t2", "proposer_actions", {"intro": "Je propose :", "actions": [
              {"id": "m3", "geste": "archiver", "raison": "Le Monde"}]})], "tool_use"),
        ([_texte("Erika attend la validation de la **facture**.\nMAINTENANT pas une ligne de mails\nMAILS: m1, inventé, m1")],
         "end_turn"),
    ])
    o = outils_courrier(base)
    q = s.lire_question(question(mail_joint=False), MAINTENANT)
    texte, cout, raison, tours = a.repondre(
        client, s.question_pour_ia(q, MAINTENANT), o, maintenant=MAINTENANT, fil=[{"question": "a", "reponse": "b"}],
        definitions=a.OUTILS + s.OUTILS_COURRIER, blocs_systeme=s.systeme(), datee=True)
    assert raison is None and tours == 2
    req = client.requetes[0]
    assert [t["name"] for t in req["tools"]][-5:] == ["preparer_brouillon", "proposer_actions", "agenda",
                                                      "chercher_dossiers_drive", "proposer_enregistrement_drive"]
    assert "Google Drive" in req["system"][0]["text"]
    assert req["system"][0]["text"].startswith("Tu es l'assistant de Courrier")
    assert req["messages"][0] == {"role": "user", "content": "a"}
    assert req["messages"][-1]["content"][0]["text"].startswith("[mardi 27/10/2026 14:05] Prépare")
    blocs = s.blocs_reponse(texte, o)
    assert blocs[0] == {"type": "texte", "texte": "Erika attend la validation de la facture.\nMAINTENANT pas une "
                                                    "ligne de mails"}
    # Seuls les mails rendus par les outils sont cités (l'id inventé est écarté), sans doublon.
    assert blocs[1]["type"] == "mails" and [m["id"] for m in blocs[1]["mails"]] == ["m1"]
    m1 = blocs[1]["mails"][0]
    assert m1["fil"] == "f1" and m1["adresse"] == "erika@seven-portage.fr" and m1["date"].endswith("+01:00")
    assert blocs[2]["type"] == "actions"


def test_separer_mails_et_brouillon_cite(base):
    assert s.separer_mails("Texte\nmails : a1 b2\n") == ("Texte", ["a1", "b2"])
    assert s.separer_mails("Rien") == ("Rien", [])
    o = outils_courrier(base, brouillons=FauxBrouillons(),
                        mail_cite={"id": "m1", "fil": "f1", "de": "Erika <erika@x.fr>", "objet": "Facture", "date": QUAND,
                                   "texte": "corps"})
    o.executer("preparer_brouillon", {"id": "m1", "a": None, "objet": None, "texte": "Bonjour"})
    blocs = s.blocs_reponse("Voici un brouillon.", o)
    # Le mail auquel répond le brouillon est cité, pour l'ouvrir ; jamais le texte du mail cité.
    assert [b["type"] for b in blocs] == ["texte", "mails", "brouillon"]
    assert blocs[1]["mails"][0]["id"] == "m1" and "corps" not in json.dumps(blocs)
    assert blocs[1]["mails"][0]["adresse"] == "erika@x.fr" and blocs[1]["mails"][0]["de"] == "Erika"


def test_valeurs_purge_et_journal():
    v = s.valeur_reponse("echec", MAINTENANT, raison="budget du mois atteint")
    assert v["statut"] == "echec" and v["blocs"] == [] and v["v"] == 1
    vieux = (MAINTENANT - timedelta(days=8)).astimezone(timezone.utc).isoformat()
    recent = (MAINTENANT - timedelta(minutes=11)).astimezone(timezone.utc).isoformat()
    enr = [{"cle": "ia_question:a", "modifie_le": vieux}, {"cle": "ia_reponse:a", "modifie_le": recent},
           {"cle": "ia_mail:b", "modifie_le": recent}, {"cle": "ia_mail:c", "modifie_le": QUAND},
           {"cle": "plus_tard:x", "modifie_le": vieux}, {"cle": "ia_question:z", "modifie_le": vieux, "supprime": True}]
    assert s.cles_a_purger(enr, MAINTENANT) == ["ia_question:a", "ia_mail:b"]
    ligne = s.journal("iPad", "Prépare une réponse secrète à Erika", ["preparer_brouillon"], 0.0213, 3,
                      {"cout_mois": 0.45}, mail_joint=True)
    assert "secrète" not in ligne and "Erika" not in ligne and "35 caractères" in ligne and "0.0213 $" in ligne
    assert "mail cité joint" in ligne


def test_espace_ia_ignore_par_la_consigne_du_tri():
    """Le module ne lit rien de la base en écriture : l'agent garde la base en lecture seule."""
    assert "sqlite3" not in Path(s.__file__).read_text(encoding="utf-8")
