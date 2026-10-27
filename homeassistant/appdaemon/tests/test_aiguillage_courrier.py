"""Tests hors Home Assistant de `aiguillage_courrier` (P9-N, lot N3). Aucun appel réseau : Gmail et l'API Claude sont
simulés."""

import base64
from datetime import datetime, timedelta
import inspect
import json
from pathlib import Path
import re
import sys
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import aiguillage_courrier as c  # noqa: E402

MAINTENANT = datetime(2026, 10, 24, 18, 0, tzinfo=c.PARIS)


def b64(texte):
    return base64.urlsafe_b64encode(texte.encode()).decode().rstrip("=")


def msg(ident, de="Marie Dupont <marie@exemple.fr>", sujet="Dîner samedi ?", corps="Tu es dispo samedi ?",
        libelles=("INBOX", "UNREAD", "CATEGORY_PERSONAL"), fil=None, quand=MAINTENANT, en_tetes=(), html=False):
    headers = [{"name": "From", "value": de}, {"name": "To", "value": "alexandre.fau@gmail.com"},
               {"name": "Subject", "value": sujet}, {"name": "Date", "value": "Sat, 24 Oct 2026 18:00:00 +0200"},
               *({"name": n, "value": v} for n, v in en_tetes)]
    partie = {"mimeType": "text/html" if html else "text/plain", "body": {"data": b64(corps)}}
    return {"id": ident, "threadId": fil or f"f{ident}", "labelIds": list(libelles), "snippet": corps[:50],
            "internalDate": str(int(quand.timestamp() * 1000)),
            "payload": {"mimeType": "multipart/alternative", "headers": headers, "parts": [partie]}}


# MARK: - Extraction

def test_base64url_sans_remplissage():
    assert c.b64url(b64("Été à Paris ? ok")) == "Été à Paris ? ok"
    assert c.b64url("") == ""


def test_en_tetes_et_adresse():
    m = msg("1", en_tetes=[("List-Unsubscribe", "<mailto:x@y>"), ("Precedence", "Bulk"), ("Reply-To", "R <r@x.fr>"),
                           ("X-Autre", "z")])
    h = c.en_tetes(m["payload"])
    assert h["from"] == "Marie Dupont <marie@exemple.fr>" and h["precedence"] == "Bulk" and "x-autre" not in h
    assert c.adresse('"Marie Dupont" <Marie@Exemple.FR>') == ("marie@exemple.fr", "Marie Dupont")
    f = c.fiche(m)
    assert f["de"] == "marie@exemple.fr" and f["nom"] == "Marie Dupont" and f["precedence"] == "bulk"
    assert f["reply_to"] == "r@x.fr" and f["list_unsubscribe"] and f["fil"] == "f1"
    assert f["date"] == "2026-10-24T16:00:00+00:00"


def test_texte_multipart_prefere_le_texte_brut():
    payload = {"mimeType": "multipart/mixed", "parts": [
        {"mimeType": "multipart/alternative", "parts": [
            {"mimeType": "text/plain", "body": {"data": b64("Bonjour,\n\n\nVoici   la facture.")}},
            {"mimeType": "text/html", "body": {"data": b64("<p>HTML</p>")}}]},
        {"mimeType": "application/pdf", "filename": "facture.pdf", "body": {"attachmentId": "a"}},
        {"mimeType": "text/plain", "filename": "notes.txt", "body": {"data": b64("pièce jointe")}}]}
    assert c.texte_du_message(payload) == "Bonjour,\nVoici la facture."


def test_texte_html_seul():
    corps = ("<html><head><style>p{color:red}</style></head><body><script>alert(1)</script>"
             "<p>Rendez-vous&nbsp;jeudi &agrave; 10&nbsp;h</p><br>Merci</body></html>")
    texte = c.texte_du_message({"mimeType": "text/html", "body": {"data": b64(corps)}})
    assert texte == "Rendez-vous jeudi à 10 h\nMerci"
    assert "alert" not in texte and "color" not in texte


def test_texte_limite_et_repli_sur_l_apercu():
    long = {"mimeType": "text/plain", "body": {"data": b64("x" * 5000)}}
    assert len(c.texte_du_message(long)) == c.LONGUEUR_EXTRAIT
    assert c.texte_du_message({"mimeType": "multipart/mixed", "parts": []}, "Aper&ccedil;u") == "Aperçu"
    assert len(c.fiche(msg("1", corps="y" * 4000))["extrait"]) == 1500


def test_a_repondu():
    fil = {"messages": [{"id": "1", "internalDate": "1000", "labelIds": ["INBOX"]},
                        {"id": "2", "internalDate": "2000", "labelIds": ["SENT"]}]}
    assert c.a_repondu(fil, "1")
    assert not c.a_repondu(fil, "2")
    fil["messages"][1]["internalDate"] = "500"
    assert not c.a_repondu(fil, "1")


# MARK: - Règles sûres et ordre de décision

def test_regles_sures():
    f = lambda **kw: c.fiche(msg("1", **kw))  # noqa: E731
    assert c.regle_sure(f(libelles=["INBOX", "CATEGORY_PROMOTIONS"]))[0] == "bruit"
    assert c.regle_sure(f(libelles=["INBOX", "CATEGORY_SOCIAL"]))[0] == "bruit"
    assert c.regle_sure(f(libelles=["INBOX", "CATEGORY_FORUMS"]))[0] == "lettre"
    assert c.regle_sure(f(en_tetes=[("List-Id", "<news.exemple.fr>")]))[0] == "lettre"
    assert c.regle_sure(f(en_tetes=[("Precedence", "bulk")]))[0] == "lettre"
    assert c.regle_sure(f(de="Service <no-reply@service.fr>", sujet="Bienvenue"))[0] == "bruit"
    assert c.regle_sure(f(de="notifications@github.com", sujet="Nouvelle étoile"))[0] == "bruit"
    # Une vraie personne : l'IA décide.
    assert c.regle_sure(f()) is None
    # Envoi automatique avec un mot d'action : l'IA décide (sauf promotions).
    assert c.regle_sure(f(de="noreply@edf.fr", sujet="Votre facture est disponible")) is None
    assert c.regle_sure(f(de="no_reply@banque.fr", sujet="Alerte", corps="Nouvelle connexion, sécurité")) is None
    assert c.regle_sure(f(en_tetes=[("List-Unsubscribe", "<x>")], sujet="Échéance de votre contrat")) is None
    assert c.regle_sure(f(libelles=["INBOX", "CATEGORY_PROMOTIONS"], sujet="Paiement en 3 fois"))[0] == "bruit"
    # « info@ » peut être une vraie entreprise qui répond : pas une adresse automatique.
    assert c.regle_sure(f(de="info@plombier.fr", sujet="Votre demande")) is None


def test_ordre_de_decision():
    f = c.fiche(msg("1", de="noreply@x.fr", sujet="Bienvenue"))
    # (a) la règle apprise passe avant les règles sûres
    assert c.decider(f, {"noreply@x.fr": "lettre"}) == {"categorie": "lettre", "source": "regle",
                                                       "raison": "règle apprise de l'expéditeur", "ia": False}
    # (b) règle sûre
    assert c.decider(f, {}) | {"raison": ""} == {"categorie": "bruit", "source": "gmail", "raison": "", "ia": False}
    # (c) l'IA
    p = c.fiche(msg("2"))
    assert c.decider(p, {})["ia"] and c.decider(p, {})["categorie"] is None
    # une règle a_traiter garde sa catégorie mais demande un résumé à l'IA
    d = c.decider(p, {"marie@exemple.fr": "a_traiter"})
    assert d["categorie"] == "a_traiter" and d["ia"] and d["source"] == "regle"
    ia = {"categorie": "bruit", "resume": "Marie propose un dîner.", "demande": "Répondre", "echeance": None,
          "confiance": 0.9}
    fin = c.finaliser(d, ia)
    assert fin["categorie"] == "a_traiter" and fin["resume"] == "Marie propose un dîner." and fin["source"] == "regle"
    fin = c.finaliser(c.decider(p, {}), ia)
    assert fin["categorie"] == "bruit" and fin["source"] == "ia"
    # Sans IA ni règle : à traiter par défaut
    fin = c.finaliser(c.decider(p, {}), None)
    assert fin["categorie"] == "a_traiter" and fin["source"] == "defaut"


