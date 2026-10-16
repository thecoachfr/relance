"""Tests hors Home Assistant de `aiguillage_spotify` : python3 homeassistant/appdaemon/tests/test_aiguillage_spotify.py"""

from datetime import date
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import aiguillage_spotify as s  # noqa: E402

TODAY = date(2026, 10, 16)


def test_liens():
    assert s.spotify_ref("https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC?si=x") == ("track", "4uLU6hMCjMI75M1A2tKUQC")
    assert s.spotify_ref("vu ici https://open.spotify.com/intl-fr/album/1ATL5GLyefJaxhQzSPVrLX") == ("album", "1ATL5GLyefJaxhQzSPVrLX")
    assert s.spotify_ref("https://open.spotify.com/episode/abc123") == ("episode", "abc123")
    assert s.spotify_ref("https://www.netflix.com/title/1") is None
    # Champ d'abord, puis les notes.
    assert s.lien_de({"envie": {"lien": "https://open.spotify.com/track/A1"}, "notes": "https://open.spotify.com/track/B2"}) == ("track", "A1")
    assert s.lien_de({"notes": "📩 Message partagé\nhttps://open.spotify.com/album/X9\n🎧 À écouter"}) == ("album", "X9")


def test_besoin():
    ecouter = {"titre": "Spaceships", "fait": False, "notes": "https://open.spotify.com/track/A1", "envie": {"type": "ecouter"}}
    assert s.needs_playlist(ecouter, TODAY)
    assert not s.needs_playlist({**ecouter, "fait": True}, TODAY)
    assert not s.needs_playlist({**ecouter, "envie": {"type": "regarder"}}, TODAY)
    # Ligne des notes, sans champ envie (tâche plus ancienne).
    assert s.needs_playlist({"titre": "x", "fait": False, "notes": "https://open.spotify.com/track/A1\n🎧 À écouter"}, TODAY)
    # Un artiste ou une playlist ne s'ajoutent pas.
    assert not s.needs_playlist({**ecouter, "notes": "https://open.spotify.com/artist/A1"}, TODAY)
    assert not s.needs_playlist({**ecouter, "notes": "rien"}, TODAY)
    fait = s.with_playlist(ecouter, "ok", TODAY, "PL", 12)
    assert fait["envie"]["playlist"] == {"statut": "ok", "maj": "2026-10-16", "ajoute_le": "2026-10-16", "playlist": "PL", "ajoutes": 12}
    assert fait["envie"]["type"] == "ecouter" and fait["v"] == 2
    assert not s.needs_playlist(fait, TODAY)
    # Échec : retenté le lendemain seulement.
    echec = s.with_playlist(ecouter, "echec", TODAY, erreur="404")
    assert not s.needs_playlist(echec, TODAY)
    assert s.needs_playlist(echec, date(2026, 10, 17))


def test_doublons_et_lecture():
    assert s.a_ajouter(["a", "b", "a", "c"], {"b"}) == ["a", "c"]
    assert s.lecture("album", "X") == {"context_uri": "spotify:album:X"}
    assert s.lecture("track", "Y") == {"uris": ["spotify:track:Y"]}
    devices = [{"id": "1", "name": "MacBook", "type": "Computer"}, {"id": "2", "name": "Freebox Player POP", "type": "TV"}]
    assert s.appareil_tv(devices)["id"] == "2"
    assert s.appareil_tv([{"id": "3", "name": "Salon", "type": "TV"}])["id"] == "3"
    assert s.appareil_tv([{"id": "1", "name": "MacBook", "type": "Computer"}]) is None


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
