"""Lieu de travail du jour (P9-N, lot N1, 24/10/2026) : `sensor.aiguillage_lieu_travail`, bureau ou télétravail.

L'agenda pro (Google Workspace de Barrière) est fermé : partage des détails interdit, Apps Script désactivé, lieu de
travail absent du Calendrier d'iOS. Le lieu vient donc de trois sources, de la plus forte à la plus faible :

1. **Position** (constaté) : l'iPhone (`device_tracker.iphone_17_lex`) passé à moins de 300 m d'un lieu du groupe
   « Travail » de Mes lieux (`config:lieux`, 33 rue d'Artois) → bureau ; un jour travaillé où il est resté à la
   maison (vu à la maison à 11 h et à 15 h, jamais au bureau) → télétravail.
2. **Exception** dite par Alexandre : « Note à moi-même » sur Signal (« demain télétravail », « mercredi bureau »,
   « congé du 3/11 au 7/11 », « demain normal » pour annuler) ou, plus tard, depuis Aiguillage (N2).
3. **Semaine type** : lundi bureau (sûr), mercredi bureau (probable, 70 %), mardi et jeudi télétravail, vendredi
   pas travaillé (4/5) sauf le premier du mois ; samedi, dimanche et jours fériés : pas travaillé.

Réglages et exceptions dans `donnees_apps` (espace `aiguillage`, clé `config:lieu_travail`), créés avec les valeurs
ci-dessus s'ils manquent ; constats dans `/config/aiguillage_lieu_travail.json` (120 jours), d'où les statistiques
par jour de la semaine et une suggestion quand la semaine type ne colle plus. Contrat : `homeassistant/LIEU-TRAVAIL.md`.

Fonctions pures, testées hors Home Assistant par `tests/test_aiguillage_lieu_travail.py` ; l'app en fin de fichier.
"""

from datetime import date, datetime, timedelta
import math
import re
import unicodedata
from zoneinfo import ZoneInfo

PARIS = ZoneInfo("Europe/Paris")
ENTITE = "sensor.aiguillage_lieu_travail"
CLE_CONFIG = "config:lieu_travail"
CLE_LIEUX = "config:lieux"
GROUPE_TRAVAIL = "travail"
RAYON_BUREAU_M = 300
NB_JOURS = 14
GARDE_CONSTATS_JOURS = 120
GARDE_EXCEPTIONS_JOURS = 30

JOURS = ("lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche")
LIEUX = ("bureau", "teletravail", "off")
LIBELLES = {"bureau": "🏢 Bureau", "teletravail": "🏠 Télétravail", "off": "Pas Barrière", "ferie": "Férié"}
COURTS = {"bureau": "Bureau", "teletravail": "Télétravail", "off": "Pas Barrière", "ferie": "Férié"}

CONFIG_DEFAUT = {
    "v": 1,
    "semaine": {
        "lundi": {"lieu": "bureau", "certitude": "sur"},
        "mardi": {"lieu": "teletravail", "certitude": "sur"},
        "mercredi": {"lieu": "bureau", "certitude": "probable"},
        "jeudi": {"lieu": "teletravail", "certitude": "sur"},
        "vendredi": {"lieu": "off", "certitude": "sur"},
        "samedi": {"lieu": "off", "certitude": "sur"},
        "dimanche": {"lieu": "off", "certitude": "sur"},
    },
    # Premier vendredi du mois : travaillé (lieu à confirmer avec Alexandre).
    "premier_vendredi": {"lieu": "bureau", "certitude": "probable"},
    "exceptions": {},
}


# MARK: - Calendrier

def paques(annee):
    """Dimanche de Pâques (algorithme de Meeus, calendrier grégorien)."""
    a, b, c = annee % 19, annee // 100, annee % 100
    d, e = b // 4, b % 4
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i, k = c // 4, c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    mois = (h + l - 7 * m + 114) // 31
    jour = (h + l - 7 * m + 114) % 31 + 1
    return date(annee, mois, jour)


