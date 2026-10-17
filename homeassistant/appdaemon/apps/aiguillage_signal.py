"""Envies reçues sur Signal (17/10/2026) : un lien Spotify ou YouTube envoyé par un proche devient une envie Aiguillage.

Fonctions pures (testées hors Home Assistant par `tests/test_aiguillage_signal.py`) et l'app AppDaemon
`AiguillageSignal`, séparée de la vigie. signal-cli tourne dans l'add-on « Signal Messenger »
(haberda/signal-addon, mode json-rpc), lié comme appareil secondaire au compte d'Alexandre ; l'app écoute son
websocket `/v1/receive/<compte>` et, pour chaque message d'un expéditeur connu (ou une note à soi-même) :

- lien Spotify (`open.spotify.com/track|album|episode|playlist|artist|show/…`) → envie « 🎧 À écouter » ;
- lien YouTube (`youtube.com/watch?v=…`, `youtu.be/…`, `/shorts/…`) → envie « 🎬 À regarder » ;
  YouTube Music → « 🎧 À écouter ».

Même format qu'un partage depuis l'iPhone : ligne du type dans les notes (« 🎧 À écouter · Proposé par Yoann »)
et champ `envie` {type, note, plateforme, id_titre, lien}. La vigie fait le reste : recette « playlist À
écouter » pour Spotify, TMDB ignore YouTube, app TV et suggestions. Clé de la tâche tirée du lien : un même
lien envoyé deux fois ne crée qu'une envie, et une envie déjà là (même faite) n'est jamais réécrite.

Titre : Spotify par l'API Web (client de `aiguillage_spotify`, « Titre · Artiste »), YouTube par oEmbed
(« Titre · Chaîne »), sinon « Morceau Spotify » / « Vidéo YouTube ».

Réglages : `/config/aiguillage_signal.json` ({"compte": "+33…", "sources": {"+33…": "Yoann"},
"note_a_soi": true}), jamais dans un dépôt. Suivi : journal AppDaemon (« Signal : … ») et capteur
`sensor.aiguillage_signal`.
"""

from urllib.parse import parse_qs, urlparse
import re
import uuid

NAMESPACE = uuid.UUID("3b7e9c1a-5d2f-4a8e-b6c4-9f0e1d2a3b4c")

URL = re.compile(r"https?://[^\s<>\"'«»]+")
SPOTIFY_TYPES = ("track", "album", "episode", "playlist", "artist", "show")
MARQUEURS = {"ecouter": "🎧 À écouter", "regarder": "🎬 À regarder"}
TITRES_PAR_DEFAUT = {"spotify": "Morceau Spotify", "youtube": "Vidéo YouTube", "youtube_music": "Morceau YouTube Music"}


def _nettoie(url):
    return url.rstrip(".,;:!?)]}…")


def ref_lien(url):
    """Lien → {type, plateforme, id_titre, lien} (lien normalisé, sans paramètres de suivi), ou None."""
    try:
        u = urlparse(_nettoie(url))
    except ValueError:
        return None
    hote = (u.hostname or "").lower().removeprefix("www.").removeprefix("m.")
    parts = [p for p in u.path.split("/") if p]
    if hote == "open.spotify.com":
        parts = [p for p in parts if not p.startswith("intl-")]
        if len(parts) >= 2 and parts[0] in SPOTIFY_TYPES and re.fullmatch(r"[A-Za-z0-9]+", parts[1]):
            return {"type": "ecouter", "plateforme": "spotify", "id_titre": f"{parts[0]}:{parts[1]}",
                    "lien": f"https://open.spotify.com/{parts[0]}/{parts[1]}"}
        return None
    if hote in ("youtube.com", "youtu.be", "music.youtube.com"):
        if hote == "youtu.be":
            vid = parts[0] if parts else None
        elif parts[:1] == ["watch"]:
            vid = (parse_qs(u.query).get("v") or [None])[0]
        elif len(parts) == 2 and parts[0] in ("shorts", "live", "embed"):
            vid = parts[1]
        else:
            vid = None
        if not vid or not re.fullmatch(r"[A-Za-z0-9_-]{6,20}", vid):
            return None
        if hote == "music.youtube.com":
            return {"type": "ecouter", "plateforme": "youtube_music", "id_titre": vid,
                    "lien": f"https://music.youtube.com/watch?v={vid}"}
        return {"type": "regarder", "plateforme": "youtube", "id_titre": vid,
                "lien": f"https://www.youtube.com/watch?v={vid}"}
    return None


