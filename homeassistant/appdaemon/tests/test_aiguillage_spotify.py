"""Tests hors Home Assistant de `aiguillage_spotify` : python3 homeassistant/appdaemon/tests/test_aiguillage_spotify.py"""

from datetime import date
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import aiguillage_spotify as s  # noqa: E402

TODAY = date(2026, 10, 16)


def test_liens():
    assert s.spotify_ref("https://open.spotify.com/track/4W6n5MoDbQmPhaZHx4MFSzb52c4f4a") == ("track", "4W6n5MoDbQmPhaZHx4MFSz")
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
    # Appareils réels du 16/10 : la TV, les enceintes du salon.
    reels = [{"id": "t", "name": "tv salon", "type": "TV"}, {"id": "l", "name": "Salon LS50", "type": "Speaker"},
             {"id": "f", "name": "Freebox Player POP", "type": "TV"}]
    assert s.appareil(reels)["id"] == "f"
    assert s.appareil(reels, "ls50")["id"] == "l"
    assert s.appareil(reels, "sonos") is None


def test_copie_playlist():
    items = [
        {"item": {"type": "track", "id": "A1", "uri": "spotify:track:A1", "name": "Spaceships",
                  "artists": [{"name": "Robots in Lilac"}],
                  "album": {"images": [{"url": "big", "width": 640}, {"url": "mid", "width": 300}, {"url": "small", "width": 64}]}}},
        {"item": {"type": "episode", "id": "E1", "uri": "spotify:episode:E1", "name": "Épisode 3",
                  "images": [{"url": "ep", "width": 600}], "show": {"name": "Un podcast"}}},
        {"item": None},  # titre retiré du catalogue
    ]
    c = s.copie_playlist(items, "PL", "2026-10-16T18:00:00+00:00")
    assert c["playlist"] == "PL" and len(c["titres"]) == 2
    # Les plus récents (ajoutés en dernier) d'abord.
    assert c["titres"][0] == {"lien": "https://open.spotify.com/episode/E1", "titre": "Épisode 3", "artistes": "Un podcast",
                              "image": "ep", "type": "episode"}
    assert c["titres"][1]["image"] == "mid" and c["titres"][1]["artistes"] == "Robots in Lilac"


def test_ecoute():
    def el(i, album):
        return {"item": {"type": "track", "id": i, "uri": f"spotify:track:{i}", "name": i, "album": {"id": album}}}
    elements = [el("T1", "AL"), el("T2", "AL"), el("T3", "AUTRE")]
    assert s.album_de(elements, ("track", "T1")) == "AL"
    assert s.album_de(elements, ("track", "X")) is None
    assert s.album_reste(elements, "AL", "spotify:track:T1")
    assert not s.album_reste(elements, "AUTRE", "spotify:track:T3")

    def tache(cle, lien, **kw):
        return {"cle": cle, "version": 3, "valeur": dict({"titre": cle, "envie": {"type": "ecouter", "lien": lien}}, **kw)}
    records = [
        tache("morceau", "https://open.spotify.com/track/T1"),
        tache("album", "https://open.spotify.com/album/AL"),
        tache("deja", "https://open.spotify.com/track/T1", fait=True),
        tache("autre", "https://open.spotify.com/track/T9"),
        {"cle": "lu", "version": 1, "valeur": {"titre": "lu", "envie": {"type": "lire", "lien": "https://open.spotify.com/track/T1"}}},
    ]
    # L'album garde des titres : seul le morceau est coché.
    assert [r["cle"] for r in s.envies_ecoutees(records, ("track", "T1"), "AL", False)] == ["morceau"]
    # Plus rien de l'album : l'album aussi.
    assert [r["cle"] for r in s.envies_ecoutees(records, ("track", "T1"), "AL", True)] == ["morceau", "album"]
    c = s.cochee({"titre": "x", "envie": {"type": "ecouter"}}, "2026-10-19T15:00:00Z")
    assert c == {"titre": "x", "envie": {"type": "ecouter"}, "fait": True, "fait_le": "2026-10-19T15:00:00Z"}


def test_coupure_reseau():
    """Coupure réseau (20/10) : appel rejoué si sans effet double, sinon l'erreur remonte tout de suite."""
    import types
    faux = types.ModuleType("httpx")
    faux.TransportError = type("TransportError", (Exception,), {})
    sys.modules.setdefault("httpx", faux)
    erreur = sys.modules["httpx"].TransportError
    s.time.sleep, dormir = (lambda _: None), s.time.sleep
    try:
        essais = []

        def requete(echecs):
            def f():
                essais.append(1)
                if len(essais) <= echecs:
                    raise erreur("Server disconnected without sending a response.")
                return "ok"
            return f

        assert s.Client._envoyer(True, requete(2)) == "ok" and len(essais) == 3
        essais.clear()
        try:
            s.Client._envoyer(True, requete(3))
            raise AssertionError("l'erreur aurait dû remonter")
        except erreur:
            assert len(essais) == 3
        essais.clear()
        try:
            s.Client._envoyer(False, requete(1))  # ajout à la playlist : pas rejoué
            raise AssertionError("l'erreur aurait dû remonter")
        except erreur:
            assert len(essais) == 1
    finally:
        s.time.sleep = dormir


