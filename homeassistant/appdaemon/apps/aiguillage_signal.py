"""Envies reçues sur Signal (17/10/2026) : un lien Spotify ou YouTube envoyé par un proche devient une envie Aiguillage.

Fonctions pures (testées hors Home Assistant par `tests/test_aiguillage_signal.py`) et l'app AppDaemon
`AiguillageSignal`, séparée de la vigie. signal-cli tourne dans l'add-on « Signal Messenger »
(haberda/signal-addon, mode json-rpc), lié comme appareil secondaire au compte d'Alexandre ; l'app écoute son
websocket `/v1/receive/<compte>` et, pour chaque message d'un expéditeur connu (ou une note à soi-même) :

- lien Spotify (`open.spotify.com/track|album|episode|playlist|artist|show/…`) → envie « 🎧 À écouter » ;
- lien YouTube (`youtube.com/watch?v=…`, `youtu.be/…`, `/shorts/…`) → envie « 🎬 À regarder » ;
  YouTube Music → « 🎧 À écouter ».

Note à moi-même : un message qui commence par « ? » part à l'agent courrier (`aiguillage_agent`, P9-N N5, 27/10,
événement `aiguillage_agent_message`) et à lui seul ; une autre note sans lien part à `aiguillage_lieu_travail`
(consignes de lieu) ; les réponses de l'agent (« 🤖 … ») sont ignorées.

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

from urllib.parse import parse_qs, quote, urlparse
import re
import uuid

NAMESPACE = uuid.UUID("3b7e9c1a-5d2f-4a8e-b6c4-9f0e1d2a3b4c")

# Avec « https:// », ou sans pour les hôtes connus (27/10 : Yoann a envoyé « youtube.com/shorts/… », ignoré).
URL = re.compile(r"(?:https?://|(?<![\w./@-])(?:(?:www|m|music)\.)?(?:youtube\.com|youtu\.be|open\.spotify\.com)/)"
                 r"[^\s<>\"'«»]+", re.IGNORECASE)
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
        # Identifiant Spotify : 22 caractères. Au-delà, du texte collé au lien (19/10 : « …MFSz » + « b52c4f4a »,
        # refusé par l'API en 400) : on garde les 22 premiers.
        if len(parts) >= 2 and parts[0] in SPOTIFY_TYPES and re.fullmatch(r"[A-Za-z0-9]+", parts[1]):
            ident = parts[1][:22]
            return {"type": "ecouter", "plateforme": "spotify", "id_titre": f"{parts[0]}:{ident}",
                    "lien": f"https://open.spotify.com/{parts[0]}/{ident}"}
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
        url = m.group(0)
        ref = ref_lien(url if re.match(r"https?://", url, re.I) else "https://" + url)
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


def images_note_a_soi(donnees, compte):
    """Photos jointes à un message de « Note à moi-même » (P9-R, liste de courses) : [{id, contentType, filename}]."""
    params = donnees.get("params", donnees) if isinstance(donnees, dict) else None
    env = (params.get("envelope") if isinstance(params, dict) else None) or {}
    envoye = (env.get("syncMessage") or {}).get("sentMessage")
    source = env.get("sourceNumber") or env.get("source")
    if not envoye or source != compte or (envoye.get("destinationNumber") or envoye.get("destination")) != compte:
        return []
    return [a for a in envoye.get("attachments") or []
            if isinstance(a, dict) and a.get("id") and (a.get("contentType") or "").startswith("image/")]


# Agent courrier (P9-N, N5, 27/10) : une « Note à moi-même » qui commence par « ? » est une question à l'agent
# (`aiguillage_agent`), transmise sans le « ? » ; ses réponses commencent par « 🤖 » et ne sont jamais retraitées.
_QUESTION = re.compile(r"^\s*[?？]\s*(.*)$", re.DOTALL)
PREFIXE_AGENT = "🤖"


def question_agent(texte):
    """« ? qu'est-ce… » ou « ?qu'est-ce… » → « qu'est-ce… » ; « ? » seul → "" ; sinon None."""
    m = _QUESTION.match(texte or "")
    return m.group(1).strip() if m else None


