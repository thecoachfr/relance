"""Tests hors Home Assistant de `aiguillage_radio_morceau` (sensor.radio_morceau, script.radio_garder_titre,
homeassistant/RADIO-MORCEAU.md)."""

from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import aiguillage_radio_morceau as R  # noqa: E402

ISO = "2026-10-29T20:35:00+01:00"
EPOCH = 1793302443.0          # 29/10/2026 vers 20 h 34 (FIP : « Divorce me C.O.D. » de 1793302292 à 1793302469)
AJOUTEES = [{"id": "tunein_s257284", "nom": "Tsugi Radio", "uri": "library://radio/5", "image": None},
            {"id": "tunein_s325460", "nom": "Sunshine Radio", "uri": "library://radio/6", "image": None}]
URI = "spotify:track:" + "A" * 22


def lecteur(ident, titre, artiste=None, album=None, state="playing", entite=R.LECTEURS[0]):
    a = {"media_content_id": ident, "media_title": titre, "source": "Music Assistant Queue",
         "app_id": "music_assistant"}
    if artiste is not None:
        a["media_artist"] = artiste
    if album is not None:
        a["media_album_name"] = album
    return {entite: {"entity_id": entite, "state": state, "attributes": a}}


def piste(nom, artistes, ident="A" * 22):
    return {"id": ident, "uri": f"spotify:track:{ident}", "name": nom, "artists": [{"name": a} for a in artistes],
            "album": {"images": [{"url": "https://i/640", "width": 640}, {"url": "https://i/300", "width": 300},
                                 {"url": "https://i/64", "width": 64}]}}


RTS = {"songList": [
    {"isPlayingNow": True, "date": "2026-10-29T20:31:56+01:00", "title": "Patricia", "artist": {"name": "Orquesta Aragon"}},
    {"isPlayingNow": False, "date": "2026-10-29T20:28:42+01:00", "title": "Selenge", "artist": {"name": "Céline Dessberg"}},
]}
# Forme réelle de livemeta/pull/7 (FIP) relevée le 29/10/2026.
RF_FIP = {"stationId": 7, "levels": [], "steps": {
    "a": {"embedType": "expression", "title": "Classique & Mix", "start": 1793300400, "end": 1793305800},
    "b": {"embedType": "song", "title": "Divorce me C.O.D.", "authors": "Merle Travis", "performers": "",
          "start": 1793302292, "end": 1793302469},
    "c": {"embedType": "song", "title": "I'm a Long Gone Daddy", "authors": "Hank Williams", "performers": "",
          "start": 1793302468, "end": 1793302636},
}}
RF_EMISSION = {"steps": {"a": {"embedType": "expression", "title": "Le 7/9", "start": 1793300400, "end": 1793305800}}}


class Faux:
    def __init__(self, json=None, pistes=None, erreur_json=None, erreur_spotify=None):
        self.json, self.pistes = json or {}, pistes or {}
        self.erreur_json, self.erreur_spotify = erreur_json, erreur_spotify
        self.urls, self.requetes = [], []

    def lire(self, url):
        self.urls.append(url)
        if self.erreur_json:
            raise self.erreur_json
        return self.json.get(url, {})

    def chercher(self, q):
        self.requetes.append(q)
        if self.erreur_spotify:
            raise self.erreur_spotify
        return self.pistes.get(q, [])


def suivi(faux):
    return R.Suivi(faux.lire, faux.chercher)


# MARK: - Textes et correspondance

def test_titre_propre_retire_feat_et_radio_edit():
    assert R.titre_propre("Newtown Chips (feat. Moonchild Sanelly)") == "Newtown Chips"
    assert R.titre_propre("Song (Radio Edit)") == "Song"
    assert R.titre_propre("Song - Radio Edit") == "Song"
    assert R.titre_propre("Song feat. X") == "Song"
    assert R.titre_propre("(REP) As It Goes") == "As It Goes" and R.titre_affiche("(REP) As It Goes") == "As It Goes"


def test_concorde_sans_accents_ni_casse():
    assert R.concorde("SELENGE", "Celine Dessberg", piste("Selenge", ["Céline Dessberg"]))
    assert R.concorde("Newtown Chips (feat. Moonchild Sanelly)", "Dejot (CH)", piste("Newtown Chips", ["Dejot"]))
    assert R.concorde("Song", "A & B", piste("Song - Radio Edit", ["B"]))
    assert R.concorde("Divorce Me C.O.D.", "Merle Travis", piste("Divorce Me C.O.D. - 2002 Remaster", ["Merle Travis"]))
    assert not R.concorde("Selenge", "Autre", piste("Selenge", ["Céline Dessberg"]))
    assert not R.concorde("Autre titre", "Céline Dessberg", piste("Selenge", ["Céline Dessberg"]))


