"""Tests hors Home Assistant de `aiguillage_signal` : python3 homeassistant/appdaemon/tests/test_aiguillage_signal.py"""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import aiguillage_signal as s  # noqa: E402

COMPTE = "+33600000001"
YOANN = "+33600000002"
SOURCES = {YOANN: "Yoann"}


def test_liens_spotify():
    # Texte collé derrière l'identifiant (19/10) : les 22 premiers caractères.
    assert s.ref_lien("https://open.spotify.com/track/4W6n5MoDbQmPhaZHx4MFSzb52c4f4a")["lien"] == \
        "https://open.spotify.com/track/4W6n5MoDbQmPhaZHx4MFSz"
    assert s.ref_lien("https://open.spotify.com/track/5rSkTcePXM5wBURKo1tj56?si=abc") == {
        "type": "ecouter", "plateforme": "spotify", "id_titre": "track:5rSkTcePXM5wBURKo1tj56",
        "lien": "https://open.spotify.com/track/5rSkTcePXM5wBURKo1tj56"}
    assert s.ref_lien("https://open.spotify.com/intl-fr/album/1ATL5GLyefJaxhQzSPVrLX")["id_titre"] == "album:1ATL5GLyefJaxhQzSPVrLX"
    assert s.ref_lien("https://open.spotify.com/episode/abc123")["type"] == "ecouter"
    assert s.ref_lien("https://open.spotify.com/user/xyz") is None
    assert s.ref_lien("https://www.netflix.com/title/1") is None


def test_liens_youtube():
    attendu = {"type": "regarder", "plateforme": "youtube", "id_titre": "dQw4w9WgXcQ",
               "lien": "https://www.youtube.com/watch?v=dQw4w9WgXcQ"}
    assert s.ref_lien("https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=xyz&t=42") == attendu
    assert s.ref_lien("https://youtu.be/dQw4w9WgXcQ?si=xyz") == attendu
    assert s.ref_lien("https://m.youtube.com/watch?v=dQw4w9WgXcQ") == attendu
    assert s.ref_lien("https://youtube.com/shorts/dQw4w9WgXcQ")["id_titre"] == "dQw4w9WgXcQ"
    musique = s.ref_lien("https://music.youtube.com/watch?v=dQw4w9WgXcQ&feature=share")
    assert musique["type"] == "ecouter" and musique["plateforme"] == "youtube_music"
    assert s.ref_lien("https://www.youtube.com/@chaine") is None
    assert s.ref_lien("https://www.youtube.com/watch") is None