def routage(texte, expediteur):
    """Où va un message retenu : ("agent", question) pour une note à soi qui commence par « ? » ; ("envies", liens)
    s'il y a des liens Spotify ou YouTube ; ("lieu", texte) pour une autre note à soi (consigne de lieu de travail,
    décidée par `aiguillage_lieu_travail`) ; ("rien", None) sinon (réponse de l'agent, « ? » seul, message vide)."""
    if expediteur is None:
        if (texte or "").lstrip().startswith(PREFIXE_AGENT):
            return "rien", None
        question = question_agent(texte)
        if question is not None:
            return ("agent", question) if question else ("rien", None)
    liens = refs(texte)
    if liens:
        return "envies", liens
    if expediteur is None and (texte or "").strip():
        return "lieu", texte
    return "rien", None


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
    from datetime import UTC, datetime, timedelta
    from pathlib import Path

    import aiohttp
    import httpx

    import aiguillage_memoire as memoire
    import aiguillage_photos
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
            # Mémoire des échanges (P9-J) : `memoire: {"actif": true}` dans aiguillage_signal.json (conversations :
            # `memoire.conversations`, sinon les `sources`). Résumés la nuit, recherche par l'événement
            # « aiguillage_memoire_chercher » (résultat dans donnees_apps, espace « memoire », clé « recherche »).
            self._db_path = self.args.get("memoire_file", "/config/aiguillage_memoire.sqlite")
            self._memoire_etat_path = Path(self.args.get("memoire_etat_file", "/config/aiguillage_memoire_etat.json"))
            self.run_daily(self._nuit, self.args.get("memoire_heure", "03:00:00"))
            self.listen_event(self._chercher, "aiguillage_memoire_chercher")
            # Import d'un historique (J5) : événement « aiguillage_memoire_importer » {fichier, expediteur,
            # conversation}, puis résumés par la Batch API, suivis toutes les 10 min.
            self.listen_event(self._importer, "aiguillage_memoire_importer")
            self.run_every(self._suivre_batch, "now+90", 600)
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
            try:
                await self._memoriser(donnees, conf)
            except Exception as exc:  # noqa: BLE001 - la mémoire ne doit jamais bloquer les envies
                self.log(f"Signal : mémoire, ERREUR {exc!r}", level="WARNING")
            retenu = message_retenu(donnees, conf["compte"], conf.get("sources") or {}, conf.get("note_a_soi", True))
            if not retenu:
                return
            texte, expediteur = retenu
            # Photo dans la Note à moi-même (P9-R) : produits à racheter, vers la liste de courses la plus récente
            # (ou celle que nomme le texte) ; rien d'autre (ni agent, ni consigne de lieu).
            images = images_note_a_soi(donnees, conf["compte"]) if expediteur is None else []
            if images:
                try:
                    titre = await self.run_in_executor(self._photos_vers_liste, images, texte)
                    self.log(f"Signal : {len(images)} photo(s) de produits vers « {titre} »")
                except Exception as exc:  # noqa: BLE001
                    self._etat["derniere_erreur"] = f"{datetime.now():%d/%m %H:%M} photos {exc}"[:250]
                    self.log(f"Signal : photos de produits, ERREUR {exc!r}", level="WARNING")
                await self._publier()
                return
            route, quoi = routage(texte, expediteur)
            if route == "agent":
                # Question à l'agent courrier (N5, 27/10) : « ? … » dans la Note à moi-même ; rien d'autre.
                await self.fire_event("aiguillage_agent_message", texte=quoi, recu_le=datetime.now(UTC).isoformat())
                return
            if route == "lieu":
                # Note à moi-même sans lien : peut-être une consigne de lieu de travail (P9-N, « demain
                # télétravail ») ; `aiguillage_lieu_travail` décide et répond, sinon rien.
                await self.fire_event("aiguillage_lieu_travail_message", texte=texte)
            if route != "envies":
                return
            liens = quoi
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

        def _photos_vers_liste(self, images, texte):
            """Photos de Signal → fichiers de `donnees_apps`, puis la liste visée (créée s'il n'y en a pas), notées à
            lire ; la vigie les lit (P9-R). Renvoie le titre de la liste."""
            base = self._hote.replace("ws://", "http://").replace("wss://", "https://")
            jeton = {"Authorization": f"Bearer {os.environ['SUPERVISOR_TOKEN']}"}
            pieces = []
            for a in images:
                r = httpx.get(f"{base}/v1/attachments/{a['id']}", timeout=30)
                r.raise_for_status()
                nom = a.get("filename") or "Photo Signal.jpg"
                envoi = httpx.post(f"{CORE_API}/donnees_apps/fichiers/{self._espace}", content=r.content, timeout=30,
                                   headers={**jeton, "Content-Type": a["contentType"], "X-Nom": quote(nom)})
                envoi.raise_for_status()
                pieces.append(envoi.json())
            note = (texte or "").strip() or None
            for _ in range(3):  # conflit de version : on relit et on recommence
                enregistrements = self._service("donnees_apps", "lire", {"espace": self._espace}).get("enregistrements", [])
                cible = aiguillage_photos.liste_cible(enregistrements, note)
                cle_liste = cible["cle"] if cible else str(uuid.uuid4())
                valeur = cible["valeur"] if cible else aiguillage_photos.nouvelle_liste(note)
                valeur = aiguillage_photos.avec_photos(valeur, pieces, datetime.now(UTC).isoformat(), note)
                resultat = self._service("donnees_apps", "ecrire", {
                    "espace": self._espace, "cle": cle_liste, "valeur": valeur,
                    "version_attendue": cible["version"] if cible else 0,
                    "modifie_par": "signal", "op_id": str(uuid.uuid4())}) or {}
                if resultat.get("statut") != "conflit":
                    return valeur.get("titre", "Courses")
            raise RuntimeError("liste en conflit trois fois de suite")

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

        # MARK: - Mémoire (P9-J)

        @staticmethod
        def _conversations(conf):
            mem = conf.get("memoire") or {}
            return (mem.get("conversations") or conf.get("sources") or {}) if mem.get("actif") else {}

        async def _memoriser(self, donnees, conf):
            conversations = self._conversations(conf)
            if not conversations:
                return
            op = memoire.lire_notification(donnees, conf["compte"], conversations)
            if op:
                total = await self.run_in_executor(self._memo_appliquer, op)
                self._etat["memoire"] = f"{total} message(s)"

        def _memo_appliquer(self, op):
            db = memoire.ouvrir(self._db_path)
            try:
                memoire.appliquer(db, op)
                return memoire.compter(db)
            finally:
                db.close()

        async def _chercher(self, event_name, data, **kwargs):
            data = data or {}
            await self.run_in_executor(self._chercher_sync, str(data.get("requete") or ""), data.get("jour"))

        def _chercher_sync(self, requete, jour=None):
            db = memoire.ouvrir(self._db_path)
            try:
                trouve = memoire.chercher(db, requete, jour=jour)
            finally:
                db.close()
            valeur = {"requete": requete, "jour": jour, "moment": datetime.now(UTC).isoformat(), **trouve}
            while len(json.dumps(valeur, ensure_ascii=False).encode()) > 60_000 and valeur["messages"]:
                valeur["messages"].pop()  # limite de 64 Ko par enregistrement
            self._service("donnees_apps", "ecrire", {
                "espace": "memoire", "cle": "recherche", "valeur": valeur,
                "modifie_par": "memoire", "op_id": str(uuid.uuid4())})
            self.log(f"Signal : mémoire, recherche ({len(valeur['messages'])} message(s), "
                     f"{len(valeur['resumes'])} résumé(s))")

        async def _nuit(self, **kwargs):
            try:
                await self.run_in_executor(self._nuit_sync)
            except Exception as exc:  # noqa: BLE001
                self.log(f"Signal : mémoire, ERREUR la nuit {exc!r}", level="WARNING")

        def _nuit_sync(self):
            """Résumés des jours sans résumé (7 derniers jours), de la semaine le lundi, du mois le 1er ; purges."""
            conf = json.loads(self._conf_path.read_text())
            conversations = self._conversations(conf)
            if not conversations:
                return
            aujourdhui = datetime.now(memoire.PARIS).date()
            db = memoire.ouvrir(self._db_path)
            try:
                client = self._client_api()
                if client is not None:
                    self._resumer_tout(db, client, conversations, aujourdhui)
                garder = (conf.get("memoire") or {}).get("garder_textes_jours", 365)
                retires = memoire.purger_textes(db, aujourdhui, garder)
                self._nettoyer_donnees(aujourdhui)
                purgees = self._purger_pieces(db)
            finally:
                db.close()
            self.log(f"Signal : mémoire, nuit faite ({retires} ancien(s) message(s) retiré(s), "
                     f"{purgees} pièce(s) jointe(s) purgée(s))")

        def _client_api(self):
            try:
                import anthropic
                cle = Path(self.args.get("api_key_file", "/config/anthropic_api_key")).read_text().strip()
            except (ImportError, FileNotFoundError) as exc:
                self.log(f"Signal : mémoire, résumés impossibles ({exc!r})", level="WARNING")
                return None
            espace = self.args.get("workspace_id")
            return anthropic.Anthropic(api_key=cle, timeout=180.0, max_retries=2,
                                       default_headers={"anthropic-workspace-id": espace} if espace else None)

        def _resumer_tout(self, db, client, conversations, aujourdhui):
            etat = self._memoire_etat()
            mois = f"{aujourdhui:%Y-%m}"
            if etat.get("mois") != mois:
                etat = {"mois": mois, "cout_mois": 0.0}
            budget = float(self.args.get("memoire_budget_mensuel", 5))
            modele = self.args.get("memoire_modele", "claude-sonnet-5-5")
            effort = self.args.get("memoire_effort", "medium")

            def faire(niveau, nom, periode, texte):
                if etat["cout_mois"] >= budget:
                    self.log(f"Signal : mémoire, budget du mois atteint ({etat['cout_mois']:.2f} $)", level="WARNING")
                    return
                resultat, usage = memoire.resumer(client, texte, modele, effort)
                prix = {"claude-sonnet-5-5": (2.0, 10.0), "claude-haiku-5-5": (0.10, 0.50)}.get(modele, (4.0, 20.0))
                etat["cout_mois"] = round(etat["cout_mois"] + (usage.input_tokens * prix[0]
                                                               + usage.output_tokens * prix[1]) / 1e6, 4)
                self._memoire_etat(etat)
                if resultat is None:
                    self.log(f"Signal : mémoire, résumé {niveau} {periode} impossible", level="WARNING")
                    return
                maintenant = datetime.now(UTC).isoformat()
                memoire.enregistrer_resume(db, niveau, nom, periode, resultat, maintenant)
                self._publier_resume(nom, niveau, periode, resultat, aujourdhui)
                self.log(f"Signal : mémoire, résumé {niveau} {periode} ({len(resultat['faits'])} fait(s)) ; "
                         f"mois : {etat['cout_mois']:.2f} $")

            for nom in sorted(set(conversations.values())):
                for recul in range(7, 0, -1):
                    jour = (aujourdhui - timedelta(days=recul)).isoformat()
                    messages = memoire.messages_du_jour(db, nom, jour)
                    if messages and not memoire.resumes(db, "jour", nom, jour, jour):
                        faire("jour", nom, jour, memoire.texte_jour(nom, jour, messages))
                for niveau, (debut, fin, periode) in (("semaine", memoire.semaine_precedente(aujourdhui)),
                                                      ("mois", memoire.mois_precedent(aujourdhui))):
                    jours = memoire.resumes(db, "jour", nom, debut.isoformat(), fin.isoformat())
                    if jours and not memoire.resumes(db, niveau, nom, periode, periode):
                        faire(niveau, nom, periode, memoire.texte_resumes(nom, niveau, periode, jours))

        # Résumés du jour gardés dans donnees_apps : les 60 derniers jours (les plus anciens restent dans SQLite,
        # trouvés par la recherche) ; semaines et mois : tous.
        JOURS_DANS_DONNEES = 60

        def _publier_resume(self, nom, niveau, periode, resultat, aujourdhui):
            if niveau == "jour" and periode < (aujourdhui - timedelta(days=self.JOURS_DANS_DONNEES)).isoformat():
                return
            self._service("donnees_apps", "ecrire", {
                "espace": "memoire", "cle": memoire.cle_donnees(nom, niveau, periode),
                "valeur": {"conversation": nom, "niveau": niveau, "periode": periode, **resultat},
                "modifie_par": "memoire", "op_id": str(uuid.uuid4())})

        def _nettoyer_donnees(self, aujourdhui):
            limite = (aujourdhui - timedelta(days=self.JOURS_DANS_DONNEES)).isoformat()
            lu = self._service("donnees_apps", "lire", {"espace": "memoire"}) or {}
            for r in lu.get("enregistrements", []):
                periode = ((r.get("valeur") or {}).get("periode") or "")
                if not r.get("supprime") and "-jour-" in r["cle"] and periode and periode < limite:
                    self._service("donnees_apps", "supprimer", {"espace": "memoire", "cle": r["cle"],
                                                                "modifie_par": "memoire", "op_id": str(uuid.uuid4())})

        # MARK: - Import d'un historique (J5)

        async def _importer(self, event_name, data, **kwargs):
            try:
                await self.run_in_executor(self._importer_sync, data or {})
            except Exception as exc:  # noqa: BLE001
                self.log(f"Signal : mémoire, ERREUR à l'import {exc!r}", level="WARNING")

        def _importer_sync(self, data):
            fichier, expediteur, nom = Path(str(data.get("fichier"))), data.get("expediteur"), data.get("conversation")
            if not (fichier.is_file() and expediteur and nom):
                self.log("Signal : mémoire, import : fichier, expediteur et conversation requis", level="WARNING")
                return
            lignes = [json.loads(l) for l in fichier.read_text().splitlines() if l.strip()]
            db = memoire.ouvrir(self._db_path)
            try:
                ops = memoire.ops_depuis_export(lignes, nom, expediteur, avant_ts=memoire.premier_ts(db))
                ajoutes = memoire.importer(db, ops)
                total = memoire.compter(db)
            finally:
                db.close()
            self.log(f"Signal : mémoire, import de {len(lignes)} ligne(s) : {ajoutes} message(s) ajouté(s), "
                     f"{total} au total")
            if data.get("resumer", True):
                self._lancer_batch(nom, "jour")

        def _lancer_batch(self, nom, phase):
            """Lance un batch de résumés : `jour` (jours sans résumé) puis `periodes` (semaines et mois)."""
            client = self._client_api()
            if client is None:
                return
            aujourdhui = datetime.now(memoire.PARIS).date()
            modele = self.args.get("memoire_modele", "claude-sonnet-5-5")
            effort = self.args.get("memoire_effort", "medium")
            db = memoire.ouvrir(self._db_path)
            try:
                if phase == "jour":
                    textes = {memoire.id_batch(nom, "jour", j): memoire.texte_jour(nom, j, memoire.messages_du_jour(db, nom, j))
                              for j in memoire.jours_sans_resume(db, nom, aujourdhui.isoformat())}
                else:
                    textes = {}
                    for niveau, periode, debut, fin in memoire.periodes_sans_resume(db, nom, aujourdhui):
                        jours = memoire.resumes(db, "jour", nom, debut.isoformat(), fin.isoformat())
                        textes[memoire.id_batch(nom, niveau, periode)] = memoire.texte_resumes(nom, niveau, periode, jours)
            finally:
                db.close()
            etat = self._memoire_etat()
            if not textes:
                etat.pop("import", None)
                self._memoire_etat(etat)
                if phase == "jour":
                    return self._lancer_batch(nom, "periodes")
                self.log("Signal : mémoire, import terminé : tous les résumés sont faits")
                return
            batch = client.messages.batches.create(requests=[
                {"custom_id": cid, "params": memoire.params_resume(texte, modele, effort)} for cid, texte in textes.items()])
            etat["import"] = {"batch": batch.id, "phase": phase, "conversation": nom, "modele": modele,
                              "requetes": len(textes), "lance_le": datetime.now(UTC).isoformat()}
            self._memoire_etat(etat)
            self.log(f"Signal : mémoire, batch {phase} lancé ({len(textes)} résumé(s), {batch.id})")

        async def _suivre_batch(self, **kwargs):
            if not (self._memoire_etat().get("import") or {}).get("batch"):
                return
            try:
                await self.run_in_executor(self._suivre_batch_sync)
            except Exception as exc:  # noqa: BLE001
                self.log(f"Signal : mémoire, ERREUR au suivi du batch {exc!r}", level="WARNING")

        def _suivre_batch_sync(self):
            etat = self._memoire_etat()
            imp = etat.get("import") or {}
            client = self._client_api()
            if client is None:
                return
            batch = client.messages.batches.retrieve(imp["batch"])
            if batch.processing_status != "ended":
                return
            nom, aujourdhui = imp["conversation"], datetime.now(memoire.PARIS).date()
            prefixe = memoire.cle_donnees(nom, "x", "x")[: -len("-x-x")] + "-"
            prix = {"claude-sonnet-5-5": (2.0, 10.0), "claude-haiku-5-5": (0.10, 0.50)}.get(imp.get("modele"), (4.0, 20.0))
            faits, echecs, cout = 0, 0, 0.0
            db = memoire.ouvrir(self._db_path)
            try:
                for res in client.messages.batches.results(imp["batch"]):
                    niveau, periode = res.custom_id[len(prefixe):].split("-", 1)
                    if res.result.type != "succeeded":
                        echecs += 1
                        continue
                    message = res.result.message
                    cout += (message.usage.input_tokens * prix[0] + message.usage.output_tokens * prix[1]) / 2e6
                    resultat = memoire.lire_reponse(message)
                    if resultat is None:
                        echecs += 1
                        continue
                    memoire.enregistrer_resume(db, niveau, nom, periode, resultat, datetime.now(UTC).isoformat())
                    try:
                        self._publier_resume(nom, niveau, periode, resultat, aujourdhui)
                    except Exception as exc:  # noqa: BLE001 - le résumé est dans SQLite, la copie est secondaire
                        self.log(f"Signal : mémoire, copie de {periode} impossible ({exc!r})", level="WARNING")
                    faits += 1
            finally:
                db.close()
            etat["cout_import"] = round(etat.get("cout_import", 0.0) + cout, 4)
            etat.pop("import", None)
            self._memoire_etat(etat)
            self.log(f"Signal : mémoire, batch {imp['phase']} fini : {faits} résumé(s), {echecs} échec(s), "
                     f"{cout:.2f} $ (import : {etat['cout_import']:.2f} $)")
            # Les échecs d'un jour sont repris par le batch suivant (`jour` repart des jours sans résumé, une fois).
            if imp["phase"] == "jour" and echecs and not imp.get("reprise"):
                self._lancer_batch(nom, "jour")
                etat = self._memoire_etat()
                if etat.get("import"):
                    etat["import"]["reprise"] = True
                    self._memoire_etat(etat)
                return
            if imp["phase"] == "jour":
                self._lancer_batch(nom, "periodes")
            else:
                self.log("Signal : mémoire, import terminé")

        def _purger_pieces(self, db):
            base = self._hote.replace("ws://", "http://").replace("wss://", "https://")
            n = 0
            for ident in memoire.pieces_a_purger(db, int(datetime.now(UTC).timestamp() * 1000)):
                try:
                    r = httpx.delete(f"{base}/v1/attachments/{ident}", timeout=10)
                except httpx.HTTPError as exc:
                    self.log(f"Signal : mémoire, purge de {ident} impossible ({exc!r})", level="WARNING")
                    continue
                if r.status_code < 300 or r.status_code == 404:
                    memoire.piece_purgee(db, ident)
                    n += 1
            return n

        def _memoire_etat(self, etat=None):
            if etat is not None:
                self._memoire_etat_path.write_text(json.dumps(etat, indent=2))
                return etat
            try:
                return json.loads(self._memoire_etat_path.read_text())
            except (FileNotFoundError, json.JSONDecodeError):
                return {}

        def _service(self, domain, service, data):
            """Action HA par l'API REST (`return_response`, exigé par `donnees_apps`, que `call_service` ne passe pas)."""
            reply = httpx.post(f"{CORE_API}/services/{domain}/{service}?return_response", json=data, timeout=15,
                               headers={"Authorization": f"Bearer {os.environ['SUPERVISOR_TOKEN']}"})
            reply.raise_for_status()
            return reply.json().get("service_response")
