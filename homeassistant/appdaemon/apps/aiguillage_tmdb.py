"""Disponibilités en France des envies « À regarder » (plan P9-B3), par l'API de TMDB.

Fonctions pures (testées hors Home Assistant par `tests_aiguillage_tmdb.py`) et un petit client. La vigie
(`relance_vigie.py`) s'en sert : pour chaque tâche `envie.type == "regarder"` pas encore vérifiée (ou vérifiée il
y a plus de 7 jours), chercher l'œuvre, puis ses plateformes en France, et l'écrire dans `envie` :

- `tmdb` = {id, type: movie|tv, titre, annee, affiche}
- `dispo_fr` = {abonnement: [...], gratuit: [...], location: [...], achat: [...]}, chaque entrée
  {id, nom, code} (`code` = celui de `envie.plateforme` quand on le connaît : netflix, disney…)
- `dispo_maj` = AAAA-MM-JJ de la vérification

Les disponibilités viennent de JustWatch, que TMDB impose de citer (« Disponibilités : JustWatch » dans l'app).
TMDB ne donne pas de lien direct vers l'app de la plateforme.
"""

from datetime import date
import re
import unicodedata

API = "https://api.themoviedb.org/3"
REFRESH_DAYS = 7
POSTER = "https://image.tmdb.org/t/p/w342"

# Noms de fournisseurs TMDB → codes de `envie.plateforme` (les autres gardent leur nom seul).
PROVIDER_CODES = [
    ("netflix", "netflix"), ("disney", "disney"), ("amazon prime", "prime"), ("prime video", "prime"),
    ("apple tv", "apple_tv"), ("canal", "canal"), ("france.tv", "france_tv"), ("france tv", "france_tv"),
    ("arte", "arte"), ("youtube", "youtube"), ("hbo max", "max"),
]


