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


# État réel du 26/10/2026 : France Culture lancée, titre-fichier, ni pochette ni artiste.
CULTURE = {"entity_id": l.ENTITE_MA, "state": "playing", "attributes": {
    "media_title": "franceculture-hifi.aac", "volume_level": 0.35,
    "media_content_id": "builtin://radio/https://icecast.radiofrance.fr/franceculture-hifi.aac?id=radiofrance"}}
AJOUTEES = [{"id": "tunein_s257284", "nom": "Tsugi Radio", "uri": "tunein--x://radio/s257284", "image": "https://logo/tsugi"},
            {"id": "ma_12", "nom": "Biblio 12", "uri": "library://radio/12", "image": ""}]


def test_contenu_station_reconnue_etat_reel():
    assert l.contenu(CULTURE, HA) == {
        "titre": "France Culture", "artiste": "En direct", "source": "France Culture",
        "image": "https://cdn-profiles.tunein.com/s2442/images/logog.png",
        "etat": "lecture", "volume": 35, "radio": True}


def test_contenu_vrai_titre_garde_et_pochette_prioritaire():
    etat = {**CULTURE, "attributes": {**CULTURE["attributes"], "media_title": "Les Matins",
                                      "media_artist": "Guillaume Erner", "entity_picture": "https://ma/pochette"}}
    c = l.contenu(etat, HA)
    assert (c["titre"], c["artiste"], c["source"], c["image"]) == ("Les Matins", "Guillaume Erner", "France Culture", "https://ma/pochette")


def test_station_radios_ajoutees():
    assert l.station("tunein--x://radio/s257284--abc", AJOUTEES) == ("Tsugi Radio", "https://logo/tsugi")
    assert l.station("tunein--x://radio/s2572841", AJOUTEES) is None
    assert l.station("library://radio/12", AJOUTEES) == ("Biblio 12", None)
    assert l.station("library://radio/123", AJOUTEES) is None
    assert l.station("library://radio/1", AJOUTEES) is None
    assert l.station("tunein://radio/s15474")[0] == "Couleur 3"
    etat = {"entity_id": l.ENTITE_MA, "state": "playing", "attributes": {
        "media_title": "s257284", "media_content_id": "tunein--x://radio/s257284"}}
    c = l.contenu(etat, HA, AJOUTEES)
    assert (c["titre"], c["artiste"], c["image"]) == ("Tsugi Radio", "En direct", "https://logo/tsugi")


def test_contenu_radio_inconnue_titre_fichier():
    etat = {"entity_id": l.ENTITE_MA, "state": "playing", "attributes": {
        "media_title": "stream.mp3", "media_content_id": "https://x.icecast/stream.mp3"}}
    c = l.contenu(etat, HA)
    assert (c["titre"], c["artiste"], c["source"], c["image"]) == ("Radio", "En direct", "Radio", None)
    assert l.titre_fichier("live", "https://x/live") and not l.titre_fichier("Les Matins", CULTURE["attributes"]["media_content_id"])


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
    assert etat["push_to_start"][j1] == {"environnement": "sandbox", "maj": 5}  # app d'avant : sans appareil
    assert not etat["en_cours"]
    assert l.ranger_jeton(etat, {"type": "activite", "jeton": j2, "activite_id": "A1"}, 6) == "activite"
    assert etat["activites"]["A1"]["jeton"] == j2 and etat["activites"]["A1"]["environnement"] == "production"
    assert etat["en_cours"]
    assert l.ranger_jeton(etat, {"type": "activite", "jeton": "zz"}, 7) is None
    assert l.ranger_jeton(etat, {"type": "autre", "jeton": j1}, 7) is None
    l.retirer_jeton(etat, j2)
    l.retirer_jeton(etat, j1)
    assert etat["activites"] == {} and etat["push_to_start"] == {}


# MARK: - Plusieurs appareils (iPad et iPhone, 23/10/2026)

IPAD, IPHONE = "IPAD-UUID", "IPHONE-UUID"
P1, P2, P3 = "a1" * 32, "b2" * 32, "c3" * 32
A1, A2 = "d4" * 40, "e5" * 40


