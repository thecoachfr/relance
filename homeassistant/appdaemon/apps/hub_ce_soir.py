"""« Ce soir » du Hub (H46, 28/10/2026) : `sensor.hub_ce_soir`, les films, séries, documentaires et reportages qui
commencent en début de soirée sur les chaînes d'Alexandre, pour le Hub TV et le Hub iPad (le Nest Hub n'a pas de
Vidéo).

- Chaînes : la table `CHAINES` (numéro Free, nom, identifiant OQEE, uuid de la Freebox), filtrée par l'API locale de
  la Freebox (`/api/v8/tv/channels`, sans jeton) : TNT (numéros 1 à 27), chaînes de l'abonnement (`has_abo`) et
  `TOUJOURS` (CANAL+ Box Office, que la Freebox marque hors abonnement alors qu'Alexandre l'a).
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

# Numéro Free, nom affiché, identifiant OQEE, uuid de la Freebox (sans « uuid-webtv- »). Correspondance
# Freebox ↔ OQEE établie le 28/10/2026 en recoupant 24 h des deux guides (titre et début à 15 min près) ; France 2
# et France 3 reprises de `Applis.CHAINES` du Hub TV (relevées en zappant). Chaînes d'info, de sport, de musique et
# de jeunesse laissées de côté. Pour une nouvelle chaîne : même recoupement (voir HUB-CE-SOIR.md).
CHAINES = [
    (1, "TF1", 536, "612"), (2, "France 2", 270, "201"), (3, "France 3", 321, "202"),
    (4, "France 4", 412, "376"), (5, "France 5", 272, "203"), (6, "M6", 537, "613"), (7, "Arte", 273, "204"),
    (8, "LCP", 294, "226"), (9, "W9", 409, "373"), (10, "TMC", 517, "497"), (11, "TFX", 410, "374"),
    (17, "CStar", 558, "678"), (18, "T18", 1304, "1751"), (19, "Novo19", 1333, "1797"),
    (20, "TF1 Séries Films", 843, "993"), (22, "6ter", 845, "995"), (23, "RMC Story", 846, "996"),
    (24, "RMC Découverte", 847, "997"), (25, "RMC Life", 848, "998"), (27, "TV5 Monde", 275, "206"),
    (28, "Paris Première", 282, "213"), (29, "RTL9", 279, "210"),
    (40, "CANAL+", 403, "362"), (45, "CANAL+ Box Office", 1164, "1648"), (46, "CANAL+ Grand Écran", 1079, "1539"),
    (47, "CANAL+ Cinéma(s)", 613, "742"), (48, "CANAL+ Docs", 1078, "1529"),
    (52, "AB1", 280, "211"), (53, "Téva", 433, "404"), (55, "TLC", 1128, "1615"),
    (56, "National Geographic", 28, "1061"), (147, "13ème Rue", 1167, "1655"), (148, "SciFi", 1173, "1656"),
    (149, "Polar+", 247, "1298"), (150, "Novelas+", 249, "1300"), (152, "Série Club", 156, "1205"),
    (511, "Museum TV", 765, "906"), (530, "Comedy Central", 267, "1318"), (546, "Planète+", 128, "1177"),
    (547, "Planète+ Aventure", 140, "1189"), (548, "Planète+ Crime", 139, "1188"), (549, "Comédie+", 130, "1179"),
    (553, "Toute l'Histoire", 314, "250"), (554, "Bravo", 1174, "1657"),
]
TNT_MAX = 27
TOUJOURS = {45}
# Chaînes mises en avant à genre égal (grandes chaînes historiques, Arte et CANAL+) ; ensuite, le plus récent d'abord
# (en attendant les notes de TMDB).
PRIORITAIRES = {1, 2, 3, 5, 6, 7, 40, 45, 46, 47, 48}

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


def mes_chaines(chaines_freebox):
    """Les lignes de `CHAINES` de l'abonnement. `chaines_freebox` : résultat de `/api/v8/tv/channels` (dict par uuid),
    ou None si la Freebox est muette (toute la table est alors gardée)."""
    if not chaines_freebox:
        return list(CHAINES)
    gardees = []
    for numero, nom, oqee, uuid in CHAINES:
        info = chaines_freebox.get(f"uuid-webtv-{uuid}") or {}
        if numero <= TNT_MAX or numero in TOUJOURS or info.get("has_abo"):
            gardees.append((numero, nom, oqee, uuid))
    return gardees


def non_reliees(chaines_freebox, bouquet):
    """Numéros des chaînes de l'abonnement (`has_abo`) absentes de la table, pour le journal."""
    connues = {f"uuid-webtv-{u}" for _, _, _, u in CHAINES}
    numeros = set()
    for c in bouquet or []:
        u = c.get("uuid")
        if c.get("sub_number", 0) == 0 and u not in connues and (chaines_freebox or {}).get(u, {}).get("has_abo"):
            numeros.add(c.get("number"))
    return sorted(n for n in numeros if n is not None)


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


