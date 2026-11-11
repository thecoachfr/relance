"""Tests hors Home Assistant de `aiguillage_salves` (11/11/2026) : salves sans changement visible, écho."""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import aiguillage_salves as salves  # noqa: E402

CLE = "0f8b6c1e-5a3d-4c2b-9e7f-1a2b3c4d5e6f"


def tache(valeur, par="iphone-aiguillage-738b", cle=CLE, supprime=False):
    return {"cle": cle, "valeur": None if supprime else valeur, "modifie_par": par, "supprime": supprime}


def test_cle_inconnue_compte_comme_changee():
    empreintes = {}
    assert salves.changements_visibles([tache({"titre": "Pain"})], empreintes) != []
    assert CLE in empreintes


def test_meme_valeur_reecrite_rien_de_visible():
    empreintes = {}
    salves.changements_visibles([tache({"titre": "Pain", "jour": "2026-11-11"})], empreintes)
    # Même contenu, ordre des champs différent : rien de visible.
    assert salves.changements_visibles([tache({"jour": "2026-11-11", "titre": "Pain"})], empreintes) == []


def test_champ_non_lu_par_l_app_rien_de_visible():
    empreintes = {}
    salves.changements_visibles([tache({"titre": "Pain"})], empreintes)
    assert salves.changements_visibles([tache({"titre": "Pain", "recettes": ["tva"]}, par="vigie")], empreintes) == []


def test_champ_lu_par_l_app_visible():
    empreintes = {}
    salves.changements_visibles([tache({"titre": "Pain"})], empreintes)
    assert len(salves.changements_visibles([tache({"titre": "Pain", "categorie": "Courses"})], empreintes)) == 1


def test_suppression_visible():
    empreintes = {}
    salves.changements_visibles([tache({"titre": "Pain"})], empreintes)
    assert len(salves.changements_visibles([tache(None, supprime=True)], empreintes)) == 1
    assert salves.changements_visibles([tache(None, supprime=True)], empreintes) == []


def test_cle_hors_tache_tout_compte():
    empreintes = {}
    autre = {"cle": "reglages", "valeur": {"x": 1}, "modifie_par": "vigie"}
    salves.changements_visibles([autre], empreintes)
    assert len(salves.changements_visibles([{**autre, "valeur": {"x": 1, "recettes": 2}}], empreintes)) == 1


def test_echo_auteur_unique():
    jetons = {"a" * 64: {"device": "iPad", "appareil": "ipad-aiguillage-12ab"},
              "b" * 64: {"device": "iPhone", "appareil": "iphone-aiguillage-738b"},
              "c" * 64: {"device": "iPad"}}  # ancien build : pas de champ appareil, reçoit tout
    auteur = salves.auteur_unique([tache({"titre": "x"}, par="ipad-aiguillage-12ab")])
    assert auteur == "ipad-aiguillage-12ab"
    assert set(salves.destinataires(jetons, auteur)) == {"b" * 64, "c" * 64}


def test_plusieurs_auteurs_tout_le_monde():
    jetons = {"a" * 64: {"appareil": "ipad-aiguillage-12ab"}, "b" * 64: {"appareil": "vigie"}}
    auteur = salves.auteur_unique([tache({}, par="ipad-aiguillage-12ab"), tache({}, par="vigie")])
    assert auteur is None
    assert len(salves.destinataires(jetons, auteur)) == 2


def test_compter_evitee():
    stats = {}
    salves.compter_evitee(stats, "2026-11-11", "rien_de_visible")
    salves.compter_evitee(stats, "2026-11-11", "rien_de_visible")
    salves.compter_evitee(stats, "2026-11-11", "echo")
    assert stats["2026-11-11"]["evitees"] == {"rien_de_visible": 2, "echo": 1}
    assert stats["2026-11-11"]["envois"] == 0
