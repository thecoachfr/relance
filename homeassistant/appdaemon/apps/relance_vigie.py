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

from datetime import UTC, datetime
import json
import os
import threading
import time
from pathlib import Path
import uuid

import httpx
import jwt
from appdaemon.plugins.hass import Hass

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
# API de Home Assistant vue depuis une app (add-on) avec `homeassistant_api: true`.
CORE_API = "http://supervisor/core/api"
# Une dictée pas encore triée attend la routine au plus ce temps avant d'être reprise telle quelle.
UNTRIAGED_GRACE = 15 * 60
# Clés et op_id dérivés de l'identifiant Google : une reprise après une coupure ne crée pas de doublon.
INBOX_NAMESPACE = uuid.UUID("6f1c2a3e-1d8b-4e5f-9a7c-2b4d6e8f0a1c")
# Plusieurs événements d'affilée (lot de l'app) : un seul push.
PUSH_DEBOUNCE = 3


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
        # Mémo de la routine de tri : Home Assistant le garde en cache, on le rafraîchit avec les tâches
        # pour que la routine lise les fiches ajoutées depuis l'app.
        self._memo = self.args.get("memo_entity", "todo.relance_memo")
        self._bundle_id = self.args["bundle_id"]
        self._tokens_path = Path(self.args.get("tokens_file", "/config/relance_tokens.json"))
        self._lock = threading.Lock()
        self._jwt = None
        self._jwt_issued_at = 0.0

        self.listen_event(self.on_register, "relance_register")
        # Bouton « Retrier » de l'app (même webhook, action « triage ») ou événement direct.
        self.listen_event(lambda *_a, **_kw: self.request_triage(), "relance_triage")
        # Diagnostic : « relance_test_push » envoie un push tout de suite à chaque appareil.
        self.listen_event(lambda *_args, **_kw: self.push_all(), "relance_test_push")
        self.listen_state(self.on_tasks_changed, self._todo)
        # Tâches rangées dans Home Assistant (intégration donnees_apps).
        self._espace = self.args.get("ha_espace")
        self._inbox = bool(self.args.get("inbox")) and bool(self._espace)
        self._inbox_path = Path(self.args.get("inbox_file", "/config/relance_inbox.json"))
        self._push_handle = None
        if self._espace:
            self.listen_event(self.on_data_changed, "donnees_apps_modifie", espace=self._espace)
        self._refreshes = 0
        self._triage_handle = None
        self._triage_day = None
        self._triage_count = 0
        self.run_every(self.refresh, "now+5", int(self.args.get("refresh_seconds", 60)))
        mode = f", tâches dans HA ({self._espace}{', boîte d’entrée Google' if self._inbox else ''})" if self._espace else ""
        self.log(f"Vigie active sur {self._todo}{mode}, {len(self._load_tokens())} appareil(s) enregistré(s)")

    # MARK: - Surveillance

    def refresh(self, **kwargs):
        self._refreshes += 1
        if self._refreshes == 1:
            self.log("Rafraîchissement automatique de Google Tasks actif")
        try:
            self.call_service("homeassistant/update_entity", entity_id=[self._todo, self._memo])
        except Exception as error:  # noqa: BLE001 — on veut voir toute erreur dans le journal
            self.log(f"Rafraîchissement impossible : {error!r}", level="WARNING")
        if self._inbox:
            # Le temps que Home Assistant ait relu Google.
            self.run_in(self.import_inbox, 5)

    def on_tasks_changed(self, entity, attribute, old, new, **kwargs):
        if old in UNAVAILABLE or new in UNAVAILABLE or old == new:
            return
        if self._inbox:
            # La liste Google n'est plus qu'une boîte d'entrée : le push part quand la tâche arrive dans HA.
            self.log(f"{entity} : {old} → {new} dans la boîte d'entrée Google")
        else:
            self.log(f"{entity} : {old} → {new} tâches à faire, réveil des appareils")
            self.push_all()
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
        """Écriture dans l'espace (app, extension, autre appareil, boîte d'entrée) : réveil des appareils."""
        if self._push_handle:
            self.cancel_timer(self._push_handle)
        self._push_handle = self.run_in(self._push_after_change, PUSH_DEBOUNCE)

    def _push_after_change(self, **kwargs):
        self._push_handle = None
        self.push_all()

    def import_inbox(self, **kwargs):
        """Vide la liste Google (dictées Google Home) dans l'espace HA, sans doublon.

        Ne démarre qu'après la migration de l'app (au moins une tâche de l'espace porte un
        `google_id`) : sinon les tâches Google seraient reprises deux fois. Une tâche déjà dans HA
        (migrée ou importée) est seulement retirée de Google. Une dictée non triée attend la
        routine jusqu'à `UNTRIAGED_GRACE`, pour que le tri la trouve encore dans Google.
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
        now = time.time()
        for item in items:
            uid = item.get("uid")
            if not uid:
                continue
            if uid in known or uid in state["processed"]:
                self._remove_from_google(uid, state)
                continue
            tache = tache_depuis_google(item)
            first_seen = state["first_seen"].setdefault(uid, now)
            if "categorie" not in tache and self.args.get("routine_id") and now - first_seen < UNTRIAGED_GRACE:
                continue
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
        state["first_seen"].pop(uid, None)

    def _load_inbox(self):
        try:
            state = json.loads(self._inbox_path.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            state = {}
        return {"processed": state.get("processed", []), "first_seen": state.get("first_seen", {})}

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
        self.run_in(lambda **_kw: self.push_all(), PUSH_AFTER_TRIAGE)

    # MARK: - Appareils

    def on_register(self, event_name, data, **kwargs):
        if data.get("action") == "triage":
            self.request_triage()
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

    def _load_tokens(self):
        try:
            return json.loads(self._tokens_path.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            return {}

    def _save_tokens(self, tokens):
        self._tokens_path.write_text(json.dumps(tokens, indent=2))

    # MARK: - APNs

    def push_all(self):
        with self._lock:
            tokens = self._load_tokens()
        if not tokens:
            self.log("Aucun appareil enregistré", level="WARNING")
            return

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

    def _send(self, client, token, environment):
        try:
            response = client.post(
                f"{APNS_HOSTS[environment]}/3/device/{token}",
                headers={
                    "authorization": f"bearer {self._provider_token()}",
                    "apns-topic": self._bundle_id,
                    "apns-push-type": "background",
                    # Un push silencieux doit être en priorité 5, sinon Apple le refuse.
                    "apns-priority": "5",
                },
                json={"aps": {"content-available": 1}},
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