def feries(annee):
    """Jours fériés de métropole : {date: nom}."""
    p = paques(annee)
    return {
        date(annee, 1, 1): "Jour de l'an", p + timedelta(days=1): "Lundi de Pâques", date(annee, 5, 1): "Fête du travail",
        date(annee, 5, 8): "Victoire 1945", p + timedelta(days=39): "Ascension", p + timedelta(days=50): "Lundi de Pentecôte",
        date(annee, 7, 14): "Fête nationale", date(annee, 8, 15): "Assomption", date(annee, 11, 1): "Toussaint",
        date(annee, 11, 11): "Armistice", date(annee, 12, 25): "Noël",
    }


def premier_vendredi(jour):
    return jour.weekday() == 4 and jour.day <= 7


# MARK: - Configuration

def config_valide(valeur):
    """Valeur de `config:lieu_travail` complétée par les défauts (une valeur abîmée ne casse rien)."""
    conf = {"v": 1, "semaine": dict(CONFIG_DEFAUT["semaine"]), "premier_vendredi": dict(CONFIG_DEFAUT["premier_vendredi"]),
            "exceptions": {}}
    if not isinstance(valeur, dict):
        return conf
    for nom, regle in (valeur.get("semaine") or {}).items():
        if nom in JOURS and isinstance(regle, dict) and regle.get("lieu") in LIEUX:
            conf["semaine"][nom] = {"lieu": regle["lieu"], "certitude": regle.get("certitude") or "sur"}
    pv = valeur.get("premier_vendredi")
    if pv is None and "premier_vendredi" in valeur:
        conf["premier_vendredi"] = None  # désactivé : le vendredi suit la semaine type
    elif isinstance(pv, dict) and pv.get("lieu") in LIEUX:
        conf["premier_vendredi"] = {"lieu": pv["lieu"], "certitude": pv.get("certitude") or "sur"}
    for jour, lieu in (valeur.get("exceptions") or {}).items():
        try:
            date.fromisoformat(jour)
        except (TypeError, ValueError):
            continue
        if lieu in LIEUX:
            conf["exceptions"][jour] = lieu
    return conf


def elaguer_exceptions(conf, aujourdhui, garde=GARDE_EXCEPTIONS_JOURS):
    limite = aujourdhui - timedelta(days=garde)
    return dict(conf, exceptions={j: l for j, l in conf["exceptions"].items() if date.fromisoformat(j) >= limite})


# MARK: - Le lieu d'un jour

def prevu(jour, conf):
    """Lieu prévu sans constat : (lieu, certitude, source). `lieu` vaut aussi « ferie »."""
    exc = conf["exceptions"].get(jour.isoformat())
    if exc:
        return exc, "sur", "exception"
    if jour in feries(jour.year):
        return "ferie", "sur", "ferie"
    if premier_vendredi(jour) and conf.get("premier_vendredi"):
        return conf["premier_vendredi"]["lieu"], conf["premier_vendredi"]["certitude"], "premier_vendredi"
    regle = conf["semaine"][JOURS[jour.weekday()]]
    return regle["lieu"], regle["certitude"], "semaine"


def jour_info(jour, conf, constats):
    """Le lieu retenu pour un jour : le constat (position) l'emporte sur l'exception et la semaine type."""
    lieu, certitude, source = prevu(jour, conf)
    constat = constats.get(jour.isoformat())
    attendu = lieu
    if constat in ("bureau", "teletravail"):
        lieu, certitude, source = constat, "constate", "position"
    libelle = LIBELLES[lieu] + (" ?" if certitude == "probable" else "")
    info = {"date": jour.isoformat(), "jour": JOURS[jour.weekday()], "lieu": lieu, "certitude": certitude,
            "source": source, "libelle": libelle}
    if source == "position" and attendu != lieu:
        info["prevu"] = attendu
    return info


