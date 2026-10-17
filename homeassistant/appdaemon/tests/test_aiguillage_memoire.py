"""Tests hors Home Assistant de `aiguillage_memoire` (plan P9-J) : python3 -m pytest homeassistant/appdaemon/tests

Numéros et messages fictifs uniquement (dépôt public)."""

from datetime import date, datetime
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import aiguillage_memoire as m  # noqa: E402

MOI, AMI, AUTRE = "+33600000000", "+33611111111", "+33622222222"
CONV = {AMI: "Paul"}
TS = int(datetime(2026, 10, 17, 18, 30, tzinfo=m.PARIS).timestamp() * 1000)


def recu(texte="", ts=TS, **data):
    return {"jsonrpc": "2.0", "method": "receive", "params": {"envelope": {
        "sourceNumber": AMI, "timestamp": ts, "dataMessage": {"timestamp": ts, "message": texte, **data}}}}


def envoye(texte, dest=AMI, ts=TS + 1000, **data):
    return {"envelope": {"sourceNumber": MOI, "timestamp": ts, "syncMessage": {"sentMessage": {
        "destinationNumber": dest, "timestamp": ts, "message": texte, **data}}}}


def lire(n):
    return m.lire_notification(n, MOI, CONV)


def test_lecture_des_notifications():
    op = lire(recu("Le resto Chez Tonton est top", quote={"id": 1, "text": "Une idée de resto ?"}))
    assert op["op"] == "ajout" and op["auteur"] == "Paul" and op["sens"] == "recu"
    assert op["citation"] == "Une idée de resto ?" and op["pieces"] == []
    op = lire(envoye("Merci !"))
    assert op["auteur"] == m.MOI and op["sens"] == "envoye" and op["conversation"] == "Paul"
    assert lire(envoye("Note à moi", dest=MOI)) is None
    assert lire(envoye("À un autre", dest=AUTRE)) is None
    assert lire(recu("Dans un groupe", groupInfo={"groupId": "g"})) is None
    assert lire(recu("")) is None  # réaction, accusé…
    autre = recu("Inconnu")
    autre["params"]["envelope"]["sourceNumber"] = AUTRE
    assert lire(autre) is None


def test_pieces_modif_suppression():
    op = lire(recu("", attachments=[{"contentType": "image/jpeg", "id": "p1.jpg", "size": 10},
                                    {"contentType": "audio/aac", "voiceNote": True, "id": "v1.aac"}]))
    assert [p["type"] for p in op["pieces"]] == ["photo", "note vocale"]
    modif = {"envelope": {"sourceNumber": AMI, "editMessage": {"targetSentTimestamp": TS,
                                                               "dataMessage": {"message": "Corrigé"}}}}
    assert lire(modif) == {"op": "modif", "conversation": "Paul", "ts": TS, "auteur": "Paul", "texte": "Corrigé"}
    supp = lire(recu(remoteDelete={"timestamp": TS}))
    assert supp["op"] == "suppression" and supp["ts"] == TS


def test_base_recherche_et_doublons():
    db = m.ouvrir(":memory:")
    assert m.appliquer(db, lire(recu("Bonjour")))
    assert m.appliquer(db, lire(recu("Le resto Chez Tonton, rue de l'Exemple, est génial", ts=TS + 10)))
    assert m.appliquer(db, lire(envoye("Je note, merci", ts=TS + 20)))
    assert not m.appliquer(db, lire(recu("Bonjour")))  # même message reçu deux fois
    assert m.compter(db) == 3
    trouve = m.chercher(db, "resto tonton")
    assert len(trouve["messages"]) == 1
    msg = trouve["messages"][0]
    assert msg["auteur"] == "Paul" and msg["quand"] == "2026-10-17 18:30"
    assert [c["texte"] for c in msg["contexte"]] == ["Bonjour", "Je note, merci"]
    assert m.chercher(db, "genial")["messages"] or not m.fts(db)  # accents ignorés avec FTS5
    # Sans mot : les derniers messages, ou ceux d'un jour.
    assert [x["texte"] for x in m.chercher(db, "")["messages"]][-1] == "Je note, merci"
    assert len(m.chercher(db, "*", limite=2)["messages"]) == 2
    assert len(m.chercher(db, "a", jour="2026-10-17")["messages"]) == 3
    assert m.chercher(db, "", jour="2026-10-16")["messages"] == []
    # Modification puis suppression : l'index suit.
    m.appliquer(db, {"op": "modif", "conversation": "Paul", "ts": TS + 10, "auteur": "Paul", "texte": "Plutôt la crêperie"})
    assert not m.chercher(db, "tonton")["messages"] and m.chercher(db, "crêperie")["messages"]
    m.appliquer(db, {"op": "suppression", "conversation": "Paul", "ts": TS + 10, "auteur": "Paul"})
    assert m.compter(db) == 2 and not m.chercher(db, "crêperie")["messages"]


def test_resumes_et_purges():
    db = m.ouvrir(":memory:")
    vieux = TS - 400 * 86_400_000
    m.appliquer(db, lire(recu("Ancien message", ts=vieux, attachments=[{"contentType": "image/png", "id": "a.png"}])))
    m.appliquer(db, lire(recu("Récent", ts=TS)))
    jour = m.jour_de(vieux)
    assert m.conversations_du_jour(db, jour) == ["Paul"]
    texte = m.texte_jour("Paul", jour, m.messages_du_jour(db, "Paul", jour))
    assert "Paul : Ancien message [photo]" in texte
    assert m.purger_textes(db, date(2026, 10, 17)) == 0  # pas encore résumé : on garde
    m.enregistrer_resume(db, "jour", "Paul", jour, {"resume": "Une photo.", "faits": [{"type": "info", "texte": "x",
                                                                                         "quand": ""}],
                                                       "mots_cles": ["photo"]}, "2026-10-17T03:00:00Z")
    assert m.chercher(db, "photo")["resumes"][0]["periode"] == jour
    assert m.purger_textes(db, date(2026, 10, 17)) == 1 and m.compter(db) == 1
    assert m.pieces_a_purger(db, TS) == ["a.png"]
    m.piece_purgee(db, "a.png")
    assert m.pieces_a_purger(db, TS) == []
    assert m.resumes(db, "jour", "Paul", jour, jour)[0]["resume"] == "Une photo."


def test_periodes_et_cles():
    assert m.semaine_precedente(date(2026, 10, 19)) == (date(2026, 10, 12), date(2026, 10, 18), "2026-W42")
    assert m.mois_precedent(date(2026, 11, 1)) == (date(2026, 10, 1), date(2026, 10, 31), "2026-10")
    assert m.cle_donnees("Paul Éric", "jour", "2026-10-17") == "paul-eric-jour-2026-10-17"


def test_schema():
    assert m.SCHEMA["additionalProperties"] is False
    assert set(m.SCHEMA["required"]) == set(m.SCHEMA["properties"])


if __name__ == "__main__":
    for nom, f in list(globals().items()):
        if nom.startswith("test_"):
            f()
    print("ok")