def test_requetes_exacte_puis_libre():
    assert R.requetes('Pa"tricia (Radio Edit)', "Orquesta Aragon") == [
        'track:"Patricia" artist:"Orquesta Aragon"', "Patricia Orquesta Aragon"]


def test_spotify_de_image_300():
    sp = R.spotify_de(piste("Patricia", ["Orquesta Aragon", "B"]))
    assert sp == {"uri": URI, "lien": "https://open.spotify.com/track/" + "A" * 22, "titre": "Patricia",
                  "artistes": "Orquesta Aragon, B", "image": "https://i/300"}


# MARK: - Sources

def test_flux_tsugi_morceau_et_jingle():
    etats = lecteur("library://radio/5", "Valley of tangled eyes", "Asagaya", "Tsugi Radio")
    _, etat, station = R.radio_en_cours(etats, AJOUTEES)
    assert station == "Tsugi Radio"
    assert R.morceau_du_flux(etat, station) == ("Valley of tangled eyes", "Asagaya")
    jingle = lecteur("library://radio/5", "JG SPRING 26", "Tsugi Radio", "Tsugi Radio")
    _, etat, station = R.radio_en_cours(jingle, AJOUTEES)
    assert R.morceau_du_flux(etat, station) is None
    jingle2 = lecteur("library://radio/6", "Jingle station", "Quelqu'un")
    _, etat, station = R.radio_en_cours(jingle2, AJOUTEES)
    assert R.morceau_du_flux(etat, station) is None


def test_flux_sans_artiste_ou_titre_fichier():
    _, etat, st = R.radio_en_cours(lecteur("library://radio/6", "Sunshine Radio"), AJOUTEES)
    assert R.morceau_du_flux(etat, st) is None
    _, etat, st = R.radio_en_cours(lecteur("https://icecast.radiofrance.fr/fip-hifi.aac", "fip-hifi.aac", "X"), [])
    assert R.morceau_du_flux(etat, st) is None


def test_radio_en_cours_ls50_puis_lsx_et_pas_en_pause():
    assert R.radio_en_cours(lecteur("library://radio/5", "x", state="paused"), AJOUTEES) is None
    assert R.radio_en_cours(lecteur("library://track/12", "Titre", "A"), AJOUTEES) is None
    lsx = lecteur("tunein--aPad5vVY://radio/s15474", "RTS Couleur 3", entite="media_player.lsx_1190fa")
    entite, _, station = R.radio_en_cours(lsx, [])
    assert (entite, station) == ("media_player.lsx_1190fa", "Couleur 3")


def test_api_de():
    assert R.api_de("tunein--aPad5vVY://radio/s15474", "Couleur 3") == ("rts", R.RTS_URL)
    assert R.api_de("https://icecast.radiofrance.fr/franceinter-hifi.aac", "France Inter")[1].endswith("/pull/1")
    assert R.api_de("https://icecast.radiofrance.fr/franceculture-hifi.aac", "France Culture")[1].endswith("/pull/5")
    assert R.api_de("https://icecast.radiofrance.fr/fip-hifi.aac", "Radio")[1].endswith("/pull/7")
    assert R.api_de("library://radio/5", "Tsugi Radio") is None


def test_rts_en_cours_ou_recent():
    assert R.morceau_rts(RTS, R._epoch("2026-10-29T20:33:00+01:00")) == ("Patricia", "Orquesta Aragon")
    vieux = {"songList": [dict(RTS["songList"][1])]}
    assert R.morceau_rts(vieux, R._epoch("2026-10-29T20:30:00+01:00")) == ("Selenge", "Céline Dessberg")
    assert R.morceau_rts(vieux, R._epoch("2026-10-29T20:40:00+01:00")) is None
    assert R.morceau_rts({}, EPOCH) is None


def test_radiofrance_pull_et_emission():
    assert R.morceau_radiofrance(RF_FIP, EPOCH) == ("Divorce me C.O.D.", "Merle Travis")
    assert R.morceau_radiofrance(RF_FIP, 1793302500) == ("I'm a Long Gone Daddy", "Hank Williams")
    assert R.morceau_radiofrance(RF_EMISSION, EPOCH) is None
    now_song = {"now": {"firstLine": "x", "song": {"title": "T", "interpreters": ["A", "B"]}}}
    assert R.morceau_radiofrance(now_song, EPOCH) == ("T", "A, B")


# MARK: - Capteur

def test_rien_sans_radio():
    etat, attrs = suivi(Faux()).calculer({}, AJOUTEES, 0, EPOCH, ISO)
    assert etat == "rien" and attrs["titre"] is None and attrs["spotify"] is None and attrs["maj"] == ISO


