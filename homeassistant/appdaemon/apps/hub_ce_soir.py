"""« Ce soir » du Hub (H46, 28/10/2026) : `sensor.hub_ce_soir`, les films, séries, documentaires et reportages qui
commencent en début de soirée sur les chaînes d'Alexandre, pour le Hub TV et le Hub iPad (le Nest Hub n'a pas de
Vidéo).

- Chaînes : la table `CHAINES` (numéro Free, nom, identifiant OQEE, uuid de la Freebox), liste fixe des chaînes
  d'Alexandre (validée par lui le 28/10/2026). Pas de filtre par la Freebox : son `has_abo` dit « chaîne payante »,
  pas « dans l'abonnement » (CANAL+ Cinéma(s) marquée oui, CANAL+ Box Office non : l'inverse de la réalité).
- Notes IMDb (28/10/2026, demande d'Alexandre) : identifiant IMDb trouvé par TMDB (titre français et année, jeton
  de la vigie `/config/tmdb_token`, résultat gardé dans `/config/hub_ce_soir_imdb.json`), note lue dans le fichier
  quotidien d'IMDb `title.ratings.tsv.gz` (gratuit, usage personnel ; copie du jour dans `/config/imdb_ratings.tsv.gz`).
  Films, séries et téléfilms seulement ; une note n'est montrée qu'avec au moins `VOTES_MIN` votes.
- Programme : le guide d'OQEE (`api.oqee.net/api/v1/epg/all/<heure>`, sans compte, non officiel), dont les clés sont
  les identifiants de chaîne qu'ouvre le Hub TV. Repli : le guide de la Freebox (`/api/v8/tv/epg/by_time/<heure>`),
  moins riche (ni sous-genre ni année).

Contrat : `homeassistant/HUB-CE-SOIR.md` ; cadrage : `hub-tv/docs/CE-SOIR.md`. Fonctions pures, testées hors Home
Assistant par `tests/test_hub_ce_soir.py` ; l'app AppDaemon est en fin de fichier.
"""

import re
import unicodedata
from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo

PARIS = ZoneInfo("Europe/Paris")
ENTITE = "sensor.hub_ce_soir"
OQEE_EPG = "https://api.oqee.net/api/v1/epg/all/{}"
FREEBOX = "http://mafreebox.freebox.fr"

# Fenêtre du début de soirée : un programme compte s'il commence entre ces deux heures.
DEBUT_MIN = time(20, 40)
DEBUT_MAX = time(21, 20)
PRIME = time(20, 50)  # avant : courts programmes d'avant-soirée (sitcoms, feuilletons), mis après à genre égal
DUREE_MIN = 20 * 60  # écarte les pastilles (« Scènes de ménages », météo…)
MAX_PROGRAMMES = 12
RESUME_MAX = 220
HAUTEUR_IMAGE = 480
VOTES_MIN = 100
IMDB_NOTES = "https://datasets.imdbws.com/title.ratings.tsv.gz"
TMDB = "https://api.themoviedb.org/3"
A_NOTER = ("film", "serie", "telefilm")

