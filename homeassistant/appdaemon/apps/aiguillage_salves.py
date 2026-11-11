"""Salves de réveil de la vigie (push silencieux après une modification dans l'espace `aiguillage`) : à qui les envoyer.

11/11/2026 : l'iPad recevait 35 et 41 pushs les 03 et 04/11 (seuil 30), toutes des salves `modification_ha`, dont
une partie ne changeait rien à ce qu'il affiche. Deux cas sûrs, sans rien deviner de l'affichage :

1. **Rien de visible n'a changé** : l'app ne lit, d'une tâche (clé UUID), que les champs de `CHAMPS_APP` (les mêmes
   que `TacheHA.CodingKeys` dans l'app) ; une écriture qui ne touche que d'autres champs (`recettes`, traces de la
   vigie…) ou réécrit la même valeur ne change rien sur aucun appareil → pas de salve du tout.
2. **Écho** : un appareil n'est pas réveillé pour des modifications qu'il a toutes faites lui-même (`modifie_par`
   = son nom d'émetteur, envoyé par l'app à l'inscription dans le champ `appareil`). Un appareil inscrit sans ce
   champ (ancien build) reçoit tout, comme avant.

Code pur (pas d'AppDaemon) : testé par `tests/test_aiguillage_salves.py`.
"""

import hashlib
import json
import uuid

# Champs d'une tâche lus par l'app (`Shared/HA/TacheHA.swift`, `CodingKeys`). Les autres sont recopiés sans être lus.
CHAMPS_APP = frozenset({
    "v", "titre", "notes", "jour", "heure", "categorie", "priorite", "tags", "relances", "fait", "lieu", "envie",
    "actions", "liste", "duree", "pieces", "contexte", "fait_le", "google_id",
})


def est_tache(cle):
    try:
        uuid.UUID(str(cle))
    except ValueError:
        return False
    return True


def empreinte(enregistrement):
    """Ce que l'app peut afficher d'un enregistrement, en abrégé. Une clé qui n'est pas une tâche : tout compte."""
    if enregistrement.get("supprime") or enregistrement.get("valeur") is None:
        return "supprime"
    valeur = enregistrement["valeur"]
    if est_tache(enregistrement.get("cle")) and isinstance(valeur, dict):
        valeur = {k: v for k, v in valeur.items() if k in CHAMPS_APP}
    texte = json.dumps(valeur, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(texte.encode()).hexdigest()[:16]


def changements_visibles(enregistrements, empreintes):
    """Enregistrements dont l'empreinte a changé ; met `empreintes` (clé → empreinte) à jour.

    Une clé jamais vue compte comme changée (prudence au démarrage de la vigie)."""
    visibles = []
    for r in enregistrements:
        cle = r.get("cle")
        if not cle:
            continue
        e = empreinte(r)
        if empreintes.get(cle) != e:
            visibles.append(r)
        empreintes[cle] = e
    return visibles


def auteur_unique(enregistrements):
    """Le seul émetteur (`modifie_par`) de ces enregistrements, ou None s'ils viennent de plusieurs, ou d'inconnus."""
    auteurs = {r.get("modifie_par") or "" for r in enregistrements}
    if len(auteurs) != 1:
        return None
    return next(iter(auteurs)) or None


def destinataires(jetons, auteur):
    """Les jetons à réveiller : tous, sauf l'appareil auteur de toutes les modifications (écho)."""
    if not auteur:
        return dict(jetons)
    return {j: info for j, info in jetons.items() if (info.get("appareil") or "") != auteur}


def compter_evitee(stats, jour, raison):
    """Salve évitée (`rien_de_visible`) ou envoi évité à un appareil (`echo`), par jour, à côté des salves."""
    jour_stats = stats.setdefault(jour, {"salves": {}, "envois": 0})
    evitees = jour_stats.setdefault("evitees", {})
    evitees[raison] = evitees.get(raison, 0) + 1
