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


def test_routine():
    from datetime import datetime, timezone
    action = {"id": "p1", "type": "preparer", "executant": "routine", "declencheur": {"quand": "avant_echeance", "jours": 5},
              "params": {"modele": "tva_micro", "recette": "tva-micro"}, "etat": "a_faire"}
    tache = {"titre": "Payer la TVA", "jour": "2026-10-21", "actions": [action]}
    assert a.due(action, tache, TODAY, executant="routine") and not a.due(action, tache, TODAY)
    texte = a.texte_routine("k-1", action, tache)
    assert "clé k-1" in texte and "id p1" in texte and "modèle tva_micro" in texte and "2026-10-21" in texte
    lance = {**action, "etat": "en_cours", "maj": "2026-10-16T08:00:00+00:00"}
    assert not a.due(lance, tache, TODAY, executant="routine")  # pas relancée
    assert not a.routine_en_retard(lance, datetime(2026, 10, 17, 7, 0, tzinfo=timezone.utc))
    assert a.routine_en_retard(lance, datetime(2026, 10, 17, 9, 0, tzinfo=timezone.utc))


def test_rappel_maison():
    action = {"id": "m1", "type": "rappel_maison", "executant": "ha", "declencheur": {"quand": "presence"}, "etat": "a_faire"}
    tache = {"titre": "Arroser les plantes", "actions": [action]}
    assert a.rappel_maison_du(action, tache, TODAY)
    # La passe des actions ne l'exécute pas (déclencheur « presence ») : seule l'arrivée à la maison le fait.
    assert not a.due(action, tache, TODAY)
    t = a.marquer_rappel(tache, "m1", "2026-10-16T19:10:00+00:00", "21:10")
    rappel = t["actions"][0]
    assert rappel["etat"] == "a_faire" and rappel["resultat"] == "Rappelé le 16/10 à 21:10"
    assert not a.rappel_maison_du(rappel, t, TODAY)  # une fois par jour
    assert a.rappel_maison_du(rappel, t, date(2026, 10, 17))
    assert not a.rappel_maison_du(action, {**tache, "fait": True}, TODAY)


def test_rappel_piece():
    action = {"id": "p1", "type": "rappel_piece", "executant": "ha", "declencheur": {"quand": "piece"},
              "params": {"piece": "Chambre"}, "etat": "a_faire"}
    tache = {"titre": "Changer l'ampoule", "actions": [action]}
    assert a.rappel_piece_du(action, tache, "chambre", TODAY)
    assert not a.rappel_piece_du(action, tache, "Salon", TODAY)
    assert not a.due(action, tache, TODAY)  # pas exécutée par la passe des actions
    t = a.marquer_rappel(tache, "p1", "2026-10-16T19:30:00+00:00", "21:30")
    assert not a.rappel_piece_du(t["actions"][0], t, "Chambre", TODAY)
    assert a.rappel_piece_du(t["actions"][0], t, "Chambre", date(2026, 10, 17))


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)


def test_a_notifier():
    tache = {"titre": "TVA", "actions": [
        {"id": "r", "executant": "routine", "etat": "faite"},
        {"id": "h", "executant": "ha", "etat": "echec", "resultat": "Spotify : 401"},
        {"id": "t", "executant": "appareil", "etat": "echec"},
        {"id": "s", "executant": "ha", "etat": "faite"},
    ]}
    actions = {x["id"]: x for x in tache["actions"]}
    assert a.a_notifier(actions["r"], tache)[0] == "📝 TVA"
    assert a.a_notifier(actions["h"], tache) == ("⚠️ TVA", "Action en échec : Spotify : 401")
    assert a.a_notifier(actions["t"], tache) is None
    assert a.a_notifier(actions["s"], tache) is None
    notee = a.noter_notifie(tache, "r")
    assert a.a_notifier(notee["actions"][0], notee) is None
    assert notee["actions"][1] == tache["actions"][1]
    # Nouvel échec après une réussite notifiée : notifié à nouveau.
    assert a.a_notifier({**notee["actions"][0], "etat": "echec"}, notee) is not None
    assert a.a_notifier(actions["h"], {**tache, "fait": True}) is None


def test_piece_dominante():
    # Assis au salon avec des sauts de quelques secondes (relevé du 16/10) : le salon est retenu.
    hist = [(0, "Salon"), (30, "Salle de bain"), (40, "Salon"), (70, "Entrée"), (75, "Salon"), (110, "Bureau"), (115, "Salon")]
    assert a.piece_dominante(hist, 120) == "Salon"
    # Rien de majoritaire : aucune pièce.
    hist = [(0, "Salon"), (40, "Entrée"), (80, "Cuisine")]
    assert a.piece_dominante(hist, 120) is None
    # Entré dans la cuisine il y a 30 s seulement : toujours le salon.
    hist = [(0, "Salon"), (90, "Cuisine")]
    assert a.piece_dominante(hist, 120) == "Salon"
    # … puis au bout de 90 s de plus.
    assert a.piece_dominante(hist, 210) == "Cuisine"
    # Pièce d'avant la fenêtre et stable : retenue ; absent : jamais.
    assert a.piece_dominante([(0, "Chambre")], 1000) == "Chambre"
    assert a.piece_dominante([(0, "Absent")], 1000) is None
    assert a.piece_dominante([], 1000) is None
