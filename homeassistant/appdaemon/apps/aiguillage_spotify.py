"""Envies « À écouter » sur Spotify (plan P9-D4) : playlist « À écouter » et lecture sur la TV.

Fonctions pures (testées hors Home Assistant par `tests/test_aiguillage_spotify.py`) et un petit client de l'API Web
(état février 2026 : `/playlists/{id}/items`, élément `item` au lieu de `track`, plus de requêtes groupées).
La vigie (`relance_vigie.py`) s'en sert :

- pour chaque envie à écouter avec un lien Spotify pas encore traité, ajouter le morceau, l'album (ses titres) ou
  l'épisode à la playlist « À écouter » (créée privée si absente), sans doublon, puis noter dans `envie.playlist`
  {ajoute_le, playlist, ajoutes, statut} (dans `envie`, que l'app conserve en entier) ;
- sur l'événement `aiguillage_spotify_lire` (script `script.aiguillage_spotify_sur_tv`), lancer la lecture sur
  l'appareil Spotify Connect du Freebox Player ;
- sur l'événement `aiguillage_spotify_ecoute` (script `script.aiguillage_spotify_ecoute`, « Écouté » d'un titre de la
  playlist sur la TV, P9-L2), retirer le titre de la playlist et cocher l'envie liée.

Identifiant, secret et jeton de rafraîchissement : `/config/spotify_aiguillage.json`, écrit une fois par
`homeassistant/scripts/spotify_jeton.py` sur le Mac ; jamais dans un dépôt.
"""

from datetime import date
import base64
import re
import time

API = "https://api.spotify.com/v1"
NOM_PLAYLIST = "À écouter"
DESCRIPTION = "Envies « À écouter » d'Aiguillage, ajoutées par la vigie."
# Un échec (lien mort, réseau) est retenté le lendemain, pas à chaque modification.
RETRY_DAYS = 1
# Coupures réseau (20/10 : connexion fermée sans réponse, poignée de main TLS interrompue) : nouvel essai après ces
# pauses, seulement pour les appels sans effet double (lecture, jeton, PUT, DELETE ; pas l'ajout à la playlist).
PAUSES_RESEAU = (1, 3)
SANS_EFFET_DOUBLE = {"GET", "PUT", "DELETE"}

# Identifiant : 22 caractères (du texte collé derrière est ignoré, cas du 19/10).
LIEN = re.compile(r"https?://open\.spotify\.com/(?:intl-[a-z-]+/)?(track|album|episode|playlist|artist|show)/([A-Za-z0-9]{1,22})")


def spotify_ref(texte):
    """Premier lien Spotify du texte → (type, id), ou None."""
    m = LIEN.search(texte or "")
    return (m.group(1), m.group(2)) if m else None


def lien_de(valeur):
    """Lien Spotify de la tâche : `envie.lien`, sinon le premier lien Spotify des notes."""
    envie = valeur.get("envie") or {}
    for texte in (envie.get("lien"), valeur.get("notes")):
        ref = spotify_ref(texte)
        if ref:
            return ref
    return None


def is_to_listen(valeur):
    """Envie « À écouter » : champ `envie.type`, ou à défaut la ligne `🎧 À écouter` des notes."""
    envie = valeur.get("envie")
    if envie:
        return envie.get("type") == "ecouter"
    return any(line.replace("️", "").strip().startswith("🎧 À écouter")
               for line in (valeur.get("notes") or "").split("\n"))


def needs_playlist(valeur, today):
    """À écouter, à faire, avec un lien Spotify ajoutable (morceau, album, épisode), pas encore ajoutée
    (ou en échec depuis au moins un jour)."""
    if valeur.get("fait") or not is_to_listen(valeur):
        return False
    ref = lien_de(valeur)
    if not ref or ref[0] not in ("track", "album", "episode"):
        return False
    deja = (valeur.get("envie") or {}).get("playlist") or {}
    if deja.get("statut") == "ok":
        return False
    if deja.get("statut") == "echec" and deja.get("maj"):
        try:
            return (today - date.fromisoformat(deja["maj"])).days >= RETRY_DAYS
        except ValueError:
            return True
    return True


