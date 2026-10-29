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


def test_reponse_jour(tmp_path):
    base = db(tmp_path)
    t0 = int(datetime(2026, 10, 22, 9, 0, tzinfo=m.PARIS).timestamp())
    # Une marche vers le nord (montre) et les mêmes lieux par l'app Compagnon : la distance ne double pas.
    marche = [{"t": t0 + i * 10, "lat": LAT + i * 0.0002, "lon": LON} for i in range(500)]   # ~11 km
    m.ajouter_points(base, marche, "sante")
    m.ajouter_points(base, [{"t": t0, "lat": LAT, "lon": LON}, {"t": t0 + 4990, "lat": LAT + 0.0998, "lon": LON}], "compagnon")
    m.ajouter_point(base, {"t": t0 - 3 * 86400, "lat": LAT, "lon": LON}, "compagnon")          # 19/10
    m.ajouter_visites(base, [{"arrivee": t0 + 2 * 86400, "depart": None, "lat": LAT, "lon": LON, "precision": 50}], "aiguillage")
    r = m.reponse_jour(base, "2026-10-22")
    assert r["km"] == 11.1 and len(r["points"]) == 502
    assert r["points"][0] == [t0, LAT, LON]
    assert (r["precedent"], r["suivant"]) == ("2026-10-19", "2026-10-24")
    petit = m.reponse_jour(base, "2026-10-22", taille_max=4000)                                # éclairci pour tenir
    assert 3 <= len(petit["points"]) < 200 and petit["km"] == 11.1
    vide = m.reponse_jour(base, "2026-10-21")
    assert vide["points"] == [] and vide["precedent"] == "2026-10-19" and vide["suivant"] == "2026-10-22"


def test_repondre(tmp_path):
    base = db(tmp_path)
    m.ajouter_visites(base, [{"arrivee": 1792650000, "depart": 1792653600, "lat": LAT, "lon": LON, "precision": 50}], "aiguillage")
    r = m.repondre(base, {"id": "a1", "type": "venu", "lat": LAT, "lon": LON})
    assert r["id"] == "a1" and r["rayon"] == 150 and r["visites"][0]["depart"] == 1792653600
    assert m.repondre(base, {"id": "a2", "type": "venu", "lat": 200, "lon": 0})["erreur"] == "point invalide"
    assert m.repondre(base, {"id": "a3", "type": "jour", "jour": "pas une date"})["erreur"]
    assert m.repondre(base, None)["erreur"] == "type inconnu"
    assert m.repondre(base, {"id": "a4", "type": "jour", "jour": "2026-10-22"})["id"] == "a4"


def test_lot_du_trace_precis():
    """M4 : lot écrit par l'app (`lot:<id>`), points [t, lat, lon, precision, vitesse]."""
    t0 = 1793260000
    valeur = {"device": "iPhone", "points": [
        [t0, 48.8086, 2.4178, 8.0, 1.4], [t0 + 30, 48.8090, 2.4180, 12.0, -1],
        [t0 + 60, 48.81, 2.42, 250.0, 1.2],        # trop imprécis
        [100, 48.81, 2.42, 5.0, 1.0],               # date impossible
        [t0 + 90, 95.0, 2.42, 5.0, 1.0], "x", [t0]]}
    pts = m.lire_lot(valeur)
    assert [p["t"] for p in pts] == [t0, t0 + 30]
    assert pts[1]["vitesse"] is None and pts[0]["precision"] == 8.0
    assert m.lire_lot(None) == [] and m.lire_lot({"points": "oups"}) == []


def test_priorite_au_trace_precis():
    t0 = 1793260000
    pts = [{"source": "compagnon", "t": t0 - 1000, "lat": 0, "lon": 0},   # avant le tracé : gardé
           {"source": "compagnon", "t": t0 + 50, "lat": 0, "lon": 0},     # pendant : retiré
           {"source": "precis", "t": t0, "lat": 0, "lon": 0},
           {"source": "precis", "t": t0 + 100, "lat": 0, "lon": 0},
           {"source": "compagnon", "t": t0 + 5000, "lat": 0, "lon": 0}]   # après : gardé
    garde = m.priorite_au_trace_precis(pts)
    assert [(p["source"], p["t"] - t0) for p in garde] == [
        ("compagnon", -1000), ("precis", 0), ("precis", 100), ("compagnon", 5000)]
    sans = [p for p in pts if p["source"] == "compagnon"]
    assert m.priorite_au_trace_precis(sans) == sans
