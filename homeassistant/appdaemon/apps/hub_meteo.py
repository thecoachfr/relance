"""Météo du Hub (24/10/2026) : `sensor.hub_meteo`, la météo commune des trois vues (Hub TV, Hub iPad/iPhone, Nest Hub).

Les vues ne font qu'afficher ce capteur : tout le calcul est ici. Contrat : `homeassistant/HUB-METEO.md`.

- **Maintenant** : la mesure de la terrasse (Sonoff, la référence), sauf si elle prend le soleil (plus de 2,5 °C
  au-dessus du jardin ou du quartier : le plus bas des deux, le capteur à l'ombre). Capteur indisponible ou figé
  (pas de changement depuis 2 h) : le suivant (terrasse, jardin, quartier Netatmo).
- **Recalage** : écart = mesure − prévision Météo-France interpolée à maintenant, ajouté aux heures suivantes avec
  une décroissance exponentielle (constante 4 h, ramenée à zéro à 8 h).
- **Dans l'heure** : `1_hour_forecast` de `sensor.alfortville_next_rain` ramené à 12 cases de 5 min.
- **Pastille, phrase, jours, vigilance** : règles simples ci-dessous.
- **Apprentissage** : chaque heure, une ligne dans `/config/hub_meteo_releves.jsonl` (prévisions MF à +1, +3, +6,
  +12, +24 h et mesure retenue, 60 jours). Pas encore de correction appliquée.

Fonctions pures, testées hors Home Assistant par `tests/test_hub_meteo.py` ; l'app AppDaemon est en fin de fichier.
"""

from datetime import datetime, timedelta
import json
import math
from zoneinfo import ZoneInfo

PARIS = ZoneInfo("Europe/Paris")
ENTITE = "sensor.hub_meteo"

# Capteurs de mesure, dans l'ordre de préférence (nom publié dans `source`).
TERRASSE = "sensor.thermometre_terrasse_temperature"
JARDIN = "sensor.thermometre_exterieur_cote_jardin_temperature"
QUARTIER = "sensor.alfortville_temperature_2"
MESURES = (("terrasse", TERRASSE), ("jardin", JARDIN), ("quartier", QUARTIER))
METEO = "weather.alfortville"
PLUIE_HEURE = "sensor.alfortville_next_rain"
VIGILANCE = "sensor.94_weather_alert"

SOLEIL_ECART = 2.5            # °C : au-delà, le capteur prend le soleil
FIGE = timedelta(hours=2)     # pas de changement depuis 2 h : capteur figé
RECALAGE_CONSTANTE_H = 4.0
RECALAGE_FIN_H = 8.0
NB_HEURES = 24
NB_JOURS = 3
PAS_MIN = 5
NB_CASES = 12
FORTE_MM = 2.0                # mm/h : pluie forte
SEUIL_PLUIE = 0.2             # mm/h : en dessous, une trace qui ne coupe pas une période sèche (phrase)
AVERSES_MM = 2.0              # mm/jour : en dessous, une journée pluvieuse en plusieurs fois = « averses »
RAFALES_ALERTE = 50           # km/h
HORIZONS_H = (1, 3, 6, 12, 24)
GARDE_JOURS = 60

NIVEAUX = {"temps sec": 0, "pluie faible": 1, "pluie modérée": 2, "pluie moderee": 2, "pluie forte": 3}
LIBELLES_NIVEAU = {1: "Pluie faible", 2: "Pluie modérée", 3: "Pluie forte"}
CONDITIONS_PLUIE = {"rainy", "pouring", "lightning-rainy", "snowy-rainy", "hail"}
LIBELLES = {
    "clear-night": "Nuit claire", "cloudy": "Nuageux", "exceptional": "Exceptionnel", "fog": "Brouillard",
    "hail": "Grêle", "lightning": "Orages", "lightning-rainy": "Orages et pluie", "partlycloudy": "Éclaircies",
    "pouring": "Pluie forte", "rainy": "Pluie", "snowy": "Neige", "snowy-rainy": "Pluie et neige",
    "sunny": "Ensoleillé", "windy": "Venteux", "windy-variant": "Venteux et nuageux",
}
DIRECTIONS = ("nord", "nord-est", "est", "sud-est", "sud", "sud-ouest", "ouest", "nord-ouest")
JOURS_NOMS = ("Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche")
COULEURS = ("Vert", "Jaune", "Orange", "Rouge")
# Attributs de `sensor.94_weather_alert` qui ne sont pas des risques.
HORS_RISQUES = {"attribution", "icon", "friendly_name"}
# Moments de la journée (heure locale de début → mot), pour la phrase et le résumé des jours.
PERIODES = ((0, "nuit"), (6, "matin"), (12, "midi"), (14, "après-midi"), (18, "soir"))


