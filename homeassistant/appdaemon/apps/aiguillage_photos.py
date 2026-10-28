"""Photo de produits → articles proposés dans une liste de courses (plan P9-R, 28/10/2026).

Une photo (shampoing, lessive, adoucissant…) arrive dans une liste, par la fiche, le partage ou la Note à moi-même de
Signal : elle est rangée comme pièce jointe de la tâche (`pieces`) et notée à lire dans `liste.photos`
(`{"piece": <sha>, "a_lire": true, "ajoute_le": …, "note": …}`). La vigie envoie l'image à Claude (vision, sortie
structurée), puis ajoute les articles lus, marqués `propose: true` (à valider dans l'app : décision d'Alexandre),
sans doublon avec ce que la liste contient déjà. La photo est ensuite notée lue (`lue_le`, `articles`) ou en échec.

Fonctions pures, testées hors Home Assistant (`tests/test_aiguillage_photos.py`) ; l'appel et l'écriture sont dans
`relance_vigie` (`photos_pass`).
"""

import base64
import re
import unicodedata
import uuid

RAYONS = ("fruits_legumes", "frais", "epicerie", "boissons", "hygiene", "maison", "placard", "autre")
# Taille d'image acceptée par l'API (5 Mo par image, avant base64) ; au-delà, la photo est notée en échec.
TAILLE_MAX = 5 * 1024 * 1024
TYPES_IMAGE = ("image/jpeg", "image/png", "image/webp", "image/gif")

SCHEMA = {
    "type": "object",
    "properties": {
        "articles": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "texte": {"type": "string"},
                    "quantite": {"type": ["string", "null"]},
                    "rayon": {"type": "string", "enum": list(RAYONS)},
                },
                "required": ["texte", "quantite", "rayon"],
                "additionalProperties": False,
            },
        },
    },
    "required": ["articles"],
    "additionalProperties": False,
}

CONSIGNE = """Tu lis une photo prise par Alexandre pour compléter sa liste de courses : des produits à racheter \
(flacons, paquets, boîtes), parfois une étiquette ou une liste manuscrite.

Rends un article par produit visible, en français, court et utile en magasin : le type de produit d'abord, puis la \
marque et la variante si on les lit (« Lessive liquide Skip », « Adoucissant Soupline Grand Air », « Désinfectant \
linge Sanytol »). Traduis les étiquettes étrangères. Ignore les prix, les codes, les cartons, les meubles et tout ce \
qui n'est pas à acheter. Un même produit en plusieurs exemplaires : un seul article, avec la quantité (« 2 »). \
Quantité : seulement si elle se voit (nombre d'exemplaires) ; sinon null.

Rayon, parmi : fruits_legumes, frais, epicerie, boissons, hygiene (corps, soins, pharmacie), maison (lessive, \
entretien, ménage), placard (conserves, pâtes, riz…), autre.

Les articles déjà dans la liste sont donnés : ne les rends pas une seconde fois. Rien de lisible : une liste vide."""


def _normaliser(texte):
    plie = unicodedata.normalize("NFKD", texte or "").encode("ascii", "ignore").decode().lower()
    return " ".join(re.findall(r"[a-z0-9]+", plie))


def photos_a_lire(valeur):
    """Les photos de la liste encore à lire (dans l'ordre d'ajout)."""
    liste = (valeur or {}).get("liste")
    if not isinstance(liste, dict) or valeur.get("fait"):
        return []
    return [p for p in liste.get("photos") or [] if isinstance(p, dict) and p.get("a_lire") and p.get("piece")]


def type_de_la_piece(valeur, piece_id):
    """Type MIME de la pièce jointe (`pieces[].type`), `image/jpeg` par défaut."""
    for p in (valeur or {}).get("pieces") or []:
        if isinstance(p, dict) and p.get("id") == piece_id and p.get("type"):
            return p["type"]
    return "image/jpeg"


def contenu(image, type_mime, deja, note=None):
    """Contenu du message : l'image (base64), puis les articles déjà là et la note éventuelle."""
    texte = "Articles déjà dans la liste : " + (", ".join(deja) if deja else "aucun") + "."
    if note:
        texte += f"\nNote d'Alexandre avec la photo : « {note} »."
    return [
        {"type": "image", "source": {"type": "base64", "media_type": type_mime,
                                     "data": base64.standard_b64encode(image).decode("ascii")}},
        {"type": "text", "text": texte},
    ]