def with_playlist(valeur, statut, today, playlist_id=None, ajoutes=0, erreur=None):
    """La tâche avec `envie.playlist` à jour (le reste recopié tel quel)."""
    valeur = dict(valeur)
    envie = dict(valeur.get("envie") or {"type": "ecouter"})
    note = {"statut": statut, "maj": today.isoformat()}
    if statut == "ok":
        note.update({"ajoute_le": today.isoformat(), "playlist": playlist_id, "ajoutes": ajoutes})
    if erreur:
        note["erreur"] = str(erreur)[:200]
    envie["playlist"] = note
    valeur["envie"] = envie
    valeur["v"] = max(valeur.get("v", 1), 2)
    return valeur


def uri(kind, ident):
    return f"spotify:{kind}:{ident}"


def a_ajouter(uris, deja):
    """URIs à ajouter, dans l'ordre, sans celles déjà dans la playlist ni doublons."""
    vus, out = set(deja), []
    for u in uris:
        if u not in vus:
            vus.add(u)
            out.append(u)
    return out


def lecture(kind, ident):
    """Corps de `PUT /me/player/play` : un contexte (album, playlist, artiste, émission) ou un élément seul."""
    if kind in ("album", "playlist", "artist", "show"):
        return {"context_uri": uri(kind, ident)}
    return {"uris": [uri(kind, ident)]}


def appareil_tv(devices):
    """Appareil Spotify Connect du Freebox Player (nom « Freebox… » ou type TV), sinon None."""
    for d in devices:
        if "freebox" in (d.get("name") or "").lower():
            return d
    tv = [d for d in devices if (d.get("type") or "").lower() in ("tv", "castvideo")]
    return tv[0] if len(tv) == 1 else None


# Appareils Spotify Connect choisis depuis l'app TV : « tv » (le Player) ou un morceau de nom (« ls50 »).
PLAYLIST_A_ECOUTER = "a_ecouter"


def appareil(devices, choix="tv"):
    """L'appareil voulu : « tv » → le Freebox Player ; sinon le premier dont le nom contient `choix`."""
    if not choix or choix == "tv":
        return appareil_tv(devices)
    voulu = choix.lower()
    return next((d for d in devices if voulu in (d.get("name") or "").lower().replace(" ", "")), None)


CLE_PLAYLIST = "config:playlist_a_ecouter"
MAX_TITRES = 100


def piste(item):
    """Élément de `/playlists/{id}/items` → {lien, titre, artistes, image, type} pour l'app TV (ou None)."""
    e = item.get("item") or item.get("track") or {}
    if not e.get("uri") or not e.get("id"):
        return None
    kind = e.get("type") or "track"
    images = (e.get("album") or {}).get("images") or e.get("images") or (e.get("show") or {}).get("images") or []
    artistes = ", ".join(a.get("name", "") for a in e.get("artists") or []) or (e.get("show") or {}).get("name", "")
    return {
        "lien": f"https://open.spotify.com/{kind}/{e['id']}",
        "titre": e.get("name") or "",
        "artistes": artistes,
        # La plus petite image d'au moins 300 px (assez pour une carte TV), sinon la première.
        "image": next((i["url"] for i in sorted(images, key=lambda i: i.get("width") or 0) if (i.get("width") or 0) >= 300),
                      images[0]["url"] if images else None),
        "type": kind,
    }


def copie_playlist(items, playlist_id, maj):
    """Valeur de `config:playlist_a_ecouter` : la playlist telle que l'app TV l'affiche (les plus récents d'abord)."""
    pistes = [p for p in (piste(i) for i in reversed(list(items))) if p]
    return {"playlist": playlist_id, "maj": maj, "titres": pistes[:MAX_TITRES]}


def album_de(elements, ref):
    """Identifiant de l'album du titre `ref` (type, id) dans les éléments de la playlist, ou None."""
    for it in elements:
        e = it.get("item") or it.get("track") or {}
        if e.get("uri") == uri(*ref):
            return (e.get("album") or {}).get("id")
    return None


def album_reste(elements, album_id, retire):
    """Vrai s'il reste dans la playlist un autre titre de l'album `album_id` que l'URI `retire`."""
    for it in elements:
        e = it.get("item") or it.get("track") or {}
        if e.get("uri") and e["uri"] != retire and (e.get("album") or {}).get("id") == album_id:
            return True
    return False


def envies_ecoutees(records, ref, album_id, album_fini):
    """Enregistrements des envies à cocher après « Écouté » sur le titre `ref` : celles dont le lien est ce titre,
    et celles dont le lien est son album quand plus aucun titre de l'album ne reste dans la playlist."""
    out = []
    for r in records:
        valeur = r.get("valeur") or {}
        if r.get("supprime") or valeur.get("fait") or not is_to_listen(valeur):
            continue
        lien = lien_de(valeur)
        if lien == ref or (album_fini and album_id and lien == ("album", album_id)):
            out.append(r)
    return out


