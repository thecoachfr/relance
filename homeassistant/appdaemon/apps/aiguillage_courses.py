"""Liste de courses unique (plan P9-U, 04/11/2026) : le magasin porté par chaque article.

Sans dépendance à AppDaemon ; `relance_vigie.py` fait la lecture, l'appel à Claude et l'écriture. Tant que la liste
unique n'existe pas dans HA (clé `CLE_LISTE`), rien ne se passe.

1. **Versement** : une liste d'achats ouverte (recette préparée, photo lue, liste créée à la main) verse ses articles
   dans la liste unique et passe en « Fait » ; les listes datées restent des tâches à part.
2. **Mémoire** (`config:articles`) : le magasin d'un article, gardé par produit. Une correction d'Alexandre
   (un article avec `magasins` sans la marque `magasins_claude`) l'emporte toujours sur un choix de Claude.
3. **Claude** : seuls les articles que la mémoire ne connaît pas lui sont demandés, par groupes de Mes lieux.
"""

from datetime import datetime, timedelta
import json

import aiguillage_photos as photos

CLE_LISTE = "1429ecec-3c3c-44ba-808b-5a68f8f70f19"  # `TacheHA.Liste.idCourses` de l'app
CLE_MEMOIRE = "config:articles"
SUPERMARCHES = photos.SUPERMARCHES
MODELE = "claude-haiku-5-5"
MARQUE_CLAUDE = "magasins_claude"
# Une liste en cours d'écriture n'est pas versée sous les doigts d'Alexandre.
DELAI_VERSEMENT = timedelta(minutes=10)
ARTICLES_PAR_PASSAGE = 40

SCHEMA = {
    "type": "object",
    "properties": {
        "articles": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {"id": {"type": "string"}, "magasins": {"type": "array", "items": {"type": "string"}}},
                "required": ["id", "magasins"],
                "additionalProperties": False,
            },
        },
    },
    "required": ["articles"],
    "additionalProperties": False,
}

CONSIGNE = """Tu ranges des articles d'une liste de courses en France : pour chacun, dans quels magasins on peut \
l'acheter, parmi les magasins donnés (recopie les noms tels quels). Donne tous ceux qui vendent couramment l'article : \
un produit ménager va à la fois en « Supermarchés » et en droguerie si elle existe. « Supermarchés » pour l'alimentation \
et tout ce qui s'y trouve couramment ; un autre magasin seul quand un supermarché ne le vend pas (une gouttière : le \
bricolage). Rends une entrée par article, avec son id."""


def liste_unique(enregistrements):
    """L'enregistrement de la liste unique, ou None tant qu'elle n'existe pas."""
    return next((e for e in enregistrements or [] if e.get("cle") == CLE_LISTE and not e.get("supprime")
                 and isinstance(e.get("valeur"), dict)
                 and ((e["valeur"].get("liste") or {}).get("permanente"))), None)


def groupes_magasins(enregistrements):
    """Les groupes de Mes lieux qui sont des magasins : [(id, nom)], hors domicile et travail."""
    gardes = [(gid, nom) for gid, nom in photos.groupes(enregistrements)
              if photos._normaliser(nom) not in ("domicile", "travail", "maison")]
    return gardes if any(gid == SUPERMARCHES for gid, _ in gardes) else [(SUPERMARCHES, "Supermarchés"), *gardes]


def memoire(enregistrements):
    """(produits connus, version de l'enregistrement) ; version 0 s'il n'existe pas encore."""
    for e in enregistrements or []:
        if e.get("cle") == CLE_MEMOIRE and not e.get("supprime") and isinstance(e.get("valeur"), dict):
            return dict(e["valeur"].get("articles") or {}), e.get("version", 0)
    return {}, 0


def _vieille(enregistrement, maintenant):
    try:
        modifie = datetime.fromisoformat(enregistrement.get("modifie_le") or "")
    except ValueError:
        return True
    return maintenant - modifie >= DELAI_VERSEMENT


