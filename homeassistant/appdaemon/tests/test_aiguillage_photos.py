"""Tests hors Home Assistant de `aiguillage_photos` (photo de produits → articles proposés, P9-R) :
uv run --with pytest python -m pytest -q homeassistant/appdaemon/tests"""

import base64
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import aiguillage_photos as p  # noqa: E402

MAINTENANT = "2026-10-28T14:00:00+01:00"


def tache(articles=(), photos=(), fait=False):
    return {"titre": "Courses", "categorie": "Achats", "fait": fait,
            "pieces": [{"id": "abc", "nom": "Photo.jpg", "type": "image/jpeg", "taille": 1000}],
            "liste": {"articles": [{"id": f"a{i}", "texte": t, "coche": False} for i, t in enumerate(articles)],
                      "photos": list(photos)}}


def test_photos_a_lire():
    v = tache(photos=[{"piece": "abc", "a_lire": True}, {"piece": "def", "lue_le": MAINTENANT}])
    assert [x["piece"] for x in p.photos_a_lire(v)] == ["abc"]
    assert p.photos_a_lire(tache(photos=[{"piece": "abc", "a_lire": True}], fait=True)) == []
    assert p.photos_a_lire({"titre": "Sans liste"}) == []
    assert p.type_de_la_piece(v, "abc") == "image/jpeg" and p.type_de_la_piece(v, "zzz") == "image/jpeg"


def test_contenu_image_puis_texte():
    c = p.contenu(b"\xff\xd8image", "image/jpeg", ["Pain"], note="Leroy Merlin", magasins=["Supermarchés", "Leroy Merlin"])
    assert c[0]["type"] == "image" and c[0]["source"]["media_type"] == "image/jpeg"
    assert base64.b64decode(c[0]["source"]["data"]) == b"\xff\xd8image"
    assert "Pain" in c[1]["text"] and "Note d'Alexandre" in c[1]["text"] and "Magasins possibles : Supermarchés, Leroy Merlin" in c[1]["text"]
    assert "aucun" in p.contenu(b"x", "image/png", [])[1]["text"]


def test_fusion_propose_sans_doublon():
    v = tache(articles=["Lessive liquide Skip"], photos=[{"piece": "abc", "a_lire": True, "ajoute_le": MAINTENANT}])
    lus = [{"texte": "Lessive liquide SKIP", "quantite": None, "rayon": "maison"},   # déjà là (casse, accents)
           {"texte": "Adoucissant Soupline Grand Air", "quantite": None, "rayon": "maison"},
           {"texte": "Désinfectant linge Sanytol", "quantite": "2", "rayon": "inconnu"},
           {"texte": "  ", "quantite": None, "rayon": "autre"}]
    nouvelle, n = p.fusion(v, "abc", lus, MAINTENANT)
    assert n == 2
    ajoutes = nouvelle["liste"]["articles"][1:]
    assert [a["texte"] for a in ajoutes] == ["Adoucissant Soupline Grand Air", "Désinfectant linge Sanytol"]
    assert all(a["propose"] and a["source"] == "photo" and not a["coche"] and a["maj"] == MAINTENANT for a in ajoutes)
    assert ajoutes[1]["quantite"] == "2" and "rayon" not in ajoutes[1] and ajoutes[0]["rayon"] == "maison"
    photo = nouvelle["liste"]["photos"][0]
    assert "a_lire" not in photo and photo["lue_le"] == MAINTENANT and photo["articles"] == 2
    assert v["liste"]["photos"][0]["a_lire"]  # l'entrée n'est pas modifiée sur place


def test_fusion_echec():
    v = tache(photos=[{"piece": "abc", "a_lire": True}])
    nouvelle, n = p.fusion(v, "abc", [], MAINTENANT, echec="image trop lourde")
    assert n == 0 and nouvelle["liste"]["photos"][0] == {"piece": "abc", "echec": "image trop lourde"}


def test_schema_strict():
    item = p.SCHEMA["properties"]["articles"]["items"]
    assert item["additionalProperties"] is False and set(item["required"]) == {"texte", "quantite", "rayon"}
    assert p.SCHEMA["required"] == ["articles", "magasin"]


CLE_A = "0b7c3a5e-1f2d-4c6b-9a8e-112233445566"
CLE_B = "1b7c3a5e-1f2d-4c6b-9a8e-112233445566"


def enr(cle, titre, modifie, **v):
    return {"cle": cle, "modifie_le": modifie, "valeur": {"titre": titre, "categorie": "Achats", "liste": {"articles": []}, **v}}


