"""Recettes et exécution des actions des tâches (plan P9-D2 et D3). Fonctions pures, testées hors Home Assistant
par `tests/test_aiguillage_actions.py` ; la vigie (`relance_vigie.py`) les appelle.

- **Recettes** (`config:recettes`, clé non UUID ignorée par la routine de tri) : « si la tâche remplit ces
  conditions, lui ajouter cette action ». Conditions (toutes requises) : `envie_type`, `hote` (du lien), `categorie`,
  `tag`, `mot` (dans le titre). Appliquées une seule fois par recette et par tâche : l'identifiant de la recette est
  gardé dans `params.recette` de l'action et dans la liste `recettes` de la tâche (une action retirée par Alexandre
  n'est donc pas remise).
- **Exécution** : actions `executant: "ha"` à l'état `a_faire` et dues (déclencheur `creation`, ou `avant_echeance`
  quand la date est assez proche). Une action faite n'est jamais refaite (`etat`).
"""

from datetime import date, timedelta
import re
import uuid

CLE_RECETTES = "config:recettes"

RECETTES_PAR_DEFAUT = [
    {
        "id": "spotify-playlist",
        "nom": "Envie À écouter avec un lien Spotify → playlist « À écouter »",
        "active": True,
        "si": {"envie_type": "ecouter", "hote": "spotify.com"},
        "alors": {"type": "playlist_spotify", "executant": "ha", "declencheur": {"quand": "creation"},
                  "params": {"playlist": "a_ecouter"}},
    },
    {
        "id": "tva-micro",
        "nom": "TVA de la micro-entreprise → préparer la déclaration 5 jours avant",
        "active": False,
        "si": {"mot": "TVA", "tag": "Micro"},
        "alors": {"type": "preparer", "executant": "routine", "declencheur": {"quand": "avant_echeance", "jours": 5},
                  "params": {"modele": "tva_micro"}},
    },
]

LIGNES_ENVIE = {"🎬 À regarder": "regarder", "🎧 À écouter": "ecouter", "📖 À lire": "lire", "👀 À voir": "voir",
                "🍽 À tester": "resto", "🛍 Magasin": "magasin", "📷 Spot photo": "spot_photo"}


def _lignes(notes):
    return [ligne.replace("️", "").strip() for ligne in (notes or "").split("\n")]


def envie_type(tache):
    envie = tache.get("envie") or {}
    if envie.get("type"):
        return envie["type"]
    for ligne in _lignes(tache.get("notes")):
        for debut, code in LIGNES_ENVIE.items():
            if ligne.startswith(debut):
                return code
    return None


def lien(tache):
    """Lien de la tâche : `envie.lien`, sinon le premier lien des notes."""
    envie = tache.get("envie") or {}
    if envie.get("lien"):
        return envie["lien"]
    m = re.search(r"https?://\S+", tache.get("notes") or "")
    return m.group(0) if m else None


def correspond(recette, tache):
    """La tâche remplit toutes les conditions de la recette (aucune condition : jamais, par prudence)."""
    si = recette.get("si") or {}
    if not si:
        return False
    if "envie_type" in si and envie_type(tache) != si["envie_type"]:
        return False
    if "hote" in si:
        hote = re.sub(r"^https?://([^/]+).*$", r"\1", lien(tache) or "").lower()
        if not hote or si["hote"].lower() not in hote:
            return False
    if "categorie" in si and (tache.get("categorie") or "") != si["categorie"]:
        return False
    if "tag" in si and si["tag"] not in (tache.get("tags") or []):
        return False
    if "mot" in si and si["mot"].casefold() not in (tache.get("titre") or "").casefold():
        return False
    return True


def appliquer_recettes(tache, recettes, maintenant):
    """La tâche avec les actions des recettes actives qu'elle remplit et qui ne lui ont pas encore été appliquées ;
    None si rien ne change (tâche faite comprise)."""
    if tache.get("fait"):
        return None
    deja = set(tache.get("recettes") or []) | {
        (a.get("params") or {}).get("recette") for a in tache.get("actions") or []}
    nouvelles = []
    for r in recettes:
        if not r.get("active") or not r.get("id") or r["id"] in deja or not correspond(r, tache):
            continue
        alors = r.get("alors") or {}
        nouvelles.append({
            "id": str(uuid.uuid4()),
            "type": alors.get("type", "inconnu"),
            "executant": alors.get("executant", "ha"),
            "declencheur": alors.get("declencheur") or {"quand": "creation"},
            "params": {**(alors.get("params") or {}), "recette": r["id"]},
            "etat": "a_faire",
            "maj": maintenant,
        })
    if not nouvelles:
        return None
    tache = dict(tache)
    tache["actions"] = list(tache.get("actions") or []) + nouvelles
    tache["recettes"] = sorted(set(tache.get("recettes") or []) | {a["params"]["recette"] for a in nouvelles})
    tache["v"] = max(tache.get("v", 1), 2)
    return tache


def due(action, tache, today, executant="ha"):
    """L'action est à faire maintenant par cet exécutant."""
    if action.get("executant") != executant or action.get("etat") != "a_faire" or tache.get("fait"):
        return False
    declencheur = action.get("declencheur") or {}
    quand = declencheur.get("quand", "creation")
    if quand == "creation":
        return True
    if quand == "avant_echeance":
        try:
            jour = date.fromisoformat(tache.get("jour") or "")
        except ValueError:
            return False
        return today >= jour - timedelta(days=int(declencheur.get("jours", 0)))
    return False


RAPPEL_MAISON = "rappel_maison"