# Numéro Free, nom affiché, identifiant OQEE, uuid de la Freebox (sans « uuid-webtv- »). Correspondance
# Freebox ↔ OQEE établie le 28/10/2026 en recoupant 24 h des deux guides (titre et début à 15 min près) ; France 2
# et France 3 reprises de `Applis.CHAINES` du Hub TV (relevées en zappant). Chaînes d'info, de sport, de musique et
# de jeunesse laissées de côté ; CANAL+ : seulement les options d'Alexandre (40, 45, 46). Pour une nouvelle chaîne :
# même recoupement (voir HUB-CE-SOIR.md).
CHAINES = [
    (1, "TF1", 536, "612"), (2, "France 2", 270, "201"), (3, "France 3", 321, "202"),
    (4, "France 4", 412, "376"), (5, "France 5", 272, "203"), (6, "M6", 537, "613"), (7, "Arte", 273, "204"),
    (8, "LCP", 294, "226"), (9, "W9", 409, "373"), (10, "TMC", 517, "497"), (11, "TFX", 410, "374"),
    (17, "CStar", 558, "678"), (18, "T18", 1304, "1751"), (19, "Novo19", 1333, "1797"),
    (20, "TF1 Séries Films", 843, "993"), (22, "6ter", 845, "995"), (23, "RMC Story", 846, "996"),
    (24, "RMC Découverte", 847, "997"), (25, "RMC Life", 848, "998"), (27, "TV5 Monde", 275, "206"),
    (28, "Paris Première", 282, "213"), (29, "RTL9", 279, "210"),
    (40, "CANAL+", 403, "362"), (45, "CANAL+ Box Office", 1164, "1648"), (46, "CANAL+ Grand Écran", 1079, "1539"),
    (52, "AB1", 280, "211"), (53, "Téva", 433, "404"), (55, "TLC", 1128, "1615"),
    (56, "National Geographic", 28, "1061"), (147, "13ème Rue", 1167, "1655"), (148, "SciFi", 1173, "1656"),
    (149, "Polar+", 247, "1298"), (150, "Novelas+", 249, "1300"), (152, "Série Club", 156, "1205"),
    (511, "Museum TV", 765, "906"), (530, "Comedy Central", 267, "1318"), (546, "Planète+", 128, "1177"),
    (547, "Planète+ Aventure", 140, "1189"), (548, "Planète+ Crime", 139, "1188"), (549, "Comédie+", 130, "1179"),
    (553, "Toute l'Histoire", 314, "250"), (554, "Bravo", 1174, "1657"),
]
# Chaînes mises en avant à genre égal (grandes chaînes historiques, Arte et CANAL+) ; ensuite, le plus récent d'abord
# (en attendant les notes de TMDB).
PRIORITAIRES = {1, 2, 3, 5, 6, 7, 40, 45, 46}

# Logos d'OQEE connus (ceux de `Applis.CHAINES` du Hub TV) : img<serveur>.oqee.net/channel_pictures/<image>/w300.
LOGOS = {536: (2, 789), 270: (2, 1045), 321: (2, 2073), 272: (1, 790), 537: (2, 2515), 273: (2, 2513),
         517: (2, 797), 294: (1, 3978), 412: (1, 1050), 1164: (2, 3109), 1079: (1, 3086)}

GENRES = {"film": "Film", "documentaire": "Documentaire", "reportage": "Reportage", "serie": "Série",
          "telefilm": "Téléfilm"}
ORDRE = ["film", "documentaire", "reportage", "serie", "telefilm"]
# Places par famille de genres, pour qu'un soir chargé en films laisse voir séries et documentaires.
QUOTAS = {"film": 6, "documentaire": 3, "reportage": 3, "serie": 3, "telefilm": 2}
FAMILLE = {"reportage": "documentaire"}
EXCLUS = ("pornographique", "érotique", "animation", "dessin animé", "jeunesse", "marionnettes", "téléréalité",
          "féerique", "charme")


def _sans_accents(texte):
    return "".join(c for c in unicodedata.normalize("NFKD", texte or "") if not unicodedata.combining(c))


def cle_titre(titre):
    """Titre réduit pour comparer : minuscules, sans accents ni ponctuation, sans « - S03E06 »."""
    t = re.sub(r"\s*-\s*s\d+\s*e\d+.*$", "", (titre or "").strip(), flags=re.I)
    return re.sub(r"[^a-z0-9]", "", _sans_accents(t).lower())


def titre_propre(titre):
    """« Tracker - S03E06 » → (« Tracker », « S3 · É6 ») ; sinon (titre, None)."""
    m = re.match(r"^(.*?)\s*-\s*S(\d+)\s*E(\d+)\s*$", (titre or "").strip(), flags=re.I)
    if not m:
        return (titre or "").strip(), None
    return m.group(1).strip(), f"S{int(m.group(2))} · É{int(m.group(3))}"


def genre(categorie, sous_categorie):
    """Code du genre gardé (film, documentaire, reportage, serie, telefilm) ou None."""
    cat = (categorie or "").strip().lower()
    sous = (sous_categorie or "").strip().lower()
    if any(mot in sous or mot in cat for mot in EXCLUS):
        return None
    if cat == "film":
        return "film"
    if cat == "documentaire":
        return "documentaire"
    if cat == "série":
        return "serie"
    if cat == "téléfilm":
        return "telefilm"
    if cat == "magazine" and sous in ("magazine de reportages", "magazine d'investigation"):
        return "reportage"
    return None


