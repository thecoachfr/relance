"""Températures du Hub (03/11/2026) : `sensor.hub_temperatures`, les thermomètres de chaque pièce et leur tendance,
communs aux trois vues (Hub TV, Hub iPad/iPhone, Nest Hub).

Les vues ne font qu'afficher ce capteur : tout le calcul est ici. Contrat : `homeassistant/HUB-TEMPERATURES.md`.

- **Thermomètres** : ceux de la pièce, le principal d'abord (celui que le plan affiche). Pas les sondes des appareils
  (clim, ventilateur, têtes de chauffage), faussées par l'appareil (choix d'Alexandre, 03/11/2026).
- **Tendance** : la valeur d'il y a 1 h, lue dans l'historique de HA (le Sonoff n'envoie que sur changement : la
  dernière valeur connue avant ce moment), comparée à la valeur actuelle. Seuil ±0,3 °C : « monte », « baisse »,
  sinon « stable » ; pas de valeur lisible à l'un des deux moments : null.
- **Tendance de la pièce** : celle du principal, sinon du premier thermomètre qui en a une.

Fonctions pures, testées hors Home Assistant par `tests/test_hub_temperatures.py` ; l'app AppDaemon est en fin de
fichier.
"""

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

PARIS = ZoneInfo("Europe/Paris")
ENTITE = "sensor.hub_temperatures"

FENETRE_MIN = 60
SEUIL = 0.3  # °C sur la fenêtre

# Pièces du plan (mêmes identifiants que les trois vues) et leurs thermomètres, le principal d'abord.
PIECES = (
    ("salon", (("Netatmo", "sensor.salon_temperature"), ("Thermomètre", "sensor.thermometree_salon_temperature"))),
    ("chambre", (("Netatmo", "sensor.chambre_temperature"), ("Thermomètre", "sensor.thermometre_chambre_temperature"))),
    ("bureau", (("Thermomètre", "sensor.bureau_temperature"),)),
    ("sdb", (("Thermomètre", "sensor.salon_canape_temperature"),)),
    ("entree", (("Couloir", "sensor.temperature_couloir_temperature"),)),
    ("terrasse", (("Thermomètre", "sensor.thermometre_terrasse_temperature"),)),
    ("jardin", (("Thermomètre", "sensor.thermometre_exterieur_cote_jardin_temperature"),)),
)
ENTITES = tuple(e for _, sondes in PIECES for _, e in sondes)


def nombre(etat):
    """La valeur d'un état HA (`{"state": "19.4"}`) ou None (`unavailable`, `unknown`, absent)."""
    try:
        return float((etat or {}).get("state"))
    except (TypeError, ValueError):
        return None


def valeur_a(historique, instant):
    """La valeur en vigueur à `instant` : le dernier état de l'historique changé au plus tard à ce moment (l'API
    d'historique de HA donne en premier l'état au début de la période). None si cet état n'est pas un nombre."""
    retenu = None
    for etat in historique or []:
        try:
            quand = datetime.fromisoformat(etat["last_changed"])
        except (KeyError, TypeError, ValueError):
            continue
        if quand <= instant:
            retenu = etat
        else:
            break
    return nombre(retenu)


def tendance(ecart):
    if ecart is None:
        return None
    if ecart >= SEUIL - 1e-9:
        return "monte"
    if ecart <= -SEUIL + 1e-9:
        return "baisse"
    return "stable"


def calculer(etats, historiques, maintenant):
    """(état, attributs) de `sensor.hub_temperatures`. `etats` : entité → état HA actuel ; `historiques` : entité →
    liste des états de la dernière heure (au moins), dans l'ordre."""
    avant = maintenant - timedelta(minutes=FENETRE_MIN)
    pieces, lues = {}, 0
    for piece, sondes in PIECES:
        liste = []
        for nom, entite in sondes:
            actuelle, ancienne = nombre(etats.get(entite)), valeur_a(historiques.get(entite), avant)
            ecart = round(actuelle - ancienne, 1) if actuelle is not None and ancienne is not None else None
            if actuelle is not None:
                lues += 1
            liste.append({"nom": nom, "entite": entite,
                          "temperature": round(actuelle, 1) if actuelle is not None else None,
                          "ecart_1h": ecart,
                          "tendance": tendance(actuelle - ancienne) if ecart is not None else None})
        principal = next((s for s in liste if s["tendance"] is not None), None)
        pieces[piece] = {"tendance": principal["tendance"] if principal else None,
                         "ecart_1h": principal["ecart_1h"] if principal else None,
                         "sondes": liste}
    return lues, {"maj": maintenant.isoformat(timespec="seconds"), "fenetre_min": FENETRE_MIN, "seuil": SEUIL,
                  "pieces": pieces}


# MARK: - App AppDaemon

try:
    import hassapi as hass
except ImportError:  # pragma: no cover
    hass = None

if hass is not None:
    import os

    import httpx

    CORE_API = "http://supervisor/core/api"

    class HubTemperatures(hass.Hass):

        def initialize(self):
            self.run_every(self._maj, "now+15", int(self.args.get("refresh_seconds", 300)))

        def _entetes(self):
            return {"Authorization": f"Bearer {os.environ['SUPERVISOR_TOKEN']}"}

        def _historiques(self, maintenant):
            debut = (maintenant - timedelta(minutes=FENETRE_MIN + 5)).isoformat(timespec="seconds")
            reply = httpx.get(f"{CORE_API}/history/period/{debut}", timeout=20, headers=self._entetes(),
                              params={"filter_entity_id": ",".join(ENTITES), "minimal_response": "",
                                      "no_attributes": ""})
            reply.raise_for_status()
            historiques = {}
            for liste in reply.json():
                if liste and liste[0].get("entity_id"):
                    historiques[liste[0]["entity_id"]] = liste
            return historiques

        def _publier(self, etat, attributs):
            """Par l'API REST de HA, comme `hub_meteo` : `self.set_state` d'AppDaemon 4.5 retire les valeurs vides
            (null, 0) des attributs, ce qui casse le contrat (`ecart_1h: 0`, `tendance: null`)."""
            reply = httpx.post(f"{CORE_API}/states/{ENTITE}", json={"state": etat, "attributes": attributs},
                               timeout=15, headers=self._entetes())
            reply.raise_for_status()

        def _maj(self, **kwargs):
            maintenant = datetime.now(PARIS)
            try:
                etats = {e: self.get_state(e, attribute="all") or {} for e in ENTITES}
                etat, attributs = calculer(etats, self._historiques(maintenant), maintenant)
                self._publier(etat, dict(attributs, friendly_name="Températures du Hub",
                                         icon="mdi:home-thermometer-outline"))
            except Exception as exc:  # noqa: BLE001 - le capteur garde sa dernière valeur
                self.log(f"Températures : calcul impossible ({exc!r})", level="WARNING")