def test_nettoyer_ia():
    assert c.nettoyer_ia({"categorie": "fait"}) is None
    r = c.nettoyer_ia({"categorie": "a_traiter", "resume": " Facture EDF. ", "demande": "", "echeance": "2026-13-01",
                       "confiance": 1.7})
    assert r == {"categorie": "a_traiter", "resume": "Facture EDF.", "demande": None, "echeance": None, "confiance": 1.0,
                 "urgent": False}
    assert c.nettoyer_ia({"categorie": "lettre", "resume": "x", "demande": None, "echeance": "2026-11-05",
                          "confiance": 0.4})["echeance"] == "2026-11-05"


class FauxClaude:
    def __init__(self, reponse=None, stop="end_turn", erreur=None):
        self.appels = []
        self.reponse = reponse or {"categorie": "a_traiter", "resume": "Marie propose un dîner samedi.",
                                   "demande": "Répondre à Marie", "echeance": "2026-10-31", "confiance": 0.8}
        self.stop, self.erreur = stop, erreur
        self.messages = self

    def create(self, **kw):
        self.appels.append(kw)
        if self.erreur:
            raise self.erreur
        return SimpleNamespace(stop_reason=self.stop, usage=SimpleNamespace(input_tokens=1000, output_tokens=200),
                               content=[SimpleNamespace(type="text", text=json.dumps(self.reponse))])


def test_classer_ia_appel():
    ia = FauxClaude()
    r, prix = c.classer_ia(ia, c.fiche(msg("1")), MAINTENANT)
    assert r["categorie"] == "a_traiter" and r["echeance"] == "2026-10-31"
    assert abs(prix - (1000 * 0.10 + 200 * 0.50) / 1e6) < 1e-12
    kw = ia.appels[0]
    assert kw["model"] == "claude-haiku-5-5" and kw["output_config"]["effort"] == "low"
    assert kw["output_config"]["format"]["type"] == "json_schema"
    assert "DONNÉES" in kw["messages"][0]["content"] and "Malt" in kw["system"]
    r, _ = c.classer_ia(FauxClaude(stop="max_tokens"), c.fiche(msg("1")), MAINTENANT)
    assert r is None


# MARK: - Budget

def test_budget():
    etat = {"mois": "2026-09", "cout_mois": 99.0}
    assert c.budget_ok(etat, 15, MAINTENANT) and etat == {"mois": "2026-10", "cout_mois": 0.0}
    c.compter(etat, 14.99, MAINTENANT)
    assert c.budget_ok(etat, 15, MAINTENANT)
    c.compter(etat, 0.02, MAINTENANT)
    assert not c.budget_ok(etat, 15, MAINTENANT)


# MARK: - Historique et apprentissage

def test_lire_historique():
    h = [{"id": "10", "messagesAdded": [{"message": {"id": "a", "threadId": "fa", "labelIds": ["INBOX", "UNREAD"]}},
                                        {"message": {"id": "b", "threadId": "fb", "labelIds": ["SENT"]}},
                                        {"message": {"id": "c", "threadId": "fc", "labelIds": ["CATEGORY_UPDATES"]}}]},
         {"id": "11", "labelsRemoved": [{"message": {"id": "a", "threadId": "fa"}, "labelIds": ["UNREAD"]},
                                        {"message": {"id": "d", "threadId": "fd"}, "labelIds": ["INBOX", "UNREAD"]}]},
         {"id": "12", "labelsAdded": [{"message": {"id": "e", "threadId": "fe"}, "labelIds": ["TRASH"]},
                                      {"message": {"id": "a", "threadId": "fa"}, "labelIds": ["STARRED"]}],
          "messagesAdded": [{"message": {"id": "a", "threadId": "fa", "labelIds": ["INBOX"]}}]}]
    nouveaux, gestes = c.lire_historique(h)
    assert nouveaux == ["a"]
    assert gestes == [(None, "fb", "repondu"), ("a", "fa", "ouvert"), ("d", "fd", "ouvert"), ("d", "fd", "archive"),
                      ("e", "fe", "archive")]


def test_regle_apprise():
    assert c.regle_apprise(3, 0, 3, 3) is None  # moins de 4 messages
    assert c.regle_apprise(5, 5, 2, 0) == "a_traiter"
    assert c.regle_apprise(4, 0, 0, 4) == "bruit"
    assert c.regle_apprise(4, 0, 0, 2) is None
    assert c.regle_apprise(4, 4, 0, 1) == "lettre"
    assert c.regle_apprise(4, 2, 1, 2) is None


def _base():
    return c.ouvrir_base(":memory:")


def test_base_gestes_et_apprentissage():
    db = _base()
    d = {"categorie": "lettre", "source": "gmail", "raison": "liste"}
    for i in range(4):
        f = c.fiche(msg(f"n{i}", de="news@journal.fr", quand=MAINTENANT - timedelta(days=i)))
        c.enregistrer(db, f, c.finaliser(d, None), MAINTENANT)
    f = c.fiche(msg("p1", fil="fp"))
    c.enregistrer(db, f, c.finaliser({"categorie": None, "source": "ia", "raison": ""}, None), MAINTENANT)
    assert c.connu(db, "p1") and not c.connu(db, "zz")
    # jamais ouverts, archivés → bruit
    n = c.appliquer_gestes(db, [(f"n{i}", f"fn{i}", "archive") for i in range(4)] + [("n0", "fn0", "archive")],
                           MAINTENANT)
    assert n == 4  # le doublon n'est pas recompté
    rangs = {r["id"]: r for r in c.lignes(db)}
    assert rangs["n0"]["categorie"] == "fait" and rangs["n0"]["categorie_tri"] == "lettre" and rangs["n0"]["fait_le"]
    assert c.apprendre(db, MAINTENANT) == {"news@journal.fr": "bruit"}
    assert c.regles(db) == {"news@journal.fr": "bruit"}
    # répondu : tout le fil passe en fait
    c.appliquer_gestes(db, [(None, "fp", "repondu")], MAINTENANT)
    p1 = {r["id"]: r for r in c.lignes(db)}["p1"]
    assert p1["repondu"] == 1 and p1["categorie"] == "fait" and p1["categorie_tri"] == "a_traiter"
    # une règle manuelle n'est jamais écrasée par l'apprentissage
    db.execute("UPDATE regles SET source = 'manuel', categorie = 'lettre'")
    c.apprendre(db, MAINTENANT)
    assert c.regles(db) == {"news@journal.fr": "lettre"}


def test_purge_90_jours():
    db = _base()
    d = c.finaliser({"categorie": "bruit", "source": "gmail", "raison": ""}, None)
    c.enregistrer(db, c.fiche(msg("vieux", quand=MAINTENANT - timedelta(days=91))), d, MAINTENANT)
    c.enregistrer(db, c.fiche(msg("recent", quand=MAINTENANT - timedelta(days=89))), d, MAINTENANT)
    c.appliquer_gestes(db, [("vieux", "", "ouvert")], MAINTENANT)
    assert c.purger(db, MAINTENANT) == 1
    assert [r["id"] for r in c.lignes(db)] == ["recent"]
    assert db.execute("SELECT COUNT(*) FROM gestes").fetchone()[0] == 0


# MARK: - Capteur et bilan

def test_capteur():
    db = _base()
    ia = {"categorie": "a_traiter", "resume": "Marie propose un dîner.", "demande": "Répondre", "echeance": None,
          "confiance": 0.9}
    c.enregistrer(db, c.fiche(msg("1", fil="f1")), c.finaliser({"categorie": None, "source": "ia", "raison": ""}, ia),
                  MAINTENANT, 0.0002)
    c.enregistrer(db, c.fiche(msg("2", quand=MAINTENANT - timedelta(days=3))),
                  c.finaliser({"categorie": "bruit", "source": "gmail", "raison": ""}, None), MAINTENANT)
    c.enregistrer(db, c.fiche(msg("3", quand=MAINTENANT - timedelta(days=10))),
                  c.finaliser({"categorie": "lettre", "source": "gmail", "raison": ""}, None), MAINTENANT)
    etat = {"mois": "2026-10", "cout_mois": 1.5, "derniere_releve": "2026-10-24T17:58:00+02:00"}
    valeur, att = c.calculer_capteur(c.lignes(db), MAINTENANT, etat, "ombre", 15, None)
    assert valeur == 1
    assert att["aujourdhui"] == {"a_traiter": 1, "lettre": 0, "bruit": 0, "fait": 0}
    assert att["sept_jours"] == {"a_traiter": 1, "lettre": 0, "bruit": 1, "fait": 0}
    carte = att["a_traiter"][0]
    assert carte == {"id": "1", "fil": "f1", "de": "Marie Dupont", "adresse": "marie@exemple.fr",
                     "sujet": "Dîner samedi ?", "resume": "Marie propose un dîner.", "demande": "Répondre",
                     "echeance": None, "date": "2026-10-24T16:00:00+00:00",
                     "lien": "https://mail.google.com/mail/u/0/#inbox/f1"}
    assert att["mode"] == "ombre" and att["cout_mois"] == 1.5 and not att["budget_atteint"]
    assert att["avertissement"] is None and att["derniere_erreur"] is None
    assert att["derniere_releve"] == "2026-10-24T17:58:00+02:00"
    _, att = c.calculer_capteur([], MAINTENANT, {"mois": "2026-10", "cout_mois": 15.2}, "ombre", 15,
                                "autorisation Google absente")
    assert att["budget_atteint"] and "Budget" in att["avertissement"]
    assert att["derniere_erreur"] == "autorisation Google absente" and att["a_traiter"] == []
    json.dumps(att)  # publiable tel quel


