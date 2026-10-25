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
    assert r == {"categorie": "a_traiter", "resume": "Facture EDF.", "demande": None, "echeance": None, "confiance": 1.0}
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
    n = c.notification(un)
    assert n["title"] == "📧 Tom CHICHA (leboncoin)" and "→ Lui répondre" in n["message"]
    assert n["data"]["url"] == "googlegmail:///cv=f1/accountId=1&create-new-tab"
    assert [a["title"] for a in n["data"]["actions"]] == ["Fait", "En faire une tâche", "Ouvrir"]
    assert n["data"]["actions"][0]["action"] == "COURRIER_FAIT_a1b2"
    assert c.notification(un, "mail")["data"]["url"] == "message://%3Cabc%40leboncoin.fr%3E"
    assert c.lien_mail(dict(un, message_id=""), "mail").startswith("googlegmail:")  # repli sans Message-ID
    r = c.resume_notifications([un] * 9)
    assert r["title"] == "📧 9 mails à traiter" and "… et 1 autre(s)" in r["message"]


def test_notifications_a_envoyer():
    db = _base()
    etat = {}
    midi = MAINTENANT.replace(hour=12)
    assert c.notifications_a_envoyer(db, etat, midi) == ([], [])
    assert etat["notif_depuis"] == midi.isoformat(timespec="seconds")  # rien d'avant la mise en route
    _a_traiter(db, "a1", midi + timedelta(minutes=1))
    _a_traiter(db, "a2", midi + timedelta(minutes=2), fil="f2", de="b@x.fr", sujet="Autre")
    notifs, ids = c.notifications_a_envoyer(db, etat, midi + timedelta(minutes=3))
    assert len(notifs) == 2 and sorted(ids) == ["a1", "a2"]  # une par mail
    c.noter_notifies(db, ids, etat, midi + timedelta(minutes=3))
    _a_traiter(db, "a3", midi + timedelta(minutes=5), fil="f3", de="c@x.fr", sujet="Trois")
    assert c.notifications_a_envoyer(db, etat, midi + timedelta(minutes=8)) == ([], [])  # moins de 10 min
    notifs, ids = c.notifications_a_envoyer(db, etat, midi + timedelta(minutes=14))
    assert ids == ["a3"]
    c.noter_notifies(db, ids, etat, midi + timedelta(minutes=14))
    nuit = MAINTENANT.replace(hour=23)
    for i in range(6):
        _a_traiter(db, f"n{i}", nuit, fil=f"fn{i}", de=f"d{i}@x.fr", sujet=f"Nuit {i}")
    assert c.notifications_a_envoyer(db, etat, nuit + timedelta(minutes=30)) == ([], [])
    notifs, ids = c.notifications_a_envoyer(db, etat, MAINTENANT.replace(hour=7, minute=32) + timedelta(days=1))
    assert len(ids) == 6 and len(notifs) == 1 and notifs[0]["title"] == "📧 6 mails à traiter"  # résumé du matin


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