def jours(aujourdhui, conf, constats, nb=NB_JOURS):
    return [jour_info(aujourdhui + timedelta(days=i), conf, constats) for i in range(nb)]


def phrase(infos):
    """« 🏢 Bureau aujourd'hui · demain 🏠 Télétravail » (aujourd'hui, puis le prochain jour travaillé)."""
    if not infos:
        return ""
    du_jour = infos[0]
    if du_jour["lieu"] in ("off", "ferie"):
        tete = "Pas de Barrière aujourd'hui" if du_jour["lieu"] == "off" else "Férié aujourd'hui"
    else:
        tete = f"{du_jour['libelle']} aujourd'hui"
    suivant = next((i for i in infos[1:] if i["lieu"] in ("bureau", "teletravail")), None)
    if not suivant:
        return tete
    ecart = (date.fromisoformat(suivant["date"]) - date.fromisoformat(du_jour["date"])).days
    quand = "demain" if ecart == 1 else suivant["jour"]
    return f"{tete} · {quand} {suivant['libelle']}"


# MARK: - Position

def distance_m(lat1, lon1, lat2, lon2):
    """Distance à vol d'oiseau (haversine), en mètres."""
    r = 6_371_000
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def lieux_travail(config_lieux):
    """Points du groupe « Travail » de Mes lieux : [(lat, lon, nom)]."""
    points = []
    for groupe in (config_lieux or {}).get("groupes") or []:
        if sans_accents(groupe.get("nom") or "").strip() == GROUPE_TRAVAIL:
            for lieu in groupe.get("lieux") or []:
                if isinstance(lieu.get("lat"), (int, float)) and isinstance(lieu.get("lon"), (int, float)):
                    points.append((lieu["lat"], lieu["lon"], lieu.get("nom") or "Bureau"))
    return points


def au_bureau(attributs, points, rayon=RAYON_BUREAU_M):
    """Position de l'app Compagnon dans un lieu « Travail » (précision déduite, plafonnée à 300 m de plus)."""
    lat, lon = attributs.get("latitude"), attributs.get("longitude")
    if not isinstance(lat, (int, float)) or not isinstance(lon, (int, float)):
        return False
    precision = min(float(attributs.get("gps_accuracy") or 0), 300.0)
    return any(distance_m(lat, lon, plat, plon) <= rayon + precision for plat, plon, _ in points)


def constat_du_soir(jour, conf, vu_bureau, maison_11h, maison_15h):
    """Constat de fin de journée (16 h) : bureau si l'iPhone y est passé ; télétravail si un jour travaillé il était
    à la maison à 11 h et à 15 h ; sinon rien (journée hors des deux, ou pas travaillée)."""
    if vu_bureau:
        return "bureau"
    lieu, _, _ = prevu(jour, conf)
    if lieu in ("bureau", "teletravail") and maison_11h and maison_15h:
        return "teletravail"
    return None


def elaguer_constats(constats, aujourdhui, garde=GARDE_CONSTATS_JOURS):
    limite = aujourdhui - timedelta(days=garde)
    return {j: l for j, l in constats.items() if date.fromisoformat(j) >= limite}


# MARK: - Statistiques et suggestion

def stats(constats, aujourdhui, semaines=8):
    """Par jour ouvré, sur les `semaines` dernières : {jour: {"bureau": n, "teletravail": n}}."""
    limite = aujourdhui - timedelta(weeks=semaines)
    res = {nom: {"bureau": 0, "teletravail": 0} for nom in JOURS[:5]}
    for jour, lieu in constats.items():
        d = date.fromisoformat(jour)
        if limite <= d < aujourdhui and d.weekday() < 5 and lieu in ("bureau", "teletravail"):
            res[JOURS[d.weekday()]][lieu] += 1
    return res


