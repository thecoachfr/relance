"""Vigie Relance : réveille l'app iOS dès que ses tâches changent.

1. Force l'intégration Google Tasks à se rafraîchir (elle ne le fait que toutes les 30 min).
2. Quand le nombre de tâches à faire change (dictée Google Home, tâche cochée ailleurs),
   envoie un push silencieux APNs à chaque appareil Relance enregistré.
3. Les appareils s'enregistrent via un webhook Home Assistant qui émet l'événement
   `relance_register` (voir README).
4. Tâches dans Home Assistant (`ha_espace: aiguillage`, intégration `donnees_apps`) :
   push à chaque événement `donnees_apps_modifie` de l'espace ; avec `inbox: true`, la liste
   Google devient une boîte d'entrée (dictées Google Home) vidée dans HA par `import_inbox`.
"""

from datetime import UTC, date, datetime
import json
import os
import secrets
import threading
import time
from pathlib import Path
import uuid
from zoneinfo import ZoneInfo

import httpx
import jwt
from appdaemon.plugins.hass import Hass

import aiguillage_actions
import aiguillage_agenda
import aiguillage_spotify
import aiguillage_tmdb
import aiguillage_tri

APNS_HOSTS = {
    "sandbox": "https://api.sandbox.push.apple.com",
    "production": "https://api.push.apple.com",
}
# Apple refuse un jeton de plus d'une heure et en limite le renouvellement : on le garde 50 min.
JWT_LIFETIME = 50 * 60
UNAVAILABLE = (None, "unavailable", "unknown")
ROUTINE_URL = "https://api.anthropic.com/v1/claude_code/routines/{}/fire"
# Laisse le temps de dicter plusieurs tâches d'affilée avant de lancer un seul tri.
TRIAGE_DELAY = 90
# Le tri prend en général moins d'une minute ; on réveille ensuite les appareils pour qu'ils voient le résultat.
PUSH_AFTER_TRIAGE = 180
MAX_TRIAGES_PER_DAY = 20
PARIS = ZoneInfo("Europe/Paris")
JOURS = ("lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche")
# API de Home Assistant vue depuis une app (add-on) avec `homeassistant_api: true`.
CORE_API = "http://supervisor/core/api"
# Clés et op_id dérivés de l'identifiant Google : une reprise après une coupure ne crée pas de doublon.
INBOX_NAMESPACE = uuid.UUID("6f1c2a3e-1d8b-4e5f-9a7c-2b4d6e8f0a1c")
# Plusieurs événements d'affilée (lot de l'app) : un seul push.
PUSH_DEBOUNCE = 3
# Disponibilités TMDB (P9-B3) : passage peu après une modification, puis toutes les heures ; plafond par passage.
TMDB_DEBOUNCE = 30
TMDB_PER_PASS = 10
# Playlist Spotify « À écouter » (P9-D4) : même rythme que TMDB.
SPOTIFY_DEBOUNCE = 30
SPOTIFY_PER_PASS = 10


def tache_depuis_google(item):
    """Tâche Google Tasks (`todo.get_items`) → valeur `donnees_apps` (format `TacheHA` de l'app).

    Les lignes ⏰, 🏷, 🔖, 🔁, ❗/🔽 en tête des notes deviennent des champs (même règle que
    `NotesTimeCodec.decode` côté app) ; le reste des notes est gardé tel quel.
    """
    tache = {"v": 1, "titre": item.get("summary", ""), "fait": False, "google_id": item["uid"]}
    lines = (item.get("description") or "").split("\n")
    while lines:
        line = lines[0].replace("\ufe0f", "")
        rest = line[1:].strip()
        if "heure" not in tache and line.startswith("⏰") and _heure(rest):
            tache["heure"] = _heure(rest)
        elif "categorie" not in tache and line.startswith("🏷") and rest:
            tache["categorie"] = rest
        elif "tags" not in tache and line.startswith("🔖"):
            tags = []
            for tag in rest.split(","):
                tag = tag.strip(" #")
                if tag and tag.lower() not in (t.lower() for t in tags):
                    tags.append(tag)
            if not tags:
                break
            tache["tags"] = tags[:3]
        elif "relances" not in tache and line.startswith("🔁") and rest:
            tache["relances"] = line
        elif "priorite" not in tache and line[:1] in ("❗", "🔽"):
            tache["priorite"] = "Urgente" if line.startswith("❗") else "Basse"
        else:
            break
        lines.pop(0)
    notes = "\n".join(lines)
    if notes:
        tache["notes"] = notes
    due = item.get("due")
    if due:
        tache["jour"] = str(due)[:10]
    else:
        tache.pop("heure", None)
    return tache


def _heure(text):
    parts = text.split(":")
    if len(parts) != 2 or not all(p.isdigit() for p in parts):
        return None
    h, m = int(parts[0]), int(parts[1])
    return f"{h:02d}:{m:02d}" if 0 <= h < 24 and 0 <= m < 60 else None