def test_capteur_15_derniers():
    rangs = [{"id": str(i), "fil": str(i), "date_ms": 0, "categorie": "a_traiter", "de": "x@y.fr"} for i in range(20)]
    valeur, att = c.calculer_capteur(rangs, MAINTENANT, {}, "ombre", 15)
    assert valeur == 20 and len(att["a_traiter"]) == 15


def test_bilan():
    db = _base()
    ia = {"categorie": "a_traiter", "resume": "Facture EDF de 82 €.", "demande": "Payer la facture",
          "echeance": "2026-11-02", "confiance": 0.9}
    c.enregistrer(db, c.fiche(msg("1", de="EDF <noreply@edf.fr>", sujet="Votre facture")),
                  c.finaliser({"categorie": None, "source": "ia", "raison": ""}, ia), MAINTENANT)
    c.enregistrer(db, c.fiche(msg("2", de="promo@shop.fr", sujet="-50 %", libelles=["INBOX", "CATEGORY_PROMOTIONS"])),
                  c.finaliser(c.decider(c.fiche(msg("2", libelles=["INBOX", "CATEGORY_PROMOTIONS"])), {}), None),
                  MAINTENANT)
    texte = c.bilan(c.lignes(db), MAINTENANT, {"mois": "2026-10", "cout_mois": 0.01}, 15)
    assert texte.startswith("# Courrier — bilan de l'ombre du 24/10/2026")
    assert "2 message(s) reçu(s) aujourd'hui : À traiter 1, Lettres d'info 0, Bruit 1, Fait 0." in texte
    assert "**EDF** — Votre facture" in texte and "Demande : Payer la facture" in texte
    assert "Échéance : 2026-11-02" in texte and "#inbox/f1" in texte
    assert "## Exemples : Bruit (1 aujourd'hui)" in texte and "onglet Promotions" in texte


# MARK: - Client Gmail simulé et relève complète

class Rep:
    def __init__(self, status, donnees=None):
        self.status_code, self._d = status, donnees or {}

    def json(self):
        return self._d


class FauxHttp:
    """Simule l'API Gmail : messages, fils, historique, profil."""

    def __init__(self, messages, historique=None, history_id="500", jeton_status=200, historique_404=False):
        self.messages, self.hist, self.history_id = messages, historique or [], history_id
        self.jeton_status, self.historique_404 = jeton_status, historique_404
        self.appels = []

    def post(self, url, data=None, **kw):
        self.appels.append(("POST", url))
        assert url == c.JETON_URL and data["grant_type"] == "refresh_token"
        return Rep(self.jeton_status, {"access_token": "jeton", "expires_in": 3600})

    def get(self, url, params=None, headers=None, **kw):
        self.appels.append(("GET", url, params))
        assert headers["Authorization"] == "Bearer jeton"
        chemin = url.removeprefix(c.API_GMAIL + "/")
        if chemin == "profile":
            return Rep(200, {"emailAddress": "alexandre.fau@gmail.com", "historyId": self.history_id})
        if chemin == "history":
            if self.historique_404:
                return Rep(404)
            assert params["historyTypes"] == ["messageAdded", "labelAdded", "labelRemoved"]
            return Rep(200, {"history": self.hist, "historyId": "600"})
        if chemin == "messages":
            assert params["q"] == "in:inbox newer_than:2d"
            return Rep(200, {"messages": [{"id": i} for i in self.messages]})
        if chemin.startswith("messages/"):
            m = self.messages.get(chemin.split("/")[1])
            return Rep(200, m) if m else Rep(404)
        if chemin.startswith("threads/"):
            fil = chemin.split("/")[1]
            liste = [m for m in self.messages.values() if m["threadId"] == fil]
            if fil == "frep":
                liste.append({"id": "envoi", "internalDate": str(10 ** 13), "labelIds": ["SENT"]})
            return Rep(200, {"messages": liste})
        return Rep(500)


AUTH = {"client_id": "id", "client_secret": "secret", "refresh_token": "rt"}


def test_releve_amorcage_puis_historique():
    messages = {
        "1": msg("1"),
        "2": msg("2", de="noreply@x.fr", sujet="Bienvenue"),
        "3": msg("3", de="Paul <paul@x.fr>", sujet="Re: devis", fil="frep"),
    }
    http = FauxHttp(messages)
    gmail = c.ClientGmail(AUTH, http=http, horloge=lambda: 1000.0)
    db, ia, etat = _base(), FauxClaude(), {}
    resume = c.releve(gmail, db, ia, etat, 15, MAINTENANT, journal=lambda t: None)
    assert resume["amorcage"] and resume["nouveaux"] == 3
    assert etat["historyId"] == "500" and etat["derniere_releve"]
    rangs = {r["id"]: r for r in c.lignes(db)}
    assert rangs["1"]["categorie"] == "a_traiter" and rangs["1"]["source"] == "ia" and rangs["1"]["resume"]
    assert rangs["2"]["categorie"] == "bruit" and rangs["2"]["source"] == "gmail" and rangs["2"]["cout"] == 0
    assert rangs["3"]["categorie"] == "fait" and rangs["3"]["repondu"] == 1  # déjà répondu dans le fil
    assert len(ia.appels) == 2 and etat["cout_mois"] > 0
    assert [a for a in http.appels if a[0] == "POST"] == [("POST", c.JETON_URL)]  # un seul jeton, aucune écriture
    # Relève suivante : par l'historique.
    messages["4"] = msg("4", de="Léa <lea@x.fr>", sujet="Photos")
    http.hist = [{"id": "550", "messagesAdded": [{"message": {"id": "4", "threadId": "f4", "labelIds": ["INBOX"]}}],
                  "labelsRemoved": [{"message": {"id": "1", "threadId": "f1"}, "labelIds": ["UNREAD"]},
                                    {"message": {"id": "2", "threadId": "f2"}, "labelIds": ["INBOX"]}]}]
    resume = c.releve(gmail, db, ia, etat, 15, MAINTENANT, journal=lambda t: None)
    assert not resume["amorcage"] and resume["nouveaux"] == 1 and resume["gestes"] == 2
    assert etat["historyId"] == "600"
    rangs = {r["id"]: r for r in c.lignes(db)}
    assert rangs["1"]["ouvert"] == 1 and rangs["1"]["categorie"] == "a_traiter"
    assert rangs["2"]["categorie"] == "fait" and rangs["2"]["archive"] == 1
    assert rangs["4"]["categorie"] == "a_traiter"


def test_releve_historique_trop_vieux_et_budget():
    http = FauxHttp({"1": msg("1")}, historique_404=True, history_id="900")
    gmail = c.ClientGmail(AUTH, http=http, horloge=lambda: 1000.0)
    db, ia = _base(), FauxClaude()
    etat = {"historyId": "1", "mois": "2026-10", "cout_mois": 15.0}
    messages = []
    resume = c.releve(gmail, db, ia, etat, 15, MAINTENANT, journal=messages.append)
    assert resume["amorcage"] and etat["historyId"] == "900" and "trop ancien" in messages[0]
    # Budget atteint : aucun appel IA, rangé par défaut.
    assert ia.appels == []
    r = c.lignes(db)[0]
    assert r["categorie"] == "a_traiter" and r["source"] == "defaut"
    # Le mois suivant, l'IA reclasse les messages rangés par défaut (2 jours au plus).
    ia2 = FauxClaude(reponse={"categorie": "lettre", "resume": "x", "demande": None, "echeance": None,
                              "confiance": 0.7})
    http.historique_404 = False
    c.releve(gmail, db, ia2, etat, 15, MAINTENANT + timedelta(days=3), journal=lambda t: None)
    assert len(ia2.appels) == 0  # trop vieux (plus de 2 jours)
    c.releve(gmail, db, ia2, {"historyId": "900"}, 15, MAINTENANT + timedelta(hours=2), journal=lambda t: None)
    assert len(ia2.appels) == 1 and c.lignes(db)[0]["categorie"] == "lettre" and c.lignes(db)[0]["source"] == "ia"