LIEUX = {"cle": "config:lieux", "valeur": {"groupes": [
    {"id": "supermarches", "nom": "Supermarchés"}, {"id": "lm", "nom": "Leroy Merlin"},
    {"id": "dom", "nom": "Domicile"}, {"id": "pharma", "nom": "Pharmacie"}]}}


def test_type_de_liste_comme_l_app():
    grps = p.groupes([LIEUX])
    assert p.type_de_liste({"titre": "Courses a Leroy merlin"}, grps) == "lm"
    assert p.type_de_liste({"titre": "Courses de la semaine"}, grps) == "supermarches"
    assert p.type_de_liste({"titre": "Achats Ikea"}, grps) == "enseigne:ikea"
    assert p.type_de_liste({"titre": "Courses", "actions": [
        {"type": "rappel_groupe", "etat": "a_faire", "params": {"groupe": "pharma"}}]}, grps) == "pharma"
    assert p.magasins(grps) == ["Supermarchés", "Leroy Merlin", "Pharmacie"]
    assert p.nom_du_type("enseigne:ikea", grps) == "Ikea" and p.nom_du_type("supermarches", grps) == "Supermarchés"


def test_un_seul_type_de_liste_a_la_fois():
    e = [LIEUX, enr(CLE_A, "Courses a Leroy merlin", "2026-10-28T10:00:00Z"),
         enr(CLE_B, "Courses de la semaine", "2026-10-27T09:00:00Z"),
         enr("aaaaaaaa-1f2d-4c6b-9a8e-112233445566", "Finie", "2026-10-28T12:00:00Z", fait=True)]
    # Sans note : la liste Supermarchés, même si la Leroy Merlin est plus récente ; type pas fixé.
    cible, t, fixe = p.liste_cible(e)
    assert cible["cle"] == CLE_B and t == "supermarches" and not fixe
    cible, t, fixe = p.liste_cible(e, "leroy MERLIN")
    assert cible["cle"] == CLE_A and t == "lm" and fixe
    cible, t, fixe = p.liste_cible(e, "Pharmacie")
    assert cible is None and t == "pharma" and fixe
    assert p.nouvelle_liste(t, p.groupes(e))["titre"] == "Courses Pharmacie"
    assert p.nouvelle_liste()["titre"] == "Courses"
    # Après lecture : une gouttière vue sur une photo reçue dans la liste Supermarchés part vers la Leroy Merlin.
    hote = e[2]
    photo = {"piece": "abc", "origine": "signal"}
    vers, t = p.destination(e, hote, photo, "Leroy Merlin")
    assert vers["cle"] == CLE_A and t == "lm"
    assert p.destination(e, hote, photo, "Supermarchés") == (None, None)
    assert p.destination(e, hote, {"piece": "abc", "origine": "fiche"}, "Leroy Merlin") == (None, None)
    assert p.destination(e, hote, {"piece": "abc", "origine": "signal", "type_fixe": True}, "Leroy Merlin") == (None, None)
    vers, t = p.destination(e, hote, photo, "Ikea")
    assert vers is None and t == "enseigne:ikea"


def test_deplacement_de_la_photo():
    v = p.avec_photos(p.nouvelle_liste(), [{"id": "abc", "nom": "IMG.jpg", "type": "image/jpeg", "taille": 9}], MAINTENANT)
    assert v["liste"]["photos"][0]["origine"] == "signal"
    apres = p.sans_piece(v, "abc", CLE_A)
    assert apres["pieces"] == [] and apres["liste"]["photos"] == [
        {"piece": "abc", "ajoute_le": MAINTENANT, "origine": "signal", "deplacee_vers": CLE_A}]
    assert p.photos_a_lire(apres) == []


def test_nouvelle_liste_et_photos():
    v = p.nouvelle_liste()
    assert v["titre"] == "Courses" and v["categorie"] == "Achats" and v["liste"] == {"articles": []}
    piece = {"id": "abc", "nom": "IMG_1.jpg", "type": "image/jpeg", "taille": 1234}
    avec = p.avec_photos(v, [piece], MAINTENANT, note="Pharmacie", type_fixe=True)
    assert avec["pieces"][0]["id"] == "abc" and avec["pieces"][0]["source"] == "signal"
    assert p.photos_a_lire(avec) == [{"piece": "abc", "a_lire": True, "ajoute_le": MAINTENANT, "origine": "signal",
                                      "type_fixe": True, "note": "Pharmacie"}]
    # Même photo envoyée deux fois : une seule pièce, une seule lecture.
    deux = p.avec_photos(avec, [piece], MAINTENANT)
    assert len(deux["pieces"]) == 1 and len(deux["liste"]["photos"]) == 1
