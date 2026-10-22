"""Tests hors Home Assistant de `aiguillage_tri` (plan P9-I) : python3 -m pytest homeassistant/appdaemon/tests

Tâches fictives uniquement (dépôt public)."""

from datetime import date
from pathlib import Path
import json
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import aiguillage_tri as t  # noqa: E402

AUJ = date(2026, 10, 17)
NOW = "2026-10-17T16:00:00Z"
TAGS = list(t.TAGS_DE_BASE)
CLE = "11111111-1111-4111-8111-111111111111"


def ch(**kw):
    """Une entrée de réponse, avec les valeurs par défaut du schéma."""
    base = {"cle": CLE, "titre": None, "categorie": None, "tags": None, "jour": None, "heure": None, "priorite": None,
            "duree": None, "lieu": None, "envie": None, "notes_a_la_fin": [], "partage_revu": False,
            "liste_nouvelle": None, "recette_preparee": None, "retirer_jour": False, "raison": "essai"}
    return base | kw


def rec(valeur, cle=CLE, **kw):
    return {"cle": cle, "version": 3, "valeur": valeur, "supprime": False, **kw}


# MARK: - Choix

def test_ouvertes_et_selection():
    faite = rec({"titre": "a", "fait": True})
    essai = rec({"titre": "b", "fait": False}, cle="essai")
    neuve = rec({"titre": "c", "fait": False}, cle="22222222-2222-4222-8222-222222222222")
    triee = rec({"titre": "d", "fait": False, "categorie": "Maison"}, cle="33333333-3333-4333-8333-333333333333",
                modifie_le="2026-10-17T10:00:00+00:00", modifie_par="routine-tri")
    retouchee = rec({"titre": "e", "fait": False, "categorie": "Perso"}, cle="44444444-4444-4444-8444-444444444444",
                    modifie_le="2026-10-17T12:00:00+00:00", modifie_par="iphone-aiguillage")
    supprimee = rec({"titre": "f", "fait": False}, cle="55555555-5555-4555-8555-555555555555", supprime=True)
    tout = [faite, essai, neuve, triee, retouchee, supprimee]
    assert [r["valeur"]["titre"] for r in t.ouvertes(tout)] == ["c", "d", "e"]
    assert [r["valeur"]["titre"] for r in t.selection(tout, "2026-10-17T11:00:00Z")] == ["c", "e"]
    assert len(t.selection(tout, "2026-10-17T11:00:00Z", complet=True)) == 3
    assert len(t.selection(tout, None)) == 3


def test_a_trier_partage_et_recette():
    base = {"titre": "x", "categorie": "Perso"}
    vieux = {"modifie_le": "2026-10-01T00:00:00+00:00", "modifie_par": "routine-tri"}
    assert not t.a_trier(rec(base, **vieux), "2026-10-17T00:00:00Z")
    assert t.a_trier(rec(base | {"notes": t.PARTAGE_A_REVOIR + "\nBonjour"}, **vieux), "2026-10-17T00:00:00Z")
    assert t.a_trier(rec(base | {"liste": {"recettes": [{"titre": "Crêpes", "a_preparer": True}]}}, **vieux),
                     "2026-10-17T00:00:00Z")


def test_tags_autorises():
    tags = t.tags_autorises([rec({"titre": "x", "tags": ["Vélo", "SCI"]})])
    assert tags[: len(t.TAGS_DE_BASE)] == list(t.TAGS_DE_BASE) and tags[-1] == "Vélo"


def test_vue_et_message():
    v = t.vue({"titre": "Courses", "fait": False, "google_id": "g", "relances": [1], "actions": [{"id": "a"}],
               "liste": {"articles": [{"id": "1", "texte": "Lait", "coche": True, "maj": NOW}],
                         "recettes": [{"titre": "Crêpes", "a_preparer": False, "ingredients": ["farine"]}]}})
    assert set(v) == {"titre", "liste"}
    assert v["liste"]["articles"] == [{"id": "1", "texte": "Lait"}]
    assert v["liste"]["recettes"] == [{"titre": "Crêpes", "a_preparer": False}]
    texte = t.message(NOW, None, [rec({"titre": "Courses"})], TAGS, ["Courses"])
    donnees = json.loads(texte[texte.index("{"):])
    assert donnees["memo"].startswith("ILLISIBLE") and donnees["taches"][0]["cle"] == CLE


def test_vides_sans_effet():
    v = {"titre": "Appeler maman", "fait": False}
    vide = ch(titre="", categorie="", tags=[], jour="", heure="", priorite="", duree=0,
              lieu=None, envie=None)
    assert t.appliquer(v, vide, AUJ, NOW, TAGS) == (None, [])