def test_refs_dans_un_message():
    texte = ("Écoute ça https://open.spotify.com/track/A1?si=x, et regarde https://youtu.be/dQw4w9WgXcQ. "
             "Encore : https://open.spotify.com/track/A1 et https://lemonde.fr/article")
    liens = [r["lien"] for r in s.refs(texte)]
    assert liens == ["https://open.spotify.com/track/A1", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"]
    assert s.refs("pas de lien") == [] and s.refs(None) == []
    assert s.sans_liens("Écoute ça\nhttps://open.spotify.com/track/A1 !") == "Écoute ça !"
    assert s.sans_liens("https://open.spotify.com/track/A1") == ""


def test_message_retenu():
    recu = {"envelope": {"sourceNumber": YOANN, "dataMessage": {"message": "https://open.spotify.com/track/A1"}}}
    assert s.message_retenu(recu, COMPTE, SOURCES) == ("https://open.spotify.com/track/A1", "Yoann")
    # Forme JSON-RPC (params) acceptée aussi.
    assert s.message_retenu({"jsonrpc": "2.0", "method": "receive", "params": recu}, COMPTE, SOURCES)[1] == "Yoann"
    # Inconnu, accusé de lecture, frappe : ignorés.
    assert s.message_retenu({"envelope": {"sourceNumber": "+33699999999", "dataMessage": {"message": "x"}}}, COMPTE, SOURCES) is None
    assert s.message_retenu({"envelope": {"sourceNumber": YOANN, "receiptMessage": {}}}, COMPTE, SOURCES) is None
    assert s.message_retenu("texte", COMPTE, SOURCES) is None
    # Note à soi-même : retenue (sans nom), sauf si désactivée ; un message envoyé à quelqu'un d'autre : ignoré.
    note = {"envelope": {"sourceNumber": COMPTE, "syncMessage": {"sentMessage": {"destinationNumber": COMPTE, "message": "https://youtu.be/dQw4w9WgXcQ"}}}}
    assert s.message_retenu(note, COMPTE, SOURCES) == ("https://youtu.be/dQw4w9WgXcQ", None)
    assert s.message_retenu(note, COMPTE, SOURCES, note_a_soi=False) is None
    envoye = {"envelope": {"sourceNumber": COMPTE, "syncMessage": {"sentMessage": {"destinationNumber": YOANN, "message": "x"}}}}
    assert s.message_retenu(envoye, COMPTE, SOURCES) is None


def test_tache():
    ref = s.ref_lien("https://open.spotify.com/track/A1?si=x")
    t = s.tache(ref, "Spaceships · Artiste", "Écoute ça https://open.spotify.com/track/A1?si=x", "Yoann")
    assert t == {
        "v": 2, "titre": "Spaceships · Artiste", "fait": False,
        "notes": "https://open.spotify.com/track/A1\nÉcoute ça\n🎧 À écouter · Proposé par Yoann",
        "envie": {"type": "ecouter", "plateforme": "spotify", "id_titre": "track:A1",
                  "lien": "https://open.spotify.com/track/A1", "note": "Proposé par Yoann"},
    }
    video = s.tache(s.ref_lien("https://youtu.be/dQw4w9WgXcQ"), None, "https://youtu.be/dQw4w9WgXcQ")
    assert video["titre"] == "Vidéo YouTube"
    assert video["notes"] == "https://www.youtube.com/watch?v=dQw4w9WgXcQ\n🎬 À regarder"
    assert "note" not in video["envie"]


def test_cle_stable():
    a = s.ref_lien("https://open.spotify.com/track/A1?si=1")
    b = s.ref_lien("https://open.spotify.com/intl-fr/track/A1?si=2")
    assert s.cle(a) == s.cle(b)
    assert s.cle(a) != s.cle(s.ref_lien("https://open.spotify.com/track/B2"))
    assert len(s.cle(a)) == 36


def test_titres():
    assert s.titre_spotify("track", {"name": "Spaceships", "artists": [{"name": "A"}, {"name": "B"}]}) == "Spaceships · A, B"
    assert s.titre_spotify("episode", {"name": "Épisode 3", "show": {"name": "Podcast"}}) == "Épisode 3 · Podcast"
    assert s.titre_spotify("playlist", {"name": "Été"}) == "Été"
    assert s.titre_spotify("track", {}) is None
    assert s.titre_youtube({"title": "Clip", "author_name": "Chaîne"}) == "Clip · Chaîne"
    assert s.titre_youtube({}) is None


def test_question_a_l_agent():
    # « ? » au début, espaces tolérés (N5, 27/10).
    assert s.question_agent("?qu'est-ce que j'ai à traiter") == "qu'est-ce que j'ai à traiter"
    assert s.question_agent("  ? qu'est-ce que j'ai\nà traiter ") == "qu'est-ce que j'ai\nà traiter"
    assert s.question_agent("？ et celui d'hier ?") == "et celui d'hier ?"
    assert s.question_agent("?") == ""
    assert s.question_agent("demain télétravail ?") is None
    assert s.question_agent(None) is None


def test_routage():
    # Note à moi-même : « ? » → l'agent seul, même avec un lien (ni envie ni consigne de lieu).
    assert s.routage("? qu'est-ce que j'ai à traiter", None) == ("agent", "qu'est-ce que j'ai à traiter")
    assert s.routage("?résume https://youtu.be/dQw4w9WgXcQ", None) == ("agent", "résume https://youtu.be/dQw4w9WgXcQ")
    assert s.routage("?", None) == ("rien", None)
    # Les réponses de l'agent (envoyées dans la même note) ne sont jamais retraitées.
    assert s.routage("🤖 Tu as 2 mails : https://youtu.be/dQw4w9WgXcQ", None) == ("rien", None)
    # Le reste ne change pas : liens → envies, note sans lien → lieu de travail.
    route, liens = s.routage("https://youtu.be/dQw4w9WgXcQ", None)
    assert route == "envies" and liens[0]["id_titre"] == "dQw4w9WgXcQ"
    assert s.routage("demain télétravail", None) == ("lieu", "demain télétravail")
    assert s.routage("   ", None) == ("rien", None)
    # Un proche qui écrit « ? … » ne parle pas à l'agent.
    assert s.routage("? tu viens samedi", "Yoann") == ("rien", None)
    assert s.routage("? https://youtu.be/dQw4w9WgXcQ", "Yoann")[0] == "envies"


if __name__ == "__main__":
    for nom, f in list(globals().items()):
        if nom.startswith("test_"):
            f()
    print("ok")
