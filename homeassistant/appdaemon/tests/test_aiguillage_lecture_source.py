"""Tests hors Home Assistant de `aiguillage_lecture_source` (sensor.lecture_source, LECTURE-SOURCE.md)."""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import aiguillage_lecture_source as S  # noqa: E402

ISO = "2026-10-29T15:40:00+01:00"


def appel(media_id="library://playlist/7", media_type="playlist", entite="media_player.salon_ls50_5",
          domaine="music_assistant", **extra):
    if domaine == "music_assistant":
        sd = {"entity_id": entite, "media_id": media_id, "media_type": media_type}
    else:
        sd = {"entity_id": entite, "media_content_id": media_id, "media_content_type": media_type}
    sd.update(extra)
    return {"domain": domaine, "service": "play_media", "service_data": sd}


def ma(state="playing", shuffle=True, queue="up84171515bd80", ident="library://track/9312", **attrs):
    a = {"source": "Music Assistant Queue", "app_id": "music_assistant", "shuffle": shuffle, "active_queue": queue,
         "media_content_id": ident, "media_title": "Fournaise (Live)", "media_artist": "Spoink",
         "media_album_name": "Live au Kilowatt"}
    a.update(attrs)
    return {"entity_id": S.ENTITE_MA, "state": state, "attributes": a}


def kef(state="playing", source="wifi"):
    return {"entity_id": S.ENTITE_KEF, "state": state,
            "attributes": {"source": source, "media_title": "Need to say", "media_artist": "ELEZO"}}


def spotify(state="lecture", sur_ls50=True, nom="Découvertes de la semaine", genre="playlist", aleatoire=None):
    return {"entity_id": S.ENTITE_SPOTIFY, "state": state,
            "attributes": {"sur_ls50": sur_ls50, "contexte": {"type": genre, "nom": nom}, "aleatoire": aleatoire}}


def memo_titres_likes(**kw):
    m = S.lancement_depuis_appel(appel(), ISO, 100.0)
    m.update({"nom": "Liked Songs Alexandre Fau", "nom_type": "playlist", "queue_id": "up84171515bd80", "items": 109})
    m.update(kw)
    return m


FILE = {"queue_id": "up84171515bd80", "items": 109, "current_index": 7, "shuffle_enabled": True}


# Lancements vus


def test_lancement_music_assistant():
    m = S.lancement_depuis_appel(appel(), ISO, 5.0)
    assert m["media_id"] == "library://playlist/7" and m["media_type"] == "playlist" and m["quand"] == ISO
    assert m["queue_id"] is None and m["items"] is None and m["nom"] is None


def test_lancement_media_player_et_liste_d_entites():
    m = S.lancement_depuis_appel(appel("spotify:album:X", "album", domaine="media_player",
                                       entite=["media_player.kef_ls50_wireless_ii", "media_player.salon_ls50_5"]),
                                 ISO, 1.0)
    assert m["media_id"] == "spotify:album:X" and m["media_type"] == "album"


def test_lancement_ailleurs_ignore():
    assert S.lancement_depuis_appel(appel(entite="media_player.chambre"), ISO, 1.0) is None
    assert S.lancement_depuis_appel({"domain": "light", "service": "turn_on", "service_data": {}}, ISO, 1.0) is None
    assert S.lancement_depuis_appel(appel(media_id=""), ISO, 1.0) is None


def test_ajout_garde_le_contexte_mais_reapprend_la_taille():
    memo = memo_titres_likes()
    ajout = S.lancement_depuis_appel(appel("library://track/1", "track", enqueue="add"), ISO, 200.0)
    assert ajout == {"ajout": True}
    apres = S.appliquer(memo, ajout)
    assert apres["media_id"] == "library://playlist/7" and apres["items"] is None and apres["nom"]


def test_nouveau_lancement_remplace():
    memo = memo_titres_likes()
    nouveau = S.lancement_depuis_appel(appel("library://radio/3", "radio", enqueue="replace"), ISO, 300.0)
    assert S.appliquer(memo, nouveau)["media_id"] == "library://radio/3"


def test_plusieurs_elements_sans_contexte():
    m = S.lancement_depuis_appel(appel(["a", "b"], "track"), ISO, 1.0)
    assert m["media_id"] is None
    assert S.nom_du_lancement(m) == (None, None)