# MARK: - Outils

def nombre(valeur):
    """Un nombre fini, ou None (« unavailable », « unknown », vide, texte)."""
    if isinstance(valeur, bool) or valeur is None:
        return None
    try:
        x = float(valeur)
    except (TypeError, ValueError):
        return None
    return x if math.isfinite(x) else None


def entier(x):
    """Arrondi à l'entier le plus proche (0,5 vers le haut, pas l'arrondi bancaire de Python)."""
    return None if x is None else int(math.floor(x + 0.5))


def un_dec(x):
    return None if x is None else math.floor(x * 10 + 0.5) / 10


def instant(texte):
    """Datetime avec fuseau, ramené à l'heure de Paris ; None si illisible."""
    if isinstance(texte, datetime):
        d = texte
    else:
        try:
            d = datetime.fromisoformat(str(texte).replace("Z", "+00:00"))
        except ValueError:
            return None
    if d.tzinfo is None:
        d = d.replace(tzinfo=PARIS)
    return d.astimezone(PARIS)


def iso(d):
    return d.astimezone(PARIS).replace(microsecond=0).isoformat()


def heure_fr(d, maintenant=None):
    """« 9 h 25 », « 15 h », « 0 h 10 » ; « demain 6 h » si ce n'est pas le même jour que `maintenant`."""
    d = d.astimezone(PARIS)
    texte = f"{d.hour} h" if d.minute == 0 else f"{d.hour} h {d.minute:02d}"
    if maintenant is not None:
        ecart = (d.date() - maintenant.astimezone(PARIS).date()).days
        if ecart == 1:
            texte = "demain " + texte
        elif ecart > 1:
            texte = f"{JOURS_NOMS[d.weekday()].lower()} {texte}"
    return texte


def periode(heure):
    nom = PERIODES[0][1]
    for debut, mot in PERIODES:
        if heure >= debut:
            nom = mot
    return nom


def moment(d, maintenant):
    """« le matin », « à midi », « l'après-midi », « en soirée », « dans la nuit » ; « demain matin »… le lendemain."""
    d = d.astimezone(PARIS)
    p = periode(d.hour)
    ecart = (d.date() - maintenant.astimezone(PARIS).date()).days
    if ecart <= 0 or p == "nuit" and ecart == 1:
        return {"nuit": "dans la nuit", "matin": "le matin", "midi": "à midi", "après-midi": "l'après-midi",
                "soir": "en soirée"}[p]
    prefixe = "demain" if ecart == 1 else JOURS_NOMS[d.weekday()].lower()
    return f"{prefixe} {'nuit' if p == 'nuit' else p}"


def direction(degres):
    x = nombre(degres)
    if x is None:
        return None
    return DIRECTIONS[int(math.floor((x % 360) / 45 + 0.5)) % 8]


# MARK: - Mesure

def choisir_mesure(etats, maintenant):
    """(température, source) d'après les trois capteurs ; (None, None) si aucun n'est utilisable.

    `etats` : entity_id → état HA ({state, last_changed}). Un capteur est utilisable s'il donne un nombre qui a changé
    depuis moins de 2 h. Le premier utilisable (terrasse, jardin, quartier) est retenu, sauf s'il dépasse de plus de
    2,5 °C l'un des autres utilisables (il prend le soleil) : alors le plus bas des autres.
    """
    utilisables = []
    for nom, entite in MESURES:
        etat = etats.get(entite) or {}
        valeur = nombre(etat.get("state"))
        change = instant(etat.get("last_changed") or etat.get("last_updated") or "")
        if valeur is None or change is None or maintenant - change > FIGE:
            continue
        utilisables.append((nom, valeur))
    if not utilisables:
        return None, None
    nom, valeur = utilisables[0]
    autres = utilisables[1:]
    if any(valeur - v > SOLEIL_ECART for _, v in autres):
        nom, valeur = min(autres, key=lambda a: a[1])
    return valeur, nom


# MARK: - Prévisions horaires et recalage

def points_mf(previsions):
    """[(instant, température)] triés, d'après les prévisions horaires (`weather.get_forecasts`)."""
    points = []
    for p in previsions or []:
        t, temp = instant(p.get("datetime")), nombre(p.get("temperature"))
        if t is not None and temp is not None:
            points.append((t, temp))
    return sorted(points)


