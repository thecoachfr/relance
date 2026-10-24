"""Tests hors Home Assistant de `hub_meteo` (Météo du Hub, `sensor.hub_meteo`) :
uv run --with pytest python -m pytest -q homeassistant/appdaemon/tests"""

from datetime import datetime, timedelta
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import hub_meteo as m  # noqa: E402

PARIS = m.PARIS
MAINTENANT = datetime(2026, 10, 24, 8, 47, tzinfo=PARIS)


def capteur(valeur, il_y_a_min=10):
    return {"state": str(valeur), "last_changed": (MAINTENANT - timedelta(minutes=il_y_a_min)).isoformat()}


def mesures(terrasse=None, jardin=None, quartier=None):
    etats = {}
    for entite, c in ((m.TERRASSE, terrasse), (m.JARDIN, jardin), (m.QUARTIER, quartier)):
        if c is not None:
            etats[entite] = c
    return etats


# États réels du 24/10/2026 vers 8 h 45.
METEO = {"state": "rainy", "last_updated": "2026-10-24T08:12:46+02:00", "attributes": {
    "temperature": 9, "apparent_temperature": 6.6, "humidity": 90, "wind_bearing": 235, "wind_gust_speed": 0,
    "wind_speed": 14.4}}
PLUIE = {"state": "2026-10-24T06:45:00+00:00", "attributes": {
    "forecast_time_ref": "2026-10-24T06:45:00+00:00",
    "1_hour_forecast": {"0 min": "Pluie faible", "5 min": "Pluie faible", "10 min": "Pluie faible",
                        "15 min": "Pluie faible", "20 min": "Temps sec", "25 min": "Pluie faible",
                        "35 min": "Pluie faible", "45 min": "Temps sec", "55 min": "Temps sec"}}}
ALERTE = {"state": "Vert", "attributes": {"Vent violent": "Vert", "Pluie-inondation": "Vert", "Orages": "Vert",
                                          "Neige-verglas": "Vert", "Inondation": "Vert", "attribution": "MF",
                                          "icon": "mdi:weather-cloudy-alert", "friendly_name": "94 Weather alert"}}


def h(heure_utc, temp, mm, cond="rainy", vent=18, rafales=0):
    return {"datetime": heure_utc, "condition": cond, "temperature": temp, "precipitation": mm,
            "wind_speed": vent, "wind_gust_speed": rafales}


# Prévisions horaires réelles (extrait : 24/10 07 h UTC → 25/10 09 h UTC), puis pas de 3 h sans précipitation.
HORAIRES = [
    h("2026-10-24T07:00:00+00:00", 9.4, 1.1, vent=14.4), h("2026-10-24T08:00:00+00:00", 9.9, 0, "partlycloudy"),
    h("2026-10-24T09:00:00+00:00", 10.5, 0, "cloudy"), h("2026-10-24T10:00:00+00:00", 11.2, 0, "cloudy"),
    h("2026-10-24T11:00:00+00:00", 11.9, 0, "cloudy"), h("2026-10-24T12:00:00+00:00", 12.7, 0, "cloudy"),
    h("2026-10-24T13:00:00+00:00", 13.1, 0.1, rafales=39.6), h("2026-10-24T14:00:00+00:00", 12.6, 0.1, rafales=43.2),
    h("2026-10-24T15:00:00+00:00", 11.7, 0.3, rafales=43.2), h("2026-10-24T16:00:00+00:00", 11.1, 1.1, rafales=46.8),
    h("2026-10-24T17:00:00+00:00", 10.5, 1.3, rafales=46.8), h("2026-10-24T18:00:00+00:00", 11, 1.6, rafales=50.4),
    h("2026-10-24T19:00:00+00:00", 11.6, 2.3, rafales=57.6), h("2026-10-24T20:00:00+00:00", 11.9, 2.7, rafales=64.8),
    h("2026-10-24T21:00:00+00:00", 12.6, 2.1, rafales=64.8), h("2026-10-24T22:00:00+00:00", 12.7, 0.5, rafales=64.8),
    h("2026-10-24T23:00:00+00:00", 12.9, 0.1, rafales=64.8), h("2026-10-25T00:00:00+00:00", 13.5, 0.4, rafales=64.8),
    h("2026-10-25T01:00:00+00:00", 13.6, 0.6, rafales=64.8), h("2026-10-25T02:00:00+00:00", 15, 1.3, rafales=64.8),
    h("2026-10-25T03:00:00+00:00", 15.1, 1.9, rafales=64.8), h("2026-10-25T04:00:00+00:00", 15.6, 1.7, rafales=64.8),
    h("2026-10-25T05:00:00+00:00", 16.1, 2.5, rafales=64.8), h("2026-10-25T06:00:00+00:00", 13.6, 3.1, rafales=57.6),
    h("2026-10-25T07:00:00+00:00", 12.7, 1.3, rafales=54), h("2026-10-25T08:00:00+00:00", 13, 0.2, rafales=50.4),
    h("2026-10-25T09:00:00+00:00", 13.4, 0.1, rafales=50.4),
] + [h(f"2026-10-25T{x:02d}:00:00+00:00", 14.5, 0, "partlycloudy") for x in range(10, 16)] + [
    {"datetime": "2026-10-26T09:00:00+00:00", "condition": "cloudy", "temperature": 10.1},
    {"datetime": "2026-10-26T12:00:00+00:00", "condition": "rainy", "temperature": 12.2},
    {"datetime": "2026-10-26T15:00:00+00:00", "condition": "rainy", "temperature": 13.5},
    {"datetime": "2026-10-26T18:00:00+00:00", "condition": "cloudy", "temperature": 14.1},
    {"datetime": "2026-10-27T09:00:00+00:00", "condition": "partlycloudy", "temperature": 15.1},
    {"datetime": "2026-10-27T12:00:00+00:00", "condition": "partlycloudy", "temperature": 17.7},
]
QUOTIDIENNES = [
    {"datetime": "2026-10-24T00:00:00+00:00", "condition": "rainy", "temperature": 16.7, "templow": 8.2, "precipitation": 17.2},
    {"datetime": "2026-10-25T00:00:00+00:00", "condition": "rainy", "temperature": 15.9, "templow": 11.4, "precipitation": 12.7},
    {"datetime": "2026-10-26T00:00:00+00:00", "condition": "rainy", "temperature": 15.6, "templow": 7.4, "precipitation": 1.6},
    {"datetime": "2026-10-27T00:00:00+00:00", "condition": "partlycloudy", "temperature": 19.1, "templow": 13.1, "precipitation": 0},
]