def _pts(etat, jeton, appareil, modele):
    return l.ranger_jeton(etat, {"type": "push_to_start", "jeton": jeton, "appareil": appareil, "modele": modele}, 1)


def test_un_jeton_push_to_start_par_appareil():
    etat = l.etat_vide()
    _pts(etat, P1, IPAD, "iPad")
    _pts(etat, P2, IPHONE, "iPhone")
    assert set(etat["push_to_start"]) == {P1, P2}
    assert etat["push_to_start"][P2] == {"environnement": "production", "maj": 1, "appareil": IPHONE, "modele": "iPhone"}
    # L'iPad change de jeton : l'ancien est remplacé, celui de l'iPhone reste.
    _pts(etat, P3, IPAD, "iPad")
    assert set(etat["push_to_start"]) == {P2, P3}
    # Le même jeton renvoyé (retour au premier plan) ne fait rien de plus.
    _pts(etat, P3, IPAD, "iPad")
    assert set(etat["push_to_start"]) == {P2, P3}


def test_demarrage_sur_chaque_appareil():
    etat = l.etat_vide()
    _pts(etat, P1, IPAD, "iPad")
    _pts(etat, P2, IPHONE, "iPhone")
    c = l.contenu(MA, HA)
    action, liste = l.envois(etat, c, None, 100)
    assert action == "start"
    assert sorted((g, j, a) for g, j, _, a, _, _ in liste) == [("start", P1, IPAD), ("start", P2, IPHONE)]
    assert all(p["aps"]["event"] == "start" for *_, p, _ in liste)
    l.apres_envois(etat, action, c, [IPAD, IPHONE], 2, [], 100)
    assert etat["en_cours"] and etat["envoye"] == c and set(etat["demarres"]) == {IPAD, IPHONE}
    # En attendant les jetons d'activité : pas de second démarrage.
    assert l.envois(etat, c, None, 102) == (None, [])


def test_mises_a_jour_a_chaque_activite():
    etat = l.etat_vide()
    c = l.contenu(MA, HA)
    l.ranger_jeton(etat, {"type": "activite", "jeton": A1, "activite_id": "X", "appareil": IPAD}, 1)
    l.ranger_jeton(etat, {"type": "activite", "jeton": A2, "activite_id": "Y", "appareil": IPHONE}, 1)
    etat["envoye"] = c
    action, liste = l.envois(etat, {**c, "volume": 50}, None, 100)
    assert action == "update"
    assert sorted((g, j) for g, j, *_ in liste) == [("activite", A1), ("activite", A2)]
    # Fin : les deux activités, puis tout est vidé.
    action, liste = l.envois(etat, None, 100, 100 + l.ARRET_AVANT_FIN)
    assert action == "end" and len(liste) == 2 and all(p["aps"]["event"] == "end" for *_, p, _ in liste)
    l.apres_envois(etat, action, None, [], 2, [], 500)
    assert (etat["en_cours"], etat["activites"], etat["demarres"]) == (False, {}, {})


def test_iphone_arrive_pendant_la_lecture():
    """L'activité tourne sur l'iPad ; l'iPhone envoie son premier jeton : il démarre aussi, l'iPad n'est pas redémarré."""
    etat = l.etat_vide()
    c = l.contenu(MA, HA)
    _pts(etat, P1, IPAD, "iPad")
    l.ranger_jeton(etat, {"type": "activite", "jeton": A1, "activite_id": "X", "appareil": IPAD}, 1)
    etat["envoye"] = c
    assert l.envois(etat, c, None, 100) == (None, [])
    _pts(etat, P2, IPHONE, "iPhone")
    action, liste = l.envois(etat, c, None, 101)
    assert action is None and [(g, j) for g, j, *_ in liste] == [("start", P2)]
    l.apres_envois(etat, action, c, [IPHONE], 1, [], 101)
    assert l.envois(etat, c, None, 102) == (None, [])
    # En pause : pas de démarrage pour un nouvel appareil.
    etat["demarres"] = {}
    assert [g for g, *_ in l.envois(etat, {**c, "etat": "pause"}, None, 103)[1]] == ["activite"]