def test_schema_unions_limitees():
    def compte(s):
        n = 1 if "anyOf" in s or isinstance(s.get("type"), list) else 0
        for sous in list(s.get("properties", {}).values()) + s.get("anyOf", []) + ([s["items"]] if "items" in s else []):
            n += compte(sous)
        return n
    assert compte(t.SCHEMA) <= 16


def test_schema_strict():
    def parcourt(s):
        if s.get("type") == "object":
            assert s["additionalProperties"] is False and set(s["required"]) == set(s["properties"])
            for sous in s["properties"].values():
                parcourt(sous)
        for sous in s.get("anyOf", []):
            parcourt(sous)
        if "items" in s:
            parcourt(s["items"])
    parcourt(t.SCHEMA)


# MARK: - Application

def test_categorie_tags_et_champs_proteges():
    v = {"titre": "Déclarer le CA", "fait": False, "relances": [{"avant": 1}], "google_id": "g", "inconnu": {"a": 1}}
    nv, refus = t.appliquer(v, ch(categorie="Administratif", tags=["Micro", "Inventé"]), AUJ, NOW, TAGS)
    assert nv["categorie"] == "Administratif" and nv["tags"] == ["Micro"]
    assert nv["relances"] == v["relances"] and nv["inconnu"] == {"a": 1} and nv["fait"] is False
    assert any("hors liste" in r for r in refus)
    # Rien ne change d'une catégorie ou de tags déjà là.
    deja = v | {"categorie": "Perso"}
    nv, refus = t.appliquer(deja, ch(categorie="Maison", tags=["SCI"]), AUJ, NOW, TAGS)
    assert nv is None and len(refus) == 2


def test_rien_a_changer():
    v = {"titre": "Appeler maman", "fait": False, "categorie": "Famille"}
    assert t.appliquer(v, ch(), AUJ, NOW, TAGS) == (None, [])


def test_titre_dicte_et_ligne_micro():
    v = {"titre": "appel et le garage demain à 9 h", "fait": False, "notes": "Pneu avant"}
    nv, refus = t.appliquer(v, ch(titre="appeler le garage", jour="2026-10-18", heure="09:00"), AUJ, NOW, TAGS)
    assert nv["titre"] == "Appeler le garage" and nv["jour"] == "2026-10-18" and nv["heure"] == "09:00"
    assert nv["notes"] == "🎙 Dicté : appel et le garage demain à 9 h\nPneu avant" and refus == []
    # Une seule correction : avec une ligne 🎙, le titre ne bouge plus.
    nv2, refus2 = t.appliquer(nv, ch(titre="Autre chose"), AUJ, NOW, TAGS)
    assert nv2 is None and refus2


def test_echeance_gardee_et_dates_controlees():
    v = {"titre": "Dentiste", "fait": False, "jour": "2026-10-20"}
    nv, refus = t.appliquer(v, ch(jour="2026-10-21", heure="10:30"), AUJ, NOW, TAGS)
    assert nv["jour"] == "2026-10-20" and nv["heure"] == "10:30" and refus == ["jour (déjà fixé)"]
    nv, refus = t.appliquer({"titre": "x", "fait": False}, ch(jour="2026-10-01"), AUJ, NOW, TAGS)
    assert nv is None and "passé" in refus[0]
    nv, refus = t.appliquer({"titre": "x", "fait": False}, ch(heure="25:00"), AUJ, NOW, TAGS)
    assert nv is None and refus


def test_duree_et_priorite():
    v = {"titre": "Réunion", "fait": False, "jour": "2026-10-18", "heure": "18:00"}
    nv, _ = t.appliquer(v, ch(duree=120, priorite="Urgente"), AUJ, NOW, TAGS)
    assert nv["duree"] == 120 and nv["v"] == 2 and nv["priorite"] == "Urgente"
    nv, refus = t.appliquer({"titre": "x", "fait": False}, ch(duree=30), AUJ, NOW, TAGS)
    assert nv is None and refus