# MARK: - Mesure

def test_terrasse_par_defaut():
    # Ce matin : terrasse 8,4, jardin 10,07, quartier 9,6 → la terrasse (plus froide, pas au soleil).
    assert m.choisir_mesure(mesures(capteur(8.4, 90), capteur(10.07), capteur(9.6)), MAINTENANT) == (8.4, "terrasse")


def test_terrasse_au_soleil_prend_le_plus_bas():
    # 14 h 30, terrasse au soleil à 21,5, quartier 15, jardin 15,8 → le quartier.
    assert m.choisir_mesure(mesures(capteur(21.5), capteur(15.8), capteur(15)), MAINTENANT) == (15.0, "quartier")
    # Le jardin à l'ombre et plus frais que le quartier → le jardin.
    assert m.choisir_mesure(mesures(capteur(21.5), capteur(14.6), capteur(15)), MAINTENANT) == (14.6, "jardin")
    # Un seul des deux autres dépassé suffit.
    assert m.choisir_mesure(mesures(capteur(17.6), capteur(15), capteur(17)), MAINTENANT) == (15.0, "jardin")


def test_seuil_soleil():
    # 2,5 °C pile : pas encore le soleil.
    assert m.choisir_mesure(mesures(capteur(17.5), capteur(15), capteur(16)), MAINTENANT) == (17.5, "terrasse")


def test_nuit_terrasse_plus_froide():
    assert m.choisir_mesure(mesures(capteur(7.2), capteur(8), capteur(8.6)), MAINTENANT) == (7.2, "terrasse")


def test_capteurs_indisponibles_ou_figes():
    assert m.choisir_mesure(mesures(capteur("unavailable"), capteur(10.1), capteur(9.6)), MAINTENANT) == (10.1, "jardin")
    # Le Sonoff n'envoie rien tant que la valeur ne change pas : 3 h sans message, ce n'est pas une panne.
    assert m.choisir_mesure(mesures(capteur(8.4, 180), capteur(10.1), capteur(9.6)), MAINTENANT) == (8.4, "terrasse")
    assert m.choisir_mesure(mesures(capteur(8.4, 600), capteur(10.1), capteur(9.6)), MAINTENANT) == (8.4, "terrasse")
    # Jardin au soleil le matin, terrasse absente → quartier.
    assert m.choisir_mesure(mesures(None, capteur(13.5), capteur(10)), MAINTENANT) == (10.0, "quartier")
    assert m.choisir_mesure(mesures(capteur("unknown"), capteur("unavailable"), capteur(9.6)), MAINTENANT) == (9.6, "quartier")
    # Soleil mais les autres indisponibles : la terrasse reste la seule mesure.
    assert m.choisir_mesure(mesures(capteur(21), capteur("unavailable"), None), MAINTENANT) == (21.0, "terrasse")
    assert m.choisir_mesure({}, MAINTENANT) == (None, None)


