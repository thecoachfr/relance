"""Tests hors Home Assistant de `aiguillage_lieu_travail` (`sensor.aiguillage_lieu_travail`) :
uv run --with pytest python -m pytest -q homeassistant/appdaemon/tests"""

from datetime import date, datetime
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import aiguillage_lieu_travail as m  # noqa: E402

CONF = m.config_valide(m.CONFIG_DEFAUT)
SAMEDI = date(2026, 10, 24)
# Mes lieux réel du 22/10 (extrait).
LIEUX = {"groupes": [
    {"id": "supermarches", "nom": "Supermarchés", "lieux": [{"nom": "Monoprix", "lat": 48.8068, "lon": 2.4186}]},
    {"id": "x", "nom": "Travail", "lieux": [{"nom": "33 Rue d'Artois, 75008 Paris", "lat": 48.8738262, "lon": 2.3059674},
                                     {"nom": "Le Lab", "lat": 48.9120, "lon": 2.3340}]},
]}


def lieu(jour, conf=CONF, constats=None):
    info = m.jour_info(jour, conf, constats or {})
    return info["lieu"], info["certitude"], info["source"]


# MARK: - Calendrier

def test_paques_et_feries():
    assert m.paques(2026) == date(2026, 4, 5)
    assert m.paques(2027) == date(2027, 3, 28)
    f = m.feries(2026)
    assert date(2026, 11, 11) in f and date(2026, 5, 14) in f  # Armistice, Ascension
    assert date(2026, 5, 25) in f  # Lundi de Pentecôte


def test_semaine_type():
    assert lieu(date(2026, 10, 26)) == ("bureau", "sur", "semaine")          # lundi
    assert lieu(date(2026, 10, 27)) == ("teletravail", "sur", "semaine")     # mardi
    assert lieu(date(2026, 10, 28)) == ("bureau", "probable", "semaine")     # mercredi
    assert lieu(date(2026, 10, 30)) == ("off", "sur", "semaine")             # vendredi ordinaire
    assert lieu(date(2026, 11, 6)) == ("bureau", "sur", "premier_vendredi")
    assert lieu(SAMEDI) == ("off", "sur", "semaine")
    assert lieu(date(2026, 11, 11)) == ("ferie", "sur", "ferie")             # mercredi férié


def test_libelles_et_phrase():
    infos = m.jours(date(2026, 10, 26), CONF, {})
    assert infos[0]["libelle"] == "🏢 Bureau" and infos[2]["libelle"] == "🏢 Bureau ?"
    assert m.phrase(infos) == "🏢 Bureau aujourd'hui · demain 🏠 Télétravail"
    assert m.phrase(m.jours(SAMEDI, CONF, {})) == "Pas de Barrière aujourd'hui · lundi 🏢 Bureau"
    assert m.phrase(m.jours(date(2026, 10, 29), CONF, {})) == "🏠 Télétravail aujourd'hui · lundi 🏢 Bureau"


def test_config_abimee_et_premier_vendredi_desactive():
    conf = m.config_valide({"semaine": {"mardi": {"lieu": "bureau"}, "jeudi": {"lieu": "plage"}},
                            "exceptions": {"pas une date": "bureau", "2026-10-27": "teletravail", "2026-10-28": "x"},
                            "premier_vendredi": None})
    assert conf["semaine"]["mardi"] == {"lieu": "bureau", "certitude": "sur"}
    assert conf["semaine"]["jeudi"]["lieu"] == "teletravail"
    assert conf["exceptions"] == {"2026-10-27": "teletravail"}
    assert lieu(date(2026, 11, 6), conf)[0] == "off"
    assert m.config_valide("n'importe quoi")["semaine"]["lundi"]["lieu"] == "bureau"


# MARK: - Position

def test_lieux_travail_et_au_bureau():
    points = m.lieux_travail(LIEUX)
    assert [p[3] for p in points] == ["bureau", "lab"]
    assert m.au_travail({"latitude": 48.8740, "longitude": 2.3062, "gps_accuracy": 20}, points) == "bureau"
    assert m.au_travail({"latitude": 48.9121, "longitude": 2.3341, "gps_accuracy": 15}, points) == "lab"
    assert m.au_travail({"latitude": 48.8086, "longitude": 2.4177, "gps_accuracy": 10}, points) is None  # maison
    assert m.au_travail({"latitude": 48.8738}, points) is None
    assert m.lieux_travail(None) == []


