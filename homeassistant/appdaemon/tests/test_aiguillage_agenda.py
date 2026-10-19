"""Tests de l'agenda « Sorties » (iCalendar) : python3 tests/test_aiguillage_agenda.py"""
from datetime import datetime
import os
import sys
from zoneinfo import ZoneInfo

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "apps"))
import aiguillage_agenda as a  # noqa: E402

CLE = "e95f346a-2682-42be-8601-8908fe91e518"
NOW = datetime(2026, 10, 19, 20, 0, tzinfo=ZoneInfo("UTC"))


def rec(cle, **v):
    return {"cle": cle, "version": 1, "valeur": {"titre": "x", "fait": False, **v}}


def test_sortie_heure_lieu_description():
    r = rec(CLE, titre="Arca M à La Maroquinerie", jour="2027-03-28", heure="19:30",
            notes="Payé 24,61 € sur Shotgun ; billet dans l'app.\nhttps://shotgun.live/events/arca-m\n📍 La Maroquinerie · 23 rue Boyer\n🎟 Sortie",
            lieu={"nom": "La Maroquinerie", "adresse": "23 rue Boyer, 75020 Paris"},
            envie={"type": "sortie", "lien": "https://shotgun.live/events/arca-m"})
    t = a.ics([r], NOW)
    assert "BEGIN:VCALENDAR" in t and t.endswith("END:VCALENDAR\r\n") and "X-WR-CALNAME:Sorties" in t
    assert f"UID:{CLE}@aiguillage" in t
    # 19 h 30 à Paris (heure d'été jusqu'au 28/03 2 h : 28/03/2027 est déjà en été) = 17 h 30 UTC ; 3 h par défaut.
    assert "DTSTART:20270328T173000Z" in t and "DTEND:20270328T203000Z" in t
    assert "LOCATION:La Maroquinerie\\, 23 rue Boyer\\, 75020 Paris" in t
    desc = a.description(r["valeur"])
    assert "📍" not in desc and "🎟" not in desc and desc.count("shotgun.live") == 1 and "24,61" in desc
    assert all(len(l.encode()) <= 75 for l in t.split("\r\n"))


def test_filtres():
    autres = [
        rec("11111111-1111-4111-8111-111111111111", jour="2026-11-01", notes="👀 À voir"),          # envie non datée
        rec("22222222-2222-4222-8222-222222222222", jour="2026-11-02"),                             # tâche ordinaire
        rec("33333333-3333-4333-8333-333333333333", notes="🎟 Sortie"),                             # sortie sans date
        {"cle": "44444444-4444-4444-8444-444444444444", "supprime": True, "valeur": {"jour": "2026-11-03", "notes": "🎟 Sortie"}},
        rec("config:abonnements", jour="2026-11-04", notes="🎟 Sortie"),
        rec("55555555-5555-4555-8555-555555555555", jour="2026-11-05", notes="🎟 Sortie", fait=True),  # vue : gardée
    ]
    assert [r["cle"][:2] for r in a.sorties(autres)] == ["55"]
    t = a.ics(autres, NOW)
    assert "DTSTART;VALUE=DATE:20261105" in t and "DTEND;VALUE=DATE:20261106" in t


def test_horodatage_ignore():
    r = rec(CLE, jour="2027-01-16", heure="20:00", notes="🎟 Sortie")
    t1 = a.ics([r], NOW)
    t2 = a.ics([r], datetime(2026, 10, 20, 8, 0, tzinfo=ZoneInfo("UTC")))
    assert t1 != t2 and a.sans_horodatage(t1) == a.sans_horodatage(t2)


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