def prevision_a(points, t):
    """Température MF interpolée (linéaire) à l'instant `t` ; None hors de la plage des points."""
    if not points or t < points[0][0] or t > points[-1][0]:
        return None
    for (t1, v1), (t2, v2) in zip(points, points[1:]):
        if t1 <= t <= t2:
            if t2 == t1:
                return v1
            return v1 + (v2 - v1) * (t - t1).total_seconds() / (t2 - t1).total_seconds()
    return points[-1][1]


def poids_recalage(heures):
    """Part de l'écart gardée après `heures` : exp(−h/4) ramenée à 0 à 8 h, sans saut (1 à 0 h, 0 dès 8 h)."""
    if heures <= 0:
        return 1.0
    if heures >= RECALAGE_FIN_H:
        return 0.0
    fin = math.exp(-RECALAGE_FIN_H / RECALAGE_CONSTANTE_H)
    return (math.exp(-heures / RECALAGE_CONSTANTE_H) - fin) / (1 - fin)


def pluvieux(entree):
    """L'heure (ou le pas de 3-6 h) est-elle pluvieuse ? La quantité fait foi quand MF la donne."""
    mm = nombre(entree.get("precipitation"))
    if mm is not None:
        return mm > 0
    return entree.get("condition") in CONDITIONS_PLUIE


def heures(previsions, maintenant, ecart):
    """Les 24 heures suivantes, températures recalées sur la mesure (écart décroissant)."""
    resultat = []
    for p in sorted(previsions or [], key=lambda p: str(p.get("datetime"))):
        t = instant(p.get("datetime"))
        mf = nombre(p.get("temperature"))
        if t is None or t <= maintenant:
            continue
        recalee = mf
        if mf is not None and ecart is not None:
            recalee = mf + ecart * poids_recalage((t - maintenant).total_seconds() / 3600)
        resultat.append({
            "heure": iso(t),
            "condition": p.get("condition"),
            "temperature": un_dec(recalee),
            "temperature_mf": un_dec(mf),
            "pluie_mm": un_dec(nombre(p.get("precipitation")) or 0.0),
            "vent_kmh": entier(nombre(p.get("wind_speed")) or 0.0),
            "rafales_kmh": entier(nombre(p.get("wind_gust_speed")) or 0.0),
        })
        if len(resultat) == NB_HEURES:
            break
    return resultat


# MARK: - Dans l'heure

def dans_l_heure(attributs):
    """{debut, pas_min, niveaux} : les clés irrégulières de `1_hour_forecast` (« 0 min » … « 55 min ») ramenées à
    12 cases de 5 min, chaque case prenant la dernière valeur connue ; None si Météo-France ne donne rien."""
    attributs = attributs or {}
    brut = attributs.get("1_hour_forecast")
    debut = instant(attributs.get("forecast_time_ref") or "")
    if not isinstance(brut, dict) or debut is None:
        return None
    connus = {}
    for cle, texte in brut.items():
        try:
            minute = int(str(cle).split()[0])
        except (ValueError, IndexError):
            continue
        niveau = NIVEAUX.get(str(texte).strip().lower())
        if niveau is not None:
            connus[minute] = niveau
    if not connus:
        return None
    niveaux, dernier = [], connus[min(connus)]
    for i in range(NB_CASES):
        dernier = connus.get(i * PAS_MIN, dernier)
        niveaux.append(dernier)
    return {"debut": iso(debut), "pas_min": PAS_MIN, "niveaux": niveaux}