def rappel_maison_du(action, tache, today):
    """« Me le rappeler à la maison » (P9-F2) : à faire, tâche pas faite, pas encore rappelé aujourd'hui.
    L'action reste « a_faire » : elle rappelle à chaque retour (une fois par jour) jusqu'à ce que la tâche soit faite."""
    if action.get("type") != RAPPEL_MAISON or action.get("etat") != "a_faire" or tache.get("fait"):
        return False
    return (action.get("maj") or "")[:10] != today.isoformat()


RAPPEL_PIECE = "rappel_piece"
CLE_PIECES = "config:pieces"


def rappel_piece_du(action, tache, piece, today):
    """« Me le rappeler dans <pièce> » (P9-F4) : même pièce (sans tenir compte de la casse), à faire, tâche pas
    faite, pas encore rappelé aujourd'hui."""
    if action.get("type") != RAPPEL_PIECE or action.get("etat") != "a_faire" or tache.get("fait"):
        return False
    voulue = ((action.get("params") or {}).get("piece") or "").casefold()
    if not voulue or voulue != (piece or "").casefold():
        return False
    return (action.get("maj") or "")[:10] != today.isoformat()


PIECE_FENETRE = 120
PIECE_PART = 0.7


def piece_dominante(historique, maintenant, fenetre=PIECE_FENETRE, part=PIECE_PART):
    """Pièce occupée au moins `part` du temps des `fenetre` dernières secondes, ou None. `historique` : liste
    chronologique de (instant en secondes, pièce) ; chaque pièce vaut jusqu'au changement suivant. Les relais
    Bermuda font sauter la pièce d'une seconde à l'autre (16/10 : 73 changements en 18 min, assis au salon) :
    on retient la pièce majoritaire plutôt que la dernière. « Absent » et les états inconnus ne comptent jamais."""
    debut = maintenant - fenetre
    durees = {}
    for i, (instant, piece) in enumerate(historique):
        fin = historique[i + 1][0] if i + 1 < len(historique) else maintenant
        d = min(fin, maintenant) - max(instant, debut)
        if d > 0:
            durees[piece] = durees.get(piece, 0) + d
    if not durees:
        return None
    piece, duree = max(durees.items(), key=lambda x: x[1])
    if piece in (None, "", "Absent", "unknown", "unavailable") or duree < part * fenetre:
        return None
    return piece


def marquer_rappel(tache, action_id, maintenant, heure):
    """La tâche avec le rappel noté (« Rappelé le JJ/MM à HH:MM »), l'action restant à faire."""
    jour = maintenant[8:10] + "/" + maintenant[5:7]
    return marquer(tache, action_id, "a_faire", f"Rappelé le {jour} à {heure}", maintenant)


def a_notifier(action, tache):
    """(titre, texte) de la notification visible à envoyer pour cette action, ou None. Échec d'une action de HA ou
    de la routine, et préparation de la routine prête ; une seule fois par état (`notifie`). Les actions de
    l'appareil (ouvrir le lien, sur la TV) ne sont jamais notifiées : Alexandre a vu le résultat à l'écran."""
    etat = action.get("etat")
    if action.get("executant") not in ("ha", "routine") or action.get("notifie") == etat or tache.get("fait"):
        return None
    titre = tache.get("titre") or "Tâche"
    if etat == "echec":
        return f"⚠️ {titre}", f"Action en échec : {action.get('resultat') or action.get('type')}"[:200]
    if etat == "faite" and action.get("executant") == "routine":
        return f"📝 {titre}", "Préparation prête : ouvre la tâche pour la lire."
    return None


def noter_notifie(tache, action_id):
    """La tâche avec l'état actuel de l'action noté comme notifié (`notifie`)."""
    tache = dict(tache)
    tache["actions"] = [{**a, "notifie": a.get("etat")} if a.get("id") == action_id else a
                        for a in tache.get("actions") or []]
    return tache


ROUTINE_DELAI_HEURES = 24


def routine_en_retard(action, maintenant_dt):
    """Action confiée à la routine (`en_cours`) sans réponse depuis plus de 24 h."""
    from datetime import datetime

    if action.get("executant") != "routine" or action.get("etat") != "en_cours" or not action.get("maj"):
        return False
    try:
        depuis = datetime.fromisoformat(action["maj"].replace("Z", "+00:00"))
    except ValueError:
        return True
    return (maintenant_dt - depuis).total_seconds() > ROUTINE_DELAI_HEURES * 3600


def texte_routine(cle, action, tache):
    """Texte de lancement de la routine « Aiguillage · actions » : de quoi retrouver la tâche et l'action.
    Données seulement (la consigne de la routine dit quoi en faire)."""
    params = action.get("params") or {}
    return (f"Action à préparer. Tâche : clé {cle} (« {tache.get('titre', '')} », échéance {tache.get('jour') or 'aucune'}). "
            f"Action : id {action.get('id')}, type {action.get('type')}, modèle {params.get('modele', 'aucun')}.")


def marquer(tache, action_id, etat, resultat, maintenant, envie=None):
    """La tâche avec l'état de l'action mis à jour (et `envie` remplacée si fournie)."""
    tache = dict(tache)
    actions = []
    for a in tache.get("actions") or []:
        if a.get("id") == action_id:
            a = {**a, "etat": etat, "maj": maintenant}
            if resultat:
                a["resultat"] = str(resultat)[:4000]
            else:
                a.pop("resultat", None)
        actions.append(a)
    tache["actions"] = actions
    if envie is not None:
        tache["envie"] = envie
    return tache