# Nom


def test_resolution_et_nouvel_essai():
    m = S.lancement_depuis_appel(appel(), ISO, 0.0)
    assert S.a_resoudre(m, 0.0)
    rate = S.nom_resolu(m, None, 10.0)
    assert rate["nom"] is None and not S.a_resoudre(rate, 100.0) and S.a_resoudre(rate, 10.0 + S.NOUVEL_ESSAI)
    ok = S.nom_resolu(m, {"name": "Liked Songs Alexandre Fau", "media_type": "playlist"}, 10.0)
    assert ok["nom"] == "Liked Songs Alexandre Fau" and not S.a_resoudre(ok, 20.0)


def test_nom_donne_tel_quel():
    m = S.lancement_depuis_appel(appel("France Inter", "radio"), ISO, 0.0)
    assert not S.a_resoudre(m, 0.0)
    assert S.nom_du_lancement(m) == ("France Inter", "radio")


def test_renommage():
    assert S.nom_affiche("Liked Songs Alexandre Fau") == "Titres likés"
    assert S.nom_affiche("Titres likés de Alexandre") == "Titres likés"
    assert S.nom_affiche("  ") is None
    assert S.nom_affiche("Daily Mix 1") == "Daily Mix 1"


# Validité


def test_apprendre_puis_valide():
    m = S.lancement_depuis_appel(appel(), ISO, 100.0)
    tot = S.apprendre(m, ma(), FILE, 103.0)
    assert tot["queue_id"] == "up84171515bd80" and tot["items"] is None   # trop tôt pour la taille
    appris = S.apprendre(tot, ma(), FILE, 115.0)
    assert appris["items"] == 109
    assert S.valide(appris, ma(), FILE)


def test_file_relancee_ailleurs():
    memo = memo_titres_likes()
    assert not S.valide(memo, ma(), dict(FILE, items=12))
    assert not S.valide(memo, ma(queue="autre"), FILE)
    assert not S.valide(memo, ma(), dict(FILE, current_index=109))
    assert not S.valide(None, ma(), FILE)


# Capteur


def test_cas_du_jour_ma_prime_sur_la_kef():
    etats = {S.ENTITE_MA: ma(), S.ENTITE_KEF: kef(), S.ENTITE_SPOTIFY: spotify("rien", False, None, None)}
    memo = memo_titres_likes()
    etat, a = S.calculer(etats, memo, S.valide(memo, etats[S.ENTITE_MA], FILE), [], ISO)
    assert etat == "music_assistant"
    assert a["ligne"] == "Music Assistant · Titres likés · aléatoire"
    assert a == {"source": "Music Assistant", "nom": "Titres likés", "type": "playlist", "aleatoire": True,
                 "ligne": "Music Assistant · Titres likés · aléatoire", "entite": S.ENTITE_MA, "maj": ISO}


def test_ma_sans_lancement_connu():
    etat, a = S.calculer({S.ENTITE_MA: ma(shuffle=False)}, None, False, [], ISO)
    assert etat == "music_assistant" and a["nom"] is None and a["ligne"] == "Music Assistant"
    assert a["aleatoire"] is False


def test_ma_lancement_perime_nom_null():
    etat, a = S.calculer({S.ENTITE_MA: ma()}, memo_titres_likes(), False, [], ISO)
    assert a["nom"] is None and a["ligne"] == "Music Assistant · aléatoire"


def test_radio_station_connue():
    etats = {S.ENTITE_MA: ma(ident="https://icecast.radiofrance.fr/franceinter-hifi.aac",
                             media_title="franceinter-hifi.aac", media_album_name="")}
    etat, a = S.calculer(etats, None, False, [], ISO)
    assert etat == "radio" and a["nom"] == "France Inter" and a["ligne"] == "Radio · France Inter"
    assert a["type"] == "radio" and a["aleatoire"] is None