def suggestion(conf, st, minimum=4, seuil=0.75):
    """Une phrase quand un jour de la semaine type contredit au moins 75 % de 4 constats ou plus, sinon None."""
    for nom in JOURS[:5]:
        b, t = st[nom]["bureau"], st[nom]["teletravail"]
        total = b + t
        if total < minimum:
            continue
        regle = conf["semaine"][nom]
        if regle["lieu"] == "teletravail" and b / total >= seuil:
            return f"Le {nom}, tu étais au bureau {b} fois sur {total} : passer le {nom} en Bureau ?"
        if regle["lieu"] == "bureau" and t / total >= seuil:
            return f"Le {nom}, tu étais en télétravail {t} fois sur {total} : passer le {nom} en Télétravail ?"
    return None


# MARK: - Exceptions dites sur Signal

def sans_accents(texte):
    return "".join(c for c in unicodedata.normalize("NFD", texte.lower()) if unicodedata.category(c) != "Mn")


MOTS_LIEU = (
    (r"pas barriere|pas travaille|ne travaille pas|conges?|off|repos|vacances|rtt|ferie", "off"),
    (r"teletravail|tele travail|tt|a la maison|maison|domicile", "teletravail"),
    (r"au bureau|bureau|sur site|artois", "bureau"),
    (r"normal|comme prevu|annule|annuler", "normal"),
)
REMPLISSAGE = r"(?:je suis|je serai|je bosse|je travaille|en|le|la|les|au|a|de|du|ce|cette|semaine|jour|journee|:|,|-)"
DATE = (r"(?P<rel>aujourd'?hui|aujourd hui|auj|demain|apres-demain|apres demain)"
        r"|(?P<nom>lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)(?:\s+(?P<jn>\d{1,2})(?:/(?P<mn>\d{1,2}))?)?"
        r"|(?P<j>\d{1,2})/(?P<m>\d{1,2})(?:/(?P<a>\d{2,4}))?")


def _date(m, aujourdhui, suffixe=""):
    g = {k[:-len(suffixe)] if suffixe and k.endswith(suffixe) else k: v for k, v in m.groupdict().items()
         if not suffixe or k.endswith(suffixe)}
    if g.get("rel"):
        rel = g["rel"].replace("-", " ")
        return aujourdhui + timedelta(days={"demain": 1, "apres demain": 2}.get(rel, 0))
    if g.get("nom"):
        if g.get("jn"):
            return _jour_mois(int(g["jn"]), int(g["mn"]) if g.get("mn") else None, None, aujourdhui)
        cible = JOURS.index(g["nom"])
        return aujourdhui + timedelta(days=(cible - aujourdhui.weekday()) % 7)
    if g.get("j"):
        return _jour_mois(int(g["j"]), int(g["m"]), g.get("a"), aujourdhui)
    return None


def _jour_mois(j, m, a, aujourdhui):
    if m is None:  # « lundi 3 » : ce mois-ci, ou le suivant si c'est passé
        m = aujourdhui.month
        try:
            d = date(aujourdhui.year, m, j)
        except ValueError:
            return None
        if d < aujourdhui:
            m2 = m % 12 + 1
            try:
                d = date(aujourdhui.year + (m2 == 1), m2, j)
            except ValueError:
                return None
        return d
    annee = int(a) + (2000 if a and len(a) == 2 else 0) if a else aujourdhui.year
    try:
        d = date(annee, m, j)
    except ValueError:
        return None
    if not a and d < aujourdhui - timedelta(days=7):
        d = date(annee + 1, m, j)
    return d


def _avec_suffixe(motif, suffixe):
    return re.sub(r"\(\?P<(\w+)>", lambda x: f"(?P<{x.group(1)}{suffixe}>", motif)


_LIEU = "|".join(f"(?:{motif})" for motif, _ in MOTS_LIEU)
_UN_JOUR = re.compile(rf"^(?:{REMPLISSAGE}\s+)*(?:(?P<date>{DATE})\s+(?:{REMPLISSAGE}\s+)*(?P<lieu>{_LIEU})"
                      rf"|(?P<lieu2>{_LIEU})\s+(?:{REMPLISSAGE}\s+)*(?P<date2>{_avec_suffixe(DATE, '2')}))$")
