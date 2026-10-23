"""Tests hors Home Assistant de `aiguillage_lecteur` (activité en direct du Hub iPad) :
uv run --with pytest python -m pytest -q homeassistant/appdaemon/tests"""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import aiguillage_lecteur as l  # noqa: E402

HA = "http://192.168.1.71:8123"
# États réels du 23/10 vers 10 h (Sunshine Radio par Music Assistant ; l'enceinte KEF la suit).
MA = {"entity_id": l.ENTITE_MA, "state": "playing", "attributes": {
    "media_title": "VAMOS A LA PLAYA", "media_artist": "Righeira", "media_album_name": "Sunshine Radio",
    "media_content_id": "library://radio/6", "volume_level": 0.35,
    "entity_picture": "https://r2.theaudiodb.com/images/media/album/thumb/cle4kq1686177951.jpg"}}
KEF = {"entity_id": l.ENTITE_KEF, "state": "playing", "attributes": {
    "media_title": "Sunshine Radio", "source": "wifi", "volume_level": 0.35,
    "entity_picture": "/api/media_player_proxy/media_player.kef_ls50_wireless_ii?token=abc&cache=def"}}
OPTIQUE = {"entity_id": l.ENTITE_KEF, "state": "playing", "attributes": {"source": "optical", "volume_level": 0.2}}


def test_choisir_ma_puis_kef():
    assert l.choisir_entite({l.ENTITE_MA: MA, l.ENTITE_KEF: KEF}) is MA
    assert l.choisir_entite({l.ENTITE_MA: {**MA, "state": "paused"}, l.ENTITE_KEF: KEF})["entity_id"] == l.ENTITE_MA
    assert l.choisir_entite({l.ENTITE_MA: {**MA, "state": "idle"}, l.ENTITE_KEF: KEF}) is KEF
    assert l.choisir_entite({l.ENTITE_MA: {**MA, "state": "idle"}, l.ENTITE_KEF: {**KEF, "state": "off"}}) is None
    assert l.choisir_entite({}) is None


def test_contenu_radio_music_assistant():
    # Le même JSON que `testContenuDeLaVigie` côté Swift (ActiviteLecteurTests).
    assert l.contenu(MA, HA) == {
        "titre": "VAMOS A LA PLAYA", "artiste": "Righeira", "source": "Sunshine Radio",
        "image": "https://r2.theaudiodb.com/images/media/album/thumb/cle4kq1686177951.jpg",
        "etat": "lecture", "volume": 35, "radio": True}


def test_contenu_spotify_en_pause():
    etat = {"entity_id": l.ENTITE_MA, "state": "paused", "attributes": {
        "media_title": "Roxanne", "media_artist": "The Police", "media_album_name": "Outlandos d'Amour",
        "media_content_id": "spotify--abc://track/3EYOJ48Et32uATr9ZmLnAo", "volume_level": 0.42}}
    c = l.contenu(etat, HA)
    assert (c["source"], c["etat"], c["volume"], c["radio"], c["image"]) == ("Spotify", "pause", 42, False, None)


def test_contenu_kef_image_relative_et_optique():
    c = l.contenu(KEF, HA)
    assert c["image"] == HA + "/api/media_player_proxy/media_player.kef_ls50_wireless_ii?token=abc&cache=def"
    assert c["source"] == "Wi-Fi"
    assert l.contenu(KEF)["image"] is None  # pas d'adresse de HA : pas d'image relative
    o = l.contenu(OPTIQUE, HA)
    assert (o["titre"], o["artiste"], o["source"], o["volume"]) == ("Optique", "", "Optique", 20)


def test_contenu_rien_si_arrete():
    assert l.contenu({**MA, "state": "idle"}) is None
    assert l.contenu(None) is None


def test_decider_demarrage_seulement_en_lecture():
    c = l.contenu(MA, HA)
    assert l.decider(c, None, False, None, 100) == ("start", 10)
    assert l.decider({**c, "etat": "pause"}, None, False, None, 100) == (None, 0)
    assert l.decider(None, None, False, None, 100) == (None, 0)


def test_decider_mises_a_jour():
    c = l.contenu(MA, HA)
    assert l.decider(c, c, True, None, 100) == (None, 0)
    assert l.decider({**c, "titre": "Autre"}, c, True, None, 100) == ("update", 10)
    assert l.decider({**c, "volume": 40}, c, True, None, 100) == ("update", 5)
    assert l.decider({**c, "etat": "pause"}, c, True, None, 100) == ("update", 5)
    assert l.decider(c, None, True, None, 100) == ("update", 10)


def test_decider_fin_apres_cinq_minutes():
    c = l.contenu(MA, HA)
    assert l.decider(None, c, True, 1000, 1000 + 299) == (None, 0)
    assert l.decider(None, c, True, 1000, 1000 + 300) == ("end", 10)
    assert l.decider(None, c, False, 1000, 5000) == (None, 0)


def test_payloads():
    c = l.contenu(MA, HA)
    s = l.payload_start(c, 1761213600.7)["aps"]
    assert s["event"] == "start" and s["timestamp"] == 1761213600
    assert s["attributes-type"] == "LecteurLS50Attributes" and s["attributes"] == {"nom": "Salon LS50"}
    assert s["content-state"] == c
    assert s["alert"] == {"title": "En lecture sur les LS50", "body": "VAMOS A LA PLAYA · Righeira"}
    assert "sound" not in s
    u = l.payload_update(c, 10)["aps"]
    assert u == {"timestamp": 10, "event": "update", "content-state": c}
    e = l.payload_end(c, 20)["aps"]
    assert e["event"] == "end" and e["dismissal-date"] == 20
    assert l.entetes(5) == {"apns-push-type": "liveactivity",
                            "apns-topic": "fr.alexandrefau.hubipad.push-type.liveactivity", "apns-priority": "5"}


def test_ranger_et_retirer_jetons():
    etat = l.etat_vide()
    j1, j2 = "ab" * 32, "cd" * 32
    assert l.ranger_jeton(etat, {"type": "push_to_start", "jeton": j1.upper(), "environnement": "sandbox"}, 5) == "push_to_start"
    assert etat["push_to_start"][j1] == {"environnement": "sandbox", "maj": 5}
    assert not etat["en_cours"]
    assert l.ranger_jeton(etat, {"type": "activite", "jeton": j2, "activite_id": "A1"}, 6) == "activite"
    assert etat["activites"]["A1"]["jeton"] == j2 and etat["activites"]["A1"]["environnement"] == "production"
    assert etat["en_cours"]
    assert l.ranger_jeton(etat, {"type": "activite", "jeton": "zz"}, 7) is None
    assert l.ranger_jeton(etat, {"type": "autre", "jeton": j1}, 7) is None
    l.retirer_jeton(etat, j2)
    l.retirer_jeton(etat, j1)
    assert etat["activites"] == {} and etat["push_to_start"] == {}