def test_radio_lancee_par_nom_de_bibliotheque():
    memo = S.lancement_depuis_appel(appel("library://radio/12", "radio"), ISO, 0.0)
    memo = S.nom_resolu(memo, {"name": "Tsugi Radio", "media_type": "radio"}, 1.0)
    etat, a = S.calculer({S.ENTITE_MA: ma(ident="library://radio/12", media_album_name="")}, memo, True, [], ISO)
    assert etat == "radio" and a["ligne"] == "Radio · Tsugi Radio"


def test_spotify_sur_les_ls50():
    etats = {S.ENTITE_MA: ma("idle"), S.ENTITE_KEF: kef(), S.ENTITE_SPOTIFY: spotify(aleatoire=False)}
    etat, a = S.calculer(etats, memo_titres_likes(), True, [], ISO)
    assert etat == "spotify" and a["ligne"] == "Spotify · Découvertes de la semaine"
    assert a["entite"] == S.ENTITE_KEF and a["type"] == "playlist" and a["aleatoire"] is False


def test_spotify_titres_likes_aleatoire_et_nom_inconnu():
    _, a = S.calculer({S.ENTITE_SPOTIFY: spotify(nom="Titres likés", genre="collection", aleatoire=True)},
                      None, False, [], ISO)
    assert a["ligne"] == "Spotify · Titres likés · aléatoire" and a["type"] == "playlist"
    _, a = S.calculer({S.ENTITE_SPOTIFY: spotify(nom=None)}, None, False, [], ISO)
    assert a["ligne"] == "Spotify" and a["nom"] is None


def test_spotify_en_lecture_passe_avant_ma_en_pause():
    etats = {S.ENTITE_MA: ma("paused"), S.ENTITE_SPOTIFY: spotify()}
    assert S.calculer(etats, None, False, [], ISO)[0] == "spotify"
    etats = {S.ENTITE_MA: ma("paused"), S.ENTITE_SPOTIFY: spotify("pause")}
    assert S.calculer(etats, None, False, [], ISO)[0] == "music_assistant"


def test_spotify_sur_un_autre_appareil_ne_compte_pas():
    etat, _ = S.calculer({S.ENTITE_SPOTIFY: spotify(sur_ls50=False)}, None, False, [], ISO)
    assert etat == "rien"


def test_kef_wifi_sans_ma_ni_capteur():
    etat, a = S.calculer({S.ENTITE_MA: ma("idle"), S.ENTITE_KEF: kef()}, None, False, [], ISO)
    assert etat == "spotify" and a["ligne"] == "Spotify"


def test_kef_autre_entree():
    etat, a = S.calculer({S.ENTITE_KEF: kef(source="bluetooth")}, None, False, [], ISO)
    assert etat == "autre" and a["ligne"] == "AirPlay / autre" and a["source"] == "AirPlay / autre"


def test_rien():
    etat, a = S.calculer({S.ENTITE_MA: ma("idle"), S.ENTITE_KEF: kef("off")}, None, False, [], ISO)
    assert etat == "rien" and a["ligne"] is None and a["maj"] == ISO


def test_publication():
    a = S.calculer({S.ENTITE_MA: ma()}, None, False, [], ISO)
    b = S.calculer({S.ENTITE_MA: ma()}, None, False, [], "2026-10-29T15:41:00+01:00")
    assert S.a_publier(None, a, 0, 0)
    assert not S.a_publier(a, b, 0, 30)
    assert S.a_publier(a, b, 0, S.REPUBLIER)
    c = S.calculer({S.ENTITE_MA: ma(shuffle=False)}, None, False, [], ISO)
    assert S.a_publier(a, c, 0, 1)


def test_memo_sur_disque():
    memo = dict(memo_titres_likes(), nom_essai=5.0)
    disque = S.memo_disque(memo)
    assert "t" not in disque and "nom_essai" not in disque and disque["items"] == 109
    relu = S.memo_charge(disque, 1000.0)
    assert relu["nom"] == "Liked Songs Alexandre Fau" and relu["nom_essai"] is None
    assert S.apprendre(dict(relu, items=None), ma(), FILE, 1000.0)["items"] == 109
    assert S.memo_charge({"media_id": None}, 1.0) is None and S.memo_charge("x", 1.0) is None
    assert S.memo_disque(None) is None


def test_indisponible():
    assert S.indisponible("KeyError", ISO) == ("unavailable", {"maj": ISO, "erreur": "KeyError"})