_PERIODE = re.compile(rf"^(?P<lieu>{_LIEU})\s+du\s+(?P<debut>{_avec_suffixe(DATE, 'd')})\s+au\s+"
                      rf"(?P<fin>{_avec_suffixe(DATE, 'f')})$")


def _lieu(mot):
    for motif, lieu in MOTS_LIEU:
        if re.fullmatch(motif, mot):
            return lieu
    return None


def lire_exception(texte, aujourdhui):
    """Message de « Note à moi-même » → [(date, lieu)] (`lieu` = « normal » pour annuler), ou None si ce n'est pas
    une consigne de lieu (le message doit être fait seulement d'un jour et d'un lieu : rien d'autre n'est pris)."""
    t = " ".join(sans_accents(texte or "").replace("’", "'").replace(".", " ").replace("!", " ").split())
    if not t or len(t) > 60:
        return None
    m = _PERIODE.match(t)
    if m:
        debut, fin = _date(m, aujourdhui, "d"), _date(m, aujourdhui, "f")
        lieu = _lieu(m.group("lieu"))
        if not debut or not fin or fin < debut or (fin - debut).days > 60 or not lieu:
            return None
        return [(debut + timedelta(days=i), lieu) for i in range((fin - debut).days + 1)]
    m = _UN_JOUR.match(t)
    if not m:
        return None
    if m.group("date"):
        jour, lieu = _date(m, aujourdhui), _lieu(m.group("lieu"))
    else:
        jour, lieu = _date(m, aujourdhui, "2"), _lieu(m.group("lieu2"))
    if not jour or not lieu or jour < aujourdhui:
        return None
    return [(jour, lieu)]


def appliquer(conf, consignes):
    """Exceptions ajoutées (ou retirées pour « normal »), en ignorant celles qui redisent la semaine type."""
    exceptions = dict(conf["exceptions"])
    for jour, lieu in consignes:
        cle = jour.isoformat()
        exceptions.pop(cle, None)
        if lieu != "normal":
            sans = dict(conf, exceptions=exceptions)
            prevu_lieu, certitude, _ = prevu(jour, sans)
            if prevu_lieu != lieu or certitude != "sur":
                exceptions[cle] = lieu
    return dict(conf, exceptions=exceptions)


def reponse(consignes, conf_avant, conf_apres):
    """Confirmation renvoyée sur Signal."""
    lignes = []
    for jour, _ in consignes[:10]:
        avant = jour_info(jour, conf_avant, {})
        apres = jour_info(jour, conf_apres, {})
        quand = f"{JOURS[jour.weekday()].capitalize()} {jour:%d/%m}"
        if avant["libelle"] == apres["libelle"]:
            lignes.append(f"{quand} : {apres['libelle']} (inchangé)")
        else:
            lignes.append(f"{quand} : {apres['libelle']} (au lieu de {avant['libelle']})")
    if len(consignes) > 10:
        lignes.append(f"… et {len(consignes) - 10} autre(s) jour(s)")
    return "✅ " + "\n".join(lignes)


def calculer(aujourdhui, conf, constats, maintenant):
    """État et attributs du capteur."""
    infos = jours(aujourdhui, conf, constats)
    st = stats(constats, aujourdhui)
    return infos[0]["lieu"], {
        "aujourdhui": infos[0], "demain": infos[1], "jours": infos, "phrase": phrase(infos),
        "stats": st, "suggestion": suggestion(conf, st), "maj": maintenant.isoformat(timespec="seconds"),
    }


# MARK: - App AppDaemon

try:
    import hassapi as hass
except ImportError:  # pragma: no cover
    hass = None

