"""Tests hors Home Assistant de `aiguillage_spotify_lecture` (sensor.spotify_lecture, scripts LS50) :
uv run --with pytest --with httpx python -m pytest -q homeassistant/appdaemon/tests/test_aiguillage_spotify_lecture.py"""

from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import aiguillage_spotify_lecture as L  # noqa: E402

ISO = "2026-10-27T17:00:00+01:00"

PISTE = {
    "type": "track", "id": "T1", "uri": "spotify:track:T1", "name": "Monsun", "duration_ms": 440000,
    "artists": [{"name": "Lukas Endhardt", "uri": "spotify:artist:A1"}, {"name": "B", "uri": "spotify:artist:B2"}],
    "album": {"name": "Buteo EP", "uri": "spotify:album:AL1",
              "images": [{"url": "https://i/640", "width": 640}, {"url": "https://i/300", "width": 300},
                         {"url": "https://i/64", "width": 64}]},
    "external_urls": {"spotify": "https://open.spotify.com/track/T1"},
}


def player(appareil="Salon LS50", joue=True, contexte="spotify:playlist:P1", item=PISTE, progress=11000):
    p = {"device": {"id": "d1", "name": appareil}, "is_playing": joue, "item": item, "progress_ms": progress}
    if contexte:
        p["context"] = {"uri": contexte, "type": contexte.split(":")[1]}
    return p


class Reponse:
    def __init__(self, code, headers=None):
        self.status_code = code
        self.headers = headers or {}


class ErreurHttp(Exception):
    def __init__(self, code, headers=None):
        super().__init__(f"http {code}")
        self.response = Reponse(code, headers)


class ReadTimeout(Exception):
    pass


class Faux:
    """Client factice : compte les appels, lève les erreurs demandées."""

    def __init__(self, lecteur=None, devices=None, noms=None, erreur=None, recents=None):
        self._lecteur = lecteur if lecteur is not None else {}
        self._devices = devices if devices is not None else [{"id": "ls", "name": "Salon LS50"}]
        self._noms = noms or {}
        self.erreur = erreur
        self._recents = recents
        self.appels = []

    def _a(self, nom):
        self.appels.append(nom)
        if self.erreur and nom in self.erreur:
            raise self.erreur[nom]

    def lecteur(self):
        self._a("lecteur")
        return self._lecteur

    def appareils(self):
        self._a("appareils")
        return self._devices

    def nom(self, kind, ident):
        self._a("nom")
        return self._noms.get((kind, ident))

    def recents(self):
        self._a("recents")
        return self._recents

    def transferer(self, device_id):
        self._a("transferer")
        self.transfere = device_id

    def jouer(self, device_id, corps):
        self._a("jouer")
        self.joue = (device_id, corps)


# MARK: - Capteur

def test_attributs_lecture_sur_ls50():
    etat, a = L.attributs(player(), False, "Matin calme", ISO)
    assert etat == "lecture"
    assert a["appareil"] == "Salon LS50" and a["sur_ls50"] is True and a["ls50_visible"] is True
    assert a["titre"] == "Monsun" and a["artistes"] == "Lukas Endhardt, B" and a["album"] == "Buteo EP"
    assert a["image"] == "https://i/300"
    assert a["lien"] == "https://open.spotify.com/track/T1"
    assert a["contexte"] == {"type": "playlist", "nom": "Matin calme", "lien": "https://open.spotify.com/playlist/P1"}
    assert a["duree_s"] == 440 and a["position_s"] == 11 and a["position_le"] == ISO and a["maj"] == ISO


def test_attributs_autre_appareil_pause_et_rien():
    etat, a = L.attributs(player("iPhone", joue=False, contexte=None), True, None, ISO)
    assert etat == "pause" and a["appareil"] == "iPhone" and a["sur_ls50"] is False and a["ls50_visible"] is True
    assert a["contexte"] == {"type": None, "nom": None, "lien": None}
    etat, a = L.attributs({}, False, None, ISO)
    assert etat == "rien" and a["appareil"] is None and a["titre"] is None and a["sur_ls50"] is False
    assert a["position_le"] is None and a["ls50_visible"] is False
    # Toutes les clés du contrat, toujours présentes (publiées par l'API REST, nulls compris).
    assert set(a) == {"appareil", "sur_ls50", "titre", "artistes", "album", "image", "lien", "contexte", "duree_s",
                      "position_s", "position_le", "ls50_visible", "maj"}