class RelanceVigie(Hass):
    def initialize(self):
        for required in ("todo_entity", "team_id", "key_id", "key_path", "bundle_id"):
            if required not in self.args:
                self.log(f"{required} est requis dans apps.yaml", level="ERROR")
                return

        self._todo = self.args["todo_entity"]
        # Mémo de la routine de tri dans Google (seulement sans tâches dans HA) : Home Assistant le garde en cache, on le rafraîchit avec les tâches
        # pour que la routine lise les fiches ajoutées depuis l'app.
        self._memo = self.args.get("memo_entity", "todo.relance_memo")
        self._bundle_id = self.args["bundle_id"]
        self._tokens_path = Path(self.args.get("tokens_file", "/config/relance_tokens.json"))
        # Audit de batterie (P9-E) : pushs envoyés par jour et par cause.
        self._push_stats_path = Path(self.args.get("push_stats_file", "/config/relance_push_stats.json"))
        # Builds Xcode Cloud signalés par ci_scripts/signaler_build.sh : numéro ↔ commit.
        self._builds_path = Path(self.args.get("builds_file", "/config/relance_builds.json"))
        # Jeton TMDB (lecture seule), déposé à la main par Alexandre ; jamais dans le dépôt.
        self._tmdb_token_path = Path(self.args.get("tmdb_token_file", "/config/tmdb_token"))
        self._tmdb_handle = None
        self._tmdb_missing_logged = False
        # Spotify (P9-D4) : identifiants et jeton de rafraîchissement, écrits par homeassistant/scripts/spotify_jeton.py.
        self._spotify_path = Path(self.args.get("spotify_file", "/config/spotify_aiguillage.json"))
        self._spotify_handle = None
        self._spotify_missing_logged = False
        self._lock = threading.Lock()
        self._jwt = None
        self._jwt_issued_at = 0.0

        self.listen_event(self.on_register, "relance_register")
        # Bouton « Retrier » de l'app (même webhook, action « triage ») ou événement direct.
        self.listen_event(lambda *_a, **_kw: self.request_triage(), "relance_triage")
        # Diagnostic : « relance_test_push » envoie un push tout de suite à chaque appareil.
        self.listen_event(lambda *_args, **_kw: self.push_all("test"), "relance_test_push")
        self.listen_state(self.on_tasks_changed, self._todo)
        # Tâches rangées dans Home Assistant (intégration donnees_apps).
        self._espace = self.args.get("ha_espace")
        self._inbox = bool(self.args.get("inbox")) and bool(self._espace)
        self._inbox_path = Path(self.args.get("inbox_file", "/config/relance_inbox.json"))
        self._push_handle = None
        self._changes = 0
        # Clés connues de l'espace : une clé nouvelle (tâche créée dans l'app ou reprise de Google) lance le tri.
        self._known_keys = None
        if self._espace:
            self.listen_event(self.on_data_changed, "donnees_apps_modifie", espace=self._espace)
            self.run_in(lambda **_kw: self._load_known_keys(), 1)
            self.run_every(self.tmdb_pass, "now+90", 3600)
            self.run_every(self.spotify_pass, "now+120", 3600)
        # Rappels « à la maison » (P9-F2) : présence approchée par la zone Hue MotionAware du salon.
        self._presence = self.args.get("presence_entity")
        if self._espace and self._presence:
            self.listen_state(self.on_presence, self._presence, new="on", old="off")
        # Retour d'Alexandre (P9-F4) : son iPhone revient à portée des relais Bermuda.
        self._domicile = self.args.get("domicile_entity")
        if self._espace and self._domicile:
            self.listen_state(self.on_presence, self._domicile, new="home", old="not_home")
        # Pièce d'Alexandre (P9-F4, Bermuda) : rappels « dans une pièce », après 30 s dans la même pièce.
        self._piece = self.args.get("piece_entity")
        self._piece_handle = None
        if self._espace and self._piece:
            self.listen_state(self.on_piece, self._piece)
            self.run_in(lambda **_kw: self._publier_pieces(), 15)
        # Essai : « aiguillage_test_maison » simule une arrivée au salon.
        self.listen_event(lambda *_a, **_kw: self.on_presence(None, None, None, None), "aiguillage_test_maison")
        # Bouton « Lire sur la TV » (app TV ou iPhone) via script.aiguillage_spotify_sur_tv.
        self.listen_event(self.on_spotify_lire, "aiguillage_spotify_lire")
        self.listen_event(self.on_spotify_ecoute, "aiguillage_spotify_ecoute")
        self._refreshes = 0
        self._triage_handle = None
        self._triage_day = None
        self._triage_count = 0
        # Tri par l'API Messages (P9-I) : `routine` (la routine claude.ai, comme avant), `ombre` (la routine trie,
        # l'API propose sans écrire, journal dans aiguillage_tri_ombre.jsonl) ou `api` (la vigie trie, la routine en secours).
        self._tri_mode = self.args.get("tri_mode", "routine")
        self._tri_lock = threading.Lock()
        self._tri_etat_path = Path(self.args.get("tri_etat_file", "/config/aiguillage_tri_etat.json"))
        self._tri_manque_logged = False
        if self._espace and self._tri_mode in ("ombre", "api"):
            # Passage du matin sur toutes les tâches ouvertes (le cron de la routine en mode `routine` et `ombre`).
            self.run_daily(lambda **_kw: self.fire_triage(complet=True), self.args.get("tri_matin", "06:45:00"))
            self.log(f"Tri par l'API en mode « {self._tri_mode} »")
        self.run_every(self.refresh, "now+5", int(self.args.get("refresh_seconds", 60)))
        self.run_daily(self._log_push_stats, "00:00:30")
        mode = f", tâches dans HA ({self._espace}{', boîte d’entrée Google' if self._inbox else ''})" if self._espace else ""
        self.log(f"Vigie active sur {self._todo}{mode}, {len(self._load_tokens())} appareil(s) enregistré(s)")

    # MARK: - Surveillance

    def refresh(self, **kwargs):
        self._refreshes += 1
        if self._refreshes == 1:
            self.log("Rafraîchissement automatique de Google Tasks actif")
        try:
            # Tâches dans HA : le mémo est une liste Local To-do de HA, plus rien à rafraîchir chez Google.
            entites = [self._todo] if self._espace else [self._todo, self._memo]
            self.call_service("homeassistant/update_entity", entity_id=entites)
        except Exception as error:  # noqa: BLE001 — on veut voir toute erreur dans le journal
            self.log(f"Rafraîchissement impossible : {error!r}", level="WARNING")
        if self._inbox:
            # Le temps que Home Assistant ait relu Google.
            self.run_in(self.import_inbox, 5)

    def on_tasks_changed(self, entity, attribute, old, new, **kwargs):
        if old in UNAVAILABLE or new in UNAVAILABLE or old == new:
            return
        if self._inbox:
            # La liste Google n'est plus qu'une boîte d'entrée : push et tri partent quand la tâche arrive dans HA.
            self.log(f"{entity} : {old} → {new} dans la boîte d'entrée Google")
            return
        self.log(f"{entity} : {old} → {new} tâches à faire, réveil des appareils")
        self.push_all("liste_google")
        if self._as_int(new) > self._as_int(old):
            self.schedule_triage()

    @staticmethod
    def _as_int(value):
        try:
            return int(float(value))
        except (TypeError, ValueError):
            return 0

    # MARK: - Tâches dans Home Assistant

    def on_data_changed(self, event_name, data, **kwargs):
        """Écriture dans l'espace (app, extension, autre appareil, boîte d'entrée) : réveil des appareils,
        et tri si c'est une tâche nouvelle."""
        key = data.get("cle")
        if self._known_keys is not None and key and self._is_task_key(key) and key not in self._known_keys:
            self._known_keys.add(key)
            self.log(f"{self._espace} : nouvelle tâche ({key[:8]}…), tri demandé")
            self.schedule_triage()
        self._changes += 1
        if self._push_handle:
            self.cancel_timer(self._push_handle)
        self._push_handle = self.run_in(self._push_after_change, PUSH_DEBOUNCE)
        # Une envie à regarder ajoutée ou modifiée : disponibilités TMDB peu après (une seule fois par rafale).
        if self._tmdb_handle:
            self.cancel_timer(self._tmdb_handle)
        self._tmdb_handle = self.run_in(self.tmdb_pass, TMDB_DEBOUNCE)
        if self._spotify_handle:
            self.cancel_timer(self._spotify_handle)
        self._spotify_handle = self.run_in(self.spotify_pass, SPOTIFY_DEBOUNCE)

    def _push_after_change(self, **kwargs):
        self._push_handle = None
        self.log(f"{self._espace} : {self._changes} modification(s) dans Home Assistant, réveil des appareils")
        self._changes = 0
        self.push_all("modification_ha")

    # MARK: - Disponibilités TMDB (P9-B3)

    def tmdb_pass(self, **kwargs):
        """Envies à regarder pas encore vérifiées (ou vérifiées il y a plus de 7 jours) : œuvre et plateformes en
        France d'après TMDB, écrites dans `envie`. Les tâches écrites ne demandent plus rien : pas de boucle."""
        self._tmdb_handle = None
        try:
            token = self._tmdb_token_path.read_text().strip()
        except FileNotFoundError:
            token = ""
        if not token:
            if not self._tmdb_missing_logged:
                self.log(f"TMDB : pas de jeton dans {self._tmdb_token_path}, disponibilités inactives")
                self._tmdb_missing_logged = True
            return
        try:
            records = self._service("donnees_apps", "lire", {"espace": self._espace}).get("enregistrements", [])
        except Exception as error:  # noqa: BLE001
            self.log(f"TMDB : tâches illisibles : {error!r}", level="WARNING")
            return
        today = date.today()
        client = aiguillage_tmdb.Client(token)
        due = [r for r in records if self._is_task_key(r.get("cle", "")) and r.get("valeur")
               and aiguillage_tmdb.needs_lookup(r["valeur"], today)]
        if due:
            self.log(f"TMDB : {len(due)} envie(s) à regarder à vérifier ({min(len(due), TMDB_PER_PASS)} ce passage)")
        for record in due[:TMDB_PER_PASS]:
            valeur = record["valeur"]
            try:
                info, dispo = client.lookup(valeur.get("titre", ""), today)
            except Exception as error:  # noqa: BLE001
                self.log(f"TMDB : « {valeur.get('titre')} » non vérifié : {error!r}", level="WARNING")
                continue
            if dispo is None:
                updated = aiguillage_tmdb.with_status(valeur, info, today)
                summary = info
            else:
                updated = aiguillage_tmdb.with_availability(valeur, info, dispo, today)
                summary = ", ".join(p["nom"] for p in dispo.get("abonnement", [])) or "aucun abonnement"
            try:
                result = self._service("donnees_apps", "ecrire", {
                    "espace": self._espace, "cle": record["cle"], "valeur": updated,
                    "version_attendue": record["version"], "modifie_par": "vigie", "op_id": str(uuid.uuid4()),
                })
            except Exception as error:  # noqa: BLE001
                self.log(f"TMDB : « {valeur.get('titre')} » non écrit : {error!r}", level="WARNING")
                continue
            # Conflit (modifiée entre-temps) : le prochain passage reprendra la nouvelle version.
            self.log(f"TMDB : « {valeur.get('titre')} » → {summary} ({result.get('statut')})")

    # MARK: - Spotify (P9-D4)

    def _spotify_client(self):
        try:
            ids = json.loads(self._spotify_path.read_text())
        except (FileNotFoundError, ValueError):
            if not self._spotify_missing_logged:
                self.log(f"Spotify : pas d'identifiants dans {self._spotify_path}, playlist et lecture inactives")
                self._spotify_missing_logged = True
            return None
        return aiguillage_spotify.Client(ids)

    def _publier_agenda(self, records):
        """Agenda « Sorties » (iCalendar) dans le dossier web de HA, derrière une clé secrète créée une fois
        (`/config/aiguillage_agenda_token`, jamais dans un dépôt) : Google Agenda et le Calendrier d'Apple s'y
        abonnent. Réécrit seulement si une sortie a changé."""
        try:
            jeton_path = Path(self.args.get("agenda_token_file", "/config/aiguillage_agenda_token"))
            if not jeton_path.exists():
                jeton_path.write_text(secrets.token_urlsafe(24))
                self.log("Agenda : clé de l'abonnement créée")
            jeton = jeton_path.read_text().strip()
            dossier = Path(self.args.get("agenda_dir", "/homeassistant/www/aiguillage")) / jeton
            fichier = dossier / "sorties.ics"
            texte = aiguillage_agenda.ics(records, datetime.now(UTC))
            ancien = fichier.read_text() if fichier.exists() else ""
            if aiguillage_agenda.sans_horodatage(ancien) == aiguillage_agenda.sans_horodatage(texte):
                return
            dossier.mkdir(parents=True, exist_ok=True)
            tmp = fichier.with_suffix(".tmp")
            tmp.write_text(texte)
            os.replace(tmp, fichier)
            self.log(f"Agenda : {len(aiguillage_agenda.sorties(records))} sortie(s) publiée(s)")
        except Exception as error:  # noqa: BLE001
            self.log(f"Agenda : publication impossible : {error!r}", level="WARNING")

    def spotify_pass(self, **kwargs):
        """Passage des actions (P9-D2, D3) : recettes appliquées aux tâches, puis actions de HA dues exécutées
        (aujourd'hui `playlist_spotify`), puis copie de la playlist pour la TV. Une action faite ou en échec n'est
        jamais relancée seule (`etat`) : pas de boucle sur les écritures de la vigie."""
        self._spotify_handle = None
        try:
            records = self._service("donnees_apps", "lire", {"espace": self._espace}).get("enregistrements", [])
        except Exception as error:  # noqa: BLE001
            self.log(f"Actions : tâches illisibles : {error!r}", level="WARNING")
            return
        self._publier_agenda(records)
        recettes = self._recettes(records)
        client = self._spotify_client()
        today = date.today()
        maintenant = datetime.now(UTC).isoformat(timespec="seconds")
        for record in records:
            if not self._is_task_key(record.get("cle", "")) or not record.get("valeur"):
                continue
            avant = record["valeur"]
            tache = aiguillage_actions.appliquer_recettes(avant, recettes, maintenant) or avant
            faites = []
            for action in list(tache.get("actions") or []):
                # Préparations confiées à la routine Claude (D5) : lancée une fois, échec si pas de réponse en 24 h.
                if aiguillage_actions.due(action, tache, today, executant="routine"):
                    if self._lancer_routine_actions(record["cle"], action, tache):
                        tache = aiguillage_actions.marquer(tache, action["id"], "en_cours", "Routine lancée", maintenant)
                        faites.append(f"{action.get('type')} : routine lancée")
                    continue
                if aiguillage_actions.routine_en_retard(action, datetime.now(UTC)):
                    tache = aiguillage_actions.marquer(tache, action["id"], "echec", "La routine n'a pas répondu en 24 h", maintenant)
                    faites.append(f"{action.get('type')} : échec (routine muette)")
                    continue
                if not aiguillage_actions.due(action, tache, today):
                    continue
                etat, resultat = self._executer(action, tache, client)
                if etat is None:
                    continue  # pas exécutable maintenant (Spotify sans identifiants, coupure réseau) : on réessaiera
                tache = aiguillage_actions.marquer(tache, action["id"], etat, resultat, maintenant)
                faites.append(f"{action.get('type')} : {etat}")
            # Échecs et préparations prêtes (routine comprise) : notification visible, une fois par état.
            for action in list(tache.get("actions") or []):
                message = aiguillage_actions.a_notifier(action, tache)
                if message:
                    envoyes = self.notify_all(*message, cause="action")
                    tache = aiguillage_actions.noter_notifie(tache, action["id"])
                    faites.append(f"{action.get('type')} : {action.get('etat')} notifié ({envoyes} iPhone)")
            if tache is avant:
                continue
            try:
                result = self._service("donnees_apps", "ecrire", {
                    "espace": self._espace, "cle": record["cle"], "valeur": tache,
                    "version_attendue": record["version"], "modifie_par": "vigie", "op_id": str(uuid.uuid4()),
                })
            except Exception as error:  # noqa: BLE001
                self.log(f"Actions : « {avant.get('titre')} » non écrite : {error!r}", level="WARNING")
                continue
            # Conflit : le prochain passage relit (une action déjà exécutée l'est sans effet : pas de doublon Spotify).
            ajoutees = len(tache.get("actions") or []) - len(avant.get("actions") or [])
            self.log(f"Actions : « {avant.get('titre')} » : {ajoutees} ajoutée(s){', ' if faites else ''}{', '.join(faites)} "
                     f"({result.get('statut')})")
        if client is not None:
            self._copier_playlist(client, records)

    def _recettes(self, records):
        """Recettes de `config:recettes` ; créées avec les recettes par défaut si absentes."""
        actuel = next((r for r in records if r.get("cle") == aiguillage_actions.CLE_RECETTES), None)
        if actuel:
            return (actuel.get("valeur") or {}).get("recettes") or []
        try:
            self._service("donnees_apps", "ecrire", {
                "espace": self._espace, "cle": aiguillage_actions.CLE_RECETTES,
                "valeur": {"recettes": aiguillage_actions.RECETTES_PAR_DEFAUT}, "version_attendue": 0,
                "modifie_par": "vigie", "op_id": str(uuid.uuid4()),
            })
            self.log("Actions : recettes par défaut créées (config:recettes)")
        except Exception as error:  # noqa: BLE001
            self.log(f"Actions : recettes non créées : {error!r}", level="WARNING")
        return aiguillage_actions.RECETTES_PAR_DEFAUT

    def _lancer_routine_actions(self, cle, action, tache):
        """Lance la routine « Aiguillage · actions » (créée depuis le chat Claude) pour une action `preparer`.
        Sans identifiant (`actions_routine_id`) ou jeton (`/config/aiguillage_actions_token`) : rien, l'action attend."""
        routine_id = self.args.get("actions_routine_id")
        token_path = Path(self.args.get("actions_routine_token_file", "/config/aiguillage_actions_token"))
        try:
            token = token_path.read_text().strip() if routine_id else ""
        except FileNotFoundError:
            token = ""
        if not token:
            if not getattr(self, "_actions_routine_missing_logged", False):
                self.log("Actions : routine « actions » non configurée (actions_routine_id, jeton), préparations en attente")
                self._actions_routine_missing_logged = True
            return False
        try:
            response = httpx.post(
                ROUTINE_URL.format(routine_id),
                headers={"Authorization": f"Bearer {token}", "anthropic-beta": "experimental-cc-routine-2026-04-01",
                         "anthropic-version": "2023-06-01"},
                json={"text": aiguillage_actions.texte_routine(cle, action, tache)}, timeout=20)
        except httpx.HTTPError as error:
            self.log(f"Actions : routine non lancée : {error}", level="WARNING")
            return False
        if response.status_code >= 300:
            self.log(f"Actions : routine refusée ({response.status_code}) : {response.text[:200]}", level="WARNING")
            return False
        return True

    # MARK: - Rappels « à la maison » (P9-F2)

    def on_presence(self, entity, attribute, old, new, **kwargs):
        """Quelqu'un arrive au salon (personne → quelqu'un) : notification visible pour chaque tâche qui porte
        l'action « Me le rappeler à la maison », une fois par jour au plus."""
        try:
            records = self._service("donnees_apps", "lire", {"espace": self._espace}).get("enregistrements", [])
        except Exception as error:  # noqa: BLE001
            self.log(f"Maison : tâches illisibles : {error!r}", level="WARNING")
            return
        today = date.today()
        maintenant = datetime.now(UTC).isoformat(timespec="seconds")
        heure = datetime.now().strftime("%H:%M")
        for record in records:
            tache = record.get("valeur") or {}
            if not self._is_task_key(record.get("cle", "")):
                continue
            dues = [a for a in tache.get("actions") or [] if aiguillage_actions.rappel_maison_du(a, tache, today)]
            if not dues:
                continue
            envoyes = self.notify_all("🏠 " + (tache.get("titre") or "Tâche"), "Tu es à la maison : c'est le moment.")
            for action in dues:
                tache = aiguillage_actions.marquer_rappel(tache, action["id"], maintenant, heure)
            try:
                self._service("donnees_apps", "ecrire", {
                    "espace": self._espace, "cle": record["cle"], "valeur": tache,
                    "version_attendue": record["version"], "modifie_par": "vigie", "op_id": str(uuid.uuid4()),
                })
            except Exception as error:  # noqa: BLE001
                self.log(f"Maison : « {tache.get('titre')} » non écrite : {error!r}", level="WARNING")
            self.log(f"Maison : rappel de « {tache.get('titre')} » ({envoyes} iPhone)")

    def on_piece(self, entity, attribute, old, new, **kwargs):
        """Changement de pièce (Bermuda) : noté ; la pièce n'est retenue que si elle domine les 2 dernières minutes."""
        maintenant = time.time()
        self._piece_hist = [(t, p) for t, p in getattr(self, "_piece_hist", [])
                            if t >= maintenant - 2 * aiguillage_actions.PIECE_FENETRE] + [(maintenant, new)]
        if not self._piece_handle:
            self._piece_handle = self.run_every(self._piece_verifier, "now+15", 15)

    def _piece_verifier(self, **kwargs):
        """Toutes les 15 s : pièce dominante (70 % des 2 dernières minutes). Nouvelle pièce → ses rappels."""
        piece = aiguillage_actions.piece_dominante(getattr(self, "_piece_hist", []), time.time())
        if piece is None or piece == getattr(self, "_piece_retenue", None):
            return
        self._piece_retenue = piece
        self._piece_stable(piece=piece)

    def _piece_stable(self, **kwargs):
        """Pièce retenue (dominante sur 2 min) : rappels de cette pièce (une fois par jour et par tâche)."""
        piece = kwargs.get("piece")
        try:
            records = self._service("donnees_apps", "lire", {"espace": self._espace}).get("enregistrements", [])
        except Exception as error:  # noqa: BLE001
            self.log(f"Pièce : tâches illisibles : {error!r}", level="WARNING")
            return
        today = date.today()
        maintenant = datetime.now(UTC).isoformat(timespec="seconds")
        heure = datetime.now().strftime("%H:%M")
        for record in records:
            tache = record.get("valeur") or {}
            if not self._is_task_key(record.get("cle", "")):
                continue
            dues = [a for a in tache.get("actions") or [] if aiguillage_actions.rappel_piece_du(a, tache, piece, today)]
            if not dues:
                continue
            envoyes = self.notify_all(f"📍 {tache.get('titre') or 'Tâche'}", f"Tu es dans : {piece}.")
            for action in dues:
                tache = aiguillage_actions.marquer_rappel(tache, action["id"], maintenant, heure)
            try:
                self._service("donnees_apps", "ecrire", {
                    "espace": self._espace, "cle": record["cle"], "valeur": tache,
                    "version_attendue": record["version"], "modifie_par": "vigie", "op_id": str(uuid.uuid4()),
                })
            except Exception as error:  # noqa: BLE001
                self.log(f"Pièce : « {tache.get('titre')} » non écrite : {error!r}", level="WARNING")
            self.log(f"Pièce : rappel de « {tache.get('titre')} » en {piece} ({envoyes} iPhone)")

    def _publier_pieces(self):
        """Pièces de la maison (zones de HA) dans `config:pieces`, pour le menu « Me le rappeler dans… » de l'app."""
        try:
            texte = self.render_template("{{ areas() | map('area_name') | list | tojson }}")
            pieces = json.loads(texte) if isinstance(texte, str) else list(texte)
        except Exception as error:  # noqa: BLE001
            self.log(f"Pièce : liste des pièces illisible : {error!r}", level="WARNING")
            return
        try:
            actuel = self._service("donnees_apps", "lire", {"espace": self._espace, "cle": aiguillage_actions.CLE_PIECES})
            enregistrement = actuel.get("enregistrement") or {}
        except Exception:  # noqa: BLE001
            enregistrement = {}
        if (enregistrement.get("valeur") or {}).get("pieces") == pieces:
            return
        try:
            self._service("donnees_apps", "ecrire", {
                "espace": self._espace, "cle": aiguillage_actions.CLE_PIECES, "valeur": {"pieces": pieces},
                "version_attendue": enregistrement.get("version", 0), "modifie_par": "vigie", "op_id": str(uuid.uuid4()),
            })
            self.log(f"Pièce : {len(pieces)} pièce(s) publiées pour l'app")
        except Exception as error:  # noqa: BLE001
            self.log(f"Pièce : pièces non publiées : {error!r}", level="WARNING")

    def notify_all(self, title, body, cause="rappel_maison"):
        """Notification visible sur les iPhone enregistrés (production : builds TestFlight). Renvoie le nombre
        d'envois réussis. Les iPad et le Mac ne la reçoivent pas, pour ne pas sonner partout à la fois."""
        with self._lock:
            tokens = self._load_tokens()
        cibles = {t: i for t, i in tokens.items()
                  if i.get("environment") == "production" and str(i.get("device", "")).startswith("iPhone")}
        self._count_push(cause, len(cibles))
        ok = 0
        with httpx.Client(http2=True, timeout=10) as client:
            for token, info in cibles.items():
                status, reason = self._send(client, token, info["environment"], alerte=(title, body))
                if status == 200:
                    ok += 1
                else:
                    self.log(f"APNs {status} {reason} pour {info.get('device', token[:8])}", level="WARNING")
        return ok

    def _executer(self, action, tache, client):
        """(etat, resultat) ; (None, None) si l'exécution doit attendre."""
        if action.get("type") == "playlist_spotify":
            if client is None:
                return None, None
            ref = aiguillage_spotify.lien_de(tache)
            if not ref or ref[0] not in ("track", "album", "episode"):
                return "echec", "Pas de lien Spotify vers un morceau, un album ou un épisode"
            try:
                _, ajoutes = client.ajouter(*ref)
            except httpx.TransportError as error:
                # Coupure réseau : l'action reste à faire, le passage suivant (1 h au plus) la reprend sans doublon.
                self.log(f"Spotify : ajout reporté (réseau) : {error!r}", level="WARNING")
                return None, None
            except Exception as error:  # noqa: BLE001
                return "echec", f"Spotify : {error!r}"[:300]
            return "faite", ("Déjà dans « À écouter »" if ajoutes == 0
                             else f"{ajoutes} titre{'s' if ajoutes > 1 else ''} ajouté{'s' if ajoutes > 1 else ''} à « À écouter »")
        return "echec", f"Type d'action inconnu de la vigie : {action.get('type')}"

    def _copier_playlist(self, client, records):
        """Copie du contenu de « À écouter » dans `config:playlist_a_ecouter` pour l'app TV (qui n'a pas de jeton
        Spotify). Écrite seulement si elle a changé (titres), pour ne pas réveiller les appareils pour rien."""
        try:
            pid = client.playlist()
            copie = aiguillage_spotify.copie_playlist(client.elements(pid), pid, datetime.now(UTC).isoformat(timespec="seconds"))
        except Exception as error:  # noqa: BLE001
            self.log(f"Spotify : playlist illisible : {error!r}", level="WARNING")
            return
        actuel = next((r for r in records if r.get("cle") == aiguillage_spotify.CLE_PLAYLIST), None)
        if actuel and (actuel.get("valeur") or {}).get("titres") == copie["titres"]:
            return
        try:
            self._service("donnees_apps", "ecrire", {
                "espace": self._espace, "cle": aiguillage_spotify.CLE_PLAYLIST, "valeur": copie,
                "version_attendue": actuel["version"] if actuel else 0, "modifie_par": "vigie", "op_id": str(uuid.uuid4()),
            })
            self.log(f"Spotify : copie de la playlist pour la TV ({len(copie['titres'])} titre(s))")
        except Exception as error:  # noqa: BLE001
            self.log(f"Spotify : copie de la playlist non écrite : {error!r}", level="WARNING")

    def on_spotify_lire(self, event_name, data, **kwargs):
        """Lecture par Spotify Connect : `lien` Spotify (morceau, album, épisode, playlist) ou `a_ecouter` (toute la
        playlist « À écouter »), sur `appareil` : « tv » (le Freebox Player, par défaut) ou un nom (« ls50 »)."""
        lien = data.get("lien", "")
        choix = (data.get("appareil") or "tv").strip().lower()
        client = self._spotify_client()
        if client is None:
            return
        try:
            if lien == aiguillage_spotify.PLAYLIST_A_ECOUTER:
                ref = ("playlist", client.playlist())
            else:
                ref = aiguillage_spotify.spotify_ref(lien)
            if not ref:
                self.log("Spotify : lecture impossible (lien non Spotify)", level="WARNING")
                return
            cible = aiguillage_spotify.appareil(client.appareils(), choix)
            if cible is None:
                self.log(f"Spotify : appareil « {choix} » absent de Spotify Connect (éteint ou app fermée ?)", level="WARNING")
                return
            client.lire(*ref, cible["id"])
            self.log(f"Spotify : lecture de {ref[0]} {ref[1][:8]}… sur « {cible.get('name')} »")
        except Exception as error:  # noqa: BLE001
            self.log(f"Spotify : lecture en échec : {error!r}", level="WARNING")

    def on_spotify_ecoute(self, event_name, data, **kwargs):
        """« Écouté » sur un titre de la playlist (app TV, P9-L2) : retire le titre de « À écouter », coche l'envie
        liée (même titre, ou son album quand il n'en reste plus rien), puis recopie la playlist pour la TV."""
        ref = aiguillage_spotify.spotify_ref(data.get("lien", ""))
        client = self._spotify_client()
        if client is None or not ref:
            return
        try:
            pid = client.playlist()
            elements = client.elements(pid)
            album_id = aiguillage_spotify.album_de(elements, ref)
            client.retirer(pid, *ref)
            album_fini = bool(album_id) and not aiguillage_spotify.album_reste(elements, album_id, aiguillage_spotify.uri(*ref))
            records = self._service("donnees_apps", "lire", {"espace": self._espace}).get("enregistrements", [])
        except Exception as error:  # noqa: BLE001
            self.log(f"Spotify : « Écouté » en échec : {error!r}", level="WARNING")
            return
        fait_le = datetime.now(UTC).isoformat(timespec="seconds").replace("+00:00", "Z")
        for r in aiguillage_spotify.envies_ecoutees([r for r in records if self._is_task_key(r.get("cle", ""))],
                                                    ref, album_id, album_fini):
            try:
                self._service("donnees_apps", "ecrire", {
                    "espace": self._espace, "cle": r["cle"], "valeur": aiguillage_spotify.cochee(r["valeur"], fait_le),
                    "version_attendue": r["version"], "modifie_par": "vigie", "op_id": str(uuid.uuid4()),
                })
                self.log(f"Spotify : « {r['valeur'].get('titre')} » écouté (coché)")
            except Exception as error:  # noqa: BLE001
                self.log(f"Spotify : « {r['valeur'].get('titre')} » non coché : {error!r}", level="WARNING")
        self.log(f"Spotify : {ref[0]} {ref[1][:8]}… retiré de « À écouter »")
        self._copier_playlist(client, records)

    def _load_known_keys(self):
        try:
            records = self._service("donnees_apps", "changements", {"espace": self._espace, "depuis_seq": 0})
        except Exception as error:  # noqa: BLE001
            self.log(f"Clés de l'espace illisibles, tri des nouvelles tâches inactif : {error!r}", level="WARNING")
            return
        self._known_keys = {r["cle"] for r in records.get("enregistrements", [])}

    @staticmethod
    def _is_task_key(key):
        """Les tâches ont pour clé un UUID ; les autres clés (essais) sont ignorées."""
        try:
            uuid.UUID(key)
        except ValueError:
            return False
        return True

    def import_inbox(self, **kwargs):
        """Vide la liste Google (dictées Google Home) dans l'espace HA, sans doublon.

        Ne démarre qu'après la migration de l'app (au moins une tâche de l'espace porte un
        `google_id`) : sinon les tâches Google seraient reprises deux fois. Une tâche déjà dans HA
        (migrée ou importée) est seulement retirée de Google. Une dictée est reprise telle quelle :
        la routine la trie ensuite dans HA (clé nouvelle, voir `on_data_changed`).
        """
        try:
            items = self._service("todo", "get_items", {"entity_id": self._todo, "status": "needs_action"})
            items = (items or {}).get(self._todo, {}).get("items", [])
            if not items:
                return
            records = self._service("donnees_apps", "changements", {"espace": self._espace, "depuis_seq": 0})
        except Exception as error:  # noqa: BLE001
            self.log(f"Boîte d'entrée : lecture impossible : {error!r}", level="WARNING")
            return
        known = {
            r["valeur"].get("google_id")
            for r in records.get("enregistrements", [])
            if not r.get("supprime") and isinstance(r.get("valeur"), dict)
        }
        known.discard(None)
        if not known:
            self.log("Boîte d'entrée en attente : l'app n'a pas encore migré ses tâches", level="DEBUG")
            return

        state = self._load_inbox()
        for item in items:
            uid = item.get("uid")
            if not uid:
                continue
            if uid in known or uid in state["processed"]:
                self._remove_from_google(uid, state)
                continue
            tache = tache_depuis_google(item)
            try:
                result = self._service("donnees_apps", "ecrire", {
                    "espace": self._espace,
                    "cle": str(uuid.uuid5(INBOX_NAMESPACE, uid)),
                    "valeur": tache,
                    "modifie_le": datetime.now(UTC).isoformat(),
                    "modifie_par": "vigie",
                    "op_id": str(uuid.uuid5(INBOX_NAMESPACE, "op-" + uid)),
                })
            except Exception as error:  # noqa: BLE001
                self.log(f"Boîte d'entrée : « {tache['titre']} » non reprise : {error!r}", level="WARNING")
                continue
            if result.get("statut") == "ok":
                self.log(f"Boîte d'entrée : « {tache['titre']} » reprise dans Home Assistant")
                self._remove_from_google(uid, state)
        self._save_inbox(state)

    def _remove_from_google(self, uid, state):
        try:
            self._service("todo", "remove_item", {"entity_id": self._todo, "item": uid}, response=False)
        except Exception as error:  # noqa: BLE001
            self.log(f"Boîte d'entrée : retrait de Google impossible ({uid}) : {error!r}", level="WARNING")
            return
        if uid not in state["processed"]:
            state["processed"].append(uid)

    def _load_inbox(self):
        try:
            state = json.loads(self._inbox_path.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            state = {}
        return {"processed": state.get("processed", [])}

    def _save_inbox(self, state):
        state["processed"] = state["processed"][-500:]
        self._inbox_path.write_text(json.dumps(state, indent=2))

    def _service(self, domain, service, data, response=True):
        """Action Home Assistant par son API REST (le jeton de l'add-on est fourni par le Supervisor).

        `call_service` d'AppDaemon ne transmet pas `return_response`, exigé par `donnees_apps`.
        """
        url = f"{CORE_API}/services/{domain}/{service}" + ("?return_response" if response else "")
        reply = httpx.post(url, json=data, timeout=15,
                           headers={"Authorization": f"Bearer {os.environ['SUPERVISOR_TOKEN']}"})
        reply.raise_for_status()
        return reply.json().get("service_response") if response else None

    # MARK: - Tri par la routine Claude

    def schedule_triage(self):
        """Nouvelle tâche : lance la routine « tri » après un court délai (regroupe les dictées)."""
        if not self.args.get("routine_id"):
            return
        if self._triage_handle:
            self.cancel_timer(self._triage_handle)
        self._triage_handle = self.run_in(self.fire_triage, TRIAGE_DELAY)

    def request_triage(self):
        """L'app a retiré catégorie et tags des tâches à retrier : on rafraîchit Google Tasks,
        puis on lance la routine peu après (le temps que Home Assistant ait la liste à jour)."""
        if not self.args.get("routine_id"):
            return
        self.log("Retri demandé par l'app")
        self.refresh()
        if self._triage_handle:
            self.cancel_timer(self._triage_handle)
        self._triage_handle = self.run_in(self.fire_triage, 20)

    def fire_triage(self, **kwargs):
        self._triage_handle = None
        token_path = Path(self.args.get("routine_token_file", "/config/relance_routine_token"))
        try:
            token = token_path.read_text().strip()
        except FileNotFoundError:
            self.log(f"Tri non lancé : jeton de routine absent ({token_path})", level="WARNING")
            return

        today = time.strftime("%Y-%m-%d")
        if self._triage_day != today:
            self._triage_day, self._triage_count = today, 0
        if self._triage_count >= MAX_TRIAGES_PER_DAY:
            self.log("Tri non lancé : plafond quotidien atteint", level="WARNING")
            return
        self._triage_count += 1

        complet = bool(kwargs.get("complet"))
        if self._tri_mode == "api" and self._espace:
            if not self._tri_api(ecrire=True, complet=complet):
                self.log("Tri : l'API n'a pas abouti, la routine prend le relais", level="WARNING")
                self._fire_routine(token)
            return
        if not complet:
            self._fire_routine(token)
        if self._tri_mode == "ombre" and self._espace:
            self._tri_api(ecrire=False, complet=complet)

    def _fire_routine(self, token):
        try:
            response = httpx.post(
                ROUTINE_URL.format(self.args["routine_id"]),
                headers={
                    "Authorization": f"Bearer {token}",
                    "anthropic-beta": "experimental-cc-routine-2026-04-01",
                    "anthropic-version": "2023-06-01",
                },
                json={"text": "Nouvelle tâche signalée par Home Assistant : trie les tâches qui en ont besoin."},
                timeout=20,
            )
        except httpx.HTTPError as error:
            self.log(f"Tri non lancé : {error}", level="WARNING")
            return
        if response.status_code >= 300:
            self.log(f"Tri refusé ({response.status_code}) : {response.text[:200]}", level="WARNING")
            return
        self.log(f"Tri lancé ({self._triage_count}/{MAX_TRIAGES_PER_DAY} aujourd'hui)")
        self.run_in(lambda **_kw: self.push_all("apres_tri"), PUSH_AFTER_TRIAGE)

    # MARK: - Tri par l'API Messages (P9-I)

    def _tri_manque(self, quoi):
        if not self._tri_manque_logged:
            self.log(f"Tri par l'API inactif : {quoi}", level="WARNING")
            self._tri_manque_logged = True
        return False

    def _tri_api(self, ecrire, complet=False):
        """Un passage de tri par l'API. `ecrire` False : mode ombre, les changements sont seulement journalisés.
        Renvoie False si le passage n'a pas abouti (la routine prend alors le relais en mode `api`)."""
        if not self._tri_lock.acquire(blocking=False):
            self.log("Tri par l'API : un passage est déjà en cours")
            return True
        try:
            return self._tri_passage(ecrire, complet)
        except Exception as error:  # noqa: BLE001 — erreur imprévue : journal, et la routine en secours
            self.log(f"Tri par l'API : erreur {error!r}", level="WARNING")
            return False
        finally:
            self._tri_lock.release()

    def _tri_passage(self, ecrire, complet):
        try:
            import anthropic
        except ImportError:
            return self._tri_manque("paquet Python « anthropic » absent (python_packages de l'add-on)")
        try:
            cle_api = Path(self.args.get("tri_cle_api_file", "/config/anthropic_api_key")).read_text().strip()
            consigne = Path(self.args.get("tri_consigne_file", "/config/aiguillage_tri_consigne.md")).read_text()
        except FileNotFoundError as error:
            return self._tri_manque(f"fichier absent ({error.filename})")
        if not cle_api.startswith("sk-ant-"):
            return self._tri_manque("clé API vide ou illisible (/config/anthropic_api_key)")
        self._tri_manque_logged = False

        etat = self._tri_etat()
        mois = datetime.now(PARIS).strftime("%Y-%m")
        if etat.get("mois") != mois:
            etat.update(mois=mois, cout_mois=0.0, passages_mois=0)
        budget = float(self.args.get("tri_budget_mensuel", 30))
        if etat["cout_mois"] >= budget:
            self.log(f"Tri par l'API : budget du mois atteint ({etat['cout_mois']:.2f} $ / {budget:.0f} $)",
                     level="WARNING")
            return False

        debut = datetime.now(UTC).isoformat()
        enregistrements = self._service("donnees_apps", "lire", {"espace": self._espace}).get("enregistrements", [])
        memo_entity = self.args.get("tri_memo_entity", "todo.aiguillage_memo")
        try:
            memo = self._service("todo", "get_items", {"entity_id": memo_entity, "status": "needs_action"})
            memo = (memo.get(memo_entity) or {}).get("items", [])
        except Exception as error:  # noqa: BLE001 — la consigne garde une copie du mémo
            self.log(f"Tri par l'API : mémo illisible ({error!r}), copie de la consigne utilisée", level="WARNING")
            memo = None
        choisies = aiguillage_tri.selection(enregistrements, etat.get("dernier_tri"), complet)
        if not choisies:
            self.log("Tri par l'API : aucune tâche à trier")
            etat["dernier_tri"] = debut
            self._tri_etat(etat)
            return True

        tags = aiguillage_tri.tags_autorises(enregistrements)
        titres = [r["valeur"].get("titre") for r in aiguillage_tri.ouvertes(enregistrements)]
        modele = self.args.get("tri_modele", aiguillage_tri.MODELE)
        effort = self.args.get("tri_effort", "high")
        # Clé d'utilisateur (« sk-ant-usr-… », non rattachée à un espace de travail) : l'API exige l'en-tête
        # anthropic-workspace-id ; l'identifiant (wrkspc_…) va dans `tri_workspace_id` (apps.yaml de HA).
        espace_travail = self.args.get("tri_workspace_id")
        client = anthropic.Anthropic(api_key=cle_api, timeout=180.0, max_retries=2,
                                     default_headers={"anthropic-workspace-id": espace_travail} if espace_travail else None)

        def demander(lot):
            local = datetime.now(PARIS)
            maintenant = f"{local:%Y-%m-%d %H:%M} ({JOURS[local.weekday()]}), Europe/Paris"
            texte = aiguillage_tri.message(maintenant, memo, lot, tags, titres)
            try:
                reponse, usage, stop = aiguillage_tri.appeler(client, consigne, texte, modele, effort)
            except anthropic.APIError as error:
                self.log(f"Tri par l'API : appel refusé ({type(error).__name__}) : {str(error)[:400]}", level="WARNING")
                return None, 0.0
            cout = aiguillage_tri.cout(usage, modele)
            etat["cout_mois"] = round(etat["cout_mois"] + cout, 4)
            etat["passages_mois"] = etat.get("passages_mois", 0) + 1
            self.log(f"Tri par l'API : {len(lot)} tâche(s) envoyée(s), {usage.input_tokens} + "
                     f"{usage.cache_read_input_tokens or 0} (cache) tokens lus, {usage.output_tokens} écrits, "
                     f"{cout:.3f} $ ; mois : {etat['cout_mois']:.2f} $")
            if reponse is None:
                self.log(f"Tri par l'API : réponse inutilisable (arrêt : {stop})", level="WARNING")
            return reponse, cout

        reponse, cout = demander(choisies)
        self._tri_etat(etat)
        if reponse is None:
            return False

        aujourdhui = datetime.now(PARIS).date()
        par_cle = {r["cle"]: r for r in choisies}
        traces, ecrites, conflits = [], 0, 0
        for changement in reponse.get("taches", []):
            record = par_cle.get(changement.get("cle"))
            if record is None:
                traces.append({"cle": changement.get("cle"), "refus": ["clé inconnue ou non envoyée"]})
                continue
            nouvelle, refus = aiguillage_tri.appliquer(record["valeur"], changement, aujourdhui,
                                                       datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"), tags)
            trace = {"cle": record["cle"], "titre": record["valeur"].get("titre"), "raison": changement.get("raison"),
                     "changements": self._tri_diff(record["valeur"], nouvelle), "refus": refus}
            if ecrire and nouvelle is not None:
                statut = self._tri_ecrire(record, nouvelle)
                if statut == "conflit":
                    # Modifiée entre-temps : relecture, nouveau passage pour cette seule tâche, un seul essai.
                    conflits += 1
                    relu = self._service("donnees_apps", "lire", {"espace": self._espace, "cle": record["cle"]})
                    relu = (relu or {}).get("enregistrement")
                    statut = "abandon"
                    if relu and not relu.get("supprime") and not (relu.get("valeur") or {}).get("fait"):
                        rep2, _ = demander([relu])
                        ch2 = next((c for c in (rep2 or {}).get("taches", []) if c.get("cle") == relu["cle"]), None)
                        if ch2:
                            nouvelle, refus2 = aiguillage_tri.appliquer(
                                relu["valeur"], ch2, aujourdhui, datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"), tags)
                            trace["refus"] += refus2
                            statut = self._tri_ecrire(relu, nouvelle) if nouvelle is not None else "rien"
                        self._tri_etat(etat)
                trace["statut"] = statut
                ecrites += statut == "ok"
            traces.append(trace)

        with Path(self.args.get("tri_journal_file", "/config/aiguillage_tri_ombre.jsonl")).open("a") as journal:
            journal.write(json.dumps({"moment": debut, "mode": "api" if ecrire else "ombre", "complet": complet,
                                      "envoyees": len(choisies), "cout": round(cout, 4), "taches": traces,
                                      "resume": reponse.get("resume"), "signalements": reponse.get("signalements")},
                                     ensure_ascii=False) + "\n")
        proposees = sum(1 for tr in traces if tr.get("changements"))
        refus = sum(len(tr.get("refus") or []) for tr in traces)
        for signal in reponse.get("signalements") or []:
            self.log(f"Tri par l'API : signalement : {str(signal)[:200]}", level="WARNING")
        self.log(f"Tri par l'API ({'écrit' if ecrire else 'ombre'}) : {proposees} tâche(s) modifiée(s)"
                 + (f", {ecrites} écrite(s), {conflits} conflit(s)" if ecrire else "") + f", {refus} refus")
        etat["dernier_tri"] = debut
        self._tri_etat(etat)
        return True

    def _tri_ecrire(self, record, nouvelle):
        result = self._service("donnees_apps", "ecrire", {
            "espace": self._espace, "cle": record["cle"], "valeur": nouvelle,
            "version_attendue": record["version"], "modifie_par": "routine-tri", "op_id": str(uuid.uuid4()),
        }) or {}
        return result.get("statut", "?")

    @staticmethod
    def _tri_diff(avant, apres):
        if apres is None:
            return {}
        return {k: apres.get(k) for k in sorted(set(avant) | set(apres)) if avant.get(k) != apres.get(k)}

    def _tri_etat(self, etat=None):
        """Lit (sans argument) ou écrit l'état du tri : dernier passage, coût et passages du mois."""
        if etat is not None:
            self._tri_etat_path.write_text(json.dumps(etat, indent=2))
            return etat
        try:
            return json.loads(self._tri_etat_path.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            return {}

    # MARK: - Appareils

    def on_register(self, event_name, data, **kwargs):
        if data.get("action") == "triage":
            self.request_triage()
            return
        if data.get("action") == "build":
            self.record_build(data)
            return
        token = str(data.get("token", "")).strip().lower()
        environment = data.get("environment", "production")
        if len(token) < 32 or not all(c in "0123456789abcdef" for c in token):
            self.log(f"Jeton refusé : {token[:12]}…", level="WARNING")
            return
        if environment not in APNS_HOSTS:
            environment = "production"

        with self._lock:
            tokens = self._load_tokens()
            tokens[token] = {
                "environment": environment,
                "device": str(data.get("device", ""))[:60],
                "updated": int(time.time()),
            }
            self._save_tokens(tokens)
        self.log(f"Appareil enregistré : {data.get('device', '?')} ({environment})")

    def record_build(self, data):
        """Build Xcode Cloud : `device` = numéro, `token` = commit, `environment` = étape. 60 builds gardés."""
        build = str(data.get("device", "")).strip()
        commit = str(data.get("token", "")).strip().lower()[:40]
        etape = str(data.get("environment", "")).strip()[:20]
        if not build.isdigit() or not all(c in "0123456789abcdef" for c in commit):
            self.log(f"Build refusé : {build[:12]} {commit[:12]}", level="WARNING")
            return
        with self._lock:
            try:
                builds = json.loads(self._builds_path.read_text())
            except (FileNotFoundError, json.JSONDecodeError):
                builds = {}
            entree = builds.setdefault(build, {"commit": commit[:7], "etapes": {}})
            entree["etapes"][etape] = datetime.now().strftime("%Y-%m-%d %H:%M")
            for old in sorted(builds, key=int)[:-60]:
                builds.pop(old)
            self._builds_path.write_text(json.dumps(builds, indent=2, sort_keys=True))
        self.log(f"Build {build} (commit {commit[:7]}) : {etape}")

    def _load_tokens(self):
        try:
            return json.loads(self._tokens_path.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            return {}

    def _save_tokens(self, tokens):
        self._tokens_path.write_text(json.dumps(tokens, indent=2))

    # MARK: - APNs

    def push_all(self, cause="autre"):
        with self._lock:
            tokens = self._load_tokens()
        if not tokens:
            self.log("Aucun appareil enregistré", level="WARNING")
            return
        self._count_push(cause, len(tokens))

        stale = []
        with httpx.Client(http2=True, timeout=10) as client:
            for token, info in tokens.items():
                status, reason = self._send(client, token, info.get("environment", "production"))
                if status == 200:
                    self.log(f"Push envoyé à {info.get('device', token[:8])}", level="DEBUG")
                elif status == 410 or reason in ("BadDeviceToken", "Unregistered"):
                    stale.append(token)
                else:
                    self.log(f"APNs {status} {reason} pour {info.get('device', token[:8])}", level="WARNING")

        if stale:
            with self._lock:
                tokens = self._load_tokens()
                for token in stale:
                    tokens.pop(token, None)
                self._save_tokens(tokens)
            self.log(f"{len(stale)} appareil(s) retiré(s) (jeton périmé)")

    def _count_push(self, cause, devices):
        """Une salve (un push à chaque appareil) de plus pour aujourd'hui ; 31 jours gardés."""
        day = datetime.now().strftime("%Y-%m-%d")
        with self._lock:
            try:
                stats = json.loads(self._push_stats_path.read_text())
            except (FileNotFoundError, json.JSONDecodeError):
                stats = {}
            jour = stats.setdefault(day, {"salves": {}, "envois": 0})
            jour["salves"][cause] = jour["salves"].get(cause, 0) + 1
            jour["envois"] += devices
            for old in sorted(stats)[:-31]:
                stats.pop(old)
            self._push_stats_path.write_text(json.dumps(stats, indent=2, sort_keys=True))

    def _log_push_stats(self, **kwargs):
        try:
            stats = json.loads(self._push_stats_path.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            return
        days = sorted(d for d in stats if d < datetime.now().strftime("%Y-%m-%d"))
        if days:
            jour = stats[days[-1]]
            detail = ", ".join(f"{cause} {n}" for cause, n in sorted(jour["salves"].items()))
            self.log(f"Pushs du {days[-1]} : {sum(jour['salves'].values())} salve(s) ({detail}), {jour['envois']} envoi(s)")

    def _send(self, client, token, environment, alerte=None):
        """Push silencieux (réveil pour synchroniser), ou notification visible si `alerte` = (titre, texte)."""
        if alerte:
            headers = {"apns-push-type": "alert", "apns-priority": "10"}
            payload = {"aps": {"alert": {"title": alerte[0], "body": alerte[1]}, "sound": "default",
                               "thread-id": "aiguillage-maison"}}
        else:
            # Un push silencieux doit être en priorité 5, sinon Apple le refuse.
            headers = {"apns-push-type": "background", "apns-priority": "5"}
            payload = {"aps": {"content-available": 1}}
        try:
            response = client.post(
                f"{APNS_HOSTS[environment]}/3/device/{token}",
                headers={"authorization": f"bearer {self._provider_token()}", "apns-topic": self._bundle_id, **headers},
                json=payload,
            )
        except httpx.HTTPError as error:
            return 0, str(error)
        if response.status_code == 200:
            return 200, ""
        try:
            return response.status_code, response.json().get("reason", "")
        except ValueError:
            return response.status_code, response.text[:80]

    def _provider_token(self):
        now = time.time()
        if self._jwt and now - self._jwt_issued_at < JWT_LIFETIME:
            return self._jwt
        key = Path(self.args["key_path"]).read_text()
        self._jwt = jwt.encode(
            {"iss": self.args["team_id"], "iat": int(now)},
            key,
            algorithm="ES256",
            headers={"kid": self.args["key_id"]},
        )
        self._jwt_issued_at = now
        return self._jwt