def test_releve_ia_en_panne():
    http = FauxHttp({"1": msg("1")})
    gmail = c.ClientGmail(AUTH, http=http, horloge=lambda: 1000.0)
    db, notes = _base(), []
    c.releve(gmail, db, FauxClaude(erreur=RuntimeError("panne")), {}, 15, MAINTENANT, journal=notes.append)
    assert c.lignes(db)[0]["source"] == "defaut" and "IA indisponible" in notes[0]


def test_client_jeton_refuse_et_rafraichi():
    gmail = c.ClientGmail(AUTH, http=FauxHttp({}, jeton_status=400), horloge=lambda: 0.0)
    try:
        gmail.profil()
        raise AssertionError("AutorisationRefusee attendue")
    except c.AutorisationRefusee:
        pass
    horloge = [0.0]
    http = FauxHttp({})
    gmail = c.ClientGmail(AUTH, http=http, horloge=lambda: horloge[0])
    gmail.profil()
    gmail.profil()
    horloge[0] = 4000.0  # jeton expiré : rafraîchi
    gmail.profil()
    assert [a[0] for a in http.appels].count("POST") == 2


# MARK: - Garde-fou : lecture seule (règle absolue d'Alexandre, 24/10)

def test_garde_fou_lecture_seule():
    publiques = {n for n, _ in inspect.getmembers(c.ClientGmail, inspect.isfunction) if not n.startswith("_")}
    assert publiques == {"profil", "historique", "lister", "message", "fil", "libelles", "creer_libelle",
                         "poser_libelles"}
    source = Path(c.__file__).read_text(encoding="utf-8")
    for interdit in ("/send", "/trash", "/untrash", "batchModify", "batchDelete", "/drafts", "/import", "/insert",
                     "/delete", "http.delete", "http.put", "http.patch", "users.messages.send"):
        assert interdit not in source, interdit
    # La seule écriture sur un message (libellés) est dans poser_libelles, qui filtre les libellés.
    assert source.count("/modify") == 1 and "/modify" in inspect.getsource(c.ClientGmail.poser_libelles)
    client = inspect.getsource(c.ClientGmail)
    assert re.findall(r"self\._http\.(\w+)\(", client) == ["post", "get", "post"]
    assert "self._http.post(JETON_URL" in client


# MARK: - Ajustements du bilan du 24/10

def test_recruteur_linkedin_passe_a_l_ia():
    inmail = c.fiche(msg("r1", de="Alexandra Farrell <inmail-hit-reply@linkedin.com>", sujet="Senior AdTech Architect",
                         libelles=("INBOX", "CATEGORY_UPDATES"), en_tetes=(("List-Unsubscribe", "<https://x>"),)))
    assert c.recruteur(inmail["de"]) and c.regle_sure(inmail) is None
    alerte = c.fiche(msg("r2", de="jobalerts-noreply@linkedin.com", sujet="Tech Lead chez Hermès",
                         libelles=("INBOX", "CATEGORY_UPDATES"), en_tetes=(("List-Unsubscribe", "<https://x>"),)))
    assert not c.recruteur(alerte["de"]) and c.regle_sure(alerte)[0] == "lettre"
    assert "InMail" in c.CONSIGNE and "commande" in c.CONSIGNE


def test_sujet_normalise():
    assert c.sujet_normalise("RE: TR:  Chèques-Vacances") == "chèques-vacances"
    assert c.sujet_normalise("Fwd: Re: Bonjour") == "bonjour"


def _a_traiter(db, ident, quand, fil="fA", de="tom@messagerie.leboncoin.fr", sujet="Nouveau message Switch",
               echeance=None):
    f = c.fiche(msg(ident, de=de, sujet=sujet, fil=fil, quand=quand))
    c.enregistrer(db, f, {"categorie": "a_traiter", "source": "ia", "raison": "IA", "echeance": echeance}, quand)


def test_ranger_une_ligne_par_conversation_et_expiration():
    db = _base()
    for i in range(3):  # trois messages de Tom dans le même fil
        _a_traiter(db, f"t{i}", MAINTENANT - timedelta(minutes=10 - i))
    _a_traiter(db, "s1", MAINTENANT - timedelta(days=2), fil="fS1", de="seb@messagerie.leboncoin.fr")
    _a_traiter(db, "s2", MAINTENANT - timedelta(hours=1), fil="fS2", de="seb@messagerie.leboncoin.fr")  # autre fil
    _a_traiter(db, "v1", MAINTENANT - timedelta(days=9), fil="fV", de="vieux@x.fr", sujet="Vieux")
    _a_traiter(db, "e1", MAINTENANT - timedelta(days=9), fil="fE", de="enedis@x.fr", sujet="Coupure",
               echeance="2026-11-03")
    assert c.ranger(db, MAINTENANT) == 4
    ouverts = {r["id"] for r in c.lignes(db) if r["categorie"] == "a_traiter"}
    assert ouverts == {"t2", "s2", "e1"}
    raisons = {r["id"]: r["raison"] for r in c.lignes(db)}
    assert raisons["t0"].startswith("remplacé") and raisons["v1"].startswith("expiré")
    assert c.ranger(db, MAINTENANT) == 0


def test_reclasser_ouverts():
    db = _base()
    _a_traiter(db, "a1", MAINTENANT)
    etat = {}
    claude = FauxClaude({"categorie": "bruit", "resume": "Annonce supprimée.", "demande": None, "echeance": None,
                         "confiance": 0.9})
    assert c.reclasser_ouverts(db, claude, etat, 15, MAINTENANT) == 1
    assert {r["id"]: r["categorie"] for r in c.lignes(db)}["a1"] == "bruit"
    assert etat["cout_mois"] > 0


def test_apprentissage_ignore_les_grands_rangements_et_protege_les_vraies_personnes():
    db = _base()
    # 20 lettres d'un même expéditeur, ouvertes et archivées en 4 minutes (boîte vidée) : rien à apprendre
    for i in range(20):
        f = c.fiche(msg(f"m{i}", de="news@journal.fr", quand=MAINTENANT - timedelta(hours=i + 1)))
        c.enregistrer(db, f, {"categorie": "lettre", "source": "gmail", "raison": "liste"}, MAINTENANT)
    gestes = [(f"m{i}", f"fm{i}", g) for i in range(20) for g in ("ouvert", "archive")]
    soir = MAINTENANT + timedelta(hours=4)
    c.appliquer_gestes(db, gestes[:20], soir)
    c.appliquer_gestes(db, gestes[20:], soir + timedelta(minutes=4))
    assert c.apprendre(db, soir) == {}
    # acheteur leboncoin : 4 messages triés à traiter, ouverts, jamais répondus dans Gmail : pas rétrogradé
    for i in range(4):
        _a_traiter(db, f"t{i}", MAINTENANT - timedelta(days=i), fil=f"ft{i}", sujet=f"Message {i}")
        db.execute("UPDATE messages SET ouvert = 1 WHERE id = ?", (f"t{i}",))
    assert "tom@messagerie.leboncoin.fr" not in c.apprendre(db, soir)
    # gestes espacés (un par heure) : l'apprentissage reprend
    db2 = _base()
    for i in range(4):
        f = c.fiche(msg(f"n{i}", de="promo@x.fr", quand=MAINTENANT - timedelta(days=i)))
        c.enregistrer(db2, f, {"categorie": "lettre", "source": "gmail", "raison": "liste"}, MAINTENANT)
        c.appliquer_gestes(db2, [(f"n{i}", f"fn{i}", "archive")], MAINTENANT + timedelta(hours=i))
    assert c.apprendre(db2, MAINTENANT) == {"promo@x.fr": "bruit"}


class FauxLibelles:
    def __init__(self, existants=None):
        self.existants = dict(existants or {})
        self.poses, self.crees = [], []

    def libelles(self):
        return dict(self.existants)

    def creer_libelle(self, nom, couleur=None):
        self.crees.append((nom, couleur))
        self.existants[nom] = f"L_{nom}"
        return self.existants[nom]

    def poser_libelles(self, message_id, ajouter, retirer, autorises):
        assert set(ajouter) | set(retirer) <= set(autorises)
        self.poses.append((message_id, list(ajouter), list(retirer)))