def test_nom_ls50_tolere_casse_et_accents():
    assert L.est_ls50("salon  ls50") and not L.est_ls50("LSX 1190FA") and not L.est_ls50(None)
    assert L.appareil_ls50([{"name": "iPad"}, {"name": "Salon LS50", "id": "x"}])["id"] == "x"


def test_episode():
    ep = {"type": "episode", "id": "E1", "name": "Épisode", "duration_ms": 60000,
          "images": [{"url": "https://i/e", "width": 640}], "show": {"name": "Le podcast", "uri": "spotify:show:S1"}}
    etat, a = L.attributs(player(item=ep, contexte="spotify:show:S1"), False, "Le podcast", ISO)
    assert a["artistes"] == "Le podcast" and a["album"] == "Le podcast" and a["image"] == "https://i/e"
    assert a["lien"] == "https://open.spotify.com/episode/E1"


def test_ref_uri_et_nom_sans_appel():
    assert L.ref_uri("spotify:playlist:P1") == ("playlist", "P1")
    assert L.ref_uri("spotify:user:alex:playlist:P2") == ("playlist", "P2")
    assert L.ref_uri("spotify:user:alex:collection") == ("collection", "alex")
    assert L.ref_uri(None) is None and L.ref_uri("x") is None
    assert L.nom_sans_appel({"uri": "spotify:album:AL1"}, PISTE) == "Buteo EP"
    assert L.nom_sans_appel({"uri": "spotify:artist:B2"}, PISTE) == "B"
    assert L.nom_sans_appel({"uri": "spotify:user:a:collection"}, PISTE) == "Titres likés"
    assert L.nom_sans_appel({"uri": "spotify:playlist:P1"}, PISTE) is None


def test_a_publier():
    a = L.attributs(player(progress=10000), True, "X", ISO)
    assert L.a_publier(None, a, 0, 0)
    # 15 s plus tard, position avancée de 15 s, même contenu : rien à publier.
    b = L.attributs(player(progress=25000), True, "X", "2026-10-27T17:00:15+01:00")
    assert not L.a_publier(a, b, 0, 15)
    # Saut dans le morceau : publié.
    c = L.attributs(player(progress=90000), True, "X", ISO)
    assert L.a_publier(a, c, 0, 15)
    # Pause : publié (état) ; changement de titre : publié ; 10 min sans publication : publié.
    assert L.a_publier(a, L.attributs(player(joue=False, progress=25000), True, "X", ISO), 0, 15)
    assert L.a_publier(a, L.attributs(player(item=dict(PISTE, name="Autre")), True, "X", ISO), 0, 15)
    assert L.a_publier(a, b, 0, L.REPUBLIER)


def test_classer():
    assert L.classer(ErreurHttp(429, {"Retry-After": "42"})) == ("429", 42)
    assert L.classer(ErreurHttp(429)) == ("429", L.PAUSE_429)
    assert L.classer(ErreurHttp(429, {"Retry-After": "99999"}))[1] == L.PAUSE_429_MAX
    assert L.classer(ErreurHttp(503)) == ("http 503", L.PAUSE_SERVEUR)
    assert L.classer(ErreurHttp(401))[1] == L.PAUSE_REFUS
    assert L.classer(ReadTimeout()) == ("délai", L.PAUSE_RESEAU)