def refs(texte):
    """Liens Spotify et YouTube du texte, dans l'ordre, sans doublon."""
    out = []
    for m in URL.finditer(texte or ""):
        ref = ref_lien(m.group(0))
        if ref and ref["lien"] not in (r["lien"] for r in out):
            out.append(ref)
    return out


def sans_liens(texte):
    """Le message sans ses liens (ce que l'expéditeur a écrit autour), sur une ligne, ou ""."""
    reste = URL.sub(" ", texte or "")
    return " ".join(reste.split())


def message_retenu(donnees, compte, sources, note_a_soi=True):
    """Notification signal-cli (brute ou JSON-RPC) → (texte, nom de l'expéditeur), ou None.

    - message reçu d'un numéro de `sources` ({numéro: nom}) ;
    - si `note_a_soi` : message envoyé par Alexandre dans « Note à moi-même » (nom None)."""
    params = donnees.get("params", donnees) if isinstance(donnees, dict) else None
    env = (params.get("envelope") if isinstance(params, dict) else None) or {}
    source = env.get("sourceNumber") or env.get("source")
    data = env.get("dataMessage")
    if data and source in sources:
        return data.get("message") or "", sources[source]
    envoye = (env.get("syncMessage") or {}).get("sentMessage")
    if note_a_soi and envoye and source == compte:
        if (envoye.get("destinationNumber") or envoye.get("destination")) == compte:
            return envoye.get("message") or "", None
    return None


def cle(ref):
    """Clé UUID de la tâche, tirée du lien : un même lien donne toujours la même envie."""
    return str(uuid.uuid5(NAMESPACE, f"{ref['plateforme']}:{ref['id_titre']}"))


def note_de(expediteur):
    return f"Proposé par {expediteur}" if expediteur else None


def tache(ref, titre, message="", expediteur=None):
    """Valeur `donnees_apps` (format `TacheHA` de l'app) d'une envie reçue sur Signal."""
    note = note_de(expediteur)
    lignes = [ref["lien"]]
    autour = sans_liens(message)
    if autour:
        lignes.append(autour)
    lignes.append(MARQUEURS[ref["type"]] + (f" · {note}" if note else ""))
    envie = {"type": ref["type"], "plateforme": ref["plateforme"], "id_titre": ref["id_titre"], "lien": ref["lien"]}
    if note:
        envie["note"] = note
    return {"v": 2, "titre": (titre or TITRES_PAR_DEFAUT[ref["plateforme"]])[:200], "fait": False,
            "notes": "\n".join(lignes), "envie": envie}


def titre_spotify(kind, data):
    """Réponse de l'API Web (`/tracks/{id}`, `/albums/{id}`, `/episodes/{id}`…) → « Titre · Artiste », ou None."""
    nom = (data or {}).get("name")
    if not nom:
        return None
    if kind in ("track", "album"):
        artistes = ", ".join(a.get("name", "") for a in data.get("artists") or [] if a.get("name"))
        return f"{nom} · {artistes}" if artistes else nom
    if kind == "episode":
        emission = (data.get("show") or {}).get("name")
        return f"{nom} · {emission}" if emission else nom
    return nom


def titre_youtube(oembed):
    """Réponse oEmbed de YouTube → « Titre · Chaîne », ou None."""
    nom = (oembed or {}).get("title")
    if not nom:
        return None
    chaine = oembed.get("author_name")
    return f"{nom} · {chaine}" if chaine else nom


try:  # L'app ne se charge que dans AppDaemon ; les fonctions ci-dessus se testent sans.
    import appdaemon.plugins.hass.hassapi as hass
except ImportError:  # pragma: no cover
    hass = None