def a_verser(enregistrements, maintenant):
    """(listes prêtes, une liste attend-elle encore son délai ?). `maintenant` : datetime avec fuseau."""
    prets, attente = [], False
    for e in photos.listes_ouvertes(enregistrements):
        v, liste = e["valeur"], e["valeur"]["liste"]
        recettes = liste.get("recettes") or []
        if (e["cle"] == CLE_LISTE or liste.get("permanente") or liste.get("versee_le") or v.get("jour")
                or not liste.get("articles") or any(isinstance(r, dict) and r.get("a_preparer") for r in recettes)
                or photos.photos_a_lire(v)):
            continue
        if _vieille(e, maintenant):
            prets.append(e)
        else:
            attente = True
    return prets, attente


def verser(articles, source, ids, maintenant):
    """`articles` de la liste unique, plus ceux à prendre de la tâche `source` (sans doublon de texte). Le magasin de
    la liste d'origine (action, groupe nommé dans le titre) suit l'article."""
    deja = {photos._normaliser(a.get("texte")) for a in articles if isinstance(a, dict) and not a.get("coche")}
    origine = photos.type_de_liste(source, list(ids.items()))
    ajouts = []
    for a in source["liste"].get("articles") or []:
        cle = photos._normaliser(a.get("texte")) if isinstance(a, dict) else ""
        if not cle or a.get("coche") or cle in deja:
            continue
        deja.add(cle)
        article = {**a, "maj": maintenant}
        if origine in ids and origine != SUPERMARCHES and not article.get("magasins"):
            article["magasins"] = [origine]
        ajouts.append(article)
    return [*articles, *ajouts]


def fermee(source, maintenant):
    """La tâche dont les articles sont passés dans la liste unique : « Fait », notée versée (ne repart pas si elle est
    rouverte)."""
    return {**source, "fait": True, "fait_le": maintenant, "liste": {**source["liste"], "versee_le": maintenant}}


def apprendre(articles, memo, ids):
    """Retient les choix faits à la main. Renvoie True si la mémoire a changé."""
    change = False
    for a in articles:
        cle = photos._normaliser(a.get("texte"))
        choix = [m for m in a.get("magasins") or [] if m in ids]
        if cle and choix and not a.get(MARQUE_CLAUDE) and memo.get(cle) != {"magasins": choix, "par": "alexandre"}:
            memo[cle] = {"magasins": choix, "par": "alexandre"}
            change = True
    return change


def classer_par_memoire(articles, memo, ids, maintenant):
    """(articles, à demander à Claude) : les articles à prendre sans magasin reçoivent celui de la mémoire."""
    resultat, a_demander = [], []
    for a in articles:
        if a.get("coche") or a.get("magasins"):
            resultat.append(a)
            continue
        connu = [m for m in (memo.get(photos._normaliser(a.get("texte"))) or {}).get("magasins") or [] if m in ids]
        if connu:
            a = {**a, "magasins": connu, MARQUE_CLAUDE: True, "maj": maintenant}
        else:
            a_demander.append(a)
        resultat.append(a)
    return resultat, a_demander[:ARTICLES_PAR_PASSAGE]


def question(a_demander, noms):
    """Le message pour Claude : les magasins possibles et les articles."""
    lignes = [json.dumps({k: a[k] for k in ("id", "texte", "rayon") if a.get(k)}, ensure_ascii=False) for a in a_demander]
    return "Magasins possibles : " + ", ".join(noms) + ".\nArticles :\n" + "\n".join(lignes)


def appliquer_reponse(articles, reponse, ids, memo, maintenant):
    """Les articles avec le choix de Claude. Une réponse hors de la liste vaut Supermarchés et n'est pas retenue."""
    par_nom = {photos._normaliser(nom): gid for gid, nom in ids.items()}
    choix = {r.get("id"): r.get("magasins") or [] for r in (reponse or {}).get("articles") or [] if isinstance(r, dict)}
    resultat = []
    for a in articles:
        if a.get("id") in choix and not a.get("coche") and not a.get("magasins"):
            valides = list(dict.fromkeys(par_nom[n] for n in map(photos._normaliser, choix[a["id"]]) if n in par_nom))
            cle = photos._normaliser(a.get("texte"))
            if valides and cle not in memo:
                memo[cle] = {"magasins": valides, "par": "claude"}
            a = {**a, "magasins": valides or [SUPERMARCHES], MARQUE_CLAUDE: True, "maj": maintenant}
        resultat.append(a)
    return resultat