def cochee(valeur, fait_le):
    """La tâche cochée (même forme que l'app TV et l'iPhone), le reste recopié tel quel."""
    return dict(valeur, fait=True, fait_le=fait_le)


class Client:
    """Appels à l'API Web avec un jeton d'accès obtenu par le jeton de rafraîchissement."""

    def __init__(self, identifiants, timeout=15):
        self._ids = identifiants
        self._timeout = timeout
        self._acces = None

    def _token(self):
        import httpx  # ici : les fonctions pures se testent sans httpx

        if self._acces:
            return self._acces
        basic = base64.b64encode(f"{self._ids['client_id']}:{self._ids['client_secret']}".encode()).decode()
        r = self._envoyer(True, lambda: httpx.post(
            "https://accounts.spotify.com/api/token", timeout=self._timeout, headers={"Authorization": f"Basic {basic}"},
            data={"grant_type": "refresh_token", "refresh_token": self._ids["refresh_token"]}))
        r.raise_for_status()
        self._acces = r.json()["access_token"]
        return self._acces

    def _call(self, method, path, **kw):
        import httpx

        url = path if path.startswith("http") else API + path
        jeton = self._token()
        r = self._envoyer(method in SANS_EFFET_DOUBLE, lambda: httpx.request(
            method, url, headers={"Authorization": f"Bearer {jeton}"}, timeout=self._timeout, **kw))
        r.raise_for_status()
        return r.json() if r.content else {}

    @staticmethod
    def _envoyer(rejouable, requete):
        """La requête, rejouée après une coupure réseau (`httpx.TransportError`) si elle est sans effet double."""
        import httpx

        for pause in (PAUSES_RESEAU if rejouable else ()):
            try:
                return requete()
            except httpx.TransportError:
                time.sleep(pause)
        return requete()

    def _pages(self, path, params=None):
        data = self._call("GET", path, params=dict(params or {}, limit=50))
        while True:
            yield from data.get("items", [])
            if not data.get("next"):
                return
            data = self._call("GET", data["next"])

    def playlist(self):
        """Identifiant de la playlist « À écouter » d'Alexandre, créée privée si absente."""
        moi = self._call("GET", "/me")["id"]
        for p in self._pages("/me/playlists"):
            if p.get("name") == NOM_PLAYLIST and (p.get("owner") or {}).get("id") == moi:
                return p["id"]
        return self._call("POST", "/me/playlists", json={"name": NOM_PLAYLIST, "public": False,
                                                         "description": DESCRIPTION})["id"]

    def contenu(self, playlist_id):
        out = set()
        for it in self._pages(f"/playlists/{playlist_id}/items", {"additional_types": "track,episode"}):
            element = it.get("item") or it.get("track") or {}
            if element.get("uri"):
                out.add(element["uri"])
        return out

    def elements(self, playlist_id):
        return list(self._pages(f"/playlists/{playlist_id}/items", {"additional_types": "track,episode"}))

    def uris(self, kind, ident):
        """Morceau ou épisode : lui-même ; album : ses titres (appels individuels, API de février 2026)."""
        if kind != "album":
            return [uri(kind, ident)]
        return [t["uri"] for t in self._pages(f"/albums/{ident}/tracks") if t.get("uri")]

    def ajouter(self, kind, ident):
        """Ajoute à la playlist ; renvoie (playlist_id, nombre ajouté)."""
        pid = self.playlist()
        nouveaux = a_ajouter(self.uris(kind, ident), self.contenu(pid))
        for i in range(0, len(nouveaux), 100):
            self._call("POST", f"/playlists/{pid}/items", json={"uris": nouveaux[i:i + 100]})
        return pid, len(nouveaux)

    def retirer(self, playlist_id, kind, ident):
        """Retire le titre de la playlist (toutes ses occurrences ; API de février 2026 : `items`)."""
        self._call("DELETE", f"/playlists/{playlist_id}/items", json={"items": [{"uri": uri(kind, ident)}]})

    def appareils(self):
        return self._call("GET", "/me/player/devices").get("devices", [])

    def lire(self, kind, ident, device_id):
        self._call("PUT", "/me/player/play", params={"device_id": device_id}, json=lecture(kind, ident))