def test_lignes_ajoutees_ordre_et_doublons():
    v = {"titre": "Rendez-vous kiné", "fait": False, "notes": "Dicté\n💡 Suggestion : lundi"}
    nv, refus = t.appliquer(v, ch(notes_a_la_fin=["💡 Suggestion : mardi", "🎒 À prendre : carte Vitale",
                                                  "📍 Cabinet · 1 rue de l'Essai", "Texte libre"],
                                  lieu={"nom": "Cabinet", "adresse": "1 rue de l'Essai", "telephone": None,
                                        "lien": None}),
                            AUJ, NOW, TAGS)
    assert nv["notes"].split("\n") == ["Dicté", "💡 Suggestion : lundi", "📍 Cabinet · 1 rue de l'Essai",
                                       "🎒 À prendre : carte Vitale"]
    assert nv["lieu"] == {"nom": "Cabinet", "adresse": "1 rue de l'Essai", "source": "memo"} and nv["v"] == 2
    assert len(refus) == 2  # 💡 en double, ligne sans préfixe


def test_variante_retiree():
    nv, _ = t.appliquer({"titre": "Expo", "fait": False}, ch(notes_a_la_fin=["\U0001F6CD️ Magasin"]), AUJ, NOW, TAGS)
    assert nv["notes"] == "🛍 Magasin" and nv["envie"] == {"type": "magasin"}


def test_envie():
    v = {"titre": "regarder The Bear sur Disney+", "fait": False}
    nv, refus = t.appliquer(v, ch(titre="The Bear", notes_a_la_fin=["🎬 À regarder"],
                                  envie={"type": "regarder", "note": None, "plateforme": "disney"}), AUJ, NOW, TAGS)
    assert nv["envie"] == {"type": "regarder", "plateforme": "disney"} and nv["v"] == 2
    assert nv["notes"] == "🎙 Dicté : regarder The Bear sur Disney+\n🎬 À regarder" and refus == []
    # Pas de seconde envie, ni d'envie sur une liste, ni d'échéance pour une envie.
    nv2, refus2 = t.appliquer(nv, ch(notes_a_la_fin=["📖 À lire"]), AUJ, NOW, TAGS)
    assert nv2 is None and refus2
    nv3, refus3 = t.appliquer({"titre": "Courses", "fait": False, "liste": {"articles": []}},
                              ch(notes_a_la_fin=["🛍 Magasin"]), AUJ, NOW, TAGS)
    assert nv3 is None and refus3
    nv4, refus4 = t.appliquer({"titre": "Expo", "fait": False}, ch(jour="2026-10-20", notes_a_la_fin=["👀 À voir"]),
                              AUJ, NOW, TAGS)
    assert "jour" not in nv4 and nv4["envie"] == {"type": "voir"} and "jour sur une envie" in refus4
    # Type de l'envie différent de la ligne : ni champ ni ligne.
    nv5, refus5 = t.appliquer({"titre": "Album", "fait": False},
                              ch(notes_a_la_fin=["🎧 À écouter"], envie={"type": "lire", "note": None,
                                                                         "plateforme": None}), AUJ, NOW, TAGS)
    assert nv5 is None and refus5


def test_radio_et_jour_mis_par_l_app():
    # Tâche créée dans « À faire » (jour du jour mis par l'app) : devient une radio, le jour est retiré (22/10).
    v = {"titre": "Écouter radio tsugi", "fait": False, "jour": "2026-10-17"}
    nv, refus = t.appliquer(v, ch(titre="Radio Tsugi", notes_a_la_fin=["🎧 À écouter · radio"], retirer_jour=True,
                                  envie={"type": "ecouter", "note": "radio", "plateforme": "tunein"}), AUJ, NOW, TAGS)
    assert refus == [] and "jour" not in nv
    assert nv["envie"] == {"type": "ecouter", "note": "radio", "plateforme": "tunein"}
    assert nv["notes"] == "🎙 Dicté : Écouter radio tsugi\n🎧 À écouter · radio"
    # Jour à venir, heure fixée, ou pas d'envie ajoutée maintenant : le jour reste.
    for avant, envie in (({"jour": "2026-10-20"}, True), ({"jour": "2026-10-17", "heure": "20:00"}, True),
                         ({"jour": "2026-10-17", "envie": {"type": "regarder"}}, False)):
        lignes = ["🎬 À regarder"] if envie else []
        nv2, refus2 = t.appliquer({"titre": "Série MobLand", "fait": False, **avant},
                                  ch(notes_a_la_fin=lignes, retirer_jour=True), AUJ, NOW, TAGS)
        assert (nv2 or avant)["jour"] == avant["jour"] and any("retirer_jour" in x for x in refus2)


