"""Tests hors Home Assistant de `hub_pour_info` (rappels « pour info » du Hub, `sensor.hub_pour_info`) :
uv run --with pytest python -m pytest -q homeassistant/appdaemon/tests"""

from datetime import date, datetime
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import hub_pour_info as p  # noqa: E402

CLE = "0b7c3a5e-1f2d-4c6b-9a8e-112233445566"
CLE2 = "1b7c3a5e-1f2d-4c6b-9a8e-112233445566"
CLE3 = "2b7c3a5e-1f2d-4c6b-9a8e-112233445566"


def d(jour, mois=10, annee=2026):
    return date(annee, mois, jour)


def regle(ligne):
    return p.repetition("Notes\n" + ligne)


# Mêmes cas que `RecurrenceTests.nextDays` (Swift) : le portage doit donner les mêmes jours.
def test_meme_suivante_que_l_app():
    fait = d(13)
    assert p.jour_suivant(regle("🔄 Tous les mois le 5"), d(5), fait) == d(5, 11)
    assert p.jour_suivant(regle("🔄 Tous les mois le dernier jour"), d(31), fait) == d(30, 11)
    lundi_jeudi = regle("🔄 Toutes les semaines : lundi, jeudi")
    assert p.jour_suivant(lundi_jeudi, d(12), d(12)) == d(15)
    assert p.jour_suivant(lundi_jeudi, d(15), d(15)) == d(19)
    assert p.jour_suivant(regle("🔄 Tous les mois le 1er lundi"), d(5), fait) == d(2, 11)
    assert p.jour_suivant(regle("🔄 Tous les ans le 15/03"), d(15, 3), fait) == d(15, 3, 2027)
    assert p.jour_suivant(regle("🔄 Tous les jours"), d(1), fait) == d(14)
    assert p.jour_suivant(regle("🔄 3 mois après avoir été faite"), d(1, 9), fait) == d(13, 1, 2027)


def test_lecture_des_regles():
    assert regle("🔄 Tous les 2 jours") == ("jour", 2)
    assert regle("🔄 Toutes les 2 semaines") == ("semaine", 2, ())
    assert regle("🔄️ Toutes les semaines : mardi, vendredi") == ("semaine", 1, (3, 6))
    assert regle("🔄 Tous les mois le dernier vendredi") == ("mois_jour_semaine", 1, -1, 6)
    assert regle("🔄 Tous les 3 mois le 15") == ("mois_jour", 3, 15)
    assert p.repetition("Rien") is None


def test_marqueur():
    assert p.est_pour_info("Clés\n📣 Pour info")
    assert p.est_pour_info("📣️ Pour info")
    assert not p.est_pour_info("Pour info")


def test_tombe_sa_date_ou_une_repetition_apres():
    lundi = regle("🔄 Toutes les semaines : lundi")
    assert p.tombe(d(19), d(19), None)
    assert not p.tombe(d(20), d(19), None)
    # Pas encore avancée par l'iPhone : le lundi suivant reste juste.
    assert p.tombe(d(26), d(12), lundi)
    assert not p.tombe(d(27), d(12), lundi)
    assert not p.tombe(d(5), d(12), lundi)


def enregistrement(cle, titre, jour, notes, **autres):
    return {"cle": cle, "valeur": {"titre": titre, "jour": jour, "notes": notes, **autres}}


def test_capteur():
    maintenant = datetime(2026, 10, 26, 7, 30, tzinfo=p.PARIS)  # lundi
    enregistrements = [
        enregistrement(CLE, "Femme de ménage", "2026-10-19", "📣 Pour info\n🔄 Toutes les semaines : lundi"),
        enregistrement(CLE2, "Poubelles", "2026-10-27", "🔄 Toutes les semaines : mardi, vendredi\n📣 Pour info"),
        enregistrement(CLE3, "Appeler le garage", "2026-10-26", "Rappel"),           # tâche ordinaire
        enregistrement(CLE3, "Ancienne", "2026-10-25", "📣 Pour info"),              # passée, sans répétition
        enregistrement(CLE3, "Faite", "2026-10-26", "📣 Pour info", fait=True),
        enregistrement("aiguillage-pieces", "Pas une tâche", "2026-10-26", "📣 Pour info"),
    ]
    etat, attributs = p.calculer(enregistrements, maintenant)
    assert etat == 1
    assert attributs["jour"] == "2026-10-26"
    assert attributs["infos"] == [{"cle": CLE, "titre": "Femme de ménage", "heure": None, "heure_texte": None}]
    assert attributs["texte"] == "Femme de ménage"
    assert attributs["a_venir"] == [
        {"cle": CLE2, "titre": "Poubelles", "jour": "2026-10-27", "heure": None, "heure_texte": None},
        {"cle": CLE, "titre": "Femme de ménage", "jour": "2026-11-02", "heure": None, "heure_texte": None}]
    assert p.texte_notification(attributs) == "Pour info : Femme de ménage"


def test_heure_affichee_et_rangee_en_premier():
    maintenant = datetime(2026, 10, 27, 7, 0, tzinfo=p.PARIS)  # mardi
    enregistrements = [
        enregistrement(CLE2, "Poubelles", "2026-10-27", "📣 Pour info"),
        enregistrement(CLE, "Sport", "2026-10-27", "🔄 Toutes les semaines : mardi, jeudi\n📣 Pour info", heure="07:30"),
        enregistrement(CLE3, "Kiné", "2026-10-27", "📣 Pour info", heure="18:00"),
    ]
    etat, attributs = p.calculer(enregistrements, maintenant)
    assert [i["titre"] for i in attributs["infos"]] == ["Sport", "Kiné", "Poubelles"]
    assert attributs["infos"][0]["heure_texte"] == "7 h 30" and attributs["infos"][1]["heure_texte"] == "18 h"
    assert attributs["texte"] == "Sport à 7 h 30 · Kiné à 18 h · Poubelles"
    assert p.texte_notification(attributs) == "Pour info : Sport à 7 h 30, Kiné à 18 h, Poubelles"
    assert attributs["a_venir"][0]["heure_texte"] == "7 h 30"  # Sport, jeudi


def test_rien_aujourd_hui():
    etat, attributs = p.calculer([], datetime(2026, 10, 26, 7, 30, tzinfo=p.PARIS))
    assert etat == 0 and attributs["infos"] == [] and attributs["texte"] is None and attributs["a_venir"] == []
    assert p.texte_notification(attributs) is None