# MARK: - Recalage

def test_interpolation():
    points = m.points_mf(HORAIRES)
    assert m.prevision_a(points, datetime(2026, 10, 24, 9, 30, tzinfo=PARIS)) == 9.65
    assert m.prevision_a(points, datetime(2026, 10, 24, 9, 0, tzinfo=PARIS)) == 9.4
    assert m.prevision_a(points, datetime(2026, 10, 24, 8, 0, tzinfo=PARIS)) is None


def test_mf_maintenant_avant_le_premier_point():
    # Entre 9 (weather.alfortville, 8 h 12 min 46 s) et 9,4 (9 h) : à 8 h 47, 9 + 0,4 × 2054 s / 2834 s.
    mf = m.mf_maintenant(m.points_mf(HORAIRES), METEO, MAINTENANT)
    assert abs(mf - (9 + 0.4 * 2054 / 2834)) < 1e-9


def test_poids_recalage():
    assert m.poids_recalage(0) == 1
    assert m.poids_recalage(8) == 0 and m.poids_recalage(12) == 0
    assert 0.6 < m.poids_recalage(1) < 0.8
    assert 0.25 < m.poids_recalage(4) < 0.3
    assert m.poids_recalage(7.99) < 0.01
    assert all(m.poids_recalage(x / 10) > m.poids_recalage(x / 10 + 0.1) for x in range(79))


def test_heures_recalees():
    liste = m.heures(HORAIRES, MAINTENANT, -1.0)
    assert len(liste) == 24
    premiere = liste[0]
    assert premiere["heure"] == "2026-10-24T09:00:00+02:00"
    assert premiere["temperature_mf"] == 9.4
    assert premiere["temperature"] == m.un_dec(9.4 - m.poids_recalage(13 / 60))
    assert premiere["pluie_mm"] == 1.1 and premiere["vent_kmh"] == 14 and premiere["rafales_kmh"] == 0
    # Au-delà de 8 h : brute.
    loin = [x for x in liste if x["heure"] >= "2026-10-24T17:00"]
    assert all(x["temperature"] == x["temperature_mf"] for x in loin)
    # Passage à l'heure d'hiver la nuit du 25/10 : 2 h CEST puis 2 h CET.
    heures_iso = [x["heure"] for x in liste]
    assert "2026-10-25T02:00:00+02:00" in heures_iso and "2026-10-25T02:00:00+01:00" in heures_iso
    assert m.heures(HORAIRES, MAINTENANT, None)[0]["temperature"] == 9.4


# MARK: - Dans l'heure

def test_douze_cases():
    d = m.dans_l_heure(PLUIE["attributes"])
    assert d == {"debut": "2026-10-24T08:45:00+02:00", "pas_min": 5,
                 "niveaux": [1, 1, 1, 1, 0, 1, 1, 1, 1, 0, 0, 0]}


def test_douze_cases_cles_manquantes_et_niveaux():
    d = m.dans_l_heure({"forecast_time_ref": "2026-10-24T06:45:00+00:00", "1_hour_forecast": {
        "0 min": "Temps sec", "10 min": "Pluie modérée", "30 min": "Pluie forte", "50 min": "Temps sec"}})
    assert d["niveaux"] == [0, 0, 2, 2, 2, 2, 3, 3, 3, 3, 0, 0]


def test_rien_de_meteo_france():
    assert m.dans_l_heure({}) is None
    assert m.dans_l_heure({"forecast_time_ref": "2026-10-24T06:45:00+00:00", "1_hour_forecast": {}}) is None
    assert m.dans_l_heure({"1_hour_forecast": {"0 min": "Temps sec"}}) is None
    assert m.dans_l_heure({"forecast_time_ref": "x", "1_hour_forecast": {"0 min": "Données indisponibles"}}) is None


def fenetre(niveaux, debut="2026-10-24T08:45:00+02:00"):
    return {"debut": debut, "pas_min": 5, "niveaux": niveaux}


# MARK: - Pastille