def heure_texte(d):
    return f"{d.hour} h" + (f" {d.minute:02d}" if d.minute else "")


def _image(gabarit):
    return gabarit.replace("%d", str(HAUTEUR_IMAGE)) if gabarit else None


def _resume(texte):
    texte = re.sub(r"\s+", " ", texte or "").strip()
    if len(texte) <= RESUME_MAX:
        return texte or None
    coupe = texte[:RESUME_MAX].rsplit(" ", 1)[0]
    return coupe.rstrip(",;:.") + "…"


def programmes_oqee(entrees, chaines):
    """Programmes bruts du guide d'OQEE (`result.entries`) pour `chaines`, au format commun."""
    par_oqee = {oqee: (numero, nom) for numero, nom, oqee, _ in chaines}
    sortie = []
    for cle, liste in (entrees or {}).items():
        try:
            oqee = int(cle)
        except ValueError:
            continue
        if oqee not in par_oqee:
            continue
        for p in liste or []:
            l = p.get("live") or {}
            if not l.get("title") or l.get("start") is None:
                continue
            images = p.get("pictures") or {}
            sortie.append({
                "oqee_id": oqee, "titre_brut": l["title"], "categorie": l.get("category"),
                "sous_categorie": l.get("sub_category"), "annee": l.get("year"), "debut": int(l["start"]),
                "duree": int(l.get("duration_seconds") or (l.get("end", l["start"]) - l["start"])),
                "resume": l.get("description"), "image": _image(images.get("main") or images.get("huge")),
                "age": l.get("parental_rating") or 0,
            })
    return sortie


def programmes_freebox(epg, chaines):
    """Repli : guide de la Freebox (`/api/v8/tv/epg/by_time`, dict par uuid puis par programme)."""
    par_uuid = {f"uuid-webtv-{u}": oqee for _, _, oqee, u in chaines}
    sortie = []
    for uuid, liste in (epg or {}).items():
        if uuid not in par_uuid:
            continue
        for p in (liste or {}).values():
            if not p.get("title") or p.get("date") is None:
                continue
            image = p.get("picture_big") or p.get("picture")
            sortie.append({
                "oqee_id": par_uuid[uuid], "titre_brut": p["title"], "categorie": p.get("category_name"),
                "sous_categorie": None, "annee": None, "debut": int(p["date"]), "duree": int(p.get("duration") or 0),
                "resume": p.get("desc"), "image": f"{FREEBOX}{image}" if image else None, "age": 0,
            })
    return sortie


def titres_envies(enregistrements):
    """Clés de titre des envies « À regarder » pas encore vues (espace `aiguillage` de `donnees_apps`)."""
    cles = set()
    for e in enregistrements or []:
        v = e.get("valeur") or {}
        envie = v.get("envie") or {}
        if envie.get("type") != "regarder" or v.get("fait"):
            continue
        for t in (v.get("titre"), (envie.get("tmdb") or {}).get("titre")):
            if cle_titre(t):
                cles.add(cle_titre(t))
    return cles


def soiree(maintenant):
    """Bornes (début min, début max) du début de soirée du jour de `maintenant`, en secondes."""
    jour = maintenant.date()
    bas = datetime.combine(jour, DEBUT_MIN, PARIS).timestamp()
    haut = datetime.combine(jour, DEBUT_MAX, PARIS).timestamp()
    return bas, haut


def candidats(bruts, maintenant):
    """Programmes bruts gardés par le filtre (genre, fenêtre, durée, âge), sans doublon d'épisodes à la suite, avec leur
    code de genre et leur clé de titre : [(programme, genre, cle)]. Les programmes finis restent (voir `calculer`)."""
    bas, haut = soiree(maintenant)
    gardes, vus = [], set()
    for p in sorted(bruts, key=lambda p: (p["oqee_id"], p["debut"])):
        code = genre(p["categorie"], p["sous_categorie"])
        if code is None or not (bas <= p["debut"] <= haut) or p["duree"] < DUREE_MIN or p["age"] >= 18:
            continue
        cle = cle_titre(p["titre_brut"])
        if (p["oqee_id"], cle) in vus:  # épisodes à la suite : le premier suffit
            continue
        vus.add((p["oqee_id"], cle))
        gardes.append((p, code, cle))
    return gardes


