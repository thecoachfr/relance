"""Tests hors Home Assistant de `hub_temperatures` (Températures du Hub, `sensor.hub_temperatures`) :
uv run --with pytest python -m pytest -q homeassistant/appdaemon/tests"""

from datetime import datetime, timedelta
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import hub_temperatures as t  # noqa: E402

MAINTENANT = datetime(2026, 11, 3, 17, 0, tzinfo=t.PARIS)


def etat(valeur, il_y_a_min):
    return {"state": str(valeur), "last_changed": (MAINTENANT - timedelta(minutes=il_y_a_min)).isoformat()}


def test_valeur_a_prend_le_dernier_etat_avant_le_moment():
    h = [etat(18.0, 65), etat(18.4, 50), etat(19.0, 10)]
    assert t.valeur_a(h, MAINTENANT - timedelta(minutes=60)) == 18.0
    assert t.valeur_a(h, MAINTENANT - timedelta(minutes=30)) == 18.4


def test_valeur_a_indisponible_ou_vide():
    assert t.valeur_a([etat("unavailable", 65)], MAINTENANT - timedelta(minutes=60)) is None
    assert t.valeur_a([], MAINTENANT) is None
    assert t.valeur_a([etat(18.0, 30)], MAINTENANT - timedelta(minutes=60)) is None


def test_tendance_et_seuil():
    assert t.tendance(0.3) == "monte"
    assert t.tendance(0.29) == "stable"
    assert t.tendance(-0.3) == "baisse"
    assert t.tendance(19.3 - 19.0) == "monte"  # 0,30000000000000071 : pas d'effet de virgule flottante
    assert t.tendance(18.7 - 19.0) == "baisse"
    assert t.tendance(None) is None


def test_calculer_piece_a_deux_thermometres():
    etats = {"sensor.salon_temperature": {"state": "19.0"}, "sensor.thermometree_salon_temperature": {"state": "18.3"}}
    historiques = {"sensor.salon_temperature": [etat(18.5, 65)],
                   "sensor.thermometree_salon_temperature": [etat(18.2, 65)]}
    lues, a = t.calculer(etats, historiques, MAINTENANT)
    salon = a["pieces"]["salon"]
    assert salon["tendance"] == "monte" and salon["ecart_1h"] == 0.5
    assert [s["nom"] for s in salon["sondes"]] == ["Netatmo", "Thermomètre"]
    assert salon["sondes"][1] == {"nom": "Thermomètre", "entite": "sensor.thermometree_salon_temperature",
                                  "temperature": 18.3, "ecart_1h": 0.1, "tendance": "stable"}
    assert lues == 2


def test_calculer_principal_sans_historique_prend_le_suivant():
    etats = {"sensor.chambre_temperature": {"state": "18.9"}, "sensor.thermometre_chambre_temperature": {"state": "18.2"}}
    historiques = {"sensor.thermometre_chambre_temperature": [etat(18.6, 90)]}
    _, a = t.calculer(etats, historiques, MAINTENANT)
    chambre = a["pieces"]["chambre"]
    assert chambre["sondes"][0]["tendance"] is None and chambre["sondes"][0]["temperature"] == 18.9
    assert chambre["tendance"] == "baisse" and chambre["ecart_1h"] == -0.4


def test_calculer_capteur_indisponible():
    _, a = t.calculer({"sensor.bureau_temperature": {"state": "unavailable"}}, {}, MAINTENANT)
    assert a["pieces"]["bureau"] == {"tendance": None, "ecart_1h": None, "sondes": [
        {"nom": "Thermomètre", "entite": "sensor.bureau_temperature", "temperature": None, "ecart_1h": None,
         "tendance": None}]}


def test_toutes_les_pieces_et_l_entree_sur_le_couloir():
    _, a = t.calculer({}, {}, MAINTENANT)
    assert list(a["pieces"]) == ["salon", "chambre", "bureau", "sdb", "entree", "terrasse", "jardin"]
    assert a["pieces"]["entree"]["sondes"][0]["entite"] == "sensor.temperature_couloir_temperature"


def test_exemple_du_contrat_a_les_memes_cles():
    exemple = json.loads((Path(__file__).resolve().parents[2] / "HUB-TEMPERATURES-exemple.json").read_text())
    _, a = t.calculer({}, {}, MAINTENANT)
    assert set(exemple["attributes"]) - {"friendly_name", "icon"} == set(a)
    assert set(exemple["attributes"]["pieces"]) == set(a["pieces"])
    assert set(exemple["attributes"]["pieces"]["salon"]) == set(a["pieces"]["salon"])
    assert set(exemple["attributes"]["pieces"]["salon"]["sondes"][0]) == set(a["pieces"]["salon"]["sondes"][0])


def releve(valeur, quand):
    return {"state": str(valeur), "last_changed": quand.isoformat()}


DEBUT = MAINTENANT - timedelta(hours=6)


def test_clim_qui_chauffe_d_apres_sa_conso():
    # Relevés réels du 03/11/2026 : +0,28 kWh entre 15 h 09 et 17 h 09, soit 140 W.
    h = [releve(351.236, DEBUT), releve(351.411, MAINTENANT - timedelta(minutes=245)),
         releve(351.501, MAINTENANT - timedelta(minutes=125)), releve(351.781, MAINTENANT - timedelta(minutes=5))]
    assert t.action_par_conso(h, "heat", MAINTENANT, DEBUT) == ("heating", 140)
    assert t.action_par_conso(h, "cool", MAINTENANT, DEBUT) == ("cooling", 140)


def test_clim_au_repos_ou_inconnue():
    faible = [releve(351.0, MAINTENANT - timedelta(minutes=150)), releve(351.06, MAINTENANT - timedelta(minutes=30))]
    assert t.action_par_conso(faible, "heat", MAINTENANT, DEBUT) == ("idle", 30)
    fige = [releve(351.0, DEBUT), releve(351.5, MAINTENANT - timedelta(minutes=200))]
    assert t.action_par_conso(fige, "heat", MAINTENANT, DEBUT) == ("idle", 0)
    assert t.action_par_conso([releve(351.0, DEBUT)], "heat", MAINTENANT, DEBUT) == (None, None)
    assert t.action_par_conso(faible, "off", MAINTENANT, DEBUT) == (None, None)
    assert t.action_par_conso(faible, "fan_only", MAINTENANT, DEBUT) == (None, None)


def test_climats_dans_le_capteur():
    etats = {"climate.clim_sejour": {"state": "heat"}}
    h = {"sensor.sejour_energy_consumption": [releve(351.5, MAINTENANT - timedelta(minutes=130)),
                                               releve(351.78, MAINTENANT - timedelta(minutes=10))]}
    _, a = t.calculer(etats, h, MAINTENANT)
    assert a["climats"] == {"climate.clim_sejour": {"action": "heating", "puissance_w": 140}}