def test_pastille():
    t = MAINTENANT
    # Une case sèche isolée (9 h 05) ne coupe pas la pluie ; elle s'arrête à 9 h 30.
    assert m.pastille(fenetre([1, 1, 1, 1, 0, 1, 1, 1, 1, 0, 0, 0]), t) == "Pluie jusqu'à 9 h 30"
    assert m.pastille(fenetre([1, 1, 2, 2, 0, 1, 1, 1, 1, 0, 0, 0], "2026-10-24T08:40:00+02:00"),
                      datetime(2026, 10, 24, 8, 40, tzinfo=PARIS)) == "Pluie jusqu'à 9 h 25"
    assert m.pastille(fenetre([0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0]), t) == "Pluie dans 10 min"
    assert m.pastille(fenetre([0, 3, 3, 1, 0, 0, 0, 0, 0, 0, 0, 0]), datetime(2026, 10, 24, 8, 45, tzinfo=PARIS)) \
        == "Pluie forte dans 5 min"
    assert m.pastille(fenetre([2] * 12), t) == "Pluie toute l'heure"
    assert m.pastille(fenetre([1, 3, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0]), t) == "Pluie forte jusqu'à 9 h 05"
    # Dernière case sèche : la pluie s'arrête à la fin de l'heure.
    assert m.pastille(fenetre([1] * 11 + [0]), t) == "Pluie jusqu'à 9 h 40"
    assert m.pastille(fenetre([0] * 12), t) is None
    assert m.pastille(None, t) is None
    # Fenêtre passée depuis plus d'une heure : rien.
    assert m.pastille(fenetre([1] * 12), t + timedelta(hours=2)) is None


def test_pastille_cases_deja_passees():
    # À 9 h 02 la case de 8 h 45 est passée : on lit à partir de la case de 9 h.
    assert m.pastille(fenetre([1, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0]), datetime(2026, 10, 24, 9, 2, tzinfo=PARIS)) \
        == "Pluie dans 15 min"


# MARK: - Phrase

def textes(segments):
    return "".join(s["texte"] for s in segments)


def test_phrase_de_ce_matin():
    liste = m.heures(HORAIRES, MAINTENANT, -0.9)
    segments = m.phrase(m.dans_l_heure(PLUIE["attributes"]), liste, MAINTENANT)
    assert segments == [
        {"texte": "Pluie jusqu'à 9 h 30", "ton": "pluie"},
        # 0,1 mm à 15 h et 16 h : des traces (< 0,2 mm/h), la pluie revient vraiment à 17 h (0,3 mm).
        {"texte": ", puis sec. La pluie revient vers 17 h, ", "ton": "normal"},
        {"texte": "forte en soirée", "ton": "pluie"},
        {"texte": " ; ", "ton": "normal"},
        {"texte": "rafales à 65 km/h vers 22 h", "ton": "alerte"},
        {"texte": ".", "ton": "normal"},
    ]


def heures_simples(pluies, rafales=None, debut=datetime(2026, 10, 24, 9, 0, tzinfo=PARIS)):
    rafales = rafales or [0] * len(pluies)
    return [{"heure": m.iso(debut + timedelta(hours=i)), "condition": "rainy" if p else "cloudy", "temperature": 10,
             "temperature_mf": 10, "pluie_mm": p, "vent_kmh": 10, "rafales_kmh": r}
            for i, (p, r) in enumerate(zip(pluies, rafales))]


def test_phrase_sec_partout():
    segments = m.phrase(fenetre([0] * 12), heures_simples([0] * 24), MAINTENANT)
    assert textes(segments) == "Pas de pluie prévue dans les 24 h."
    assert all(s["ton"] == "normal" for s in segments)
    assert textes(m.phrase(None, heures_simples([0] * 24), MAINTENANT)) == "Pas de pluie prévue dans les 24 h."


def test_phrase_pluie_qui_arrive_plus_tard():
    pluies = [0] * 11 + [0.4, 1, 2.4] + [0] * 10   # 20 h, 21 h, 22 h (forte)
    assert textes(m.phrase(fenetre([0] * 12), heures_simples(pluies), MAINTENANT)) \
        == "Sec pour l'instant. La pluie arrive vers 20 h, forte vers 22 h."
    # Une trace (0,1 mm) ne compte pas.
    pluies = [0] * 5 + [0.1] + [0] * 5 + [0.4] + [0] * 12
    assert textes(m.phrase(fenetre([0] * 12), heures_simples(pluies), MAINTENANT)) \
        == "Sec pour l'instant. La pluie arrive vers 20 h."
    # Le lendemain matin.
    pluies = [0] * 22 + [0.3, 0.3]                  # 7 h et 8 h le 25
    assert textes(m.phrase(fenetre([0] * 12), heures_simples(pluies), MAINTENANT)) \
        == "Sec pour l'instant. La pluie arrive demain matin."