def test_poser_libelles_refuse_tout_autre_libelle():
    http = FauxHttp({})
    gmail = c.ClientGmail(AUTH, http=http)
    for mauvais in (["INBOX"], ["UNREAD"], ["TRASH"], ["Label_9"]):
        try:
            gmail.poser_libelles("m1", [], mauvais, ["L_a", "L_b"])
            raise AssertionError("aurait dû refuser")
        except ValueError:
            pass
    try:
        gmail.creer_libelle("Perso")
        raise AssertionError("aurait dû refuser")
    except ValueError:
        pass
    assert not [a for a in http.appels if a[0] == "POST" and a[1] != c.JETON_URL]


def test_synchroniser_libelles():
    db = _base()
    _a_traiter(db, "t0", MAINTENANT - timedelta(minutes=10))
    _a_traiter(db, "t1", MAINTENANT - timedelta(minutes=5))   # remplace t0
    f = c.fiche(msg("b1", de="promo@x.fr", quand=MAINTENANT - timedelta(hours=1)))
    c.enregistrer(db, f, {"categorie": "bruit", "source": "gmail", "raison": "promo"}, MAINTENANT)
    f = c.fiche(msg("vieux", de="v@x.fr", quand=MAINTENANT - timedelta(days=5)))
    c.enregistrer(db, f, {"categorie": "lettre", "source": "gmail", "raison": "liste"}, MAINTENANT)
    g, etat = FauxLibelles(), {}
    assert c.synchroniser_libelles(g, db, etat, MAINTENANT, journal=lambda t: None) == 3
    assert [n for n, _ in g.crees] == ["Tri", "Tri/À traiter", "Tri/Lettre", "Tri/Bruit"]
    assert sorted(g.poses) == [("b1", ["L_Tri/Bruit"], []), ("t0", ["L_Tri/À traiter"], []),
                               ("t1", ["L_Tri/À traiter"], [])]  # « vieux » : avant les 2 derniers jours
    # t0 remplacé par t1 : son libellé rouge est retiré ; rien d'autre ne bouge
    c.ranger(db, MAINTENANT)
    g.poses.clear()
    assert c.synchroniser_libelles(g, db, etat, MAINTENANT, journal=lambda t: None) == 1
    assert g.poses == [("t0", [], ["L_Tri/À traiter"])]
    assert c.synchroniser_libelles(g, db, etat, MAINTENANT, journal=lambda t: None) == 0


# MARK: - Notifications (25/10)

def test_silence_et_notification():
    assert c.en_silence(MAINTENANT.replace(hour=23)) and c.en_silence(MAINTENANT.replace(hour=7, minute=29))
    assert not c.en_silence(MAINTENANT.replace(hour=7, minute=30)) and not c.en_silence(MAINTENANT.replace(hour=21))
    un = {"id": "a1b2", "fil": "f1", "nom": "Tom CHICHA via leboncoin", "de": "x@y", "resume": "Veut la Switch.",
          "demande": "Lui répondre", "sujet": "s", "message_id": "<abc@leboncoin.fr>"}
    n = c.notification_urgente([un])
    assert n["title"] == "⚠️ Tom CHICHA (leboncoin)" and "→ Lui répondre" in n["message"]
    assert n["data"]["url"] == "readdle-spark://" and "actions" not in n["data"]
    assert c.notification_urgente([un], "gmail")["data"]["url"] == "googlegmail:///cv=f1/accountId=1&create-new-tab"
    assert c.lien_mail(un, "mail") == "message://%3Cabc%40leboncoin.fr%3E"
    assert c.notification_urgente([un, un])["title"] == "⚠️ 2 mails urgents"
    r = c.notification_resume([un] * 9)
    assert r["title"] == "📧 9 mails à traiter" and "… et 1 autre(s)" in r["message"]
    assert c.notification_resume([un])["title"] == "📧 1 mail à traiter"


def test_urgent_vient_de_l_ia():
    assert c.nettoyer_ia({"categorie": "a_traiter", "resume": "x", "demande": None, "echeance": None,
                          "confiance": 0.9, "urgent": True})["urgent"] is True
    assert c.nettoyer_ia({"categorie": "lettre", "resume": "x", "demande": None, "echeance": None,
                          "confiance": 0.9, "urgent": True})["urgent"] is False
    assert "urgent" in c.SCHEMA["required"] and "12 h" in c.CONSIGNE


def _urgent(db, ident, quand, **kw):
    _a_traiter(db, ident, quand, **kw)
    db.execute("UPDATE messages SET urgent = 1 WHERE id = ?", (ident,))
    db.commit()


def test_notifications_a_envoyer_seulement_l_urgent():
    db = _base()
    etat = {}
    midi = MAINTENANT.replace(hour=12)
    assert c.notifications_a_envoyer(db, etat, midi) == ([], [])
    _a_traiter(db, "a1", midi + timedelta(minutes=1))                                   # pas urgent : attend
    _urgent(db, "u1", midi + timedelta(minutes=2), fil="f2", de="b@x.fr", sujet="Autre")
    notifs, ids = c.notifications_a_envoyer(db, etat, midi + timedelta(minutes=3))
    assert ids == ["u1"] and notifs[0]["title"].startswith("⚠️")
    c.noter_notifies(db, ids, etat, midi + timedelta(minutes=3))
    _urgent(db, "u2", midi + timedelta(minutes=5), fil="f3", de="c@x.fr", sujet="Trois")
    assert c.notifications_a_envoyer(db, etat, midi + timedelta(minutes=8)) == ([], [])  # moins de 10 min
    assert c.notifications_a_envoyer(db, etat, midi + timedelta(minutes=14))[1] == ["u2"]
    c.noter_notifies(db, ["u2"], etat, midi + timedelta(minutes=14))
    # résumé de 18 h : le non-urgent resté en attente
    notifs, ids = c.resume_a_envoyer(db, etat, MAINTENANT.replace(hour=18))
    assert ids == ["a1"] and notifs[0]["title"] == "📧 1 mail à traiter"
    c.noter_notifies(db, ids, etat, MAINTENANT.replace(hour=18), urgent=False)
    assert c.resume_a_envoyer(db, etat, MAINTENANT.replace(hour=18, minute=1)) == ([], [])
    # urgent de la nuit : pas de notification immédiate, il part dans le résumé de 9 h
    nuit = MAINTENANT.replace(hour=23)
    _urgent(db, "n1", nuit, fil="fn", de="d@x.fr", sujet="Nuit")
    assert c.notifications_a_envoyer(db, etat, nuit + timedelta(minutes=30)) == ([], [])
    assert c.resume_a_envoyer(db, etat, MAINTENANT.replace(hour=9) + timedelta(days=1))[1] == ["n1"]


def test_actions_de_notification():
    assert c.lire_action("COURRIER_FAIT_1a16cd") == ("fait", "1a16cd")
    assert c.lire_action("COURRIER_TACHE_1a16cd") == ("tache", "1a16cd")
    assert c.lire_action("URI") is None and c.lire_action("COURRIER_FAIT_x;drop") is None
    db = _base()
    _a_traiter(db, "aa1", MAINTENANT - timedelta(minutes=5))
    _a_traiter(db, "aa2", MAINTENANT, sujet="Suite")  # même fil fA
    assert c.marquer_fait(db, "aa2", "fait depuis la notification", MAINTENANT) == 2
    assert {r["categorie"] for r in c.lignes(db)} == {"fait"}
    assert c.marquer_fait(db, "inconnu", "x", MAINTENANT) == 0
    r = {"id": "aa1", "fil": "fA", "nom": "Enedis", "de": "noreply@enedis.fr", "sujet": "Coupure",
         "resume": "Coupure le 3/11.", "demande": "Prévoir la coupure du 3/11", "echeance": "2026-11-03"}
    cle, t = c.tache_du_mail(r, MAINTENANT)
    assert t == {"v": 2, "titre": "Prévoir la coupure du 3/11", "fait": False, "jour": "2026-11-03",
                 "notes": "https://mail.google.com/mail/u/0/#inbox/fA\nCoupure le 3/11.\n📧 Mail de Enedis"}
    assert cle == c.tache_du_mail(r, MAINTENANT)[0]  # même mail, même tâche (pas de doublon)
    t2 = c.tache_du_mail(dict(r, demande=None, echeance=None), MAINTENANT)[1]
    assert t2["titre"] == "Répondre à Enedis : Coupure" and t2["jour"] == "2026-10-24"


# MARK: - Espace `courrier` de donnees_apps (lot C2 de l'app Courrier, 26/10)

