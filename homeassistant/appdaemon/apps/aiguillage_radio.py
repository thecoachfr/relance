"""Radios à ajouter (22/10/2026) : une envie « À écouter » de plateforme `tunein` (« écouter radio Tsugi », rangée
par le tri) est cherchée sur TuneIn par Music Assistant, puis ajoutée à la liste des radios du Hub.

- La liste vit dans `config:radios` (espace aiguillage) : {radios: [{id, nom, uri, image, ajoute_le, tache}]}.
  Elle ne perd jamais une radio seule : la tâche cochée ou supprimée, la station reste. La vigie la recopie dans
  l'état `sensor.aiguillage_radios` (attribut `radios`), que lisent les trois vues du Hub.
- Station trouvée : la tâche est cochée (`fait`, `fait_le`) et `envie.radio` = {uri, nom, image, statut: "ajoutee"}.
- Rien ou plusieurs stations sans nom identique : `envie.radio` = {statut: "introuvable"|"ambigu", maj, requete,
  candidats}, avec une ligne 💡 une seule fois ; nouvel essai après 7 jours ou si le titre change.

Fonctions pures, testées hors Home Assistant par `tests/test_aiguillage_radio.py`.
"""

from datetime import date
import re
import unicodedata

CLE_RADIOS = "config:radios"
ENTITE = "sensor.aiguillage_radios"
REESSAI_JOURS = 7
SUGGESTION = "💡 Suggestion : préciser le nom de la station (TuneIn ne la trouve pas, ou en trouve plusieurs)"


def _plier(texte):
    texte = unicodedata.normalize("NFKD", texte or "")
    texte = "".join(c for c in texte if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]+", " ", texte.lower()).strip()


def est_radio(valeur):
    envie = valeur.get("envie") or {}
    return envie.get("type") == "ecouter" and envie.get("plateforme") == "tunein"


def requete(titre):
    """Titre de la tâche → nom cherché. « Écouter la radio Tsugi » → « radio Tsugi » ; « Rádio Oxigénio
    (portugaise) » → « Rádio Oxigénio »."""
    q = re.sub(r"\([^)]*\)", " ", titre or "")
    q = re.sub(r"^\s*(r?[ée]couter)\s+(la\s+)?", "", q, flags=re.IGNORECASE)
    q = re.sub(r"\s+sur\s+tune\s?in\s*$", "", q, flags=re.IGNORECASE)
    return re.sub(r"\s+", " ", q).strip(" -–:,")


def a_chercher(valeur, aujourdhui):
    """Radio à faire, jamais cherchée, ou sans station trouvée depuis 7 jours, ou dont le titre a changé."""
    if valeur.get("fait") or not est_radio(valeur):
        return False
    radio = (valeur.get("envie") or {}).get("radio") or {}
    if radio.get("statut") == "ajoutee":
        return False
    if not radio.get("maj") or radio.get("requete") != requete(valeur.get("titre", "")):
        return True
    try:
        return (aujourdhui - date.fromisoformat(radio["maj"])).days >= REESSAI_JOURS
    except ValueError:
        return True


def _sans_mot_radio(texte):
    return re.sub(r"\b(radio|radios|fm|webradio)\b", " ", _plier(texte)).split()


def choisir(resultats, cherche):
    """La station qui correspond : nom identique (sans accents ni casse ; « Radio Tsugi » = « Tsugi Radio »), la
    première dans l'ordre de TuneIn si plusieurs portent ce nom ; sinon le seul résultat ; sinon None."""
    stations = [r for r in resultats if r.get("uri")]
    voulu = sorted(_sans_mot_radio(cherche))
    if not voulu:
        return None
    exacts = [r for r in stations if sorted(_sans_mot_radio(r.get("name"))) == voulu]
    if exacts:
        return exacts[0]
    # Nom contenu en entier (« Oxigénio » → « Rádio Oxigénio ») : seulement si une seule station le contient.
    contient = [r for r in stations if set(voulu) <= set(_sans_mot_radio(r.get("name")))]
    if len(contient) == 1:
        return contient[0]
    return stations[0] if len(stations) == 1 else None


def identifiant(uri):
    """`tunein--aPad5vVY://radio/s257284` → `tunein_s257284` (stable, sans l'instance de Music Assistant)."""
    m = re.search(r"/radio/([^/?#]+)$", uri or "")
    fournisseur = (uri or "").split("--")[0].split(":")[0] or "radio"
    return f"{fournisseur}_{m.group(1)}" if m else re.sub(r"[^a-z0-9]+", "_", (uri or "").lower()).strip("_")


def station(resultat):
    out = {"id": identifiant(resultat["uri"]), "nom": resultat.get("name") or "", "uri": resultat["uri"]}
    if resultat.get("image"):
        out["image"] = resultat["image"]
    return out


def avec_station(valeur, st, maintenant):
    """La tâche cochée, avec la station trouvée dans `envie.radio`."""
    valeur = dict(valeur)
    envie = dict(valeur.get("envie") or {})
    envie["radio"] = {k: st[k] for k in ("uri", "nom", "image") if st.get(k)} | {
        "statut": "ajoutee", "maj": maintenant[:10], "requete": requete(valeur.get("titre", ""))}
    valeur["envie"] = envie
    valeur["fait"] = True
    valeur["fait_le"] = maintenant
    valeur["v"] = max(valeur.get("v") or 1, 2)
    return valeur


def avec_statut(valeur, statut, candidats, aujourdhui):
    """Pas de station sûre : noté (avec les 3 premiers candidats) pour ne pas redemander avant 7 jours."""
    valeur = dict(valeur)
    envie = dict(valeur.get("envie") or {})
    envie["radio"] = {"statut": statut, "maj": aujourdhui.isoformat(), "requete": requete(valeur.get("titre", "")),
                      "candidats": [r.get("name") for r in candidats[:3] if r.get("name")]}
    valeur["envie"] = envie
    valeur["v"] = max(valeur.get("v") or 1, 2)
    notes = valeur.get("notes") or ""
    if "préciser le nom de la station" not in notes:
        valeur["notes"] = (notes + "\n" if notes else "") + SUGGESTION
    return valeur


def ajouter(liste, st, cle_tache, maintenant):
    """`config:radios` avec la station en plus (à la fin), ou None si elle y est déjà."""
    radios = list((liste or {}).get("radios") or [])
    if any(r.get("id") == st["id"] for r in radios):
        return None
    radios.append(st | {"ajoute_le": maintenant, "tache": cle_tache})
    return {"radios": radios}


def etat(liste):
    """(état, attributs) de `sensor.aiguillage_radios`."""
    radios = [{k: r[k] for k in ("id", "nom", "uri", "image") if r.get(k)} for r in (liste or {}).get("radios") or []]
    return str(len(radios)), {"radios": radios, "friendly_name": "Aiguillage · radios", "icon": "mdi:radio"}