def test_activite_d_avant_sans_appareil():
    """Activité de l'app d'avant (sans appareil) : on ne sait pas de quel écran elle est, rien d'autre ne démarre."""
    etat = l.etat_vide()
    c = l.contenu(MA, HA)
    l.ranger_jeton(etat, {"type": "activite", "jeton": A1, "activite_id": "X"}, 1)
    etat["envoye"] = c
    _pts(etat, P1, IPAD, "iPad")
    assert l.envois(etat, c, None, 100) == (None, [])


def test_jeton_perime_retire():
    etat = l.etat_vide()
    _pts(etat, P1, IPAD, "iPad")
    _pts(etat, P2, IPHONE, "iPhone")
    c = l.contenu(MA, HA)
    action, _ = l.envois(etat, c, None, 100)
    l.apres_envois(etat, action, c, [IPAD], 1, [P2], 100)
    assert set(etat["push_to_start"]) == {P1} and set(etat["demarres"]) == {IPAD} and etat["en_cours"]


# MARK: - Spotify Connect : pas de doublon sur l'écran verrouillé (23/10/2026)

# États réels du 23/10 vers 11 h 37 : Spotify lancé depuis le téléphone ; Music Assistant au repos, la KEF joue en Wi-Fi.
MA_REPOS = {**MA, "state": "idle"}
KEF_SPOTIFY = {"entity_id": l.ENTITE_KEF, "state": "playing", "attributes": {
    "media_title": "Gas", "media_artist": "BICEP", "media_album_name": "Gas / Ultra / Equarium", "source": "wifi",
    "media_duration": 218, "volume_level": 0.41}}


def test_spotify_connect_reconnu():
    choisi = l.choisir_entite({l.ENTITE_MA: MA_REPOS, l.ENTITE_KEF: KEF_SPOTIFY})
    assert choisi is KEF_SPOTIFY and l.spotify_connect(choisi)
    assert l.spotify_connect({**KEF_SPOTIFY, "state": "paused"})
    # Music Assistant joue (radio, « À écouter » par Spotify dans Music Assistant) : ce n'est pas Spotify Connect.
    assert not l.spotify_connect(l.choisir_entite({l.ENTITE_MA: MA, l.ENTITE_KEF: KEF_SPOTIFY}))
    assert not l.spotify_connect(OPTIQUE)  # TV par l'entrée optique
    assert not l.spotify_connect({**KEF_SPOTIFY, "state": "idle"})
    assert not l.spotify_connect(None)


def _avec_reglage(etat, jeton, appareil, masquer):
    return l.ranger_jeton(etat, {"type": "push_to_start", "jeton": jeton, "appareil": appareil, "masquer_spotify": masquer}, 1)


def test_reglage_masquer_spotify_par_appareil():
    etat = l.etat_vide()
    _avec_reglage(etat, P1, IPAD, "True")     # texte rendu par le modèle du script
    _avec_reglage(etat, P2, IPHONE, False)    # vrai booléen
    assert l.masque_spotify(etat, IPAD) and not l.masque_spotify(etat, IPHONE)
    assert l.masque_spotify(etat, "inconnu") and l.masque_spotify(etat, None)  # par défaut : masqué
    # Champ absent ou vide (app d'avant) : le réglage ne bouge pas.
    l.ranger_jeton(etat, {"type": "push_to_start", "jeton": P2, "appareil": IPHONE, "masquer_spotify": ""}, 2)
    assert not l.masque_spotify(etat, IPHONE)


def test_spotify_ne_demarre_que_sur_les_appareils_qui_ne_masquent_pas():
    etat = l.etat_vide()
    _avec_reglage(etat, P1, IPAD, True)
    _avec_reglage(etat, P2, IPHONE, False)
    c = l.contenu(KEF_SPOTIFY, HA)
    action, liste = l.envois(etat, c, None, 100, spotify=True)
    assert action == "start" and [(g, j) for g, j, *_ in liste] == [("start", P2)]
    # Tout le monde masque : rien.
    _avec_reglage(etat, P2, IPHONE, True)
    assert l.envois(etat, c, None, 100, spotify=True) == ("start", [])