def test_phrase_pluie_dans_l_heure_puis_sec():
    segments = m.phrase(fenetre([0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]), heures_simples([1, 0.5, 0, 0] + [0] * 20),
                        MAINTENANT)
    assert segments[0] == {"texte": "Pluie dans 10 min", "ton": "pluie"}
    assert textes(segments) == "Pluie dans 10 min, jusqu'à 11 h."


def test_phrase_pluie_toute_l_heure_forte_ensuite():
    segments = m.phrase(fenetre([1] * 12), heures_simples([1, 2.5, 0.5] + [0] * 21), MAINTENANT)
    assert textes(segments) == "Pluie toute l'heure, jusqu'à 12 h, forte le matin."
    assert segments[-2] == {"texte": "forte le matin", "ton": "pluie"}


def test_phrase_rafales():
    rafales = [0] * 12 + [49] + [0] * 11
    assert "rafales" not in textes(m.phrase(fenetre([0] * 12), heures_simples([0] * 24, rafales), MAINTENANT))
    rafales[12] = 50
    segments = m.phrase(fenetre([0] * 12), heures_simples([0] * 24, rafales), MAINTENANT)
    assert segments[-2] == {"texte": "rafales à 50 km/h vers 21 h", "ton": "alerte"}


def test_mots():
    tout = textes(m.phrase(m.dans_l_heure(PLUIE["attributes"]), m.heures(HORAIRES, MAINTENANT, 0), MAINTENANT))
    assert "au salon" not in tout
    assert m.heure_fr(datetime(2026, 10, 24, 9, 5, tzinfo=PARIS)) == "9 h 05"
    assert m.heure_fr(datetime(2026, 10, 24, 15, 0, tzinfo=PARIS)) == "15 h"
    assert m.heure_fr(datetime(2026, 10, 25, 0, 10, tzinfo=PARIS), MAINTENANT) == "demain 0 h 10"


# MARK: - Jours

def test_jours():
    j = m.jours(HORAIRES, QUOTIDIENNES, MAINTENANT)
    assert [x["date"] for x in j] == ["2026-10-25", "2026-10-26", "2026-10-27"]
    assert [x["nom"] for x in j] == ["Dimanche", "Lundi", "Mardi"]
    assert j[0] == {"date": "2026-10-25", "nom": "Dimanche", "condition": "rainy", "min": 11, "max": 16,
                    "resume": "pluie le matin"}
    # Lundi : pas de 3 h sans précipitation, « rainy » à 13 h et 16 h (UTC 12 et 15, heure d'hiver) : 13-15 h et 16-18 h.
    # Trois périodes mais 1,6 mm sur la journée : « averses ».
    assert j[1]["resume"] == "averses"
    assert j[1]["min"] == 7 and j[1]["max"] == 16
    assert j[2]["resume"] == "sec" and j[2]["condition"] == "partlycloudy"


def test_jours_repli_sur_les_heures():
    j = m.jours(HORAIRES, [], MAINTENANT, nb=1)
    assert j[0]["min"] == 13 and j[0]["max"] == 16   # 12,7 → 13 ; 16,1 → 16
    assert j[0]["condition"] == "partlycloudy"       # le plus fréquent de 6 h à 21 h


def test_resume_jour():
    assert m.resume_jour(set()) == "sec"
    assert m.resume_jour({8, 9}) == "pluie le matin"
    assert m.resume_jour({12}) == "pluie à midi"
    assert m.resume_jour({15}) == "pluie l'après-midi"
    assert m.resume_jour({20}) == "pluie le soir"
    assert m.resume_jour({2, 3}) == "pluie la nuit"
    assert m.resume_jour({2, 8, 13, 15, 19}) == "pluie toute la journée"
    assert m.resume_jour({8, 19}) == "pluie toute la journée"
    assert m.resume_jour({8, 19}, 5.0) == "pluie toute la journée"
    assert m.resume_jour({8, 12, 15}, 1.6) == "averses"
    assert m.resume_jour({8}, 0.4) == "pluie le matin"
    assert m.resume_jour({3, 8}) == "pluie le matin"
    # Court pour la TV : 22 caractères au plus (« pluie toute la journée »).
    for heures_pluie in ({8}, {12}, {15}, {20}, {2}, {8, 20}):
        assert len(m.resume_jour(heures_pluie)) <= 22


