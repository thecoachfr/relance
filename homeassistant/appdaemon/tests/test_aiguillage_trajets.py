"""Tests hors Home Assistant de `aiguillage_trajets` (plan P9-M) : python3 -m pytest homeassistant/appdaemon/tests

Points fictifs uniquement (dépôt public) : une ligne droite autour du pont Marie."""

from datetime import date, datetime
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import aiguillage_trajets as m  # noqa: E402

LAT, LON = 48.8530, 2.3570


def etat(lat=LAT, lon=LON, precision=12.0, quand="2026-10-22T08:00:00+00:00", **attrs):
    return {"latitude": lat, "longitude": lon, "gps_accuracy": precision, "source_type": "gps", "speed": 1, **attrs}, quand


def db(tmp_path):
    return m.ouvrir(str(tmp_path / "t.sqlite"))


def test_point_depuis_etat():
    p = m.point_depuis_etat(*etat())
    assert p == {"t": int(datetime.fromisoformat("2026-10-22T08:00:00+00:00").timestamp()),
                 "lat": LAT, "lon": LON, "precision": 12.0, "vitesse": 1.0}
    assert m.point_depuis_etat(*etat(precision=250)) is None          # trop imprécis
    assert m.point_depuis_etat(*etat(lat=None)) is None               # pas de position
    assert m.point_depuis_etat(*etat(source_type="router")) is None   # présence Wi-Fi, pas un point
    assert m.point_depuis_etat(*etat(quand="pas une date")) is None
    assert m.point_depuis_etat(*etat(speed=-1))["vitesse"] is None


def test_points_sans_doublon_ni_repetition(tmp_path):
    base = db(tmp_path)
    p1 = m.point_depuis_etat(*etat(quand="2026-10-22T08:00:00+00:00"))
    assert m.ajouter_point(base, p1, "compagnon")
    assert not m.ajouter_point(base, p1, "compagnon")                 # même point rejoué (reprise de l'historique)
    p2 = m.point_depuis_etat(*etat(quand="2026-10-22T08:00:05+00:00"))
    assert not m.ajouter_point(base, p2, "compagnon")                 # téléphone immobile : même position
    p3 = m.point_depuis_etat(*etat(lat=LAT + 0.001, quand="2026-10-22T08:01:00+00:00"))
    assert m.ajouter_point(base, p3, "compagnon")
    assert m.compter(base)["points"] == 2


def test_lire_visites():
    brut = [
        {"arrivee": 1792650000, "depart": 1792653600, "lat": LAT, "lon": LON, "precision": 60},
        {"arrivee": 1792660000, "depart": None, "lat": LAT, "lon": LON, "precision": 40},   # pas encore parti
        {"arrivee": 1792670000, "depart": 1792660000, "lat": LAT, "lon": LON},             # départ incohérent
        {"arrivee": 0, "lat": LAT, "lon": LON},                                            # arrivée inconnue
        {"arrivee": 1792680000, "lat": 120, "lon": LON},                                   # hors bornes
        {"arrivee": 1792690000, "lat": LAT, "lon": LON, "precision": 5000},                # trop imprécis
        "pas un objet",
    ]
    v = m.lire_visites(brut)
    assert [x["arrivee"] for x in v] == [1792650000, 1792660000, 1792670000]
    assert v[2]["depart"] is None
    assert m.lire_visites('[{"arrivee": 1792650000, "lat": 48.85, "lon": 2.35}]')[0]["lat"] == 48.85
    assert m.lire_visites("") == [] and m.lire_visites(None) == [] and m.lire_visites("{") == []


def test_visite_completee_au_depart(tmp_path):
    base = db(tmp_path)
    arrivee = int(datetime(2026, 10, 22, 9, 0, tzinfo=m.PARIS).timestamp())
    m.ajouter_visites(base, m.lire_visites([{"arrivee": arrivee, "lat": LAT, "lon": LON, "precision": 80}]), "aiguillage")
    m.ajouter_visites(base, m.lire_visites([{"arrivee": arrivee, "depart": arrivee + 1800, "lat": LAT, "lon": LON,
                                             "precision": 50}]), "aiguillage")
    # Lot renvoyé une seconde fois sans départ (file de l'app rejouée) : le départ connu reste.
    m.ajouter_visites(base, m.lire_visites([{"arrivee": arrivee, "lat": LAT, "lon": LON}]), "aiguillage")
    jour = m.lire_jour(base, date(2026, 10, 22))
    assert len(jour["visites"]) == 1 and jour["visites"][0]["depart"] == arrivee + 1800


def test_lire_jour_et_deja_venu(tmp_path):
    base = db(tmp_path)
    veille = int(datetime(2026, 10, 21, 23, 30, tzinfo=m.PARIS).timestamp())
    jour = int(datetime(2026, 10, 22, 0, 30, tzinfo=m.PARIS).timestamp())
    m.ajouter_point(base, {"t": veille, "lat": LAT, "lon": LON}, "compagnon")
    m.ajouter_point(base, {"t": jour, "lat": LAT + 0.01, "lon": LON}, "compagnon")      # à ~1,1 km
    # Visite de la veille qui finit après minuit : elle compte dans les deux jours.
    m.ajouter_visites(base, [{"arrivee": veille, "depart": jour, "lat": LAT, "lon": LON, "precision": 50}], "aiguillage")
    j = m.lire_jour(base, "2026-10-22")
    assert [p["t"] for p in j["points"]] == [jour] and len(j["visites"]) == 1
    venu = m.deja_venu(base, LAT + 0.0005, LON)                                         # à ~55 m
    assert [v["arrivee"] for v in venu["visites"]] == [veille] and venu["jours"] == ["2026-10-21"]
    assert m.deja_venu(base, LAT + 0.005, LON) == {"visites": [], "jours": []}           # à ~550 m


def test_distance():
    assert abs(m.distance_m(LAT, LON, LAT + 0.01, LON) - 1112) < 5


GPX = """<gpx><trk><trkseg>
<trkpt lon="2.357000" lat="48.853000"><ele>32</ele><time>2026-10-22T06:51:37Z</time><extensions><speed>1.3</speed><hAcc>11.5</hAcc></extensions></trkpt>
<trkpt lon="2.357010" lat="48.853010"><time>2026-10-22T06:51:38Z</time><extensions><speed>1.3</speed><hAcc>10</hAcc></extensions></trkpt>
<trkpt lon="2.357000" lat="48.853200"><time>2026-10-22T06:51:52Z</time><extensions><speed>-1</speed><hAcc>250</hAcc></extensions></trkpt>
<trkpt lon="2.357000" lat="48.853300"><time>2026-10-22T06:52:00Z</time><extensions><hAcc>9</hAcc></extensions></trkpt>
<trkpt lon="2.357000" lat="48.853305"><time>2026-10-22T06:52:01Z</time></trkpt>
</trkseg></trk></gpx>"""


def test_gpx_sante_eclairci(tmp_path):
    points = m.lire_gpx(GPX)
    assert len(points) == 4                                      # le point à 250 m de précision est retiré
    assert points[0] == {"t": int(datetime.fromisoformat("2026-10-22T06:51:37+00:00").timestamp()),
                         "lat": 48.853, "lon": 2.357, "precision": 11.5, "vitesse": 1.3}
    garde = m.eclaircir(points)
    # Le 2e point (à ~1 m) est sauté ; le dernier est toujours gardé.
    assert [p["lat"] for p in garde] == [48.853, 48.8533, 48.853305]
    base = db(tmp_path)
    assert m.ajouter_points(base, garde, "sante") == 3
    assert m.ajouter_points(base, garde, "sante") == 0           # import rejoué : rien en double