def test_classer_vraies_erreurs_httpx():
    httpx = pytest.importorskip("httpx")
    if not hasattr(httpx, "Request"):  # un autre test a mis un faux httpx dans sys.modules
        pytest.skip("faux httpx chargé par un autre test")
    requete = httpx.Request("GET", "https://api.spotify.com/v1/me/player")
    erreur = httpx.HTTPStatusError("x", request=requete,
                                   response=httpx.Response(429, headers={"Retry-After": "7"}, request=requete))
    assert L.classer(erreur) == ("429", 7)
    assert L.classer(httpx.ConnectTimeout("x"))[0] == "délai"
    assert L.classer(httpx.ConnectError("x"))[0] == "réseau"


# MARK: - Rythme, cache, erreurs

def test_rythme_rapide_lent_et_ecart_minimum():
    faux = Faux(lecteur=player())
    lec = L.Lecture(lambda: faux)
    assert lec.due(0, False)
    assert lec.interroger(0, ISO)[0] == "lecture"
    # Jamais deux interrogations à moins de 15 s, même forcées.
    assert lec.interroger(5, ISO) is None
    assert not lec.due(10, True) and lec.due(15, True)
    # Hors Wi-Fi et sans demande : 2 min.
    assert not lec.due(60, False) and lec.due(120, False)
    # Une vue demande : rythme rapide pendant 5 min.
    lec.demander(100)
    assert lec.due(15, False) and lec.rapide(399, False) and not lec.rapide(400, False)


def test_erreurs_donnent_unavailable_et_pause_sans_rien_ecrire():
    faux = Faux(erreur={"lecteur": ErreurHttp(429, {"Retry-After": "60"})})
    lec = L.Lecture(lambda: faux)
    etat, a = lec.interroger(0, ISO)
    assert etat == "unavailable" and a["erreur"] == "429"
    assert not lec.due(59, True) and lec.interroger(59, ISO) is None and lec.due(60, True)
    for erreur, pause in ((ErreurHttp(502), L.PAUSE_SERVEUR), (ReadTimeout(), L.PAUSE_RESEAU)):
        faux = Faux(erreur={"lecteur": erreur})
        lec = L.Lecture(lambda: faux)
        assert lec.interroger(0, ISO)[0] == "unavailable"
        assert not lec.due(pause - 1, True) and lec.due(pause, True)
    # Erreur sur la liste des appareils : unavailable aussi. Jamais d'écriture.
    faux = Faux(lecteur=player("iPhone"), erreur={"appareils": ErreurHttp(500)})
    assert L.Lecture(lambda: faux).interroger(0, ISO)[0] == "unavailable"
    assert "transferer" not in faux.appels and "jouer" not in faux.appels


def test_sans_identifiants():
    assert L.Lecture(lambda: None).interroger(0, ISO) == ("unavailable", {"maj": ISO, "erreur": "identifiants absents"})


def test_cache_des_noms_et_des_appareils():
    faux = Faux(lecteur=player("iPhone"), noms={("playlist", "P1"): "Matin calme"})
    lec = L.Lecture(lambda: faux)
    assert lec.interroger(0, ISO)[1]["contexte"]["nom"] == "Matin calme"
    lec.interroger(15, ISO)
    lec.interroger(30, ISO)
    assert faux.appels.count("nom") == 1           # nom en cache
    assert faux.appels.count("appareils") == 1     # appareils relus au plus une fois par minute
    lec.interroger(60, ISO)
    assert faux.appels.count("appareils") == 2
    # Lecture sur les LS50 : pas besoin de la liste des appareils.
    faux2 = Faux(lecteur=player("Salon LS50", contexte="spotify:album:AL1"))
    attributs = L.Lecture(lambda: faux2).interroger(0, ISO)[1]
    assert faux2.appels == ["lecteur"] and attributs["contexte"]["nom"] == "Buteo EP"


def test_nom_introuvable_sans_unavailable_mais_429_si():
    faux = Faux(lecteur=player(), erreur={"nom": ErreurHttp(404)})
    lec = L.Lecture(lambda: faux)
    etat, a = lec.interroger(0, ISO)
    assert etat == "lecture" and a["contexte"]["nom"] is None and a["contexte"]["type"] == "playlist"
    lec.interroger(15, ISO)
    assert faux.appels.count("nom") == 1           # absence gardée 1 h
    faux = Faux(lecteur=player(), erreur={"nom": ErreurHttp(429, {"Retry-After": "5"})})
    assert L.Lecture(lambda: faux).interroger(0, ISO)[0] == "unavailable"


