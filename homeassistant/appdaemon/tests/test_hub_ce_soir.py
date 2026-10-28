"""Tests hors Home Assistant de `hub_ce_soir` (« Ce soir » du Hub, `sensor.hub_ce_soir`) :
uv run --with pytest python -m pytest -q homeassistant/appdaemon/tests"""

from datetime import datetime
from pathlib import Path
import json
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import hub_ce_soir as c  # noqa: E402

SOIR = datetime(2026, 10, 28, 18, 0, tzinfo=c.PARIS)
CHAINES = list(c.CHAINES)


def t(h, m=0):
    return int(datetime(2026, 10, 28, h, m, tzinfo=c.PARIS).timestamp())


def prog(oqee, titre, cat="Film", sous="Thriller", h=21, m=0, duree=6000, annee=2020, age=0):
    return {"oqee_id": oqee, "titre_brut": titre, "categorie": cat, "sous_categorie": sous, "annee": annee,
            "debut": t(h, m), "duree": duree, "resume": "Résumé.", "image": None, "age": age}


def titres(bruts, envies=(), maintenant=SOIR):
    return [p["titre"] for p in c.calculer(bruts, CHAINES, set(envies), maintenant)[1]["programmes"]]


def test_genres_gardes_et_ecartes():
    assert c.genre("Film", "Thriller") == "film"
    assert c.genre("Série", "Série policière") == "serie"
    assert c.genre("Documentaire", "Documentaire histoire") == "documentaire"
    assert c.genre("Magazine", "Magazine de reportages") == "reportage"
    assert c.genre("Téléfilm", "Téléfilm dramatique") == "telefilm"
    for cat, sous in [("Film", "Film pornographique"), ("Série", "Série d'animation"), ("Série", "Série jeunesse"),
                      ("Documentaire", "Documentaire téléréalité"), ("Magazine", "Magazine d'actualité"),
                      ("Divers", "Journal"), ("Emission sportive", "Football"), ("Téléfilm", "Téléfilm érotique")]:
        assert c.genre(cat, sous) is None, (cat, sous)


def test_titres_et_episodes():
    assert c.titre_propre("Tracker - S03E06") == ("Tracker", "S3 · É6")
    assert c.titre_propre("The Game") == ("The Game", None)
    assert c.cle_titre("Twilight, chapitre 2 : Tentation") == c.cle_titre("twilight chapitre 2 : tentation")
    assert c.cle_titre("Big Bang Theory - S05E05") == c.cle_titre("Big Bang Theory")


def test_fenetre_duree_age_et_fin():
    bruts = [prog(273, "Dans la fenêtre", h=21, m=20), prog(273, "Trop tôt", h=20, m=30),
             prog(273, "Trop tard", h=21, m=25), prog(536, "Pastille", cat="Série", sous="Série humoristique",
                                                      duree=600), prog(537, "Interdit", age=18)]
    assert titres(bruts) == ["Dans la fenêtre"]
    # Fini à 23 h : n'est plus « ce soir ».
    assert titres([prog(273, "Fini", duree=3600)], maintenant=datetime(2026, 10, 28, 23, 0, tzinfo=c.PARIS)) == []


def test_en_cours_et_champs():
    _, a = c.calculer([prog(1164, "La Femme de ménage - S01E02", annee=2025)], CHAINES, set(),
                      datetime(2026, 10, 28, 21, 30, tzinfo=c.PARIS))
    p = a["programmes"][0]
    assert p["en_cours"] is True and p["episode"] == "S1 · É2" and p["chaine"] == "CANAL+ Box Office"
    assert p["numero"] == 45 and p["oqee_id"] == 1164 and p["heure_texte"] == "21 h"
    assert p["logo"] == "https://img2.oqee.net/channel_pictures/3109/w300"
    assert p["debut"] == "2026-10-28T21:00+01:00" and a["soiree"] == "2026-10-28"


def test_episodes_a_la_suite_une_seule_fois():
    bruts = [prog(846, "Big Bang Theory - S05E05", "Série", "Série humoristique", h=20, m=45, duree=1500),
             prog(846, "Big Bang Theory - S05E06", "Série", "Série humoristique", h=21, m=10, duree=1500)]
    assert titres(bruts) == ["Big Bang Theory"]


