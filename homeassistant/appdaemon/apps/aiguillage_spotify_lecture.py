"""Lecture Spotify pour le Hub (27/10/2026) : `sensor.spotify_lecture` et les scripts `script.spotify_sur_ls50` /
`script.spotify_reprendre`. Contrat : `homeassistant/SPOTIFY-LECTURE.md` (AJOUT seulement : rien d'existant ne change).

Le capteur est en LECTURE SEULE de l'API Web (`GET /me/player`, `GET /me/player/devices`, nom de la playlist ou de
l'artiste en cache). Leçon des playlists en double (27/10) : une erreur Spotify (5xx, délai, 429, jeton refusé) donne
`unavailable`, n'écrit et ne crée rien ; un 429 est respecté (`Retry-After`). Seuls les scripts, appelés à la main
depuis une vue, écrivent (`PUT /me/player`, `PUT /me/player/play`).

Fonctions pures et `Lecture` (le rythme, le cache, les erreurs) testées hors Home Assistant par
`tests/test_aiguillage_spotify_lecture.py` ; la vigie (`relance_vigie.py`) fait le lien avec HA.
Client : celui de `aiguillage_spotify` (même fichier d'identifiants), sans nouvel essai sur coupure (le passage suivant
réessaie) et avec un jeton d'accès renouvelé sur un 401 (le client vit plusieurs heures).
"""

import threading

import aiguillage_spotify

ENTITE = "sensor.spotify_lecture"
NOM_LS50 = "Salon LS50"
ENTITE_KEF = "media_player.kef_ls50_wireless_ii"
# Rythme : toutes les 15 s quand les LS50 sont en entrée Wi-Fi (Spotify Connect possible) ou qu'une vue l'a demandé
# depuis moins de 5 min ; sinon toutes les 2 min. Jamais deux interrogations à moins de 15 s.
INTERVALLE_RAPIDE = 15
INTERVALLE_LENT = 120
ECART_MIN = 15
DEMANDE_VALIDE = 300
# Liste des appareils (pour `ls50_visible`) : relue au plus une fois par minute, et seulement si la lecture n'est pas
# déjà sur les LS50.
APPAREILS_VALIDES = 60
# Nom d'un contexte : gardé 6 h ; un nom introuvable (404/403 : playlist de Spotify fermée aux apps) gardé 1 h.
NOM_VALIDE = 6 * 3600
NOM_ABSENT_VALIDE = 3600
NOMS_MAX = 200
# Pauses après une erreur (s) ; 429 : `Retry-After` (30 s s'il manque, 1 h au plus).
PAUSE_RESEAU = 30
PAUSE_SERVEUR = 30
PAUSE_429 = 30
PAUSE_429_MAX = 3600
PAUSE_REFUS = 300
PAUSE_AUTRE = 60
# Publication : à chaque changement, et au moins toutes les 10 min (le capteur revient après un redémarrage de HA).
REPUBLIER = 600
DERIVE_POSITION = 3
# Réveil des LS50 pour les scripts : relire les appareils toutes les 4 s, 20 s au plus.
REVEIL_PAS = 4
REVEIL_MAX = 20


def est_ls50(nom):
    return aiguillage_spotify.nom_cle(nom) == aiguillage_spotify.nom_cle(NOM_LS50)


def appareil_ls50(devices):
    """L'appareil Spotify Connect « Salon LS50 », ou None."""
    return next((d for d in devices or [] if est_ls50(d.get("name"))), None)


def image(images):
    """La plus petite image d'au moins 300 px, sinon la plus grande (même choix que la playlist pour la TV)."""
    images = [i for i in images or [] if i.get("url")]
    if not images:
        return None
    triees = sorted(images, key=lambda i: i.get("width") or 0)
    return next((i["url"] for i in triees if (i.get("width") or 0) >= 300), triees[-1]["url"])


def ref_uri(uri):
    """`spotify:playlist:ID` → ("playlist", "ID") ; `spotify:user:x:collection` → ("collection", "x") ;
    ancienne forme `spotify:user:x:playlist:ID` comprise. None si illisible."""
    parts = (uri or "").split(":")
    if len(parts) < 3 or parts[0] != "spotify":
        return None
    if parts[-1] == "collection":
        return ("collection", parts[2] if len(parts) > 3 else "")
    return (parts[-2], parts[-1])


def lien_ouvert(kind, ident):
    if kind == "collection":
        return "https://open.spotify.com/collection/tracks"
    return f"https://open.spotify.com/{kind}/{ident}" if kind and ident else None