# MARK: - Vigilance, maintenant, calcul complet

def test_vigilance():
    assert m.vigilance(ALERTE) == {"couleur": "Vert", "risques": []}
    jaune = {"state": "Jaune", "attributes": {**ALERTE["attributes"], "Vent violent": "Jaune", "Orages": "Orange"}}
    assert m.vigilance(jaune) == {"couleur": "Jaune", "risques": ["Vent violent", "Orages"]}
    assert m.vigilance({"state": "unavailable"}) == {"couleur": "Vert", "risques": []}


def test_maintenant():
    b = m.bloc_maintenant(METEO, 8.4, "terrasse", -0.9, m.dans_l_heure(PLUIE["attributes"]), MAINTENANT)
    assert b == {"temperature": 8.4, "source": "terrasse", "ressenti": 6, "condition": "rainy",
                 "libelle": "Pluie faible", "vent_kmh": 14, "vent_dir": "sud-ouest", "rafales_kmh": None,
                 "humidite": 90}
    sec = m.bloc_maintenant({**METEO, "state": "cloudy"}, 8.4, "terrasse", 0, fenetre([0] * 12), MAINTENANT)
    assert sec["condition"] == "cloudy" and sec["libelle"] == "Nuageux"
    forte = m.bloc_maintenant({**METEO, "state": "cloudy"}, 8.4, "terrasse", 0, fenetre([3] * 12), MAINTENANT)
    assert forte["condition"] == "pouring" and forte["libelle"] == "Pluie forte"
    assert m.direction(0) == "nord" and m.direction(350) == "nord" and m.direction(90) == "est"


def test_calcul_complet_de_ce_matin():
    etats = {**mesures(capteur(8.4, 94), capteur(10.07), capteur(9.6)),
             m.METEO: METEO, m.PLUIE_HEURE: PLUIE, m.VIGILANCE: ALERTE}
    etat, a = m.calculer(etats, HORAIRES, QUOTIDIENNES, MAINTENANT)
    assert etat == "8.4"
    assert set(a) == {"maj", "maintenant", "dans_l_heure", "pastille", "phrase", "heures", "jours", "vigilance",
                      "apprentissage"}
    assert a["apprentissage"] == {"jours_de_donnees": 0, "actif": False, "ecarts": [None] * 24,
                                  "maj": "2026-10-24T08:47:00+02:00"}
    assert a["maj"] == "2026-10-24T08:47:00+02:00"
    assert a["pastille"] == "Pluie jusqu'à 9 h 30"
    assert a["maintenant"]["source"] == "terrasse" and a["maintenant"]["ressenti"] == 6
    assert len(a["heures"]) == 24 and len(a["jours"]) == 3
    # Recalage : la terrasse est ~0,9 °C sous MF ; à 9 h, 9,4 − 0,9 × 0,95.
    assert a["heures"][0]["temperature"] == 8.6
    # Mêmes clés que l'exemple du contrat.
    exemple = json.loads((Path(__file__).resolve().parents[2] / "HUB-METEO-exemple.json").read_text())
    ex = exemple["attributes"]
    assert set(a["maintenant"]) == set(ex["maintenant"])
    assert set(a["dans_l_heure"]) == set(ex["dans_l_heure"])
    assert set(a["heures"][0]) == set(ex["heures"][0])
    assert set(a["jours"][0]) == set(ex["jours"][0])
    assert set(a["vigilance"]) == set(ex["vigilance"])
    assert set(a["apprentissage"]) == set(ex["apprentissage"])
    # Taille raisonnable pour l'enregistreur de HA (limite 16 Ko).
    assert len(json.dumps(a, ensure_ascii=False).encode()) < 8000


def test_sans_mesure():
    etat, a = m.calculer({m.METEO: METEO}, [], [], MAINTENANT)
    assert etat == "unavailable"
    assert a["maintenant"]["temperature"] is None and a["maintenant"]["source"] is None
    assert a["dans_l_heure"] is None and a["pastille"] is None and a["heures"] == [] and a["phrase"] == []
    # Sans prévisions horaires, la phrase ne parle que de l'heure à venir.
    assert m.phrase(fenetre([0] * 12), [], MAINTENANT) == [{"texte": "Pas de pluie dans l'heure.", "ton": "normal"}]
    assert textes(m.phrase(fenetre([1] * 12), [], MAINTENANT)) == "Pluie toute l'heure."


# MARK: - Apprentissage