def test_ordre_envie_genre_prime_chaine_annee():
    bruts = [prog(267, "Série", "Série", "Série policière"),
             prog(1173, "Film récent", annee=2024), prog(279, "Film ancien", annee=1990),
             prog(273, "Film d'Arte", annee=1997), prog(128, "Docu", "Documentaire", "Documentaire histoire"),
             prog(409, "Film d'avant-soirée", h=20, m=45, annee=2025),
             prog(282, "Mon envie", "Série", "Série policière")]
    assert titres(bruts, envies={c.cle_titre("Mon envie")}) == [
        "Mon envie", "Film d'Arte", "Film récent", "Film ancien", "Film d'avant-soirée", "Docu", "Série"]


def test_quotas_par_genre():
    films = [prog(o, f"Film {i}", annee=2000 + i) for i, (_, _, o, _) in enumerate(CHAINES[:9])]
    series = [prog(o, f"Série {i}", "Série", "Série dramatique") for i, (_, _, o, _) in enumerate(CHAINES[9:13])]
    resultat = titres(films + series)
    assert sum(r.startswith("Film") for r in resultat) == c.QUOTAS["film"]
    assert sum(r.startswith("Série") for r in resultat) == c.QUOTAS["serie"]


def test_mes_chaines_par_la_freebox():
    freebox = {f"uuid-webtv-{u}": {"has_abo": n in (40, 46)} for n, _, _, u in c.CHAINES}
    numeros = [n for n, _, _, _ in c.mes_chaines(freebox)]
    assert 1 in numeros and 27 in numeros and 40 in numeros and 46 in numeros
    assert 45 in numeros  # CANAL+ Box Office : marquée hors abonnement par la Freebox, gardée quand même
    assert 47 not in numeros and 546 not in numeros
    assert c.mes_chaines(None) == list(c.CHAINES)
    bouquet = [{"number": 999, "uuid": "uuid-webtv-x", "sub_number": 0}, {"number": 40, "uuid": "uuid-webtv-362"}]
    assert c.non_reliees({"uuid-webtv-x": {"has_abo": True}}, bouquet) == [999]


def test_lecture_des_deux_guides():
    entrees = {"273": [{"pictures": {"main": "https://img1.oqee.net/pictures/1/wide/h%d"},
                        "live": {"title": "The Game", "category": "Film", "sub_category": "Thriller", "year": 1997,
                                 "start": t(21), "duration_seconds": 7800, "description": "x"}}],
               "99999": [{"live": {"title": "Hors table", "start": t(21)}}]}
    bruts = c.programmes_oqee(entrees, CHAINES)
    assert len(bruts) == 1 and bruts[0]["image"] == "https://img1.oqee.net/pictures/1/wide/h480"
    epg = {"uuid-webtv-204": {"a": {"title": "The Game", "date": t(21), "duration": 7800, "category_name": "Film",
                                    "picture_big": "/api/latest/tv/img/x.jpg"}}}
    fb = c.programmes_freebox(epg, CHAINES)
    assert fb[0]["oqee_id"] == 273 and fb[0]["image"] == "http://mafreebox.freebox.fr/api/latest/tv/img/x.jpg"
    assert titres(fb) == ["The Game"]


def test_envies_a_regarder():
    enregistrements = [
        {"valeur": {"titre": "the game", "envie": {"type": "regarder"}}},
        {"valeur": {"titre": "Vu", "fait": True, "envie": {"type": "regarder"}}},
        {"valeur": {"titre": "Un album", "envie": {"type": "ecouter"}}},
        {"valeur": {"titre": "Mr Wolff 2016", "envie": {"type": "regarder", "tmdb": {"titre": "Mr Wolff"}}}},
    ]
    assert c.titres_envies(enregistrements) == {c.cle_titre("The Game"), c.cle_titre("Mr Wolff 2016"),
                                                c.cle_titre("Mr Wolff")}


def test_cles_du_contrat():
    exemple = json.loads((Path(__file__).resolve().parents[2] / "HUB-CE-SOIR-exemple.json").read_text())
    _, a = c.calculer([prog(273, "The Game")], CHAINES, set(), SOIR)
    assert set(a) == set(exemple["attributes"]) - {"friendly_name", "icon"}
    assert set(a["programmes"][0]) == set(exemple["attributes"]["programmes"][0])


def test_taille_des_attributs():
    long = "mot " * 200
    bruts = [dict(prog(o, f"Programme {i}"), resume=long) for i, (_, _, o, _) in enumerate(CHAINES)]
    _, a = c.calculer(bruts, CHAINES, set(), SOIR)
    assert len(json.dumps(a, ensure_ascii=False).encode()) < 12000  # limite de l'enregistreur : 16 Ko
    assert all(len(p["resume"]) <= c.RESUME_MAX + 1 for p in a["programmes"])
