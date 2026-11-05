"""Tests hors Home Assistant de `aiguillage_courses` (liste de courses unique, P9-U) :
uv run --with pytest python -m pytest -q homeassistant/appdaemon/tests"""

from datetime import UTC, datetime, timedelta
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import aiguillage_courses as c  # noqa: E402

INSTANT = datetime(2026, 11, 4, 12, 0, tzinfo=UTC)
NOW = INSTANT.isoformat()
ANCIEN = (INSTANT - timedelta(hours=1)).isoformat()
RECENT = (INSTANT - timedelta(minutes=2)).isoformat()
IDS = {"supermarches": "Supermarchés", "drog": "Droguerie", "brico": "Bricolage"}
CLE = "22222222-2222-4222-8222-222222222222"
LIEUX = {"cle": "config:lieux", "valeur": {"groupes": [
    {"id": "supermarches", "nom": "Supermarchés"}, {"id": "dom", "nom": "Domicile"}, {"id": "t", "nom": "Travail"},
    {"id": "drog", "nom": "Droguerie"}]}}


def art(texte, **kw):
    return {"id": texte.lower(), "texte": texte, "coche": False} | kw


def unique(*articles):
    return {"cle": c.CLE_LISTE, "version": 4, "supprime": False, "valeur": {
        "titre": "Courses", "categorie": "Achats", "fait": False, "liste": {"permanente": True, "articles": list(articles)}}}


def liste(*articles, titre="Courses", modifie=ANCIEN, cle=CLE, **kw):
    return {"cle": cle, "version": 2, "supprime": False, "modifie_le": modifie, "valeur": {
        "titre": titre, "categorie": "Achats", "fait": False, "liste": {"articles": list(articles), **kw.pop("liste", {})},
        **kw}}


def test_rien_sans_liste_unique():
    assert c.liste_unique([LIEUX, liste(art("Pain"))]) is None
    faux = liste(art("Pain"), cle=c.CLE_LISTE)  # la bonne clé, mais pas permanente
    assert c.liste_unique([faux]) is None
    assert c.liste_unique([unique()])["version"] == 4
    assert c.liste_unique([{**unique(), "supprime": True}]) is None


def test_groupes_magasins_sans_domicile_ni_travail():
    assert c.groupes_magasins([LIEUX]) == [("supermarches", "Supermarchés"), ("drog", "Droguerie")]
    assert c.groupes_magasins([]) == [("supermarches", "Supermarchés")]


def test_quelles_listes_sont_versees():
    prete = liste(art("Pain"))
    assert c.a_verser([unique(), prete], INSTANT) == ([prete], False)
    datee = liste(art("Pain"), jour="2026-11-08")  # décision du 04/11 : versée aussi
    assert c.a_verser([unique(), datee], INSTANT) == ([datee], False)
    # Trop récente : attend ; le passage devra revenir.
    assert c.a_verser([unique(), liste(art("Pain"), modifie=RECENT)], INSTANT) == ([], True)
    # Vide, recette à préparer, photo à lire, déjà versée, hors Achats : ne bougent pas.
    for autre in (liste(),
                  liste(art("Pain"), liste={"recettes": [{"titre": "Risotto", "a_preparer": True}]}),
                  liste(art("Pain"), liste={"photos": [{"piece": "p", "a_lire": True}]}),
                  liste(art("Pain"), liste={"versee_le": ANCIEN})):
        assert c.a_verser([unique(), autre], INSTANT) == ([], False)
    valise = liste(art("Chaussettes"))
    valise["valeur"]["categorie"] = "Voyage"
    assert c.a_verser([unique(), valise], INSTANT) == ([], False)


def test_versement_sans_doublon_et_magasin_du_titre():
    source = liste(art("Lait"), art("Pain"), art("Déjà pris", coche=True), art("Colle"), titre="Courses Bricolage")["valeur"]
    resultat = c.verser([art("LAIT", id="x")], source, IDS, NOW)
    assert [a["texte"] for a in resultat] == ["LAIT", "Pain", "Colle"]
    assert resultat[1]["magasins"] == ["brico"] and resultat[1]["maj"] == NOW
    # Une liste sans magasin nommé : Claude choisira.
    assert "magasins" not in c.verser([], liste(art("Lait"))["valeur"], IDS, NOW)[0]
    # Déjà pris dans la liste unique : on en reprend.
    assert len(c.verser([art("Lait", coche=True)], liste(art("Lait"))["valeur"], IDS, NOW)) == 2