def nom_sans_appel(contexte, item):
    """Nom du contexte lu dans le morceau lui-même (album, artiste, émission, titres likés), sans appel ; sinon None."""
    uri = (contexte or {}).get("uri")
    ref = ref_uri(uri)
    if not ref or not item:
        return None
    if ref[0] == "collection":
        return "Titres likés"
    if ref[0] == "album" and (item.get("album") or {}).get("uri") == uri:
        return item["album"].get("name")
    if ref[0] == "artist":
        return next((a.get("name") for a in item.get("artists") or [] if a.get("uri") == uri), None)
    if ref[0] == "show" and (item.get("show") or {}).get("uri") == uri:
        return item["show"].get("name")
    return None


def etat_lecture(player):
    """« lecture » | « pause » | « rien » d'après `GET /me/player` ({} quand Spotify répond 204)."""
    if not player or not player.get("device"):
        return "rien"
    if player.get("is_playing"):
        return "lecture"
    return "pause" if player.get("item") else "rien"


def attributs(player, ls50_visible, nom_contexte, maintenant_iso):
    """(état, attributs) du capteur (contrat : SPOTIFY-LECTURE.md). `player` : réponse de `GET /me/player`."""
    etat = etat_lecture(player)
    player = player or {}
    item = player.get("item") or {}
    appareil = (player.get("device") or {}).get("name") if etat != "rien" else None
    kind = item.get("type") or "track"
    contexte = player.get("context") or {}
    ref = ref_uri(contexte.get("uri"))
    if etat == "rien" or not item:
        titre = artistes = album = img = lien = duree = position = None
    else:
        show = item.get("show") or {}
        titre = item.get("name")
        artistes = ", ".join(a.get("name", "") for a in item.get("artists") or []) or show.get("name") or None
        album = (item.get("album") or {}).get("name") or show.get("name")
        img = image((item.get("album") or {}).get("images") or item.get("images") or show.get("images"))
        lien = (item.get("external_urls") or {}).get("spotify") or lien_ouvert(kind, item.get("id"))
        duree = round(item["duration_ms"] / 1000) if item.get("duration_ms") is not None else None
        position = round(player["progress_ms"] / 1000) if player.get("progress_ms") is not None else None
    sur_ls50 = etat != "rien" and est_ls50(appareil)
    return etat, {
        "appareil": appareil,
        "sur_ls50": sur_ls50,
        "titre": titre,
        "artistes": artistes,
        "album": album,
        "image": img,
        "lien": lien,
        "contexte": {
            "type": ref[0] if ref and etat != "rien" else None,
            "nom": nom_contexte if ref and etat != "rien" else None,
            "lien": ((contexte.get("external_urls") or {}).get("spotify") or lien_ouvert(*ref))
            if ref and etat != "rien" else None,
        },
        # Aléatoire (29/10/2026, LECTURE-SOURCE.md) : `shuffle_state` de Spotify, repris par sensor.lecture_source.
        "aleatoire": player.get("shuffle_state") if etat != "rien" and isinstance(player.get("shuffle_state"), bool)
        else None,
        "duree_s": duree,
        "position_s": position,
        "position_le": maintenant_iso if position is not None else None,
        "ls50_visible": bool(sur_ls50 or ls50_visible),
        "maj": maintenant_iso,
    }


def indisponible(motif, maintenant_iso):
    return "unavailable", {"maj": maintenant_iso, "erreur": motif}


def a_publier(ancien, nouveau, t_ancien, t):
    """Publier ? Oui si l'état ou un attribut change (hors `maj` et position qui avance normalement), si la position a
    sauté (plus de 3 s d'écart avec l'attendu), ou si la dernière publication a plus de 10 min."""
    if ancien is None or t - t_ancien >= REPUBLIER:
        return True
    (e1, a1), (e2, a2) = ancien, nouveau
    if e1 != e2:
        return True
    ignores = {"maj", "position_s", "position_le"}
    if {k: v for k, v in a1.items() if k not in ignores} != {k: v for k, v in a2.items() if k not in ignores}:
        return True
    p1, p2 = a1.get("position_s"), a2.get("position_s")
    if (p1 is None) != (p2 is None):
        return True
    if p1 is None:
        return False
    attendu = p1 + (t - t_ancien if e2 == "lecture" else 0)
    return abs(p2 - attendu) > DERIVE_POSITION


