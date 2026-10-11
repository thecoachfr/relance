"""Vigie Relance : réveille l'app iOS dès que la liste Google Tasks change.

1. Force l'intégration Google Tasks à se rafraîchir (elle ne le fait que toutes les 30 min).
2. Quand le nombre de tâches à faire change (dictée Google Home, tâche cochée ailleurs),
   envoie un push silencieux APNs à chaque appareil Relance enregistré.
3. Les appareils s'enregistrent via un webhook Home Assistant qui émet l'événement
   `relance_register` (voir README).
"""

import json
import threading
import time
from pathlib import Path

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


class RelanceVigie(Hass):
    def initialize(self):
        for required in ("todo_entity", "team_id", "key_id", "key_path", "bundle_id"):
            if required not in self.args:
                self.log(f"{required} est requis dans apps.yaml", level="ERROR")
                return

        self._todo = self.args["todo_entity"]
        self._bundle_id = self.args["bundle_id"]
        self._tokens_path = Path(self.args.get("tokens_file", "/config/relance_tokens.json"))
        self._lock = threading.Lock()
        self._jwt = None
        self._jwt_issued_at = 0.0

        self.listen_event(self.on_register, "relance_register")
        self.listen_state(self.on_tasks_changed, self._todo)
        self.run_every(self.refresh, "now+10", int(self.args.get("refresh_seconds", 60)))
        self.log(f"Vigie active sur {self._todo}, {len(self._load_tokens())} appareil(s) enregistré(s)")

    # MARK: - Surveillance

    def refresh(self, **kwargs):
        self.call_service("homeassistant/update_entity", entity_id=self._todo)

    def on_tasks_changed(self, entity, attribute, old, new, **kwargs):
        if old in UNAVAILABLE or new in UNAVAILABLE or old == new:
            return
        self.log(f"{entity} : {old} → {new} tâches à faire, réveil des appareils")
        self.push_all()

    # MARK: - Appareils

    def on_register(self, event_name, data, **kwargs):
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