def test_trouve_par_le_flux_et_cache_spotify():
    q = 'track:"Valley of tangled eyes" artist:"Asagaya"'
    f = Faux(pistes={q: [piste("Valley Of Tangled Eyes", ["Asagaya"])]})
    s = suivi(f)
    etats = lecteur("library://radio/5", "Valley of tangled eyes", "Asagaya", "Tsugi Radio")
    etat, attrs = s.calculer(etats, AJOUTEES, 0, EPOCH, ISO)
    assert etat == "trouve"
    assert attrs["origine"] == "flux" and attrs["station"] == "Tsugi Radio" and attrs["spotify"]["uri"] == URI
    assert attrs["deja_garde"] is False
    s.calculer(etats, AJOUTEES, 5, EPOCH, ISO)
    assert f.requetes == [q]          # une seule recherche par morceau
    assert f.urls == []               # pas d'API pour Tsugi
    s.garde(URI, "aime")
    assert s.calculer(etats, AJOUTEES, 10, EPOCH, ISO)[1]["deja_garde"] is True


def test_deja_garde_par_les_titres_likes_en_cache():
    appels = []

    def contient(uri):
        appels.append(uri)
        if len(appels) == 1:
            raise ConnectionError()
        return [True][0]

    q = 'track:"Valley of tangled eyes" artist:"Asagaya"'
    s = R.Suivi(Faux().lire, Faux(pistes={q: [piste("Valley of tangled eyes", ["Asagaya"])]}).chercher, contient)
    etats = lecteur("library://radio/5", "Valley of tangled eyes", "Asagaya", "Tsugi Radio")
    etat, attrs = s.calculer(etats, AJOUTEES, 0, EPOCH, ISO)
    assert etat == "trouve" and attrs["deja_garde"] is False      # erreur : pas indisponible, pas en cache
    assert s.calculer(etats, AJOUTEES, 5, EPOCH, ISO)[1]["deja_garde"] is True
    s.calculer(etats, AJOUTEES, 10, EPOCH, ISO)
    assert appels == [URI, URI]


def test_inconnu_spotify_apres_deux_recherches():
    f = Faux()
    etat, attrs = suivi(f).calculer(lecteur("library://radio/6", "Rare", "Inconnu"), AJOUTEES, 0, EPOCH, ISO)
    assert etat == "inconnu_spotify" and attrs["titre"] == "Rare" and attrs["spotify"] is None
    assert len(f.requetes) == 2


def test_emission_jingle():
    etat, attrs = suivi(Faux()).calculer(lecteur("library://radio/5", "JG SPRING 26", "Tsugi Radio", "Tsugi Radio"),
                                         AJOUTEES, 0, EPOCH, ISO)
    assert etat == "emission" and attrs["station"] == "Tsugi Radio" and attrs["titre"] is None


def test_couleur3_par_la_rts_avant_le_flux_et_rythme_30s():
    f = Faux(json={R.RTS_URL: RTS},
             pistes={'track:"Patricia" artist:"Orquesta Aragon"': [piste("Patricia", ["Orquesta Aragon"])]})
    s = suivi(f)
    etats = lecteur("tunein--aPad5vVY://radio/s15474", "Nom de l'émission", "Couleur 3")
    etat, attrs = s.calculer(etats, [], 100, R._epoch("2026-10-29T20:33:00+01:00"), ISO)
    assert etat == "trouve" and attrs["origine"] == "rts" and attrs["station"] == "Couleur 3"
    s.calculer(etats, [], 110, R._epoch("2026-10-29T20:33:10+01:00"), ISO)
    assert len(f.urls) == 1
    s.calculer(etats, [], 131, R._epoch("2026-10-29T20:33:31+01:00"), ISO)
    assert len(f.urls) == 2


def test_radiofrance_emission():
    url = R.RF_URL.format(1)
    etat, attrs = suivi(Faux(json={url: RF_EMISSION})).calculer(
        lecteur("https://icecast.radiofrance.fr/franceinter-hifi.aac", "franceinter-hifi.aac"), [], 0, EPOCH, ISO)
    assert etat == "emission" and attrs["origine"] == "radiofrance" and attrs["station"] == "France Inter"