def calculer(bruts, chaines, envies, maintenant, source="oqee"):
    """(état, attributs) de `sensor.hub_ce_soir` (contrat : HUB-CE-SOIR.md)."""
    par_oqee = {oqee: (numero, nom) for numero, nom, oqee, _ in chaines}
    bas, haut = soiree(maintenant)
    instant = maintenant.timestamp()
    retenus, vus = [], set()
    for p in sorted(bruts, key=lambda p: (p["oqee_id"], p["debut"])):
        code = genre(p["categorie"], p["sous_categorie"])
        if code is None or not (bas <= p["debut"] <= haut) or p["duree"] < DUREE_MIN or p["age"] >= 18:
            continue
        if p["debut"] + p["duree"] <= instant:
            continue
        cle = cle_titre(p["titre_brut"])
        if (p["oqee_id"], cle) in vus:  # épisodes à la suite : le premier suffit
            continue
        vus.add((p["oqee_id"], cle))
        numero, nom = par_oqee[p["oqee_id"]]
        titre, episode = titre_propre(p["titre_brut"])
        debut = datetime.fromtimestamp(p["debut"], PARIS)
        fin = datetime.fromtimestamp(p["debut"] + p["duree"], PARIS)
        logo = LOGOS.get(p["oqee_id"])
        retenus.append({
            "titre": titre, "episode": episode, "genre": code, "genre_texte": p["sous_categorie"] or GENRES[code],
            "annee": p["annee"], "chaine": nom, "numero": numero, "oqee_id": p["oqee_id"],
            "logo": f"https://img{logo[0]}.oqee.net/channel_pictures/{logo[1]}/w300" if logo else None,
            "debut": debut.isoformat(timespec="minutes"), "fin": fin.isoformat(timespec="minutes"),
            "heure_texte": heure_texte(debut), "en_cours": p["debut"] <= instant,
            "image": p["image"], "resume": _resume(p["resume"]), "envie": cle in envies,
        })
    prime = datetime.combine(maintenant.date(), PRIME, PARIS).isoformat(timespec="minutes")
    retenus.sort(key=lambda r: (not r["envie"], ORDRE.index(r["genre"]), r["debut"] < prime,
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
    import os

    import httpx

    CORE_API = "http://supervisor/core/api"

    class HubCeSoir(hass.Hass):

        def initialize(self):
            self._espace = self.args.get("espace", "aiguillage")
            self._cache = None  # (jour, source, bruts, chaines)
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
            liste = self._freebox("tv/channels")
            chaines = mes_chaines(liste)
            if liste:
                manquent = non_reliees(liste, self._freebox("tv/bouquets/freeboxtv/channels"))
                if manquent:
                    self.log(f"Ce soir : chaînes de l'abonnement hors table : {manquent}")
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

        def _relire(self, **kwargs):
            self._cache = None
            self._maj()

        def _maj(self, **kwargs):
            maintenant = datetime.now(PARIS)
            try:
                if self._cache is None or self._cache[0] != maintenant.date():
                    source, bruts, chaines = self._guide(maintenant)
                    self._cache = (maintenant.date(), source, bruts, chaines)
                _, source, bruts, chaines = self._cache
                try:
                    lu = self._api("services/donnees_apps/lire", {"espace": self._espace}, reponse=True)
                    envies = titres_envies((lu.get("service_response") or {}).get("enregistrements", []))
                except Exception as exc:  # noqa: BLE001 - sans envies, le tri reste bon
                    self.log(f"Ce soir : envies illisibles ({exc!r})", level="WARNING")
                    envies = set()
                etat, attributs = calculer(bruts, chaines, envies, maintenant, source)
                # Par l'API REST et non `set_state` : AppDaemon retire les valeurs vides des attributs (voir hub_meteo).
                self._api(f"states/{ENTITE}", {"state": etat, "attributes": dict(
                    attributs, friendly_name="Ce soir à la TV", icon="mdi:television-classic")})
            except Exception as exc:  # noqa: BLE001 - le capteur garde sa dernière valeur
                self._cache = None
                self.log(f"Ce soir : calcul impossible ({exc!r})", level="WARNING")