class FauxDonnees:
    """`donnees_apps` simulé : `changements` renvoie `self.changements`, `lot` applique et répond `ok` (ou `refuse`
    pour les clés de `self.refuser`)."""

    def __init__(self):
        self.espace, self.seq, self.appels, self.refuser = {}, 0, [], set()
        self.changements = {"enregistrements": [], "seq_max": 0}

    def __call__(self, domaine, action, donnees):
        assert domaine == "donnees_apps" and donnees["espace"] == "courrier"
        self.appels.append((action, donnees))
        if action == "changements":
            return self.changements
        resultats = []
        for op in donnees["operations"]:
            assert op["modifie_par"] == "nuc-courrier" and op["op_id"] and "version_attendue" not in op
            if op["cle"] in self.refuser:
                resultats.append({"statut": "refuse", "raison": "x"})
                continue
            self.seq += 1
            if op["type"] == "ecrire":
                self.espace[op["cle"]] = op["valeur"]
            else:
                self.espace.pop(op["cle"], None)
            resultats.append({"statut": "ok", "cle": op["cle"], "seq": self.seq})
        return {"resultats": resultats, "seq_max": self.seq}

    def lots(self):
        return [d["operations"] for a, d in self.appels if a == "lot"]


def test_valeur_courrier_sans_corps_ni_extrait():
    db = _base()
    _urgent(db, "u1", MAINTENANT, fil="fU", de="Tom <tom@x.fr>")
    db.execute("UPDATE messages SET resume = 'Veut la Switch.', demande = 'Lui répondre', echeance = '2026-10-25' "
               "WHERE id = 'u1'")
    r = c.lignes(db)[0]
    v = c.valeur_courrier(r)
    assert v == {"v": 1, "fil": "fU", "de": "Tom", "adresse": "tom@x.fr", "sujet": "Nouveau message Switch",
                 "date": r["date"], "resume": "Veut la Switch.", "demande": "Lui répondre",
                 "echeance": "2026-10-25", "urgent": True, "raison": "IA"}
    assert "extrait" not in v and r["extrait"] not in json.dumps(v)
    assert c.empreinte(v) == c.empreinte(dict(reversed(list(v.items()))))  # ordre des clés indifférent
    assert c.empreinte(v) != c.empreinte(dict(v, urgent=False))


def test_synchroniser_courrier_differentiel():
    db = _base()
    _a_traiter(db, "a1", MAINTENANT - timedelta(hours=2), fil="f1", de="a@x.fr", sujet="Un")
    _a_traiter(db, "a2", MAINTENANT - timedelta(hours=1), fil="f2", de="b@x.fr", sujet="Deux")
    f = c.fiche(msg("b1", de="promo@x.fr"))
    c.enregistrer(db, f, {"categorie": "bruit", "source": "gmail", "raison": "promo"}, MAINTENANT)
    ha, etat = FauxDonnees(), {}
    r = c.synchroniser_courrier(ha, db, etat, MAINTENANT)
    assert r == {"plus_tard": 0, "corrections": 0, "reclasses": 0, "ecrits": 2, "supprimes": 0, "refuses": 0,
                 "appareils": 0, "essais": []}
    assert set(ha.espace) == {"a1", "a2"} and [o["cle"] for o in ha.lots()[0]] == ["a2", "a1"]  # récents d'abord
    assert etat["courrier_seq"] == 0
    # Rien n'a changé : aucune écriture.
    assert c.synchroniser_courrier(ha, db, etat, MAINTENANT)["ecrits"] == 0 and len(ha.lots()) == 1
    # Le résumé change : seul a1 est réécrit ; a2 devient fait : supprimé (suppressions d'abord).
    db.execute("UPDATE messages SET resume = 'Nouveau résumé' WHERE id = 'a1'")
    c.marquer_fait(db, "a2", "fait", MAINTENANT)
    r = c.synchroniser_courrier(ha, db, etat, MAINTENANT)
    assert (r["ecrits"], r["supprimes"]) == (1, 1)
    assert [(o["type"], o["cle"]) for o in ha.lots()[-1]] == [("supprimer", "a2"), ("ecrire", "a1")]
    assert set(ha.espace) == {"a1"} and ha.espace["a1"]["resume"] == "Nouveau résumé"


def test_synchroniser_courrier_limite_et_refus():
    db = _base()
    for i in range(5):
        _a_traiter(db, f"m{i}", MAINTENANT - timedelta(minutes=i), fil=f"f{i}", de=f"{i}@x.fr", sujet=f"S{i}")
    ha, etat = FauxDonnees(), {}
    ha.refuser = {"m1"}
    r = c.synchroniser_courrier(ha, db, etat, MAINTENANT, limite=3)
    assert (r["ecrits"], r["refuses"]) == (2, 1) and set(ha.espace) == {"m0", "m2"}
    ha.refuser = set()
    c.synchroniser_courrier(ha, db, etat, MAINTENANT, limite=3)
    assert set(ha.espace) == {"m0", "m1", "m2", "m3", "m4"}  # le refusé repart à la passe suivante


def _correction(adresse, categorie, supprime=False):
    return {"cle": f"correction:{adresse}", "valeur": None if supprime else {"categorie": categorie,
                                                                            "quand": "2026-10-24T16:00:00Z"},
            "supprime": supprime}


def test_correction_de_l_app_devient_regle_manuelle_et_reclasse():
    """Lot C4 : « Ce n'est pas du bruit » (→ à traiter) sur un expéditeur : règle `manuel`, mails ouverts reclassés
    (pas les faits), publiés dans l'espace `courrier`, libellés à reposer, puis la clé `correction:` est effacée."""
    db = _base()
    for i in range(3):
        f = c.fiche(msg(f"b{i}", de="Leboncoin <annonces@leboncoin.fr>", fil=f"fb{i}", sujet=f"Annonce {i}",
                        quand=MAINTENANT - timedelta(hours=i + 1)))
        c.enregistrer(db, f, {"categorie": "bruit", "source": "gmail", "raison": "promo"}, MAINTENANT)
    db.execute("UPDATE messages SET libelle = 'Tri/Bruit'")
    db.execute("UPDATE messages SET categorie = 'fait', archive = 1 WHERE id = 'b2'")   # déjà fait : pas reclassé
    ha, etat = FauxDonnees(), {}
    ha.espace["correction:Annonces@Leboncoin.fr"] = {"categorie": "a_traiter"}
    ha.changements = {"enregistrements": [_correction("Annonces@Leboncoin.fr", "a_traiter")], "seq_max": 7}
    r = c.synchroniser_courrier(ha, db, etat, MAINTENANT)
    assert (r["corrections"], r["reclasses"], r["ecrits"]) == (1, 2, 2)
    regle = dict(db.execute("SELECT * FROM regles WHERE expediteur = 'annonces@leboncoin.fr'").fetchone())
    assert regle["categorie"] == "a_traiter" and regle["source"] == "manuel"
    cats = {x["id"]: (x["categorie"], x["source"]) for x in db.execute("SELECT id, categorie, source FROM messages")}
    assert cats["b0"] == ("a_traiter", "regle") and cats["b1"] == ("a_traiter", "regle") and cats["b2"][0] == "fait"
    # La clé lue (telle quelle) est effacée dans le même lot, en premier ; les deux mails sont publiés.
    lot = ha.lots()[-1]
    assert (lot[0]["type"], lot[0]["cle"]) == ("supprimer", "correction:Annonces@Leboncoin.fr")
    assert set(ha.espace) == {"b0", "b1"}
    assert etat["corrections_a_retirer"] == [] and etat["courrier_seq"] == 7
    # Libellés : Tri/Bruit → Tri/À traiter à la prochaine passe de synchroniser_libelles.
    a_poser = {i: (pose, voulu) for i, pose, voulu in c.libelles_a_poser(db, 0)}
    assert a_poser["b0"] == ("Tri/Bruit", "Tri/À traiter")
    # Le prochain mail de l'expéditeur suit la règle manuelle ; l'apprentissage ne l'écrase pas.
    assert c.decider(c.fiche(msg("b9", de="annonces@leboncoin.fr")), c.regles(db))["categorie"] == "a_traiter"
    c.apprendre(db, MAINTENANT)
    assert db.execute("SELECT source FROM regles WHERE expediteur = 'annonces@leboncoin.fr'").fetchone()[0] == "manuel"