def test_releve_et_elagage():
    points = m.points_mf(HORAIRES)
    r = m.releve(points, 8.4, "terrasse", 9.3, datetime(2026, 10, 24, 9, 2, tzinfo=PARIS))
    assert r["t"] == "2026-10-24T09:00:00+02:00"
    assert r["prev"]["1"] == 9.9 and r["prev"]["3"] == 11.2 and r["prev"]["12"] == 11.6
    assert set(r["prev"]) == {"1", "3", "6", "12", "24"}
    vieux = {**r, "t": "2026-08-20T09:00:00+02:00"}
    gardees = m.elaguer([json.dumps(vieux), json.dumps(r), "illisible"], MAINTENANT)
    assert gardees == [r]


def test_ecart_moyen_par_heure():
    releves = [
        {"t": "2026-10-24T08:00:00+02:00", "mesure": 8.0, "prev": {"1": 10.0}},
        {"t": "2026-10-24T09:00:00+02:00", "mesure": 9.0, "prev": {"1": 11.0}},
        {"t": "2026-10-25T08:00:00+01:00", "mesure": 8.5, "prev": {"1": 9.0}},
        {"t": "2026-10-25T09:00:00+01:00", "mesure": 8.0, "prev": {"1": 9.0}},
    ]
    assert m.ecart_moyen_par_heure(releves, 1) == {9: (-1.0, 2)}