def test_spotify_termine_l_activite_en_cours_puis_redemarre_apres():
    etat = l.etat_vide()
    _avec_reglage(etat, P1, IPAD, True)
    _avec_reglage(etat, P2, IPHONE, False)
    radio = l.contenu(MA, HA)
    action, _ = l.envois(etat, radio, None, 100)
    l.apres_envois(etat, action, radio, [IPAD, IPHONE], 2, [], 100)
    l.ranger_jeton(etat, {"type": "activite", "jeton": A1, "activite_id": "X", "appareil": IPAD}, 101)
    l.ranger_jeton(etat, {"type": "activite", "jeton": A2, "activite_id": "Y", "appareil": IPHONE}, 101)
    etat["envoye"] = radio
    # La source bascule sur Spotify Connect : fin sur l'iPad (qui masque), mise à jour sur l'iPhone.
    spot = l.contenu(KEF_SPOTIFY, HA)
    action, liste = l.envois(etat, spot, None, 200, spotify=True)
    assert action == "update"
    assert sorted((g, j) for g, j, *_ in liste) == [("activite", A2), ("fin", A1)]
    fin = next(p for g, _, _, _, p, _ in liste if g == "fin")["aps"]
    assert fin["event"] == "end" and fin["content-state"]["titre"] == radio["titre"]
    l.apres_envois(etat, action, spot, [], 2, [], 200, finis=[A1])
    assert list(etat["activites"]) == ["Y"] and IPAD not in etat["demarres"]
    # Toujours Spotify : rien de plus pour l'iPad.
    assert l.envois(etat, spot, None, 210, spotify=True) == (None, [])
    # Retour à Music Assistant : l'iPad redémarre, l'iPhone reçoit la mise à jour.
    action, liste = l.envois(etat, radio, None, 300)
    assert action == "update" and sorted((g, j) for g, j, *_ in liste) == [("activite", A2), ("start", P1)]


# MARK: - Compte des pushs par appareil (suivi batterie)

def test_nom_appareil_et_compte():
    etat = l.etat_vide()
    _pts(etat, P1, IPHONE, "iPhone")
    assert l.nom_appareil(etat, IPHONE) == "iPhone IPHONE-U"
    assert l.nom_appareil(etat, "ABCDEF123456") == "appareil ABCDEF12"
    assert l.nom_appareil(etat, None) == "ancien"
    stats = {}
    l.compter_pushs(stats, "2026-10-23", [("iPad A", "start"), ("iPad A", "update"), ("iPad A", "update"), ("iPhone B", "echec")])
    assert stats == {"2026-10-23": {"iPad A": {"start": 1, "update": 2}, "iPhone B": {"echec": 1}}}
    assert l.compter_pushs(stats, "2026-10-24", []) == stats  # rien d'envoyé : rien ne bouge
    for i in range(40):
        l.compter_pushs(stats, f"2026-11-{i:02d}", [("iPad A", "update")])
    assert len(stats) == 31 and "2026-10-23" not in stats


def test_jetons_d_avant_retires_par_l_ipad():
    """Jetons sans appareil (app d'avant, seulement sur l'iPad) : retirés quand l'iPad envoie le sien, pas par l'iPhone."""
    etat = l.etat_vide()
    l.ranger_jeton(etat, {"type": "push_to_start", "jeton": P1}, 1)
    _pts(etat, P2, IPHONE, "iPhone")
    assert set(etat["push_to_start"]) == {P1, P2}
    _pts(etat, P3, IPAD, "iPad")
    assert set(etat["push_to_start"]) == {P2, P3}