def test_correction_effacement_refuse_repart():
    db = _base()
    ha, etat = FauxDonnees(), {}
    ha.refuser = {"correction:x@y.fr"}
    ha.changements = {"enregistrements": [_correction("x@y.fr", "lettre"), _correction("z@y.fr", "inconnue")],
                      "seq_max": 3}
    r = c.synchroniser_courrier(ha, db, etat, MAINTENANT)
    assert r["corrections"] == 1   # catégorie inconnue ignorée (mais sa clé est effacée)
    assert etat["corrections_a_retirer"] == ["correction:x@y.fr"]
    assert db.execute("SELECT categorie FROM regles WHERE expediteur = 'x@y.fr'").fetchone()[0] == "lettre"
    # Passe suivante, sans nouveau changement : l'effacement refusé repart.
    ha.refuser, ha.changements = set(), {"enregistrements": [], "seq_max": 3}
    c.synchroniser_courrier(ha, db, etat, MAINTENANT)
    assert [o["cle"] for o in ha.lots()[-1]] == ["correction:x@y.fr"] and etat["corrections_a_retirer"] == []
    # Une suppression vue dans les changements (la nôtre) n'est pas une correction.
    ha.changements = {"enregistrements": [_correction("x@y.fr", None, supprime=True)], "seq_max": 4}
    assert c.synchroniser_courrier(ha, db, etat, MAINTENANT)["corrections"] == 0


def test_correction_vers_lettre_retire_de_l_espace():
    db = _base()
    _a_traiter(db, "a1", MAINTENANT - timedelta(hours=1), fil="f1", de="news@journal.fr", sujet="Lettre")
    ha, etat = FauxDonnees(), {}
    c.synchroniser_courrier(ha, db, etat, MAINTENANT)
    assert set(ha.espace) == {"a1"}
    ha.changements = {"enregistrements": [_correction("news@journal.fr", "lettre")], "seq_max": 2}
    r = c.synchroniser_courrier(ha, db, etat, MAINTENANT)
    assert (r["reclasses"], r["supprimes"]) == (1, 1) and set(ha.espace) == set()


def _plus_tard(cle, jusqua=None, supprime=False):
    return {"cle": f"plus_tard:{cle}", "valeur": None if supprime else {"jusqua": jusqua}, "supprime": supprime}


def test_plus_tard_retient_la_notification_puis_revient_au_resume():
    db = _base()
    midi = MAINTENANT.replace(hour=12)
    etat = {"notif_depuis": (midi - timedelta(hours=1)).isoformat(timespec="seconds")}
    _urgent(db, "u1", midi, fil="fu", de="u@x.fr", sujet="Urgent")
    _a_traiter(db, "a1", midi, fil="fa", de="a@x.fr", sujet="Normal")
    ha = FauxDonnees()
    ha.changements = {"enregistrements": [
        _plus_tard("u1", "2026-10-24T16:00:00Z"),           # 18 h à Paris (« Ce soir »)
        _plus_tard("a1", "2026-10-25T09:00:00+02:00"),      # demain 9 h
        {"cle": "u1", "valeur": {"v": 1}, "supprime": False},  # clé du NUC : ignorée
    ], "seq_max": 7}
    assert c.synchroniser_courrier(ha, db, etat, midi)["plus_tard"] == 2 and etat["courrier_seq"] == 7
    # (a) Pas de notification avant l'heure, ni immédiate ni dans le résumé de 12 h.
    assert c.notifications_a_envoyer(db, etat, midi + timedelta(minutes=5)) == ([], [])
    assert c.resume_a_envoyer(db, etat, midi.replace(hour=12, minute=1)) == ([], [])
    # (b) Au résumé de 18 h : u1 revient (même déjà notifié), a1 reste de côté.
    db.execute("UPDATE messages SET notifie = '2026-10-24T08:00:00+02:00' WHERE id = 'u1'")
    db.commit()
    soir = MAINTENANT.replace(hour=18)
    notifs, ids = c.resume_a_envoyer(db, etat, soir)
    assert ids == ["u1"] and notifs[0]["title"] == "📧 1 mail à traiter"
    c.noter_notifies(db, ids, etat, soir, urgent=False)
    c.noter_rappeles(db, ids, soir)
    assert c.resume_a_envoyer(db, etat, soir + timedelta(minutes=1)) == ([], [])  # rappelé une seule fois
    # Le lendemain 9 h : a1 revient.
    assert c.resume_a_envoyer(db, etat, MAINTENANT.replace(hour=9) + timedelta(days=1))[1] == ["a1"]


def test_plus_tard_retire_par_l_app():
    db = _base()
    midi = MAINTENANT.replace(hour=12)
    for i in ("p1", "p2", "p3"):
        _a_traiter(db, i, midi, fil=f"f{i}", de=f"{i}@x.fr", sujet=i)
    ha, etat = FauxDonnees(), {}
    ha.changements = {"enregistrements": [_plus_tard("p1", "2026-10-24T16:00:00Z"),
                                          _plus_tard("p2", "2026-10-24T09:00:00Z"),
                                          _plus_tard("p3", "pas une date")], "seq_max": 3}
    c.synchroniser_courrier(ha, db, etat, midi)
    assert c.mis_de_cote(db, midi) == {"p1"} and [r["id"] for r in c.plus_tard_revenus(db, midi)] == ["p2"]
    # L'app retire les deux : p1 (à venir) est annulé ; p2 (échu, pas encore rappelé) attend son résumé.
    ha.changements = {"enregistrements": [_plus_tard("p1", supprime=True), _plus_tard("p2", supprime=True)],
                      "seq_max": 5}
    c.synchroniser_courrier(ha, db, etat, midi)
    assert c.mis_de_cote(db, midi) == set() and [r["id"] for r in c.plus_tard_revenus(db, midi)] == ["p2"]
    assert [d for a, d in ha.appels if a == "changements"][-1] == {"espace": "courrier", "depuis_seq": 3}
    # Le mail traité perd son « Plus tard ».
    c.marquer_fait(db, "p2", "fait", midi)
    c.appliquer_plus_tard(db, {"enregistrements": []}, midi)
    assert c.plus_tard_revenus(db, midi) == []
    # Resynchro complète : ce qui n'est plus sur le serveur est oublié.
    c.appliquer_plus_tard(db, {"enregistrements": [_plus_tard("p3", "2026-10-25T07:00:00Z")]}, midi)
    c.appliquer_plus_tard(db, {"enregistrements": [_plus_tard("p1", "2026-10-25T07:00:00Z")],
                               "resynchro_complete": True}, midi)
    assert c.mis_de_cote(db, midi) == {"p1"}


# MARK: - Notifications directes à l'app Courrier (lot C5, 26/10)

JETON_A, JETON_B = "a1" * 32, "b2" * 32


def _appareil(ident, jeton=JETON_A, env="sandbox", supprime=False):
    return {"cle": f"appareil:{ident}", "supprime": supprime,
            "valeur": None if supprime else {"jeton": jeton, "environnement": env, "app_version": "0.1 (1)",
                                             "maj": "2026-10-26T20:00:00Z"}}


def _essai(ident, quand="2026-10-24T15:58:00Z"):
    return {"cle": f"essai_notification:{ident}", "valeur": {"appareil": ident, "quand": quand}, "supprime": False}


def test_appareils_lus_dans_l_espace():
    db = _base()
    rep = {"enregistrements": [_appareil("iphone"), _appareil("ipad", JETON_B, "production"),
                               _appareil("abime", "pas-hexa"), _appareil("autre", JETON_A, "beta"),
                               {"cle": "a1", "valeur": {"v": 1}, "supprime": False}]}
    assert c.appliquer_appareils(db, rep, MAINTENANT) == 2
    assert [(a["cle"], a["environnement"]) for a in c.appareils(db)] == [("appareil:ipad", "production"),
                                                                        ("appareil:iphone", "sandbox")]
    assert c.appliquer_appareils(db, {"enregistrements": [_appareil("iphone")]}, MAINTENANT) == 0  # inchangé
    assert c.appliquer_appareils(db, {"enregistrements": [_appareil("iphone", JETON_B)]}, MAINTENANT) == 1
    assert c.appliquer_appareils(db, {"enregistrements": [_appareil("ipad", supprime=True)]}, MAINTENANT) == 1
    assert [a["jeton"] for a in c.appareils(db)] == [JETON_B]
    # Resynchro complète : un appareil absent du serveur est oublié.
    c.appliquer_appareils(db, {"enregistrements": [], "resynchro_complete": True}, MAINTENANT)
    assert c.appareils(db) == []


def test_choix_du_canal():
    assert c.par_ha("auto", 0, 0) is True             # pas d'appareil Courrier : app HA (comportement d'avant C5)
    assert c.par_ha("auto", 1, 1) is False            # Courrier reçoit : plus d'app HA
    assert c.par_ha("auto", 2, 0) is True             # tous les envois APNs ont échoué : repli
    assert c.par_ha("toujours", 1, 1) is True and c.par_ha("jamais", 0, 0) is False