def _fold(text):
    text = unicodedata.normalize("NFKD", text or "")
    text = "".join(c for c in text if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()


def code_for(provider_name):
    name = (provider_name or "").lower()
    if name == "max":
        return "max"
    return next((code for key, code in PROVIDER_CODES if key in name), None)


PLATFORM_WORDS = r"(netflix|disney\+?|disney plus|apple tv\+?|canal\+?|mycanal|prime video|amazon( prime)?( video)?|youtube|france\.?tv|france tv|arte|max|ocs|paramount\+?)"


def search_query(title):
    """Titre de la tâche → (requête, année). « Dune (2021) » → (« Dune », 2021) ; les autres parenthèses
    (« (saison 2) », « (essai) ») sont retirées, comme le verbe proposé par la routine pour un message partagé
    (« Regarder Haunted Hotel sur Netflix » → « Haunted Hotel », 16/10)."""
    year = None
    m = re.search(r"\((19|20)\d{2}\)", title or "")
    if m:
        year = int(m.group(0)[1:-1])
    query = re.sub(r"\([^)]*\)", " ", title or "")
    query = re.sub(r"^\s*(re)?(regarder|voir|mater)\s+((le|la|les)\s+(film|série|serie|documentaire|saison)s?\s+)?",
                   "", query, flags=re.IGNORECASE)
    query = re.sub(r"\s+en\s+(ligne|streaming)\s*$", "", query, flags=re.IGNORECASE)
    query = re.sub(r"\s+sur\s+" + PLATFORM_WORDS + r"\s*$", "", query, flags=re.IGNORECASE)
    query = re.sub(r"^\s*à regarder\s*$", "", query, flags=re.IGNORECASE)
    return re.sub(r"\s+", " ", query).strip(" -–:"), year


def is_video(valeur):
    """Une vidéo YouTube ou Twitch n'est pas sur TMDB : on ne la cherche pas."""
    envie = valeur.get("envie") or {}
    if envie.get("plateforme") in ("youtube", "twitch", "vimeo"):
        return True
    return re.search(r"(youtube\.com|youtu\.be|twitch\.tv|vimeo\.com)/", valeur.get("notes") or "") is not None


def is_to_watch(valeur):
    """Envie « À regarder » : champ `envie.type`, ou à défaut la ligne `🎬 À regarder` des notes (tâches
    écrites avant le champ `envie`, que l'app n'a pas encore réécrites)."""
    envie = valeur.get("envie")
    if envie:
        return envie.get("type") == "regarder"
    return any(line.replace("\ufe0f", "").strip().startswith("🎬 À regarder")
               for line in (valeur.get("notes") or "").split("\n"))


def needs_lookup(valeur, today):
    """Envie à regarder, à faire, jamais vérifiée (ni marquée ambiguë ou introuvable depuis moins de 7 jours),
    ou dont les disponibilités ont plus de 7 jours."""
    envie = valeur.get("envie") or {}
    if valeur.get("fait") or not is_to_watch(valeur) or is_video(valeur):
        return False
    # Titre changé depuis la dernière recherche (année ajoutée, faute corrigée) : on recherche tout de suite.
    # (Aussi pour une recherche faite avant que le texte cherché soit mémorisé.)
    if ("tmdb" in envie or "tmdb_statut" in envie) and envie.get("tmdb_requete") != search_query(valeur.get("titre", ""))[0]:
        return True
    checked = envie.get("dispo_maj") or envie.get("tmdb_maj")
    if not checked:
        return True
    try:
        return (today - date.fromisoformat(checked)).days >= REFRESH_DAYS
    except ValueError:
        return True


def choose(results, query, year=None):
    """L'œuvre (film ou série) qui correspond, ou None si rien ou plusieurs œuvres plausibles."""
    works = [r for r in results if r.get("media_type") in ("movie", "tv")]
    if year:
        dated = [r for r in works if (r.get("release_date") or r.get("first_air_date") or "")[:4] == str(year)]
        works = dated or works
    wanted = _fold(query)
    exact = [r for r in works if wanted in {_fold(r.get(k)) for k in ("title", "name", "original_title", "original_name")}]
    if len(exact) == 1:
        return exact[0]
    if len(exact) > 1:
        # Homonymes (remake, série et film) : le plus connu seulement s'il domine nettement.
        ranked = sorted(exact, key=lambda r: r.get("popularity") or 0, reverse=True)
        if (ranked[0].get("popularity") or 0) >= 5 * (ranked[1].get("popularity") or 0.001):
            return ranked[0]
        return None
    return works[0] if len(works) == 1 else None


def work_info(result):
    kind = result.get("media_type")
    released = result.get("release_date") or result.get("first_air_date") or ""
    info = {"id": result["id"], "type": kind, "titre": result.get("title") or result.get("name") or ""}
    if released[:4].isdigit():
        info["annee"] = int(released[:4])
    if result.get("poster_path"):
        info["affiche"] = POSTER + result["poster_path"]
    return info


def providers_fr(payload):
    """Réponse de `/{movie|tv}/{id}/watch/providers` → disponibilités en France."""
    fr = (payload.get("results") or {}).get("FR") or {}

    def entries(*keys):
        # Une plateforme par code : « Netflix » et « Netflix Standard with Ads » ne font qu'une (16/10).
        seen, out = set(), []
        for key in keys:
            for p in fr.get(key) or []:
                code = code_for(p.get("provider_name"))
                if p.get("provider_id") in seen or (code and code in seen):
                    continue
                seen.add(p.get("provider_id"))
                entry = {"id": p.get("provider_id"), "nom": p.get("provider_name", "")}
                if code:
                    seen.add(code)
                    entry["code"] = code
                out.append(entry)
        return out

    dispo = {"abonnement": entries("flatrate"), "gratuit": entries("free", "ads"),
             "location": entries("rent"), "achat": entries("buy")}
    return {k: v for k, v in dispo.items() if v}


def with_availability(valeur, info, dispo, today):
    """La tâche avec `tmdb`, `dispo_fr`, `dispo_maj` ; plateforme déduite de l'abonnement si elle manque."""
    valeur = dict(valeur)
    envie = dict(valeur.get("envie") or {"type": "regarder"})
    envie["tmdb"] = info
    envie["tmdb_requete"] = search_query(valeur.get("titre", ""))[0]
    envie["dispo_fr"] = dispo
    envie["dispo_maj"] = today.isoformat()
    envie.pop("tmdb_maj", None)
    envie.pop("tmdb_statut", None)
    if not envie.get("plateforme"):
        codes = [p["code"] for p in dispo.get("abonnement", []) + dispo.get("gratuit", []) if p.get("code")]
        if codes:
            envie["plateforme"] = codes[0]
    valeur["envie"] = envie
    valeur["v"] = max(valeur.get("v", 1), 2)
    return valeur


SUGGESTION = "💡 Suggestion : préciser l'année dans le titre (plusieurs œuvres portent ce nom sur TMDB)"


def with_status(valeur, statut, today):
    """Aucune œuvre (`introuvable`) ou plusieurs (`ambigu`, avec une suggestion une seule fois) : noté pour ne pas
    redemander avant 7 jours."""
    valeur = dict(valeur)
    envie = dict(valeur.get("envie") or {"type": "regarder"})
    envie["tmdb_statut"] = statut
    envie["tmdb_maj"] = today.isoformat()
    envie["tmdb_requete"] = search_query(valeur.get("titre", ""))[0]
    valeur["envie"] = envie
    valeur["v"] = max(valeur.get("v", 1), 2)
    notes = valeur.get("notes") or ""
    if statut == "ambigu" and "préciser l'année" not in notes:
        valeur["notes"] = (notes + "\n" if notes else "") + SUGGESTION
    return valeur


def vue(enregistrement, fait_le):
    """« Vu » sur une envie « À regarder » (Hub TV et Hub iPad, 27/10/2026 ; pendant de « Écouté ») : la tâche cochée
    (même forme que l'app TV, l'iPhone et « Écouté » : `fait`, `fait_le`, le reste recopié tel quel), ou None si
    l'enregistrement n'est pas une envie encore à faire (supprimé, déjà coché, autre tâche) : rien à écrire."""
    valeur = (enregistrement or {}).get("valeur") or {}
    if not valeur or enregistrement.get("supprime") or valeur.get("fait"):
        return None
    if not is_to_watch(valeur) and (valeur.get("envie") or {}).get("type") != "ecouter":
        return None
    return dict(valeur, fait=True, fait_le=fait_le)


class Client:
    """Appels à TMDB avec le jeton d'accès en lecture (v4, en-tête Bearer)."""

    def __init__(self, token, timeout=10):
        self._headers = {"Authorization": f"Bearer {token}", "accept": "application/json"}
        self._timeout = timeout

    def _get(self, path, params=None):
        import httpx  # ici : les fonctions pures se testent sans httpx

        reply = httpx.get(API + path, params=params or {}, headers=self._headers, timeout=self._timeout)
        reply.raise_for_status()
        return reply.json()

    def search(self, query):
        return self._get("/search/multi", {"query": query, "language": "fr-FR", "include_adult": "false"}).get("results", [])

    def providers(self, kind, tmdb_id):
        return self._get(f"/{kind}/{tmdb_id}/watch/providers")

    def lookup(self, title, today):
        """(info, dispo) ; ou ("ambigu"|"introuvable", None)."""
        query, year = search_query(title)
        if not query:
            return "introuvable", None
        results = self.search(query)
        found = choose(results, query, year)
        if found is None:
            return ("ambigu" if any(r.get("media_type") in ("movie", "tv") for r in results) else "introuvable"), None
        info = work_info(found)
        return info, providers_fr(self.providers(info["type"], info["id"]))