def _cases_restantes(heure, maintenant):
    """(début, index de la case en cours, niveaux) ; None si rien ou si la fenêtre est passée."""
    if not heure:
        return None
    debut = instant(heure["debut"])
    niveaux = heure["niveaux"]
    i0 = max(0, int((maintenant - debut).total_seconds() // (PAS_MIN * 60)))
    if i0 >= len(niveaux):
        return None
    return debut, i0, niveaux


def _fin_averse(niveaux, i):
    """(index de fin, index de reprise) de la pluie qui tombe à la case `i` : la fin est la première accalmie d'au
    moins deux cases (10 min), ou qui va jusqu'au bout de l'heure (une case sèche isolée ne compte pas) ; la reprise
    est la case où la pluie revient plus loin dans l'heure. (None, None) si elle ne s'arrête pas dans l'heure."""
    n = len(niveaux)
    for j in range(i + 1, n):
        if niveaux[j] == 0 and (j + 1 == n or niveaux[j + 1] == 0):
            return j, next((k for k in range(j + 1, n) if niveaux[k] > 0), None)
    return None, None


def episode_heure(heure, maintenant):
    """Lecture de l'heure à venir : None (sec ou rien), ou un dict
    {type: "jusqu" | "toute" | "dans", fin, retour, arrivee, minutes, forte}.

    - « jusqu » : il pleut maintenant et ça s'arrête dans l'heure, à `fin` (voir `_fin_averse`) ; `retour` = l'heure
      où la pluie reprend plus loin dans l'heure, ou None.
    - « toute » : il pleut maintenant et toute l'heure.
    - « dans » : sec maintenant, la pluie arrive dans `minutes` (multiple de 5, au moins 5), à `arrivee` ; `fin` et
      `retour` comme pour « jusqu » (None si l'averse dure jusqu'au bout de l'heure).
    `forte` : une case « Pluie forte » dans l'averse.
    """
    lu = _cases_restantes(heure, maintenant)
    if lu is None:
        return None
    debut, i0, niveaux = lu
    pas = timedelta(minutes=PAS_MIN)

    def quand(k):
        return None if k is None else debut + k * pas

    if niveaux[i0] > 0:
        j, r = _fin_averse(niveaux, i0)
        if j is None:
            return {"type": "toute", "forte": 3 in niveaux[i0:]}
        return {"type": "jusqu", "fin": quand(j), "retour": quand(r), "forte": 3 in niveaux[i0:j]}
    a = next((k for k in range(i0 + 1, len(niveaux)) if niveaux[k] > 0), None)
    if a is None:
        return None
    j, r = _fin_averse(niveaux, a)
    minutes = (quand(a) - maintenant).total_seconds() / 60
    minutes = max(PAS_MIN, int(math.ceil(minutes / PAS_MIN - 1e-9)) * PAS_MIN)
    return {"type": "dans", "arrivee": quand(a), "minutes": minutes, "fin": quand(j), "retour": quand(r),
            "forte": 3 in niveaux[a:j]}


def pastille(heure, maintenant):
    """Texte court de l'en-tête des trois vues, ou None s'il ne pleut pas dans l'heure."""
    e = episode_heure(heure, maintenant)
    if e is None:
        return None
    pluie = "Pluie forte" if e["forte"] else "Pluie"
    if e["type"] == "jusqu":
        return f"{pluie} jusqu'à {heure_fr(e['fin'])}"
    if e["type"] == "toute":
        return f"{pluie} toute l'heure"
    return f"{pluie} dans {e['minutes']} min"


# MARK: - Phrase

def _apres(liste, t):
    """Les heures dont plus de la moitié tombe après `t` (la fenêtre minute par minute fait foi avant)."""
    return [h for h in liste if instant(h["heure"]) + timedelta(minutes=30) > t]


def phrase(heure, liste_heures, maintenant):
    """Segments [{texte, ton}] : la pluie dans l'heure d'abord, puis la prochaine bascule sec / pluie sur 24 h,
    la pluie forte (≥ 2 mm/h) et les rafales (≥ 50 km/h, en alerte)."""
    segments = []

    def ajoute(texte, ton="normal"):
        if segments and segments[-1]["ton"] == ton:
            segments[-1]["texte"] += texte
        else:
            segments.append({"texte": texte, "ton": ton})

    e = episode_heure(heure, maintenant)
    lu = _cases_restantes(heure, maintenant)
    if not liste_heures:
        # Prévisions horaires illisibles : seulement ce que dit l'heure à venir (rien si elle ne dit rien non plus).
        if e is None:
            return [{"texte": "Pas de pluie dans l'heure.", "ton": "normal"}] if lu else []
        return [{"texte": pastille(heure, maintenant), "ton": "pluie"}, {"texte": ".", "ton": "normal"}]
    fin_fenetre = (instant(heure["debut"]) + timedelta(minutes=PAS_MIN * NB_CASES)) if lu else maintenant

    if e is None:
        suite = _apres(liste_heures, fin_fenetre if lu else maintenant)
        r = next((h for h in suite if h["pluie_mm"] >= SEUIL_PLUIE), None)
        if r is None:
            ajoute("Pas de pluie prévue dans les 24 h")
        else:
            t = instant(r["heure"])
            ajoute(f"Sec pour l'instant. La pluie arrive {quand_reprise(t, maintenant)}")
            _forte(ajoute, _apres(liste_heures, t), maintenant, t)
    elif e["type"] == "jusqu" or e["type"] == "dans" and e["fin"] is not None:
        if e["type"] == "jusqu":
            ajoute(f"Pluie{' forte' if e['forte'] else ''} jusqu'à {heure_fr(e['fin'])}", "pluie")
        else:
            ajoute(f"Pluie{' forte' if e['forte'] else ''} dans {e['minutes']} min", "pluie")
            ajoute(f", jusqu'à {heure_fr(e['fin'])}")
        if e["retour"] is not None:
            t = e["retour"]
        else:
            r = next((h for h in _apres(liste_heures, fin_fenetre) if h["pluie_mm"] >= SEUIL_PLUIE), None)
            t = instant(r["heure"]) if r else None
        if t is None:
            ajoute(", puis sec pour les prochaines 24 h")
        else:
            ajoute(f", puis sec. La pluie revient {quand_reprise(t, maintenant)}")
            _forte(ajoute, _apres(liste_heures, t), maintenant, t)
    else:
        if e["type"] == "toute":
            ajoute(f"Pluie{' forte' if e['forte'] else ''} toute l'heure", "pluie")
        else:
            ajoute(f"Pluie{' forte' if e['forte'] else ''} dans {e['minutes']} min", "pluie")
        suite = _apres(liste_heures, fin_fenetre)
        s = next((h for h in suite if h["pluie_mm"] < SEUIL_PLUIE), None)
        if s is None:
            ajoute(", pour les prochaines 24 h")
        else:
            ajoute(f", jusqu'à {heure_fr(instant(s['heure']), maintenant)}")
        if not e["forte"]:
            _forte(ajoute, [h for h in liste_heures if s is None or instant(h["heure"]) < instant(s["heure"])],
                   maintenant, None)

    rafale = max(liste_heures, key=lambda h: h["rafales_kmh"], default=None)
    if rafale and rafale["rafales_kmh"] >= RAFALES_ALERTE:
        ajoute(" ; ")
        ajoute(f"rafales à {rafale['rafales_kmh']} km/h vers {heure_fr(instant(rafale['heure']), maintenant)}",
               "alerte")
    ajoute(".")
    return segments


def quand_reprise(t, maintenant):
    """Quand la pluie reprend : l'heure le jour même (« vers 17 h »), le moment un autre jour (« demain matin »)."""
    if t.astimezone(PARIS).date() == maintenant.astimezone(PARIS).date():
        return f"vers {heure_fr(t)}"
    return moment(t, maintenant)


def _forte(ajoute, liste, maintenant, debut):
    """« , forte en soirée » : première heure à au moins 2 mm dans l'épisode de pluie qui commence à `liste[0]`
    (jusqu'à la prochaine heure sous 0,2 mm). Le moment est une période (« en soirée ») ; « vers 21 h » si c'est la
    même période que le début de la pluie, « forte » seule si c'est la même heure."""
    for h in liste:
        if h["pluie_mm"] < SEUIL_PLUIE and debut is not None:
            return
        if h["pluie_mm"] >= FORTE_MM:
            t = instant(h["heure"])
            quand = " " + moment(t, maintenant)
            if debut is not None and t == debut:
                quand = ""
            elif debut is not None and moment(t, maintenant) == moment(debut, maintenant):
                quand = f" vers {heure_fr(t, maintenant)}"
            ajoute(", ")
            ajoute(f"forte{quand}", "pluie")
            return


# MARK: - Jours

def _pluie_par_heure(previsions, jour):
    """Heures locales (0-23) du jour `jour` couvertes par une prévision pluvieuse (pas d'1, 3 ou 6 h)."""
    entrees = sorted(((instant(p.get("datetime")), p) for p in previsions or [] if instant(p.get("datetime"))),
                     key=lambda e: e[0])
    pluie = set()
    for i, (t, p) in enumerate(entrees):
        suivant = entrees[i + 1][0] if i + 1 < len(entrees) else t + timedelta(hours=1)
        pas = min(max(suivant - t, timedelta(hours=1)), timedelta(hours=6))
        if not pluvieux(p):
            continue
        h = t
        while h < t + pas:
            if h.date() == jour:
                pluie.add(h.hour)
            h += timedelta(hours=1)
    return pluie


def resume_jour(heures_pluie, cumul_mm=None):
    """Court (20 caractères au plus, une seule période, coupé sinon sur la TV) : « sec », « pluie le matin »,
    « pluie à midi », « pluie l'après-midi », « pluie le soir », « pluie la nuit » (seulement si c'est la seule pluie
    du jour) ; deux périodes ou plus : « pluie toute la journée », ou « averses » si le cumul du jour est sous 2 mm."""
    mots = {"nuit": "la nuit", "matin": "le matin", "midi": "à midi", "après-midi": "l'après-midi", "soir": "le soir"}
    moments = [p for _, p in PERIODES if any(periode(h) == p for h in heures_pluie)]
    jour = [p for p in moments if p != "nuit"] or moments
    if not jour:
        return "sec"
    if len(jour) == 1:
        return "pluie " + mots[jour[0]]
    if cumul_mm is not None and cumul_mm < AVERSES_MM:
        return "averses"
    return "pluie toute la journée"


def _cumul_jour(quotidienne, horaires, jour):
    """Pluie du jour en mm : celle de la prévision du jour de MF, sinon la somme des heures si elles la donnent toutes."""
    cumul = nombre((quotidienne or {}).get("precipitation"))
    if cumul is not None:
        return cumul
    du_jour = [p for p in horaires or [] if (t := instant(p.get("datetime"))) and t.date() == jour]
    valeurs = [nombre(p.get("precipitation")) for p in du_jour]
    return sum(valeurs) if du_jour and None not in valeurs else None


def jours(horaires, quotidiennes, maintenant, nb=NB_JOURS):
    """Demain et les jours suivants : min et max entiers (prévision du jour de MF, sinon les heures), condition
    dominante (celle du jour de MF, sinon la plus fréquente de 6 h à 21 h), résumé de la pluie."""
    par_jour = {}
    for p in quotidiennes or []:
        t = instant(p.get("datetime"))
        if t is not None:
            par_jour[t.date()] = p
    resultat = []
    aujourd_hui = maintenant.astimezone(PARIS).date()
    for k in range(1, nb + 1):
        jour = aujourd_hui + timedelta(days=k)
        q = par_jour.get(jour, {})
        du_jour = [p for p in horaires or [] if (t := instant(p.get("datetime"))) and t.date() == jour]
        temps = [x for p in du_jour if (x := nombre(p.get("temperature"))) is not None]
        bas = nombre(q.get("templow"))
        haut = nombre(q.get("temperature"))
        bas = bas if bas is not None else (min(temps) if temps else None)
        haut = haut if haut is not None else (max(temps) if temps else None)
        condition = q.get("condition")
        if not condition:
            jour_ = [p.get("condition") for p in du_jour if 6 <= instant(p.get("datetime")).hour <= 21]
            condition = max(set(jour_), key=jour_.count) if jour_ else None
        resultat.append({
            "date": jour.isoformat(),
            "nom": JOURS_NOMS[jour.weekday()],
            "condition": condition,
            "min": entier(bas),
            "max": entier(haut),
            "resume": resume_jour(_pluie_par_heure(horaires, jour), _cumul_jour(q, horaires, jour)),
        })
    return resultat


# MARK: - Vigilance et maintenant

def vigilance(etat):
    """{couleur, risques} : couleur de `sensor.94_weather_alert` (Vert si inconnue), risques non verts."""
    etat = etat or {}
    couleur = etat.get("state") if etat.get("state") in COULEURS else "Vert"
    risques = [cle for cle, val in (etat.get("attributes") or {}).items()
               if cle not in HORS_RISQUES and val in COULEURS and val != "Vert"]
    return {"couleur": couleur, "risques": risques}


def bloc_maintenant(meteo, temperature, source, ecart, heure, instant_):
    """Bloc `maintenant` : mesure, ressenti recalé du même écart, condition et libellé (la pluie de la case en cours
    l'emporte : « Pluie faible / modérée / forte »), vent, rafales, humidité."""
    meteo = meteo or {}
    a = meteo.get("attributes") or {}
    condition = meteo.get("state") if meteo.get("state") not in (None, "unavailable", "unknown") else None
    libelle = LIBELLES.get(condition) if condition else None
    lu = _cases_restantes(heure, instant_)
    if lu is not None:
        niveau = lu[2][lu[1]]
        if niveau > 0:
            libelle = LIBELLES_NIVEAU[niveau]
            if condition not in CONDITIONS_PLUIE or niveau == 3:
                condition = "pouring" if niveau == 3 else "rainy"
    ressenti = nombre(a.get("apparent_temperature"))
    if ressenti is not None and ecart is not None:
        ressenti += ecart
    elif ressenti is None:
        ressenti = temperature
    rafales = entier(nombre(a.get("wind_gust_speed")))
    return {
        "temperature": un_dec(temperature),
        "source": source,
        "ressenti": entier(ressenti),
        "condition": condition,
        "libelle": libelle,
        "vent_kmh": entier(nombre(a.get("wind_speed"))),
        "vent_dir": direction(a.get("wind_bearing")),
        "rafales_kmh": rafales if rafales else None,
        "humidite": entier(nombre(a.get("humidity"))),
    }


def mf_maintenant(points, meteo, instant_):
    """Prévision MF à l'instant : interpolée entre les points horaires ; avant le premier point (les prévisions
    commencent à l'heure suivante), entre la température actuelle de `weather.alfortville` (à son `last_updated`)
    et le premier point."""
    a = (meteo or {}).get("attributes") or {}
    actuelle = nombre(a.get("temperature"))
    t_actuelle = instant((meteo or {}).get("last_updated") or "")
    tous = list(points)
    if actuelle is not None and t_actuelle is not None and (not tous or t_actuelle < tous[0][0]):
        tous = sorted(tous + [(min(t_actuelle, instant_), actuelle)])
    valeur = prevision_a(tous, instant_)
    if valeur is None and actuelle is not None:
        valeur = actuelle
    return valeur


# MARK: - Calcul complet

def calculer(etats, horaires, quotidiennes, instant_, passe=()):
    """(état, attributs) de `sensor.hub_meteo`, d'après les états HA (`etats`, entity_id → état), les prévisions
    horaires et quotidiennes de `weather.get_forecasts` et l'instant du calcul. `passe` : points horaires déjà
    passés gardés du calcul précédent (pour interpoler à maintenant)."""
    temperature, source = choisir_mesure(etats, instant_)
    meteo = etats.get(METEO)
    points = sorted(set(points_mf(horaires)) | set(passe))
    mf = mf_maintenant(points, meteo, instant_)
    ecart = temperature - mf if temperature is not None and mf is not None else None
    heure = dans_l_heure((etats.get(PLUIE_HEURE) or {}).get("attributes"))
    liste = heures(horaires, instant_, ecart)
    attributs = {
        "maj": iso(instant_),
        "maintenant": bloc_maintenant(meteo, temperature, source, ecart, heure, instant_),
        "dans_l_heure": heure,
        "pastille": pastille(heure, instant_),
        "phrase": phrase(heure, liste, instant_),
        "heures": liste,
        "jours": jours(horaires, quotidiennes, instant_),
        "vigilance": vigilance(etats.get(VIGILANCE)),
    }
    etat = f"{un_dec(temperature):.1f}" if temperature is not None else "unavailable"
    return etat, attributs


# MARK: - Apprentissage (préparé le 24/10, pas encore appliqué)

def releve(points, temperature, source, mf, instant_):
    """Ligne du journal d'apprentissage : mesure retenue, prévision MF à maintenant, et prévisions MF faites
    maintenant pour +1, +3, +6, +12 et +24 h (clés « 1 », « 3 »…)."""
    t = instant_.replace(minute=0, second=0, microsecond=0)
    return {
        "t": iso(t),
        "mesure": un_dec(temperature),
        "source": source,
        "mf": un_dec(mf),
        "prev": {str(h): un_dec(prevision_a(points, t + timedelta(hours=h))) for h in HORIZONS_H},
    }


def elaguer(lignes, instant_, jours_gardes=GARDE_JOURS):
    """Garde les relevés des `jours_gardes` derniers jours (lignes illisibles retirées)."""
    limite = instant_ - timedelta(days=jours_gardes)
    gardees = []
    for ligne in lignes:
        try:
            r = json.loads(ligne) if isinstance(ligne, str) else ligne
            t = instant(r["t"])
        except (ValueError, KeyError, TypeError):
            continue
        if t is not None and t >= limite:
            gardees.append(r)
    return gardees


def ecart_moyen_par_heure(releves, horizon):
    """Écart moyen mesure − prévision MF faite `horizon` heures plus tôt, par heure de la journée (0-23) :
    {heure: (écart moyen, nombre)}. Pour le jour où on appliquera la correction (voir HUB-METEO.md)."""
    par_t = {r["t"]: r for r in releves}
    sommes = {}
    for r in releves:
        t = instant(r["t"])
        avant = par_t.get(iso(t - timedelta(hours=horizon)))
        if not avant or r.get("mesure") is None:
            continue
        prevu = (avant.get("prev") or {}).get(str(horizon))
        if prevu is None:
            continue
        s, n = sommes.get(t.hour, (0.0, 0))
        sommes[t.hour] = (s + r["mesure"] - prevu, n + 1)
    return {h: (round(s / n, 2), n) for h, (s, n) in sorted(sommes.items())}


# MARK: - App AppDaemon

try:
    import hassapi as hass
except ImportError:  # pragma: no cover
    hass = None

if hass is not None:
    import os
    from datetime import time as heure_du_jour
    from pathlib import Path

    import httpx

    CORE_API = "http://supervisor/core/api"

    class HubMeteo(hass.Hass):

        def initialize(self):
            self._releves_path = Path(self.args.get("releves_file", "/config/hub_meteo_releves.jsonl"))
            self._passe = []      # points horaires MF déjà passés (dernières heures), pour interpoler à maintenant
            self._dernier = None  # (points, température, source, mf) du dernier calcul, pour le relevé horaire
            self._attente = None
            self.run_every(self._maj, "now+10", int(self.args.get("refresh_seconds", 300)))
            self.listen_state(self._pluie_change, PLUIE_HEURE, attribute="all")
            self.run_hourly(self._releve, heure_du_jour(0, 2, 0))

        def _pluie_change(self, entity, attribute, old, new, **kwargs):
            if self._attente is not None:
                try:
                    self.cancel_timer(self._attente)
                except Exception:  # noqa: BLE001 - minuterie déjà passée
                    pass
            self._attente = self.run_in(self._maj, 3)

        def _previsions(self, genre):
            reply = httpx.post(f"{CORE_API}/services/weather/get_forecasts?return_response",
                               json={"entity_id": METEO, "type": genre}, timeout=15,
                               headers={"Authorization": f"Bearer {os.environ['SUPERVISOR_TOKEN']}"})
            reply.raise_for_status()
            return ((reply.json().get("service_response") or {}).get(METEO) or {}).get("forecast") or []

        def _publier(self, etat, attributs):
            """État publié par l'API REST de HA (`POST /api/states`) et non par `self.set_state` : AppDaemon 4.5
            retire des attributs les valeurs vides, récursivement (0, null, listes vides : `niveaux` passait de
            12 cases à 2, `rafales_kmh: 0` et `pluie_mm: 0` disparaissaient), ce qui casse le contrat."""
            reply = httpx.post(f"{CORE_API}/states/{ENTITE}", json={"state": etat, "attributes": attributs},
                               timeout=15, headers={"Authorization": f"Bearer {os.environ['SUPERVISOR_TOKEN']}"})
            reply.raise_for_status()

        def _maj(self, **kwargs):
            self._attente = None
            maintenant = datetime.now(PARIS)
            try:
                etats = {e: self.get_state(e, attribute="all") or {}
                         for e in (TERRASSE, JARDIN, QUARTIER, METEO, PLUIE_HEURE, VIGILANCE)}
                try:
                    horaires, quotidiennes = self._previsions("hourly"), self._previsions("daily")
                except Exception as exc:  # noqa: BLE001 - la mesure et la pluie dans l'heure restent publiées
                    self.log(f"Météo : prévisions illisibles ({exc!r})", level="WARNING")
                    horaires, quotidiennes = [], []
                points = points_mf(horaires)
                limite = maintenant - timedelta(hours=3)
                self._passe = sorted({p for p in self._passe + [p for p in points if p[0] <= maintenant]
                                      if p[0] >= limite})
                etat, attributs = calculer(etats, horaires, quotidiennes, maintenant, self._passe)
                tous = sorted(set(points) | set(self._passe))
                self._dernier = (tous, attributs["maintenant"]["temperature"], attributs["maintenant"]["source"],
                                 mf_maintenant(tous, etats.get(METEO), maintenant))
                self._publier(etat, dict(
                    attributs, friendly_name="Météo du Hub", unit_of_measurement="°C", device_class="temperature",
                    icon="mdi:weather-partly-rainy"))
            except Exception as exc:  # noqa: BLE001 - le capteur garde sa dernière valeur
                self.log(f"Météo : calcul impossible ({exc!r})", level="WARNING")

        def _releve(self, **kwargs):
            if self._dernier is None:
                return
            maintenant = datetime.now(PARIS)
            points, temperature, source, mf = self._dernier
            ligne = releve(points, temperature, source, mf, maintenant)
            try:
                anciennes = self._releves_path.read_text(encoding="utf-8").splitlines() \
                    if self._releves_path.exists() else []
                gardees = [r for r in elaguer(anciennes, maintenant) if r.get("t") != ligne["t"]] + [ligne]
                tmp = self._releves_path.with_suffix(".tmp")
                tmp.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in gardees), encoding="utf-8")
                tmp.replace(self._releves_path)
                self.log(f"Météo : relevé {ligne['t']} ({source} {temperature}, MF {ligne['mf']}), "
                         f"{len(gardees)} relevé(s) gardé(s)")
            except OSError as exc:
                self.log(f"Météo : relevé impossible ({exc!r})", level="WARNING")