if hass is not None:
    import json
    import os
    import uuid
    from datetime import UTC
    from pathlib import Path

    import httpx

    CORE_API = "http://supervisor/core/api"
    ICONES = {"bureau": "mdi:office-building", "teletravail": "mdi:home-account", "off": "mdi:beach",
              "ferie": "mdi:party-popper"}

    class AiguillageLieuTravail(hass.Hass):

        def initialize(self):
            self._espace = self.args.get("ha_espace", "aiguillage")
            self._tracker = self.args.get("entite", "device_tracker.iphone_17_lex")
            self._etat_path = Path(self.args.get("etat_file", "/config/aiguillage_lieu_travail.json"))
            self._signal_conf = Path(self.args.get("signal_config", "/config/aiguillage_signal.json"))
            self._signal_url = self.args.get("signal_url", "http://1315902c-signal-messenger:8080")
            self._etat = self._lire_etat()
            self._points = []
            self.listen_state(self._position, self._tracker, attribute="all")
            self.listen_event(self._message, "aiguillage_lieu_travail_message")
            self.listen_event(self._maj_evenement, "aiguillage_lieu_travail_maj")
            self.run_daily(self._echantillon, "11:00:00", moment="maison_11h")
            self.run_daily(self._echantillon, "15:00:00", moment="maison_15h")
            self.run_daily(self._soir, "16:00:00")
            self.run_daily(self._maj, "00:00:30")
            self.run_every(self._maj, "now+5", int(self.args.get("refresh_seconds", 900)))

        # Fichier d'état : constats et échantillons du jour.
        def _lire_etat(self):
            try:
                etat = json.loads(self._etat_path.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                etat = {}
            etat.setdefault("constats", {})
            etat.setdefault("jour", {})
            return etat

        def _ecrire_etat(self):
            tmp = self._etat_path.with_suffix(".tmp")
            tmp.write_text(json.dumps(self._etat, ensure_ascii=False, indent=1), encoding="utf-8")
            tmp.replace(self._etat_path)

        def _du_jour(self):
            aujourdhui = datetime.now(PARIS).date().isoformat()
            if self._etat["jour"].get("date") != aujourdhui:
                self._etat["jour"] = {"date": aujourdhui, "vu_bureau": False, "maison_11h": False, "maison_15h": False}
            return self._etat["jour"]

        def _service(self, domain, service, data):
            reply = httpx.post(f"{CORE_API}/services/{domain}/{service}?return_response", json=data, timeout=15,
                               headers={"Authorization": f"Bearer {os.environ['SUPERVISOR_TOKEN']}"})
            reply.raise_for_status()
            return reply.json().get("service_response")

        def _lire(self, cle):
            rep = self._service("donnees_apps", "lire", {"espace": self._espace, "cle": cle}) or {}
            enr = rep.get("enregistrement") or {}
            if not enr or enr.get("supprime"):
                return None, 0
            return enr.get("valeur"), enr.get("version", 0)

        def _config(self):
            """Réglages (créés avec les défauts s'ils manquent) et version, pour écrire sans écraser."""
            valeur, version = self._lire(CLE_CONFIG)
            if valeur is None:
                self._ecrire_config(CONFIG_DEFAUT, 0)
                return config_valide(CONFIG_DEFAUT), 1
            return config_valide(valeur), version

        def _ecrire_config(self, conf, version):
            rep = self._service("donnees_apps", "ecrire", {
                "espace": self._espace, "cle": CLE_CONFIG, "valeur": conf, "version_attendue": version,
                "modifie_le": datetime.now(UTC).isoformat(), "modifie_par": "lieu-travail", "op_id": str(uuid.uuid4()),
            }) or {}
            return rep.get("statut")

        def _publier(self, etat, attributs):
            """Par l'API REST (comme `sensor.hub_meteo`) : AppDaemon 4.5 retire les null des attributs."""
            reply = httpx.post(f"{CORE_API}/states/{ENTITE}", json={"state": etat, "attributes": attributs},
                               timeout=15, headers={"Authorization": f"Bearer {os.environ['SUPERVISOR_TOKEN']}"})
            reply.raise_for_status()

        def _maj(self, *args, **kwargs):
            maintenant = datetime.now(PARIS)
            try:
                conf, _ = self._config()
                lieux, _ = self._lire(CLE_LIEUX)
                self._points = lieux_travail(lieux)
                du_jour = self._du_jour()
                constats = dict(self._etat["constats"])
                if du_jour.get("vu_bureau"):
                    constats[du_jour["date"]] = "bureau"
                etat, attributs = calculer(maintenant.date(), conf, constats, maintenant)
                attributs.update(friendly_name="Lieu de travail", icon=ICONES.get(etat, "mdi:briefcase"),
                                 bureau=[{"nom": n, "lat": la, "lon": lo} for la, lo, n in self._points])
                self._publier(etat, attributs)
            except Exception as exc:  # noqa: BLE001 - le capteur garde sa dernière valeur
                self.log(f"Lieu de travail : calcul impossible ({exc!r})", level="WARNING")

        def _maj_evenement(self, event_name, data, **kwargs):
            self._maj()

        def _position(self, entity, attribute, old, new, **kwargs):
            attributs = (new or {}).get("attributes") or {}
            if not self._points or not au_bureau(attributs, self._points):
                return
            du_jour = self._du_jour()
            if not du_jour["vu_bureau"]:
                du_jour["vu_bureau"] = True
                self._ecrire_etat()
                self.log("Lieu de travail : iPhone au bureau, journée constatée « bureau »")
                self._maj()

        def _echantillon(self, **kwargs):
            du_jour = self._du_jour()
            du_jour[kwargs["moment"]] = self.get_state(self._tracker) == "home"
            self._ecrire_etat()

        def _soir(self, **kwargs):
            maintenant = datetime.now(PARIS)
            try:
                conf, _ = self._config()
                du_jour = self._du_jour()
                constat = constat_du_soir(maintenant.date(), conf, du_jour["vu_bureau"], du_jour["maison_11h"],
                                          du_jour["maison_15h"])
                if constat:
                    self._etat["constats"][du_jour["date"]] = constat
                self._etat["constats"] = elaguer_constats(self._etat["constats"], maintenant.date())
                self._ecrire_etat()
                self.log(f"Lieu de travail : constat du {du_jour['date']} : {constat or 'aucun'}")
                self._maj()
            except Exception as exc:  # noqa: BLE001
                self.log(f"Lieu de travail : constat impossible ({exc!r})", level="WARNING")

        def _message(self, event_name, data, **kwargs):
            """Note à moi-même reçue par `aiguillage_signal` (sans lien) : consigne de lieu, ou rien."""
            aujourdhui = datetime.now(PARIS).date()
            consignes = lire_exception((data or {}).get("texte"), aujourdhui)
            if not consignes:
                return
            for _ in range(3):  # conflit de version (l'app écrit en même temps) : on relit et on recommence
                avant, version = self._config()
                apres = elaguer_exceptions(appliquer(avant, consignes), aujourdhui)
                statut = self._ecrire_config(apres, version)
                if statut == "ok":
                    break
            else:
                self.log(f"Lieu de travail : consigne non écrite ({statut})", level="WARNING")
                self._repondre("⚠️ Lieu de travail : je n'ai pas pu enregistrer, réessaie.")
                return
            self.log(f"Lieu de travail : consigne « {data.get('texte')} » → {[(j.isoformat(), l) for j, l in consignes]}")
            self._maj()
            self._repondre(reponse(consignes, avant, apres))

        def _repondre(self, texte):
            try:
                compte = json.loads(self._signal_conf.read_text())["compte"]
                r = httpx.post(f"{self._signal_url}/v2/send", timeout=20,
                               json={"message": texte, "number": compte, "recipients": [compte]})
                r.raise_for_status()
            except Exception as exc:  # noqa: BLE001 - la consigne est enregistrée, seule la réponse manque
                self.log(f"Lieu de travail : réponse Signal impossible ({exc!r})", level="WARNING")