def classer(erreur):
    """Erreur d'un appel → (motif, pause en secondes avant le prochain appel)."""
    reponse = getattr(erreur, "response", None)
    code = getattr(reponse, "status_code", None) if reponse is not None else None
    if isinstance(code, int):
        if code == 429:
            try:
                pause = int(float(reponse.headers.get("Retry-After")))
            except (TypeError, ValueError, AttributeError):
                pause = PAUSE_429
            return "429", max(1, min(pause, PAUSE_429_MAX))
        if code >= 500:
            return f"http {code}", PAUSE_SERVEUR
        if code in (400, 401, 403):
            return f"http {code}", PAUSE_REFUS
        return f"http {code}", PAUSE_AUTRE
    nom = type(erreur).__name__
    if any(m in nom for m in ("Timeout", "Transport", "Connect", "Network", "Protocol", "Read", "Write")):
        return "réseau" if "Timeout" not in nom else "délai", PAUSE_RESEAU
    return nom, PAUSE_AUTRE


def _code(erreur):
    reponse = getattr(erreur, "response", None)
    return getattr(reponse, "status_code", None) if reponse is not None else None


def corps_depuis_recents(recents):
    """Corps de `PUT /me/player/play` pour reprendre le dernier écouté (`/me/player/recently-played`) : son contexte
    (playlist, album…), à défaut le titre seul. None si la liste est vide."""
    for it in (recents or {}).get("items") or []:
        uri = ((it.get("context") or {}).get("uri"))
        if ref_uri(uri):
            return {"context_uri": uri}
        piste = (it.get("track") or {}).get("uri")
        if piste:
            return {"uris": [piste]}
    return None


def corps_depuis_memoire(memoire):
    """Même chose depuis le dernier contexte (ou titre) vu par le capteur depuis le démarrage de la vigie."""
    if not memoire:
        return None
    if memoire.get("context_uri"):
        return {"context_uri": memoire["context_uri"]}
    if memoire.get("uri"):
        return {"uris": [memoire["uri"]]}
    return None


class ClientLecture(aiguillage_spotify.Client):
    """Le client d'`aiguillage_spotify`, pour un usage long : pas de nouvel essai sur coupure (le passage suivant
    réessaie, 15 s plus tard au plus tôt), délai de 8 s, jeton d'accès renouvelé une fois sur un 401."""

    def __init__(self, identifiants, timeout=8):
        super().__init__(identifiants, timeout=timeout)

    @staticmethod
    def _envoyer(rejouable, requete):
        return requete()

    def _call(self, method, path, **kw):
        try:
            return super()._call(method, path, **kw)
        except Exception as erreur:  # noqa: BLE001 - httpx.HTTPStatusError, importé seulement dans HA
            if _code(erreur) != 401 or self._acces is None:
                raise
            self._acces = None
            return super()._call(method, path, **kw)

    def lecteur(self):
        return self._call("GET", "/me/player", params={"additional_types": "episode"})

    def nom(self, kind, ident):
        if kind == "playlist":
            return self._call("GET", f"/playlists/{ident}", params={"fields": "name"}).get("name")
        if kind in ("album", "artist", "show"):
            return self._call("GET", f"/{kind}s/{ident}").get("name")
        return None

    def recents(self):
        return self._call("GET", "/me/player/recently-played", params={"limit": 1})

    def transferer(self, device_id):
        self._call("PUT", "/me/player", json={"device_ids": [device_id], "play": True})

    def jouer(self, device_id, corps):
        self._call("PUT", "/me/player/play", params={"device_id": device_id}, json=corps)