def a_noter(bruts, maintenant):
    """Ce qu'il faut chercher sur TMDB / IMDb : {(genre, titre propre, année)} des films, séries et téléfilms gardés."""
    return {(code, titre_propre(p["titre_brut"])[0], p["annee"]) for p, code, _ in candidats(bruts, maintenant) if code in A_NOTER}


def cle_note(code, titre, annee):
    """Clé du cache des identifiants IMDb : l'année ne compte pas pour une série (OQEE donne celle de l'épisode)."""
    return f"{'serie' if code == 'serie' else 'film'}|{cle_titre(titre)}|{'' if code == 'serie' else annee or ''}"


def _annee(resultat):
    d = resultat.get("release_date") or resultat.get("first_air_date") or ""
    return int(d[:4]) if d[:4].isdigit() else None


def choisir_tmdb(resultats, titre, annee, serie):
    """L'identifiant TMDB du bon résultat, ou None : titre (français ou original) identique à la clé près ; pour un
    film, année à un an près si on la connaît (OQEE donne parfois l'année de production)."""
    cle = cle_titre(titre)
    for r in resultats or []:
        noms = (r.get("name"), r.get("original_name")) if serie else (r.get("title"), r.get("original_title"))
        if cle not in {cle_titre(n) for n in noms if n}:
            continue
        if not serie and annee and _annee(r) and abs(_annee(r) - annee) > 1:
            continue
        return r.get("id")
    return None


def lire_notes(lignes, ids):
    """{imdb_id: (note, votes)} pour `ids`, depuis les lignes de `title.ratings.tsv` (tconst, averageRating, numVotes)."""
    notes = {}
    for ligne in lignes:
        tconst, _, reste = ligne.partition("\t")
        if tconst in ids:
            note, _, votes = reste.strip().partition("\t")
            try:
                notes[tconst] = (float(note), int(votes))
            except ValueError:
                continue
            if len(notes) == len(ids):
                break
    return notes


def calculer(bruts, chaines, envies, maintenant, source="oqee", notes=None):
    """(état, attributs) de `sensor.hub_ce_soir` (contrat : HUB-CE-SOIR.md). `notes` : {cle_note: (imdb_id, note,
    votes)} (absent : pas de note)."""
    par_oqee = {oqee: (numero, nom) for numero, nom, oqee, _ in chaines}
    instant = maintenant.timestamp()
    notes = notes or {}
    retenus = []
    for p, code, cle in candidats(bruts, maintenant):
        if p["debut"] + p["duree"] <= instant or p["oqee_id"] not in par_oqee:
            continue
        numero, nom = par_oqee[p["oqee_id"]]
        titre, episode = titre_propre(p["titre_brut"])
        debut = datetime.fromtimestamp(p["debut"], PARIS)
        fin = datetime.fromtimestamp(p["debut"] + p["duree"], PARIS)
        logo = LOGOS.get(p["oqee_id"])
        imdb_id, note, votes = notes.get(cle_note(code, titre, p["annee"])) or (None, None, None)
        if note is not None and (votes or 0) < VOTES_MIN:
            note = None
        retenus.append({
            "titre": titre, "episode": episode, "genre": code, "genre_texte": p["sous_categorie"] or GENRES[code],
            "annee": p["annee"], "chaine": nom, "numero": numero, "oqee_id": p["oqee_id"],
            "logo": f"https://img{logo[0]}.oqee.net/channel_pictures/{logo[1]}/w300" if logo else None,
            "debut": debut.isoformat(timespec="minutes"), "fin": fin.isoformat(timespec="minutes"),
            "heure_texte": heure_texte(debut), "en_cours": p["debut"] <= instant,
            "image": p["image"], "resume": _resume(p["resume"]), "envie": cle in envies,
            "imdb_id": imdb_id, "note_imdb": note, "note_texte": f"{note:.1f}".replace(".", ",") if note is not None else None,
        })
    prime = datetime.combine(maintenant.date(), PRIME, PARIS).isoformat(timespec="minutes")
    # À genre égal : le vrai début de soirée, puis la note IMDb (sans note : après), puis grandes chaînes, puis le plus récent.
    retenus.sort(key=lambda r: (not r["envie"], ORDRE.index(r["genre"]), r["debut"] < prime, -(r["note_imdb"] or 0),
                                r["numero"] not in PRIORITAIRES, -(r["annee"] or 0), r["debut"], r["numero"]))
    places, gardes = dict(QUOTAS), []
    for r in retenus:
        famille = FAMILLE.get(r["genre"], r["genre"])
        if r["envie"] or places[famille] > 0:  # une envie passe toujours
            places[famille] -= 1
            gardes.append(r)
    retenus = gardes[:MAX_PROGRAMMES]
    return len(retenus), {
        "maj": maintenant.isoformat(timespec="seconds"),
        "soiree": maintenant.date().isoformat(),
        "source": source,
        "programmes": retenus,
    }


