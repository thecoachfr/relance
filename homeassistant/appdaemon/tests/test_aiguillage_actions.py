"""Tests hors Home Assistant de `aiguillage_actions` : python3 homeassistant/appdaemon/tests/test_aiguillage_actions.py"""

from datetime import date
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import aiguillage_actions as a  # noqa: E402

TODAY = date(2026, 10, 16)
NOW = "2026-10-16T18:00:00+00:00"
SPOTIFY, TVA = a.RECETTES_PAR_DEFAUT


def test_correspond():
    ecouter = {"titre": "Spaceships", "fait": False, "notes": "https://open.spotify.com/track/A1\n🎧 À écouter"}
    assert a.correspond(SPOTIFY, ecouter)
    assert not a.correspond(SPOTIFY, {**ecouter, "notes": "https://music.apple.com/x\n🎧 À écouter"})
    assert not a.correspond(SPOTIFY, {"titre": "x", "notes": "https://open.spotify.com/track/A1"})  # pas une envie
    tva = {"titre": "Payer la TVA du T3", "tags": ["Micro"], "jour": "2026-10-24"}
    assert a.correspond(TVA, tva)
    assert not a.correspond(TVA, {**tva, "tags": ["SCI"]})
    assert not a.correspond({"id": "vide", "si": {}}, tva)


def test_une_seule_fois():
    ecouter = {"titre": "Spaceships", "fait": False, "notes": "https://open.spotify.com/track/A1\n🎧 À écouter"}
    t = a.appliquer_recettes(ecouter, a.RECETTES_PAR_DEFAUT, NOW)
    assert len(t["actions"]) == 1 and t["recettes"] == ["spotify-playlist"]
    action = t["actions"][0]
    assert action["type"] == "playlist_spotify" and action["executant"] == "ha" and action["etat"] == "a_faire"
    assert action["params"] == {"playlist": "a_ecouter", "recette": "spotify-playlist"}
    # Deuxième passage, modification du titre : rien de plus.
    assert a.appliquer_recettes({**t, "titre": "Spaceships (live)"}, a.RECETTES_PAR_DEFAUT, NOW) is None
    # Action retirée par Alexandre : la recette ne la remet pas.
    assert a.appliquer_recettes({**t, "actions": []}, a.RECETTES_PAR_DEFAUT, NOW) is None
    # Recette inactive (TVA par défaut) ou tâche faite : rien.
    assert a.appliquer_recettes({"titre": "TVA", "tags": ["Micro"]}, a.RECETTES_PAR_DEFAUT, NOW) is None
    assert a.appliquer_recettes({**ecouter, "fait": True}, a.RECETTES_PAR_DEFAUT, NOW) is None


def test_due_et_marquer():
    tache = {"titre": "TVA", "jour": "2026-10-21", "actions": [
        {"id": "1", "type": "playlist_spotify", "executant": "ha", "declencheur": {"quand": "creation"}, "etat": "a_faire"},
        {"id": "2", "type": "preparer", "executant": "ha", "declencheur": {"quand": "avant_echeance", "jours": 5}, "etat": "a_faire"},
        {"id": "3", "type": "sur_tv", "executant": "appareil", "etat": "a_faire"},
        {"id": "4", "type": "playlist_spotify", "executant": "ha", "etat": "faite"},
    ]}
    dues = [x["id"] for x in tache["actions"] if a.due(x, tache, TODAY)]
    assert dues == ["1", "2"]  # le 21 moins 5 jours = le 16
    assert not a.due(tache["actions"][1], {**tache, "jour": "2026-10-22"}, TODAY)
    assert not a.due(tache["actions"][1], {**tache, "jour": None}, TODAY)
    t = a.marquer(tache, "1", "faite", "1 titre ajouté", NOW)
    assert t["actions"][0]["etat"] == "faite" and t["actions"][0]["resultat"] == "1 titre ajouté"
    assert t["actions"][0]["maj"] == NOW and tache["actions"][0]["etat"] == "a_faire"  # pas de modification en place


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