def test_playlist_meme_nom():
    """27/10 : trois « À écouter ». Nom comparé sans accents, casse, espaces ni forme Unicode ; autres comptes ignorés."""
    import unicodedata
    moi = "alex"
    nfd = unicodedata.normalize("NFD", "À écouter")
    assert s.nom_cle(nfd) == s.nom_cle("À écouter") == s.nom_cle(" a  ÉCOUTER ") == "a ecouter"
    playlists = [{"id": "X", "name": "À écouter", "owner": {"id": "autre"}},
                 {"id": "Y", "name": "Jazz", "owner": {"id": moi}},
                 {"id": "Z", "name": nfd, "owner": {"id": moi}},
                 {"id": "W", "name": "A écouter", "owner": {"id": moi}}]
    assert s.playlist_existante(playlists, moi) == "Z"
    assert s.playlist_existante(playlists[:2], moi) is None
    assert s.playlist_existante([{"id": "V", "name": None}], moi) is None


def test_playlist_configuree():
    pid = "3bZ9RxcAN2UIXIhgGYHhlp"
    assert s.playlist_configuree({"valeur": {"playlist": pid, "titres": []}}) == pid
    for vide in (None, {}, {"valeur": None}, {"valeur": {"playlist": ""}}, {"valeur": {"playlist": "a/b"}}, {"valeur": []}):
        assert s.playlist_configuree(vide) is None


class _Faux(s.Client):
    """Client sans réseau : réponses rangées par (méthode, chemin)."""

    def __init__(self, reponses, playlist_id=None):
        super().__init__({}, playlist_id=playlist_id)
        self.reponses, self.appels = reponses, []

    def _call(self, method, path, **kw):
        self.appels.append((method, path))
        r = self.reponses[(method, path)]
        if isinstance(r, Exception):
            raise r
        return r


def _httpx():
    """httpx réel, ou à défaut un faux module (comme `test_reseau`) avec l'erreur HTTP et son code."""
    import types
    try:
        import httpx
    except ImportError:
        httpx = sys.modules.setdefault("httpx", types.ModuleType("httpx"))
    if not hasattr(httpx, "HTTPStatusError"):
        class HTTPStatusError(Exception):
            def __init__(self, message, request=None, response=None):
                super().__init__(message)
                self.response = response
        httpx.HTTPStatusError = HTTPStatusError
    return httpx


def _erreur_http(code):
    import types
    return _httpx().HTTPStatusError(str(code), request=None, response=types.SimpleNamespace(status_code=code))


def test_client_reutilise_la_playlist_configuree():
    httpx = _httpx()
    pid, autre = "3bZ9RxcAN2UIXIhgGYHhlp", "2Rs2gc1QxanmMILrDnpHzu"
    moi = {("GET", "/me"): {"id": "alex"}}
    liste = {("GET", "/me/playlists"): {"items": [{"id": autre, "name": "À écouter", "owner": {"id": "alex"}}]}}
    creee = {("POST", "/me/playlists"): {"id": "NOUVELLE"}}
    # Configurée et présente : ni recherche ni création, et gardée pour les appels suivants.
    c = _Faux({**moi, ("GET", f"/playlists/{pid}"): {"id": pid, "owner": {"id": "alex"}}, **liste, **creee}, pid)
    assert c.playlist() == pid and c.playlist() == pid
    assert ("GET", "/me/playlists") not in c.appels and ("POST", "/me/playlists") not in c.appels
    # Panne de Spotify (503) : l'erreur remonte, rien n'est créé.
    c = _Faux({**moi, ("GET", f"/playlists/{pid}"): _erreur_http(503), **liste, **creee}, pid)
    try:
        c.playlist()
        raise AssertionError("le 503 aurait dû remonter")
    except httpx.HTTPStatusError:
        assert ("POST", "/me/playlists") not in c.appels
    # Configurée mais supprimée (404) : une existante du même nom plutôt qu'une nouvelle.
    c = _Faux({**moi, ("GET", f"/playlists/{pid}"): _erreur_http(404), **liste, **creee}, pid)
    assert c.playlist() == autre and ("POST", "/me/playlists") not in c.appels
    # Rien de configuré ni d'existant : création (une seule fois).
    c = _Faux({**moi, ("GET", "/me/playlists"): {"items": []}, **creee})
    assert c.playlist() == "NOUVELLE" and c.playlist() == "NOUVELLE"
    assert c.appels.count(("POST", "/me/playlists")) == 1


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