def test_sortie():
    # Règle T (P9-L1) : un billet devient une sortie datée ; le texte des pièces est montré au modèle.
    v = {"titre": "Billet", "fait": False, "pieces": [{"id": "x", "nom": "billet.pdf", "texte": "Feist · Olympia · 23/10 20h"}]}
    assert t.vue(v)["pieces"] == [{"nom": "billet.pdf", "texte": "Feist · Olympia · 23/10 20h"}]
    nv, refus = t.appliquer(v, ch(jour="2026-10-23", heure="20:00", notes_a_la_fin=["🎟 Sortie"],
                                  envie={"type": "sortie", "note": None, "plateforme": None}), AUJ, NOW, TAGS)
    assert refus == [] and nv["jour"] == "2026-10-23" and nv["heure"] == "20:00"
    assert nv["envie"] == {"type": "sortie"} and nv["notes"].endswith("🎟 Sortie")


def test_message_partage():
    v = {"titre": "Message de Paul", "fait": False, "notes": t.PARTAGE_A_REVOIR + "\nTu peux renvoyer le devis ?"}
    nv, refus = t.appliquer(v, ch(titre="renvoyer le devis à Paul", partage_revu=True), AUJ, NOW, TAGS)
    assert nv["titre"] == "Renvoyer le devis à Paul" and refus == []
    assert nv["notes"] == t.PARTAGE + "\nTu peux renvoyer le devis ?"  # pas de ligne 🎙
    # Titre choisi par Alexandre (ligne 📩 sans « à revoir ») : intouchable.
    nv2, refus2 = t.appliquer(nv, ch(titre="Autre"), AUJ, NOW, TAGS)
    assert nv2 is None and refus2


def test_notes_existantes_intactes():
    notes = "Ligne 1\n📍 Ancien lieu\n🔔 Rappel\nLigne 4"
    v = {"titre": "x", "fait": False, "notes": notes, "categorie": "Perso"}
    nv, refus = t.appliquer(v, ch(notes_a_la_fin=["📍 Nouveau", "🔄 Tous les jours"]), AUJ, NOW, TAGS)
    assert nv["notes"] == notes + "\n🔄 Tous les jours" and refus == ["ligne 📍 déjà présente"]


def test_liste_nouvelle_et_existante():
    v = {"titre": "Courses pour des crêpes", "fait": False}
    nv, _ = t.appliquer(v, ch(liste_nouvelle={"articles": [{"texte": "Farine", "quantite": "250 g",
                                                            "rayon": "placard"}],
                                              "parts": 4, "recette_proposee": "Crêpes"}), AUJ, NOW, TAGS)
    art = nv["liste"]["articles"][0]
    assert art["texte"] == "Farine" and art["coche"] is False and art["source"] == "routine" and art["maj"] == NOW
    assert nv["liste"]["recettes"] == [{"titre": "Crêpes", "a_preparer": False, "proposee": True}] and nv["v"] == 2
    nv2, refus = t.appliquer(nv, ch(liste_nouvelle={"articles": [{"texte": "Lait", "quantite": None,
                                                                  "rayon": "frais"}],
                                                    "parts": None, "recette_proposee": None}), AUJ, NOW, TAGS)
    assert nv2 is None and refus


def test_recette_preparee():
    liste = {"articles": [{"id": "a1", "texte": "Oignons", "quantite": "2", "coche": True, "maj": "avant"}],
             "recettes": [{"titre": "Soupe", "a_preparer": True, "ingredients": ["1 oignon", "1 l d'eau"]},
                          {"titre": "Autre", "a_preparer": False}]}
    v = {"titre": "Courses", "fait": False, "liste": liste}
    nv, refus = t.appliquer(v, ch(recette_preparee={
        "titre": "Soupe", "articles": [{"texte": "Bouillon", "quantite": "1 l", "rayon": "epicerie"}],
        "quantites_ajustees": [{"id": "a1", "quantite": "3"}, {"id": "zz", "quantite": "1"}]}), AUJ, NOW, TAGS)
    articles = nv["liste"]["articles"]
    assert articles[0] == {"id": "a1", "texte": "Oignons", "quantite": "3", "coche": True, "maj": NOW}
    assert articles[1]["texte"] == "Bouillon" and articles[1]["source"] == "recette"
    assert [r["a_preparer"] for r in nv["liste"]["recettes"]] == [False, False] and len(refus) == 1
    assert v["liste"]["articles"][0]["quantite"] == "2"  # l'objet lu n'est pas modifié


def test_cout():
    usage = {"input_tokens": 20_000, "output_tokens": 3_000, "cache_read_input_tokens": 0,
             "cache_creation_input_tokens": 10_000}
    assert abs(t.cout(usage) - (0.04 + 0.03 + 0.025)) < 1e-9


if __name__ == "__main__":
    for nom, f in list(globals().items()):
        if nom.startswith("test_"):
            f()
    print("ok")