class Lecture:
    """Le rythme des interrogations, le cache des noms et des appareils, les pauses après erreur.

    `fabrique` : fonction sans argument qui rend un client (`ClientLecture`) ou None (pas d'identifiants)."""

    def __init__(self, fabrique):
        self._fabrique = fabrique
        self._client = None
        self.verrou = threading.Lock()
        self._dernier = None          # instant (s) de la dernière interrogation
        self._pause_jusqua = 0.0
        self._demande = None          # dernière demande d'une vue
        self._noms = {}               # uri → (nom, expire)
        self._appareils = None        # (liste, instant)
        self.memoire = None           # dernier contexte / titre vu (pour « Reprendre »)
        self.dernier_motif = None

    def client(self):
        if self._client is None:
            self._client = self._fabrique()
        return self._client

    def demander(self, t):
        """Une vue (ou un script) veut des nouvelles fraîches : rythme rapide pendant 5 min."""
        self._demande = t

    def rapide(self, t, ls50_wifi):
        return bool(ls50_wifi) or (self._demande is not None and t - self._demande < DEMANDE_VALIDE)

    def en_pause(self, t):
        return t < self._pause_jusqua

    def pause(self, t, secondes):
        self._pause_jusqua = max(self._pause_jusqua, t + secondes)

    def due(self, t, ls50_wifi):
        """Faut-il interroger maintenant ? (appelé toutes les 5 s par la vigie)."""
        if self.en_pause(t):
            return False
        if self._dernier is None:
            return True
        intervalle = INTERVALLE_RAPIDE if self.rapide(t, ls50_wifi) else INTERVALLE_LENT
        return t - self._dernier >= max(ECART_MIN, intervalle) - 0.5

    def interroger(self, t, maintenant_iso):
        """(état, attributs) du capteur, ou None si trop tôt / en pause. Ne lève jamais : une erreur donne
        `unavailable` et une pause."""
        if self.en_pause(t) or (self._dernier is not None and t - self._dernier < ECART_MIN - 0.5):
            return None
        self._dernier = t
        client = self.client()
        if client is None:
            return indisponible("identifiants absents", maintenant_iso)
        try:
            player = client.lecteur() or {}
            etat = etat_lecture(player)
            sur_ls50 = etat != "rien" and est_ls50((player.get("device") or {}).get("name"))
            visible = sur_ls50 or self._ls50_visible(client, t)
            nom = self._nom(client, player, t) if etat != "rien" else None
        except Exception as erreur:  # noqa: BLE001 - toute erreur : unavailable, rien d'écrit
            motif, attente = classer(erreur)
            self.pause(t, attente)
            self.dernier_motif = motif
            return indisponible(motif, maintenant_iso)
        self.dernier_motif = None
        item = player.get("item") or {}
        if item.get("uri"):
            self.memoire = {"context_uri": (player.get("context") or {}).get("uri"), "uri": item["uri"]}
        return attributs(player, visible, nom, maintenant_iso)

    def _ls50_visible(self, client, t):
        if self._appareils is None or t - self._appareils[1] >= APPAREILS_VALIDES:
            self._appareils = (client.appareils(), t)
        return appareil_ls50(self._appareils[0]) is not None

    def appareils_lus(self, devices, t):
        """Les scripts ont relu la liste : le capteur s'en sert (pas d'appel de plus)."""
        self._appareils = (devices, t)

    def _nom(self, client, player, t):
        contexte = player.get("context") or {}
        uri = contexte.get("uri")
        ref = ref_uri(uri)
        if not ref:
            return None
        sans = nom_sans_appel(contexte, player.get("item"))
        if sans:
            return sans
        cache = self._noms.get(uri)
        if cache and t < cache[1]:
            return cache[0]
        try:
            nom = client.nom(*ref)
            duree = NOM_VALIDE if nom else NOM_ABSENT_VALIDE
        except Exception as erreur:  # noqa: BLE001
            code = _code(erreur)
            if code not in (400, 403, 404):
                raise  # 429, 5xx, réseau : tout le capteur en unavailable
            nom, duree = None, NOM_ABSENT_VALIDE
        if len(self._noms) >= NOMS_MAX:
            self._noms.clear()
        self._noms[uri] = (nom, t + duree)
        return nom


# MARK: - Scripts (appelés depuis une vue ; seuls à écrire chez Spotify)

DROIT_RECENTS = "user-read-recently-played"


def agir(action, client, device_id, memoire=None, recents_permis=True):
    """Exécute `script.spotify_sur_ls50` (« transfert ») ou `script.spotify_reprendre` (« reprendre ») vers l'appareil
    `device_id` (« Salon LS50 », déjà trouvé). Rend (fait, texte) ; les erreurs Spotify remontent (la vigie notifie).

    - transfert : la lecture en cours ailleurs passe sur les LS50 (`PUT /me/player`, play true) ; rien si rien ne
      joue, ou si elle y est déjà.
    - reprendre : une lecture en pause (sur n'importe quel appareil) reprend sur les LS50 là où elle en était ; sinon
      le dernier contexte écouté (`/me/player/recently-played`, si le droit est accordé), sinon le dernier vu par le
      capteur depuis le démarrage de la vigie."""
    player = client.lecteur() or {}
    etat = etat_lecture(player)
    ici = est_ls50((player.get("device") or {}).get("name"))
    if action == "transfert":
        if etat == "rien":
            return False, "rien ne joue sur Spotify"
        if ici and etat == "lecture":
            return False, "déjà sur les LS50"
        client.transferer(device_id)
        return True, f"transférée depuis « {(player.get('device') or {}).get('name')} »"
    if etat == "lecture" and ici:
        return False, "déjà en lecture sur les LS50"
    if etat != "rien":
        client.transferer(device_id)
        return True, "reprise là où elle en était"
    corps = None
    if recents_permis:
        try:
            corps = corps_depuis_recents(client.recents())
        except Exception as erreur:  # noqa: BLE001
            if _code(erreur) not in (401, 403):
                raise
    corps = corps or corps_depuis_memoire(memoire)
    if not corps:
        return False, "rien à reprendre"
    client.jouer(device_id, corps)
    return True, "relancée : " + (corps.get("context_uri") or corps["uris"][0])