if hass is not None:
    import asyncio
    import json
    import os
    from datetime import UTC, datetime
    from pathlib import Path

    import aiohttp
    import httpx

    import aiguillage_spotify

    CORE_API = "http://supervisor/core/api"
    CAPTEUR = "sensor.aiguillage_signal"

    class AiguillageSignal(hass.Hass):

        async def initialize(self):
            self._conf_path = Path(self.args.get("config_file", "/config/aiguillage_signal.json"))
            self._ids_path = Path(self.args.get("spotify_file", "/config/spotify_aiguillage.json"))
            self._hote = self.args.get("signal_url", "ws://1315902c-signal-messenger:8080")
            self._espace = self.args.get("ha_espace", "aiguillage")
            self._etat = {"connexion": "démarrage", "dernier_message": None, "derniere_erreur": None}
            self._derniere = "aucune"
            self._arret = False
            self._tache = asyncio.ensure_future(self._boucle())

        async def terminate(self):
            self._arret = True
            if getattr(self, "_tache", None):
                self._tache.cancel()

        async def _publier(self):
            await self.set_state(CAPTEUR, state=self._derniere[:250],
                                 attributes=dict(self._etat, friendly_name="Signal → Aiguillage", icon="mdi:message-arrow-right"))

        async def _boucle(self):
            attente = 5
            while not self._arret:
                try:
                    conf = json.loads(self._conf_path.read_text())
                    async with aiohttp.ClientSession() as session:
                        async with session.ws_connect(f"{self._hote}/v1/receive/{conf['compte']}", heartbeat=60) as ws:
                            self.log("Signal : connecté au websocket de l'add-on")
                            self._etat["connexion"] = "connecté"
                            await self._publier()
                            attente = 5
                            async for msg in ws:
                                if msg.type == aiohttp.WSMsgType.TEXT:
                                    await self._traiter(msg.data, conf)
                                elif msg.type in (aiohttp.WSMsgType.ERROR, aiohttp.WSMsgType.CLOSED):
                                    break
                    self._etat["connexion"] = "déconnecté"
                except asyncio.CancelledError:
                    return
                except Exception as exc:  # noqa: BLE001 - on journalise et on se reconnecte
                    self._etat.update(connexion="erreur", derniere_erreur=f"{datetime.now():%d/%m %H:%M} {exc}"[:250])
                    self.log(f"Signal : websocket indisponible ({exc}), nouvel essai dans {attente} s", level="WARNING")
                try:
                    await self._publier()
                except Exception:  # noqa: BLE001
                    pass
                await asyncio.sleep(attente)
                attente = min(attente * 2, 300)

        async def _traiter(self, brut, conf):
            try:
                donnees = json.loads(brut)
            except json.JSONDecodeError:
                return
            retenu = message_retenu(donnees, conf["compte"], conf.get("sources") or {}, conf.get("note_a_soi", True))
            if not retenu:
                return
            texte, expediteur = retenu
            liens = refs(texte)
            if not liens:
                return
            self._etat["dernier_message"] = f"{datetime.now():%d/%m %H:%M} {len(liens)} lien(s)"
            for ref in liens:
                try:
                    # Appels HTTP bloquants (httpx) : hors de la boucle asyncio d'AppDaemon.
                    titre, statut = await self.run_in_executor(self._creer, ref, texte, expediteur)
                    if statut == "ok":
                        self._derniere = f"{datetime.now():%d/%m %H:%M} {titre}"
                        self.log(f"Signal : envie « {titre} » créée ({ref['plateforme']})")
                    else:
                        self.log(f"Signal : envie déjà là, rien d'écrit ({ref['lien']}, {statut})")
                except Exception as exc:  # noqa: BLE001
                    self._etat["derniere_erreur"] = f"{datetime.now():%d/%m %H:%M} {ref['lien']} {exc}"[:250]
                    self.log(f"Signal : ERREUR pour {ref['lien']} : {exc!r}", level="WARNING")
            await self._publier()

        def _creer(self, ref, texte, expediteur):
            """Écrit l'envie (version attendue 0 : jamais par-dessus une envie existante). Renvoie (titre, statut)."""
            titre = self._titre(ref)
            result = self._service("donnees_apps", "ecrire", {
                "espace": self._espace, "cle": cle(ref), "valeur": tache(ref, titre, texte, expediteur),
                "version_attendue": 0, "modifie_le": datetime.now(UTC).isoformat(),
                "modifie_par": "signal", "op_id": str(uuid.uuid4()),
            }) or {}
            return titre or TITRES_PAR_DEFAUT[ref["plateforme"]], result.get("statut", "?")

        def _titre(self, ref):
            try:
                if ref["plateforme"] == "spotify":
                    kind, ident = ref["id_titre"].split(":", 1)
                    client = aiguillage_spotify.Client(json.loads(self._ids_path.read_text()))
                    return titre_spotify(kind, client._call("GET", f"/{kind}s/{ident}"))
                r = httpx.get("https://www.youtube.com/oembed", params={"url": ref["lien"], "format": "json"}, timeout=10)
                r.raise_for_status()
                return titre_youtube(r.json())
            except Exception as exc:  # noqa: BLE001 - titre par défaut, l'envie est créée quand même
                self.log(f"Signal : titre introuvable pour {ref['lien']} ({exc!r})", level="WARNING")
                return None

        def _service(self, domain, service, data):
            """Action HA par l'API REST (`return_response`, exigé par `donnees_apps`, que `call_service` ne passe pas)."""
            reply = httpx.post(f"{CORE_API}/services/{domain}/{service}?return_response", json=data, timeout=15,
                               headers={"Authorization": f"Bearer {os.environ['SUPERVISOR_TOKEN']}"})
            reply.raise_for_status()
            return reply.json().get("service_response")