def articles_deja(valeur):
    liste = (valeur or {}).get("liste") or {}
    return [a.get("texte", "") for a in liste.get("articles") or [] if isinstance(a, dict) and a.get("texte")]


def fusion(valeur, piece_id, lus, maintenant, echec=None):
    """La tâche avec les articles lus ajoutés (proposés, sans doublon) et la photo notée lue ou en échec.

    Renvoie (nouvelle valeur, nombre d'articles ajoutés). `maintenant` : horodatage ISO 8601."""
    valeur = dict(valeur)
    liste = dict(valeur.get("liste") or {})
    articles = list(liste.get("articles") or [])
    connus = {_normaliser(a.get("texte")) for a in articles if isinstance(a, dict)}
    ajoutes = 0
    for lu in lus or []:
        texte = (lu.get("texte") or "").strip()
        cle = _normaliser(texte)
        if not cle or cle in connus:
            continue
        connus.add(cle)
        article = {"id": str(uuid.uuid4()), "texte": texte, "coche": False, "maj": maintenant, "source": "photo",
                   "propose": True}
        if lu.get("quantite"):
            article["quantite"] = str(lu["quantite"]).strip()
        if lu.get("rayon") in RAYONS:
            article["rayon"] = lu["rayon"]
        articles.append(article)
        ajoutes += 1
    photos = []
    for p in liste.get("photos") or []:
        if isinstance(p, dict) and p.get("piece") == piece_id and p.get("a_lire"):
            p = {k: v for k, v in p.items() if k != "a_lire"}
            if echec:
                p["echec"] = echec
            else:
                p.update(lue_le=maintenant, articles=ajoutes)
        photos.append(p)
    liste.update(articles=articles, photos=photos)
    valeur["liste"] = liste
    return valeur, ajoutes


# MARK: - Photo reçue hors de l'app (Signal, partage) : la liste visée

CLE_TACHE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.I)


def listes_ouvertes(enregistrements):
    """Listes d'achats en cours (catégorie Achats, liste, pas faite), la plus récemment modifiée d'abord."""
    ouvertes = [e for e in enregistrements or [] if CLE_TACHE.match(e.get("cle", "")) and not e.get("supprime")
                and isinstance(e.get("valeur"), dict) and not e["valeur"].get("fait")
                and e["valeur"].get("categorie") == "Achats" and isinstance(e["valeur"].get("liste"), dict)]
    return sorted(ouvertes, key=lambda e: e.get("modifie_le") or "", reverse=True)


def liste_cible(enregistrements, note=None):
    """La liste qui reçoit la photo (décision d'Alexandre, 28/10 : la plus récente) ; une note qui nomme une liste
    ouverte (« Leroy Merlin ») la désigne. `None` : aucune liste ouverte, en créer une (`nouvelle_liste`)."""
    ouvertes = listes_ouvertes(enregistrements)
    n = _normaliser(note)
    if n:
        for e in ouvertes:
            if n in _normaliser(e["valeur"].get("titre")):
                return e
    return ouvertes[0] if ouvertes else None


def nouvelle_liste(note=None):
    """Une tâche « Courses » (ou le texte envoyé avec la photo), catégorie Achats, liste vide."""
    titre = (note or "").strip()[:120] or "Courses"
    return {"v": 2, "titre": titre, "fait": False, "notes": "", "categorie": "Achats", "liste": {"articles": []}}


def avec_photos(valeur, pieces, maintenant, note=None, source="signal"):
    """La tâche avec ces pièces jointes (`{id, nom, type, taille}` du stockage) et leurs photos à lire."""
    valeur = dict(valeur)
    existantes = list(valeur.get("pieces") or [])
    connues = {p.get("id") for p in existantes if isinstance(p, dict)}
    liste = dict(valeur.get("liste") or {"articles": []})
    photos = list(liste.get("photos") or [])
    for p in pieces:
        if p["id"] not in connues:
            existantes.append({"id": p["id"], "nom": p.get("nom") or "Photo.jpg", "type": p.get("type") or "image/jpeg",
                               "taille": p.get("taille") or 0, "ajoute_le": maintenant, "source": source})
            connues.add(p["id"])
        if not any(isinstance(x, dict) and x.get("piece") == p["id"] for x in photos):
            entree = {"piece": p["id"], "a_lire": True, "ajoute_le": maintenant}
            if note:
                entree["note"] = note
            photos.append(entree)
    liste["photos"] = photos
    valeur.update(pieces=existantes, liste=liste)
    return valeur