def heure_du_guide(maintenant):
    """L'heure ronde de 21 h du jour : le guide d'OQEE y donne ce qui passe à 21 h et ce qui commence avant 22 h,
    donc tout ce qui commence entre 20 h 40 et 21 h 20 (hors pastilles de moins de 20 min)."""
    return int(datetime.combine(maintenant.date(), time(21, 0), PARIS).timestamp())


# MARK: - App AppDaemon

try:
    import hassapi as hass
except ImportError:  # pragma: no cover
    hass = None

if hass is not None:
    import gzip
    import json
    import os
    import time as horloge
    from pathlib import Path

    import httpx

    CORE_API = "http://supervisor/core/api"

    class HubCeSoir(hass.Hass):

        def initialize(self):
            self._espace = self.args.get("espace", "aiguillage")
            self._cache = None  # (jour, source, bruts, chaines, notes)
            self._jeton_tmdb = Path(self.args.get("tmdb_token_file", "/config/tmdb_token"))
            self._ids_imdb = Path(self.args.get("imdb_ids_file", "/config/hub_ce_soir_imdb.json"))
            self._fichier_notes = Path(self.args.get("imdb_ratings_file", "/config/imdb_ratings.tsv.gz"))
            # Toutes les 15 min : « en cours » et les programmes finis ; le guide n'est relu que de temps en temps.
            self.run_every(self._maj, "now+10", int(self.args.get("refresh_seconds", 900)))
            for h in self.args.get("relectures", ["06:00", "17:00", "20:15"]):
                hh, mm = (int(x) for x in str(h).split(":"))
                self.run_daily(self._relire, time(hh, mm, 0))

        def _api(self, chemin, donnees, reponse=False):
            url = f"{CORE_API}/{chemin}" + ("?return_response" if reponse else "")
            reply = httpx.post(url, json=donnees, timeout=15,
                               headers={"Authorization": f"Bearer {os.environ['SUPERVISOR_TOKEN']}"})
            reply.raise_for_status()
            return reply.json() if reponse else None

        def _freebox(self, chemin):
            try:
                r = httpx.get(f"{FREEBOX}/api/v8/{chemin}", timeout=15)
                r.raise_for_status()
                return r.json().get("result")
            except Exception as exc:  # noqa: BLE001
                self.log(f"Ce soir : Freebox muette ({chemin}, {exc!r})", level="WARNING")
                return None

        def _guide(self, maintenant):
            """(source, bruts, chaines) : OQEE, sinon la Freebox."""
            chaines = list(CHAINES)
            heure = heure_du_guide(maintenant)
            try:
                r = httpx.get(OQEE_EPG.format(heure), timeout=30)
                r.raise_for_status()
                bruts = programmes_oqee(r.json()["result"]["entries"], chaines)
                if bruts:
                    return "oqee", bruts, chaines
            except Exception as exc:  # noqa: BLE001
                self.log(f"Ce soir : guide d'OQEE illisible ({exc!r}), repli sur la Freebox", level="WARNING")
            return "freebox", programmes_freebox(self._freebox(f"tv/epg/by_time/{heure}"), chaines), chaines

        def _imdb_id(self, entetes, code, titre, annee):
            """Identifiant IMDb par TMDB (recherche en français, puis `external_ids`), ou "" si introuvable."""
            serie = code == "serie"
            genre_tmdb = "tv" if serie else "movie"
            r = httpx.get(f"{TMDB}/search/{genre_tmdb}", headers=entetes, timeout=10,
                          params={"query": titre, "language": "fr-FR", "include_adult": "false"})
            r.raise_for_status()
            tmdb_id = choisir_tmdb(r.json().get("results"), titre, annee, serie)
            if tmdb_id is None:
                return ""
            r = httpx.get(f"{TMDB}/{genre_tmdb}/{tmdb_id}/external_ids", headers=entetes, timeout=10)
            r.raise_for_status()
            return r.json().get("imdb_id") or ""

        def _notes(self, bruts, maintenant):
            """{cle_note: (imdb_id, note, votes)} pour les films, séries et téléfilms de la soirée ; {} si TMDB ou IMDb manque."""
            try:
                jeton = self._jeton_tmdb.read_text().strip()
            except OSError:
                self.log(f"Ce soir : pas de jeton TMDB dans {self._jeton_tmdb}, pas de notes IMDb", level="WARNING")
                return {}
            entetes = {"Authorization": f"Bearer {jeton}", "accept": "application/json"}
            try:
                ids = json.loads(self._ids_imdb.read_text())
            except (OSError, ValueError):
                ids = {}
            nouveaux = 0
            for code, titre, annee in a_noter(bruts, maintenant):
                cle = cle_note(code, titre, annee)
                if cle in ids:
                    continue
                try:
                    ids[cle] = self._imdb_id(entetes, code, titre, annee)
                    nouveaux += 1
                except Exception as exc:  # noqa: BLE001 - réessayé à la prochaine relecture
                    self.log(f"Ce soir : TMDB muet pour « {titre} » ({exc!r})", level="WARNING")
            if nouveaux:
                self._ids_imdb.write_text(json.dumps(ids, ensure_ascii=False, indent=0))
            # Fichier des notes d'IMDb : retéléchargé s'il a plus de 20 h (publié chaque jour vers 2 h).
            try:
                if not self._fichier_notes.exists() or horloge.time() - self._fichier_notes.stat().st_mtime > 20 * 3600:
                    r = httpx.get(IMDB_NOTES, timeout=60, follow_redirects=True)
                    r.raise_for_status()
                    provisoire = self._fichier_notes.with_suffix(".part")
                    provisoire.write_bytes(r.content)
                    provisoire.replace(self._fichier_notes)
            except Exception as exc:  # noqa: BLE001 - l'ancienne copie sert encore
                self.log(f"Ce soir : notes d'IMDb pas mises à jour ({exc!r})", level="WARNING")
            voulus = {i for i in ids.values() if i}
            if not voulus or not self._fichier_notes.exists():
                return {}
            with gzip.open(self._fichier_notes, "rt", encoding="utf-8") as f:
                lues = lire_notes(f, voulus)
            self.log(f"Ce soir : {len(lues)} notes IMDb ({nouveaux} titres cherchés sur TMDB)")
            return {cle: (i, *lues[i]) for cle, i in ids.items() if i in lues}

        def _relire(self, **kwargs):
            self._cache = None
            self._maj()

        def _maj(self, **kwargs):
            maintenant = datetime.now(PARIS)
            try:
                if self._cache is None or self._cache[0] != maintenant.date():
                    source, bruts, chaines = self._guide(maintenant)
                    try:
                        notes = self._notes(bruts, maintenant)
                    except Exception as exc:  # noqa: BLE001 - sans notes, le tri reste bon
                        self.log(f"Ce soir : notes IMDb impossibles ({exc!r})", level="WARNING")
                        notes = {}
                    self._cache = (maintenant.date(), source, bruts, chaines, notes)
                _, source, bruts, chaines, notes = self._cache
                try:
                    lu = self._api("services/donnees_apps/lire", {"espace": self._espace}, reponse=True)
                    envies = titres_envies((lu.get("service_response") or {}).get("enregistrements", []))
                except Exception as exc:  # noqa: BLE001 - sans envies, le tri reste bon
                    self.log(f"Ce soir : envies illisibles ({exc!r})", level="WARNING")
                    envies = set()
                etat, attributs = calculer(bruts, chaines, envies, maintenant, source, notes)
                # Par l'API REST et non `set_state` : AppDaemon retire les valeurs vides des attributs (voir hub_meteo).
                self._api(f"states/{ENTITE}", {"state": etat, "attributes": dict(
                    attributs, friendly_name="Ce soir à la TV", icon="mdi:television-classic")})
            except Exception as exc:  # noqa: BLE001 - le capteur garde sa dernière valeur
                self._cache = None
                self.log(f"Ce soir : calcul impossible ({exc!r})", level="WARNING")