def test_tache_fermee():
    v = c.fermee(liste(art("Pain"))["valeur"], NOW)
    assert v["fait"] is True and v["fait_le"] == NOW and v["liste"]["versee_le"] == NOW and v["liste"]["articles"]


def test_correction_retenue_et_prioritaire():
    memo = {"lessive": {"magasins": ["supermarches"], "par": "claude"}}
    assert c.apprendre([art("Lessive", magasins=["drog"])], memo, IDS)
    assert memo["lessive"] == {"magasins": ["drog"], "par": "alexandre"}
    assert not c.apprendre([art("Lessive", magasins=["drog"])], memo, IDS)  # rien de nouveau
    # Un choix de Claude ne s'apprend pas comme une correction.
    assert not c.apprendre([art("Pain", magasins=["drog"], magasins_claude=True)], memo, IDS)
    assert "pain" not in memo
    # Claude ne remplace pas une correction.
    articles = c.appliquer_reponse([art("Lessive")], {"articles": [{"id": "lessive", "magasins": ["Supermarchés"]}]},
                                   IDS, memo, NOW)
    assert memo["lessive"]["par"] == "alexandre" and articles[0]["magasins"] == ["supermarches"]


def test_supermarches_renomme():
    ids = {"supermarches": "Grandes surfaces", "drog": "Droguerie"}
    memo = {}
    reponse = {"articles": [{"id": "lessive", "magasins": ["Supermarchés"]}]}
    articles = c.appliquer_reponse([art("Lessive")], reponse, ids, memo, NOW)
    assert articles[0]["magasins"] == ["supermarches"] and memo["lessive"]["magasins"] == ["supermarches"]


def test_memoire_avant_claude():
    memo = {"lessive": {"magasins": ["drog", "ancien"], "par": "alexandre"}, "vieux": {"magasins": ["ancien"], "par": "claude"}}
    articles, a_demander = c.classer_par_memoire(
        [art("Lessive"), art("Vieux"), art("Pain"), art("Fait", coche=True), art("Colle", magasins=["brico"])], memo, IDS, NOW)
    assert articles[0]["magasins"] == ["drog"] and articles[0]["magasins_claude"] is True and articles[0]["maj"] == NOW
    assert [a["texte"] for a in a_demander] == ["Vieux", "Pain"]  # groupe disparu : à redemander
    assert articles[4] == art("Colle", magasins=["brico"])
    trop = [art(f"Article {i}") for i in range(c.ARTICLES_PAR_PASSAGE + 5)]
    assert len(c.classer_par_memoire(trop, {}, IDS, NOW)[1]) == c.ARTICLES_PAR_PASSAGE


def test_reponse_de_claude():
    memo = {}
    reponse = {"articles": [{"id": "lessive", "magasins": ["supermarchés", "DROGUERIE", "Droguerie"]},
                            {"id": "tuile", "magasins": ["Couvreur"]}, {"id": "inconnu", "magasins": ["Droguerie"]}]}
    articles = c.appliquer_reponse([art("Lessive"), art("Tuile"), art("Pain")], reponse, IDS, memo, NOW)
    assert articles[0]["magasins"] == ["supermarches", "drog"] and articles[0]["magasins_claude"] is True
    # Hors liste : Supermarchés, sans le retenir ; pas de réponse : l'article attend le prochain passage.
    assert articles[1]["magasins"] == ["supermarches"] and "tuile" not in memo
    assert "magasins" not in articles[2]
    assert memo == {"lessive": {"magasins": ["supermarches", "drog"], "par": "claude"}}


def test_question_et_memoire_lue():
    q = c.question([art("Lessive", rayon="maison")], ["Supermarchés", "Droguerie"])
    assert "Supermarchés, Droguerie" in q and '"texte": "Lessive"' in q and '"rayon": "maison"' in q
    assert c.memoire([]) == ({}, 0)
    assert c.memoire([{"cle": c.CLE_MEMOIRE, "version": 3, "valeur": {"articles": {"a": {}}}}]) == ({"a": {}}, 3)