def test_erreur_api_ou_spotify_indisponible():
    erreur = ConnectionError("coupure")
    etats = lecteur("tunein--aPad5vVY://radio/s15474", "RTS Couleur 3")
    etat, attrs = suivi(Faux(erreur_json=erreur)).calculer(etats, [], 0, EPOCH, ISO)
    assert etat == "unavailable" and attrs == {"maj": ISO, "erreur": "ConnectionError"}
    f = Faux(erreur_spotify=TimeoutError())
    s = suivi(f)
    etats = lecteur("library://radio/5", "Valley of tangled eyes", "Asagaya", "Tsugi Radio")
    assert s.calculer(etats, AJOUTEES, 0, EPOCH, ISO)[0] == "unavailable"
    assert s.cache == {}              # l'erreur n'est pas gardée comme « pas sur Spotify »


def test_a_publier():
    a = R.sortie("rien", "x")
    assert R.a_publier(None, a, 0, 0)
    assert not R.a_publier(a, R.sortie("rien", "y"), 0, 30)
    assert R.a_publier(a, R.sortie("rien", "y"), 0, 601)
    assert R.a_publier(a, R.sortie("emission", "y", station="FIP"), 0, 30)


# MARK: - Garder ce titre

class ClientFaux:
    def __init__(self, contenu=(), erreur=None):
        self._contenu, self.erreur = set(contenu), erreur
        self.appels = []

    def contenu(self, pid):
        if self.erreur:
            raise self.erreur
        self.appels.append(("contenu", pid))
        return set(self._contenu)

    def _call(self, method, path, **kw):
        self.appels.append((method, path, kw.get("json")))
        return {}

    def aimer(self, kind, ident):
        self.appels.append(("aimer", kind, ident))


def test_garder_ajoute_sans_creer_ni_doublon():
    c = ClientFaux()
    assert R.garder(c, "PID", URI, "a_ecouter") is True
    assert c.appels == [("contenu", "PID"), ("POST", "/playlists/PID/items", {"uris": [URI]})]
    c = ClientFaux(contenu=[URI])
    assert R.garder(c, "PID", URI, "a_ecouter") is False
    assert [a[0] for a in c.appels] == ["contenu"]


def test_garder_aime_et_erreurs():
    c = ClientFaux()
    assert R.garder(c, None, URI) is True and c.appels == [("aimer", "track", "A" * 22)]   # défaut : titres likés
    with pytest.raises(ValueError):
        R.garder(ClientFaux(), "PID", "spotify:album:" + "A" * 22)
    with pytest.raises(ValueError):
        R.garder(ClientFaux(), None, URI, "a_ecouter")
    with pytest.raises(ConnectionError):
        R.garder(ClientFaux(erreur=ConnectionError()), "PID", URI, "a_ecouter")


def test_destination_et_uri():
    assert R.destination(None) == "aime" and R.destination("a_ecouter") == "a_ecouter" and R.destination("x") == "aime"
    assert R.uri_valide(URI) == "A" * 22 and R.uri_valide("spotify:track:court") is None


def test_infos_garde_et_entendus():
    dernier = R.sortie("trouve", ISO, "Patricia", "Orquesta Aragon", "Couleur 3", "rts", {"uri": URI}, False)
    assert R.infos_garde(URI, dernier, {}) == {"titre": "Patricia", "artiste": "Orquesta Aragon", "station": "Couleur 3"}
    cache = {("a", "b"): {"uri": URI, "titre": "T", "artistes": "A"}}
    assert R.infos_garde(URI, None, cache) == {"titre": "T", "artiste": "A", "station": None}
    assert R.texte_garde({"titre": "Patricia", "artiste": "Orquesta Aragon"}) == "Liké : Patricia — Orquesta Aragon"
    assert R.texte_garde({"titre": "Patricia", "artiste": "X"}, "a_ecouter") == "Gardé : Patricia — X"
    valeur = {"entendus": [{"uri": f"u{i}"} for i in range(200)]}
    apres = R.entendus_apres(valeur, {"uri": URI})
    assert len(apres["entendus"]) == 200 and apres["entendus"][0]["uri"] == URI
    assert R.entendus_apres(None, {"uri": URI}) == {"entendus": [{"uri": URI}]}
    assert R.uris_entendus(apres) >= {URI, "u0"}


def test_contient_library_puis_repli_tracks():
    import httpx

    class C:
        def __init__(self, code=None):
            self.code, self.appels = code, []

        def _call(self, method, path, **kw):
            self.appels.append((path, kw["params"]))
            if path == "/me/library/contains" and self.code:
                raise httpx.HTTPStatusError("x", request=None, response=httpx.Response(self.code))
            return [True]

    c = C()
    assert R.contient(c, URI) is True and c.appels == [("/me/library/contains", {"uris": URI})]
    c = C(404)
    assert R.contient(c, URI) is True and c.appels[1] == ("/me/tracks/contains", {"ids": "A" * 22})
    with pytest.raises(httpx.HTTPStatusError):
        R.contient(C(503), URI)