def test_activites_fermees_par_ios_apres_une_mise_a_jour():
    """24/10/2026 : la mise à jour de l'app ferme l'activité de l'iPhone ; il renvoie son jeton avec `activites` = 0,
    la vigie oublie son activité et le redémarre ; celle de l'iPad continue de recevoir les mises à jour."""
    etat = l.etat_vide()
    c = l.contenu(MA, HA)
    _pts(etat, P1, IPAD, "iPad")
    _pts(etat, P2, IPHONE, "iPhone")
    l.apres_envois(etat, "start", c, [IPAD, IPHONE], 2, [], 100)
    l.ranger_jeton(etat, {"type": "activite", "jeton": A1, "activite_id": "X", "appareil": IPAD}, 101)
    l.ranger_jeton(etat, {"type": "activite", "jeton": A2, "activite_id": "Y", "appareil": IPHONE}, 101)
    etat["envoye"] = c
    assert l.envois(etat, c, None, 500) == (None, [])
    # Valeur rendue par le modèle du script : texte « 0 ».
    l.ranger_jeton(etat, {"type": "push_to_start", "jeton": P3, "appareil": IPHONE, "modele": "iPhone",
                          "activites": "0"}, 1000)
    assert set(etat["activites"]) == {"X"} and set(etat["demarres"]) == {IPAD}
    action, liste = l.envois(etat, c, None, 1001)
    assert action is None and [(g, j, a) for g, j, _, a, _, _ in liste] == [("start", P3, IPHONE)]
    action, liste = l.envois(etat, {**c, "volume": 50}, None, 1002)
    assert action == "update" and sorted((g, j) for g, j, *_ in liste) == [("activite", A1), ("start", P3)]


def test_activites_absent_vide_ou_non_nul_ne_change_rien():
    etat = l.etat_vide()
    l.apres_envois(etat, "start", l.contenu(MA, HA), [IPHONE], 1, [], 100)
    l.ranger_jeton(etat, {"type": "activite", "jeton": A2, "activite_id": "Y", "appareil": IPHONE}, 101)
    for valeur in (None, "", "1", 2, "abc", True, -1):
        data = {"type": "push_to_start", "jeton": P2, "appareil": IPHONE, "modele": "iPhone"}
        if valeur is not None:
            data["activites"] = valeur
        l.ranger_jeton(etat, data, 1000)
        assert set(etat["activites"]) == {"Y"} and set(etat["demarres"]) == {IPHONE}, valeur
    # Sans appareil (app d'avant) : rien n'est oublié.
    l.ranger_jeton(etat, {"type": "push_to_start", "jeton": P1, "activites": 0}, 1000)
    assert set(etat["activites"]) == {"Y"}


def test_activites_zero_garde_un_demarrage_recent():
    """Démarrage de moins d'une minute : l'activité n'est peut-être pas encore créée, pas de second démarrage."""
    etat = l.etat_vide()
    c = l.contenu(MA, HA)
    _pts(etat, P2, IPHONE, "iPhone")
    l.apres_envois(etat, "start", c, [IPHONE], 1, [], 100)
    l.ranger_jeton(etat, {"type": "push_to_start", "jeton": P2, "appareil": IPHONE, "activites": 0}, 100 + 30)
    assert set(etat["demarres"]) == {IPHONE}
    assert l.envois(etat, c, None, 131) == (None, [])
    l.ranger_jeton(etat, {"type": "push_to_start", "jeton": P2, "appareil": IPHONE, "activites": 0},
                   100 + l.GARDE_DEMARRAGE)
    assert etat["demarres"] == {}
    assert [g for g, *_ in l.envois(etat, c, None, 161)[1]] == ["start"]


def test_meme_jeton_sous_un_autre_identifiant_oublie_l_ancien():
    """24/10/2026 : l'iPhone a changé d'`identifierForVendor` en gardant son jeton push-to-start ; l'activité morte de
    l'ancien identifiant, son démarrage et ses réglages partent."""
    etat = l.etat_vide()
    _pts(etat, P2, "ANCIEN", "iPhone")
    l.apres_envois(etat, "start", l.contenu(MA, HA), ["ANCIEN", IPAD], 2, [], 100)
    l.ranger_jeton(etat, {"type": "activite", "jeton": A2, "activite_id": "Y", "appareil": "ANCIEN",
                          "masquer_spotify": False}, 101)
    l.ranger_jeton(etat, {"type": "push_to_start", "jeton": P2, "appareil": IPHONE, "modele": "iPhone"}, 102)
    assert etat["activites"] == {} and set(etat["demarres"]) == {IPAD} and "ANCIEN" not in etat["reglages"]
    assert etat["push_to_start"][P2]["appareil"] == IPHONE