def test_constat_l_emporte():
    mardi = date(2026, 10, 27)
    info = m.jour_info(mardi, CONF, {"2026-10-27": "bureau"})
    assert (info["lieu"], info["certitude"], info["source"], info["prevu"]) == ("bureau", "constate", "position", "teletravail")


def test_constat_du_soir():
    lundi, vendredi = date(2026, 10, 26), date(2026, 10, 30)
    assert m.constat_du_soir(lundi, CONF, "bureau", False, False) == "bureau"
    assert m.constat_du_soir(lundi, CONF, "lab", False, False) == "lab"
    assert m.constat_du_soir(lundi, CONF, None, True, True) == "teletravail"
    assert m.constat_du_soir(lundi, CONF, None, True, False) is None       # parti l'après-midi : on ne sait pas
    assert m.constat_du_soir(vendredi, CONF, None, True, True) is None     # pas travaillé
    assert m.constat_du_soir(vendredi, CONF, "bureau", False, False) == "bureau"


def test_stats_et_suggestion():
    constats = {"2026-09-30": "teletravail", "2026-10-07": "teletravail", "2026-10-14": "teletravail",
                "2026-10-21": "teletravail", "2026-10-20": "bureau", "2026-08-25": "bureau"}
    st = m.stats(constats, SAMEDI)
    assert st["mercredi"] == {"bureau": 0, "teletravail": 4}
    assert st["mardi"] == {"bureau": 1, "teletravail": 0}   # le 25/08 est hors des 8 semaines
    assert m.suggestion(CONF, st) == "Le mercredi, tu étais en télétravail 4 fois sur 4 : passer le mercredi en Télétravail ?"
    assert m.suggestion(CONF, m.stats({}, SAMEDI)) is None


# MARK: - Consignes Signal

def test_lire_exception():
    lire = lambda t: m.lire_exception(t, SAMEDI)  # noqa: E731
    assert lire("demain télétravail") == [(date(2026, 10, 25), "teletravail")]  # samedi → dimanche
    assert lire("Lundi télétravail") == [(date(2026, 10, 26), "teletravail")]
    assert lire("mercredi je suis au bureau") == [(date(2026, 10, 28), "bureau")]
    assert lire("je serai en télétravail mercredi") == [(date(2026, 10, 28), "teletravail")]
    assert lire("le 6/11 congé") == [(date(2026, 11, 6), "off")]
    assert lire("vendredi 6 bureau") == [(date(2026, 11, 6), "bureau")]  # le 6/10 est passé : novembre
    assert lire("lundi normal") == [(date(2026, 10, 26), "normal")]
    assert lire("lundi TT") == [(date(2026, 10, 26), "teletravail")]
    assert lire("jeudi au Lab") == [(date(2026, 10, 29), "lab")]
    assert lire("le 5/11 à Saint-Ouen") == [(date(2026, 11, 5), "lab")]
    assert len(lire("congé du 2/11 au 6/11")) == 5
    assert lire("demain on va au resto au bureau de tabac") is None
    assert lire("bureau") is None
    assert lire("acheter du pain demain") is None
    assert lire("le 1/10 bureau") == [(date(2027, 10, 1), "bureau")]  # date passée de plus d'une semaine : l'an prochain


def test_lire_exception_demain():
    lundi = date(2026, 10, 26)
    assert m.lire_exception("demain télétravail", lundi) == [(date(2026, 10, 27), "teletravail")]
    assert m.lire_exception("Demain bureau !", lundi) == [(date(2026, 10, 27), "bureau")]
    assert m.lire_exception("aujourd'hui télétravail", lundi) == [(lundi, "teletravail")]
    assert m.lire_exception("après-demain bureau", lundi) == [(date(2026, 10, 28), "bureau")]