def test_phrase_heure_mf_couverte_par_la_fenetre():
    # 24/10, 8 h 55 (vu en vrai au déploiement) : MF annonce 1,1 mm de 9 h à 10 h, mais les cases disent qu'il ne
    # tombe qu'une averse de 5 min à 9 h 15. L'heure de 9 h (plus qu'à moitié dans la fenêtre) ne compte pas, la
    # reprise se lit dans les cases.
    t = datetime(2026, 10, 24, 8, 56, tzinfo=PARIS)
    cases = fenetre([1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0], "2026-10-24T08:55:00+02:00")
    liste = m.heures(HORAIRES, t, -1.0)
    assert m.pastille(cases, t) == "Pluie jusqu'à 9 h"
    assert textes(m.phrase(cases, liste, t)).startswith("Pluie jusqu'à 9 h, puis sec. La pluie revient vers 9 h 15 ;")
    # Sans reprise dans l'heure : la prochaine heure MF pluvieuse après la fenêtre (15 h).
    cases = fenetre([1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "2026-10-24T08:55:00+02:00")
    assert textes(m.phrase(cases, liste, t)).startswith("Pluie jusqu'à 9 h, puis sec. La pluie revient vers 17 h, forte en soirée")


def test_phrase_averse_qui_arrive_et_s_arrete_dans_l_heure():
    # 24/10, 8 h 58 (vu en vrai) : une averse de 5 min à 9 h 15, puis MF annonce 0,1 mm (une trace) de 10 h à 11 h
    # et 0,5 mm à 15 h.
    t = datetime(2026, 10, 24, 8, 58, tzinfo=PARIS)
    cases = fenetre([0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0], "2026-10-24T09:00:00+02:00")
    liste = heures_simples([1.1, 0.1, 0, 0, 0, 0, 0.5] + [0] * 17)
    assert m.pastille(cases, t) == "Pluie dans 20 min"
    assert textes(m.phrase(cases, liste, t)) \
        == "Pluie dans 20 min, jusqu'à 9 h 20, puis sec. La pluie revient vers 15 h."
    assert textes(m.phrase(cases, heures_simples([1.1, 0.1] + [0] * 22), t)) \
        == "Pluie dans 20 min, jusqu'à 9 h 20, puis sec pour les prochaines 24 h."



# MARK: - Apprentissage automatique (24/10)

def releves_fictifs(nb_jours, heure, ecarts, fin=datetime(2026, 11, 20, 3, 30, tzinfo=PARIS)):
    """Un relevé par jour à `heure`, mesure − mf = ecarts[i % len(ecarts)]."""
    r = []
    for i in range(nb_jours):
        t = (fin - timedelta(days=i + 1)).replace(hour=heure, minute=0)
        r.append({"t": m.iso(t), "mesure": 10 + ecarts[i % len(ecarts)], "mf": 10.0, "source": "terrasse"})
    return r


FIN = datetime(2026, 11, 20, 3, 30, tzinfo=PARIS)


def test_apprentissage_pas_assez_de_donnees():
    assert m.apprendre([], FIN)["actif"] is False
    a = m.apprendre(releves_fictifs(13, 14, [2.0, 2.2]), FIN)
    assert a["jours_de_donnees"] == 13 and a["actif"] is False and a["ecarts"] == [None] * 24
    # Aujourd'hui : un seul relevé.
    a = m.apprendre([{"t": "2026-10-24T09:00:00+02:00", "mesure": 8.4, "mf": 9.3}], MAINTENANT + timedelta(hours=1))
    assert a["jours_de_donnees"] == 1 and a["actif"] is False


def test_apprentissage_stable():
    a = m.apprendre(releves_fictifs(20, 14, [1.8, 2.2]), FIN)
    assert a["actif"] is True and a["jours_de_donnees"] == 20
    assert a["ecarts"][14] == 2.0 and a["ecarts"][13] is None and a["ecarts"][15] is None
    assert m.correction_apprise(a, datetime(2026, 11, 20, 14, 30, tzinfo=PARIS)) == 2.0
    assert m.correction_apprise(a, datetime(2026, 11, 20, 9, 0, tzinfo=PARIS)) == 0.0
    # Relevés de plus de 30 jours : ignorés.
    vieux = releves_fictifs(20, 14, [2.0], fin=FIN - timedelta(days=31))
    assert m.apprendre(vieux, FIN)["actif"] is False


def test_apprentissage_instable():
    a = m.apprendre(releves_fictifs(20, 14, [-1.0, 3.0]), FIN)  # écart-type 2
    assert a["actif"] is False and a["ecarts"][14] is None
    assert a["detail"][14]["ecart_type"] == 2.0


def test_apprentissage_plafond_et_lissage():
    assert m.apprendre(releves_fictifs(20, 14, [5.0]), FIN)["ecarts"][14] == 3.0
    r = releves_fictifs(20, 13, [1.0]) + releves_fictifs(20, 14, [2.0]) + releves_fictifs(20, 15, [3.0])
    a = m.apprendre(r, FIN)
    assert a["ecarts"][14] == 2.0                    # (1 + 2×2 + 3) / 4
    assert a["ecarts"][13] == 1.3                    # (2×1 + 2) / 3, l'heure de 12 h n'est pas corrigée
    assert a["ecarts"][15] == 2.7                    # (2 + 2×3) / 3
    assert a["ecarts"][12] is None


def test_correction_inactive():
    a = {"actif": False, "ecarts": [2.0] * 24}
    assert m.correction_apprise(a, MAINTENANT) == 0.0
    assert m.correction_apprise(None, MAINTENANT) == 0.0


def test_pas_de_double_comptage():
    appris = {"jours_de_donnees": 20, "actif": True, "ecarts": [2.0] * 24, "maj": "x"}
    mf = m.mf_maintenant(m.points_mf(HORAIRES), METEO, MAINTENANT)
    # La mesure vaut exactement la prévision corrigée (+2) : rien à recaler, les heures = MF + 2, pas + 4.
    etats = {**mesures(capteur(round(mf + 2, 6)), capteur(20), capteur(20)), m.METEO: METEO,
             m.PLUIE_HEURE: PLUIE, m.VIGILANCE: ALERTE}
    _, a = m.calculer(etats, HORAIRES, QUOTIDIENNES, MAINTENANT, appris=appris)
    for x in a["heures"]:
        assert x["temperature"] == m.un_dec(x["temperature_mf"] + 2)
    assert a["apprentissage"] == appris
    # Mesure 1 °C sous la prévision corrigée : le recalage ne porte que sur ce −1.
    etats[m.TERRASSE] = capteur(round(mf + 1, 6))
    _, a = m.calculer(etats, HORAIRES, QUOTIDIENNES, MAINTENANT, appris=appris)
    premiere = a["heures"][0]
    assert premiere["temperature"] == m.un_dec(premiere["temperature_mf"] + 2 - m.poids_recalage(13 / 60))
    # Le ressenti suit la mesure (écart total + 1 avec MF), pas la correction en plus.
    assert a["maintenant"]["ressenti"] == m.entier(6.6 + 1)


def test_jours_avec_correction():
    appris = {"actif": True, "ecarts": [1.0] * 12 + [3.0] * 12}
    j = m.jours(HORAIRES, QUOTIDIENNES, MAINTENANT, nb=1, correction=lambda t: m.correction_apprise(appris, t))
    # Dimanche : heures de MF entre 12,7 et 16,1 (16,1 à 6 h, 14,5 l'après-midi). Corrigées : min +1, max 17,5
    # (14,5 + 3) au lieu de 16,1, soit +1,4. Min de MF 11,4 + 1 → 12 ; max 15,9 + 1,4 → 17.
    assert j[0]["min"] == 12 and j[0]["max"] == 17