def test_memoire_pour_reprendre():
    lec = L.Lecture(lambda: Faux(lecteur=player()))
    lec.interroger(0, ISO)
    assert lec.memoire == {"context_uri": "spotify:playlist:P1", "uri": "spotify:track:T1"}


# MARK: - Scripts

def test_transfert():
    faux = Faux(lecteur=player("iPhone"))
    assert L.agir("transfert", faux, "ls")[0] and faux.transfere == "ls"
    faux = Faux(lecteur=player("Salon LS50"))
    assert L.agir("transfert", faux, "ls") == (False, "déjà sur les LS50") and "transferer" not in faux.appels
    faux = Faux(lecteur={})
    assert L.agir("transfert", faux, "ls") == (False, "rien ne joue sur Spotify") and "transferer" not in faux.appels


def test_reprendre():
    # En pause (ici ou ailleurs) : reprise là où elle en était, par transfert.
    faux = Faux(lecteur=player("iPhone", joue=False))
    assert L.agir("reprendre", faux, "ls")[0] and faux.transfere == "ls"
    # Rien : dernier contexte de recently-played.
    faux = Faux(lecteur={}, recents={"items": [{"track": {"uri": "spotify:track:X"},
                                                "context": {"uri": "spotify:album:AL9"}}]})
    assert L.agir("reprendre", faux, "ls")[0] and faux.joue == ("ls", {"context_uri": "spotify:album:AL9"})
    # Sans contexte : le titre seul.
    faux = Faux(lecteur={}, recents={"items": [{"track": {"uri": "spotify:track:X"}, "context": None}]})
    L.agir("reprendre", faux, "ls")
    assert faux.joue == ("ls", {"uris": ["spotify:track:X"]})
    # Droit absent (403) ou non accordé : mémoire du capteur.
    faux = Faux(lecteur={}, erreur={"recents": ErreurHttp(403)})
    assert L.agir("reprendre", faux, "ls", {"context_uri": "spotify:playlist:P1", "uri": "spotify:track:T1"})[0]
    assert faux.joue == ("ls", {"context_uri": "spotify:playlist:P1"})
    faux = Faux(lecteur={})
    assert L.agir("reprendre", faux, "ls", None, recents_permis=False) == (False, "rien à reprendre")
    assert "recents" not in faux.appels and "jouer" not in faux.appels
    # Déjà en lecture sur les LS50 : rien.
    faux = Faux(lecteur=player())
    assert not L.agir("reprendre", faux, "ls")[0] and "transferer" not in faux.appels


def test_scripts_erreur_spotify_remonte_sans_ecrire():
    faux = Faux(lecteur={}, erreur={"recents": ErreurHttp(503)})
    with pytest.raises(ErreurHttp):
        L.agir("reprendre", faux, "ls", {"context_uri": "spotify:playlist:P1"})
    assert "jouer" not in faux.appels


def test_client_renouvelle_le_jeton_sur_401(monkeypatch):
    import aiguillage_spotify
    appels = []

    def call(self, method, path, **kw):
        appels.append((method, path, self._acces))
        if len(appels) == 1:
            raise ErreurHttp(401)
        return {"device": {"name": "iPad"}}

    monkeypatch.setattr(aiguillage_spotify.Client, "_call", call)
    client = L.ClientLecture({"client_id": "a", "client_secret": "b", "refresh_token": "c"})
    client._acces = "perime"
    assert client.lecteur() == {"device": {"name": "iPad"}}
    assert appels[1][2] is None  # jeton oublié avant le second essai
    # Jeton jamais obtenu (401 du serveur de jetons) : pas de boucle.
    appels.clear()
    client._acces = None
    with pytest.raises(ErreurHttp):
        client.lecteur()
    assert len(appels) == 1