def test_appliquer_et_reponse():
    mardi, mercredi = date(2026, 10, 27), date(2026, 10, 28)
    apres = m.appliquer(CONF, [(mardi, "bureau"), (mercredi, "bureau")])
    assert apres["exceptions"] == {"2026-10-27": "bureau", "2026-10-28": "bureau"}  # mercredi devient sûr
    assert lieu(mercredi, apres) == ("bureau", "sur", "exception")
    texte = m.reponse([(mardi, "bureau")], CONF, apres)
    assert texte == "✅ Mardi 27/10 : 🏢 Bureau (au lieu de 🏠 Télétravail)"
    # Redire la semaine type ne crée rien ; « normal » annule.
    assert m.appliquer(CONF, [(date(2026, 10, 26), "bureau")])["exceptions"] == {}
    assert m.appliquer(apres, [(mardi, "normal")])["exceptions"] == {"2026-10-28": "bureau"}


def test_elaguer():
    conf = dict(CONF, exceptions={"2026-08-01": "off", "2026-10-20": "bureau"})
    assert m.elaguer_exceptions(conf, SAMEDI)["exceptions"] == {"2026-10-20": "bureau"}
    assert m.elaguer_constats({"2026-01-01": "bureau", "2026-10-01": "bureau"}, SAMEDI) == {"2026-10-01": "bureau"}


def test_calculer():
    maintenant = datetime(2026, 10, 26, 8, 0, tzinfo=m.PARIS)
    etat, attr = m.calculer(maintenant.date(), CONF, {}, maintenant)
    assert etat == "bureau"
    assert attr["demain"]["lieu"] == "teletravail" and len(attr["jours"]) == 14
    assert attr["phrase"].startswith("🏢 Bureau aujourd'hui")
    assert attr["suggestion"] is None


def test_lab():
    jeudi = date(2026, 10, 29)
    conf = m.appliquer(CONF, [(jeudi, "lab")])
    info = m.jour_info(jeudi, conf, {})
    assert (info["lieu"], info["libelle"]) == ("lab", "🧪 Le Lab")
    assert m.phrase(m.jours(date(2026, 10, 28), conf, {})).endswith("demain 🧪 Le Lab")
    assert m.reponse([(jeudi, "lab")], CONF, conf) == "✅ Jeudi 29/10 : 🧪 Le Lab (au lieu de 🏠 Télétravail)"
    assert m.jour_info(date(2026, 10, 27), CONF, {"2026-10-27": "lab"})["lieu"] == "lab"


def test_ecrit_par_aiguillage():
    """Réglages écrits par l'écran « Lieu de travail » d'Aiguillage (N2) : champs inconnus gardés, recalcul sur
    l'événement de `donnees_apps`."""
    brut = {"v": 1, "futur": {"x": 1},
            "semaine": dict(m.CONFIG_DEFAUT["semaine"], mardi={"lieu": "bureau", "certitude": "probable", "note": "n"}),
            "premier_vendredi": None, "exceptions": {"2026-10-29": "lab", "2026-10-30": "teletravail"}}
    conf = m.config_valide(brut)
    assert conf["semaine"]["mardi"] == {"lieu": "bureau", "certitude": "probable"}
    assert conf["premier_vendredi"] is None
    assert m.jour_info(date(2026, 11, 6), conf, {})["lieu"] == "off"  # premier vendredi désactivé
    assert m.jour_info(date(2026, 10, 27), conf, {})["libelle"] == "🏢 Bureau ?"
    ecrit = m.avec_inconnus(brut, m.appliquer(conf, [(date(2026, 10, 29), "normal")]))
    assert ecrit["futur"] == {"x": 1} and ecrit["exceptions"] == {"2026-10-30": "teletravail"}
    assert m.avec_inconnus(None, conf) == conf
    assert m.doit_recalculer({"espace": "aiguillage", "cle": "config:lieu_travail", "seq": 3}, "aiguillage")
    assert m.doit_recalculer({"espace": "aiguillage", "cle": "config:lieux"}, "aiguillage")
    assert not m.doit_recalculer({"espace": "aiguillage", "cle": "6f1c2a3e-1d8b-4e5f-9a7c-2b4d6e8f0a1c"}, "aiguillage")
    assert not m.doit_recalculer({"espace": "autre", "cle": "config:lieu_travail"}, "aiguillage")
    assert not m.doit_recalculer(None, "aiguillage")
