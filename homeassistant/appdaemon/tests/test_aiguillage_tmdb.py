"""Tests hors Home Assistant de `aiguillage_tmdb` : python3 homeassistant/appdaemon/tests/test_aiguillage_tmdb.py"""

from datetime import date
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import aiguillage_tmdb as t  # noqa: E402

TODAY = date(2026, 10, 16)


def test_search_query():
    assert t.search_query("Dune (2021)") == ("Dune", 2021)
    assert t.search_query("The Bear (essai B2)") == ("The Bear", None)
    assert t.search_query("À regarder sur Netflix") == ("À regarder sur Netflix", None)


def test_needs_lookup():
    regarder = {"titre": "Dune", "fait": False, "envie": {"type": "regarder"}}
    assert t.needs_lookup(regarder, TODAY)
    assert not t.needs_lookup({**regarder, "fait": True}, TODAY)
    assert not t.needs_lookup({"titre": "x", "envie": {"type": "lire"}}, TODAY)
    fresh = {**regarder, "envie": {"type": "regarder", "dispo_maj": "2026-10-12"}}
    assert not t.needs_lookup(fresh, TODAY)
    old = {**regarder, "envie": {"type": "regarder", "dispo_maj": "2026-10-01"}}
    assert t.needs_lookup(old, TODAY)
    ambigu = {**regarder, "envie": {"type": "regarder", "tmdb_statut": "ambigu", "tmdb_maj": "2026-10-15"}}
    assert not t.needs_lookup(ambigu, TODAY)


def test_choose():
    bear = {"media_type": "tv", "id": 136315, "name": "The Bear", "original_name": "The Bear",
            "first_air_date": "2022-06-23", "popularity": 120}
    other = {"media_type": "movie", "id": 1, "title": "The Bear", "release_date": "1988-10-19", "popularity": 3}
    person = {"media_type": "person", "id": 9, "name": "The Bear"}
    # Homonymes, mais la série domine nettement.
    assert t.choose([bear, other, person], "The Bear")["id"] == 136315
    # L'année tranche.
    assert t.choose([bear, other], "The Bear", 1988)["id"] == 1
    # Deux homonymes aussi connus : ambigu.
    twin = {**other, "popularity": 100}
    assert t.choose([bear, twin], "The Bear") is None
    # Accents et ponctuation ignorés.
    assert t.choose([{"media_type": "movie", "id": 2, "title": "Amélie", "popularity": 1}], "amelie")["id"] == 2
    assert t.choose([], "Rien") is None


def test_providers_and_availability():
    payload = {"id": 136315, "results": {"FR": {
        "flatrate": [{"provider_id": 337, "provider_name": "Disney Plus"}],
        "rent": [{"provider_id": 2, "provider_name": "Apple TV"}],
        "buy": [{"provider_id": 2, "provider_name": "Apple TV"}, {"provider_id": 10, "provider_name": "Amazon Video"}],
    }, "US": {"flatrate": [{"provider_id": 15, "provider_name": "Hulu"}]}}}
    dispo = t.providers_fr(payload)
    assert dispo["abonnement"] == [{"id": 337, "nom": "Disney Plus", "code": "disney"}]
    assert dispo["location"][0]["code"] == "apple_tv"
    assert "gratuit" not in dispo
    info = t.work_info({"media_type": "tv", "id": 136315, "name": "The Bear", "first_air_date": "2022-06-23",
                        "poster_path": "/abc.jpg"})
    assert info == {"id": 136315, "type": "tv", "titre": "The Bear", "annee": 2022,
                    "affiche": "https://image.tmdb.org/t/p/w342/abc.jpg"}
    tache = {"titre": "The Bear", "v": 1, "fait": False, "envie": {"type": "regarder", "id_titre": "x"}}
    out = t.with_availability(tache, info, dispo, TODAY)
    assert out["v"] == 2 and out["envie"]["plateforme"] == "disney" and out["envie"]["id_titre"] == "x"
    assert out["envie"]["dispo_maj"] == "2026-10-16" and not t.needs_lookup(out, TODAY)
    # Une plateforme déjà dite (« sur Netflix ») n'est pas remplacée.
    kept = t.with_availability({**tache, "envie": {"type": "regarder", "plateforme": "netflix"}}, info, dispo, TODAY)
    assert kept["envie"]["plateforme"] == "netflix"
    assert t.providers_fr({"results": {}}) == {}


def test_status():
    tache = {"titre": "Dune", "notes": "🎬 À regarder", "envie": {"type": "regarder"}}
    out = t.with_status(tache, "ambigu", TODAY)
    assert out["notes"].endswith(t.SUGGESTION) and out["envie"]["tmdb_statut"] == "ambigu"
    assert t.with_status(out, "ambigu", TODAY)["notes"].count("préciser l'année") == 1
    assert not t.needs_lookup(out, TODAY)


def test_codes():
    assert t.code_for("Netflix") == "netflix" and t.code_for("Canal+") == "canal"
    assert t.code_for("Amazon Prime Video") == "prime" and t.code_for("Max") == "max"
    assert t.code_for("Mubi") is None


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