def test_payloads():
    un = {"title": "⚠️ Tom", "message": "Veut la Switch.\n→ Lui répondre", "data": {}}
    charge, collapse = c.push_courrier(un, [{"id": "1a2b", "fil": "f9"}], MAINTENANT)
    assert charge == {"aps": {"alert": {"title": "⚠️ Tom", "body": "Veut la Switch.\n→ Lui répondre"},
                              "thread-id": "courrier", "sound": "default"},
                      "courrier": {"type": "mail", "id": "1a2b", "fil": "f9"}}
    assert collapse == "1a2b" and "actions" not in json.dumps(charge) and "category" not in charge["aps"]
    plusieurs = [{"id": "x", "fil": "fx"}, {"id": "y", "fil": "fy"}]
    charge, collapse = c.push_courrier(un, plusieurs, MAINTENANT.replace(hour=9, minute=0), resume=True)
    assert charge["courrier"] == {"type": "resume"} and collapse == "resume-09"
    assert c.push_courrier(un, plusieurs, MAINTENANT.replace(hour=14, minute=7))[1] == "urgent-1407"
    essai, collapse = c.push_essai()
    assert essai["courrier"] == {"type": "resume"} and collapse == "essai" and essai["aps"]["thread-id"] == "courrier"


class FauxApple:
    """APNs simulé : un statut par jeton (200 par défaut)."""

    def __init__(self, statuts=None):
        self.statuts, self.envois = statuts or {}, []

    def __call__(self, appareil, charge, collapse_id):
        self.envois.append((appareil["jeton"], appareil["environnement"], charge, collapse_id))
        return self.statuts.get(appareil["jeton"], (200, ""))


def test_diffusion_courrier_puis_repli_ha():
    db = _base()
    _urgent(db, "u1", MAINTENANT, fil="fu")
    notif = c.notification_urgente([dict(db.execute("SELECT * FROM messages WHERE id = 'u1'").fetchone())])
    ha_envois = []

    def ha(notifs):
        ha_envois.append(notifs)
        return 1

    # (1) Aucun appareil Courrier : l'app HA, comme avant.
    apple, etat = FauxApple(), {}
    assert c.diffuser(db, etat, [notif], ["u1"], MAINTENANT, apple, ha, journal=lambda t: None) == 1
    assert apple.envois == [] and len(ha_envois) == 1
    # (2) Un appareil : APNs seulement, payload « mail ».
    c.appliquer_appareils(db, {"enregistrements": [_appareil("iphone")]}, MAINTENANT)
    assert c.diffuser(db, etat, [notif], ["u1"], MAINTENANT, apple, ha, journal=lambda t: None) == 1
    assert len(ha_envois) == 1 and apple.envois[0][1] == "sandbox" and apple.envois[0][3] == "u1"
    assert apple.envois[0][2]["courrier"] == {"type": "mail", "id": "u1", "fil": "fu"}
    # (3) `toujours` : les deux ; (4) sans Key ID : repli HA.
    c.diffuser(db, etat, [notif], ["u1"], MAINTENANT, apple, ha, reglage="toujours", journal=lambda t: None)
    assert len(ha_envois) == 2
    c.diffuser(db, etat, [notif], ["u1"], MAINTENANT, apple, ha, apns_pret=False, journal=lambda t: None)
    assert len(ha_envois) == 3
    # (5) Apple injoignable : repli HA, l'appareil est gardé.
    panne = FauxApple({JETON_A: (0, "ConnectError")})
    assert c.diffuser(db, etat, [notif], ["u1"], MAINTENANT, panne, ha, journal=lambda t: None) == 1
    assert len(ha_envois) == 4 and len(c.appareils(db)) == 1
    # (6) `jamais` et Apple en panne : rien ne part (0), le mail sera repris.
    assert c.diffuser(db, etat, [notif], ["u1"], MAINTENANT, panne, ha, reglage="jamais", journal=lambda t: None) == 0


def test_jeton_refuse_retire_l_appareil_et_sa_cle():
    db = _base()
    _a_traiter(db, "a1", MAINTENANT, fil="f1")
    c.appliquer_appareils(db, {"enregistrements": [_appareil("vieux", JETON_A), _appareil("bon", JETON_B, "production"),
                                                   _appareil("autre", "c3" * 32)]}, MAINTENANT)
    apple = FauxApple({JETON_A: (410, "Unregistered"), "c3" * 32: (400, "BadDeviceToken")})
    etat, journal = {}, []
    notif = c.notification_resume([{"nom": "Tom", "resume": "x"}])
    assert c.diffuser(db, etat, [notif], ["a1"], MAINTENANT, apple, lambda n: 99, resume=True, journal=journal.append) == 1
    assert [a["cle"] for a in c.appareils(db)] == ["appareil:bon"]
    assert etat["corrections_a_retirer"] == ["appareil:autre", "appareil:vieux"]
    assert any("APNs 410 Unregistered" in t for t in journal) and not any(JETON_A in t for t in journal)
    # À la passe suivante, les clés sont effacées de l'espace (en premier dans le lot).
    ha = FauxDonnees()
    ha.espace.update({"appareil:vieux": {}, "appareil:autre": {}})
    c.synchroniser_courrier(ha, db, etat, MAINTENANT)
    assert [o["cle"] for o in ha.lots()[-1][:2]] == ["appareil:autre", "appareil:vieux"]
    assert "appareil:vieux" not in ha.espace and etat["corrections_a_retirer"] == []


def test_essai_de_notification():
    db = _base()
    ha, etat = FauxDonnees(), {}
    ha.espace["essai_notification:iphone"] = {}
    ha.changements = {"enregistrements": [_appareil("iphone"), _essai("iphone"),
                                          _essai("ancien", "2026-10-24T15:00:00Z")], "seq_max": 4}
    r = c.synchroniser_courrier(ha, db, etat, MAINTENANT)        # 18 h à Paris = 16 h UTC
    assert r["appareils"] == 1 and r["essais"] == ["appareil:iphone"]   # l'essai d'il y a une heure est ignoré
    assert {o["cle"] for o in ha.lots()[-1]} >= {"essai_notification:iphone", "essai_notification:ancien"}
    assert "essai_notification:iphone" not in ha.espace
    apple = FauxApple()
    charge, collapse = c.push_essai()
    assert c.pousser(db, etat, c.appareils(db), charge, collapse, apple) == 1 and apple.envois[0][3] == "essai"


def test_espace_courrier_ignore_appareils_et_essais_dans_les_mails():
    """Les clés de l'app (appareil, essai) ne sont ni des « Plus tard » ni des corrections, et le NUC ne les publie
    jamais comme des mails."""
    db = _base()
    rep = {"enregistrements": [_appareil("iphone"), _essai("iphone")]}
    assert c.appliquer_plus_tard(db, rep, MAINTENANT) == 0 and c.lire_corrections(rep) == ({}, set())
    assert c.operations_courrier(db) == []


def test_cle_apns_lue_dans_le_bloc_de_la_vigie():
    texte = ("relance_vigie:\n  module: relance_vigie\n  team_id: GD6W292ZXP\n  key_id: ABCDE12345\n"
             "  key_path: /config/apps/AuthKey_relance.p8\n\naiguillage_courrier:\n  module: aiguillage_courrier\n")
    assert c.cle_apns_de_la_vigie(texte) == {"team_id": "GD6W292ZXP", "key_id": "ABCDE12345",
                                             "key_path": "/config/apps/AuthKey_relance.p8"}
    assert c.cle_apns_de_la_vigie("autre:\n  module: x\n") == {}


def test_mail_a_soi_meme_est_un_pense_bete():
    f = c.fiche(msg("s1", de="Alexandre Fau <alexandre.fau@gmail.com>", sujet="Test avec accent éî", corps="Teet"))
    assert c.a_soi_meme(f)
    d = c.decider(f, {"alexandre.fau@gmail.com": "bruit"})
    assert d["categorie"] == "a_traiter" and d["ia"] and d["raison"].startswith("mail à soi-même")
    assert c.a_soi_meme(dict(f, de="alexandre.fau+malt@gmail.com"))
    assert not c.a_soi_meme(c.fiche(msg("s2")))
    # envoyé à soi-même (SENT + INBOX) : pas un geste « répondu »
    nouveaux, gestes = c.lire_historique([{"messagesAdded": [
        {"message": {"id": "s1", "threadId": "fs", "labelIds": ["SENT", "INBOX", "UNREAD"]}}]}])
    assert nouveaux == ["s1"] and gestes == []
    _, gestes = c.lire_historique([{"messagesAdded": [{"message": {"id": "r", "threadId": "fx", "labelIds": ["SENT"]}}]}])
    assert gestes == [(None, "fx", "repondu")]
