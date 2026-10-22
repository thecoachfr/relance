"""Historique des trajets (plan P9-M, 22/10/2026) : remplacer la Chronologie Google, tout gardé sur le NUC.

Deux sources, rangées dans `/config/aiguillage_trajets.sqlite` (dossier d'AppDaemon, donc dans les sauvegardes HA) :

- **M1, points de l'app Compagnon** : chaque position GPS de `device_tracker.iphone_17_lex` (source `compagnon`),
  gardée au-delà des 10 jours du recorder. Au démarrage, l'historique encore présent dans HA est repris (sans
  doublon). Points trop imprécis (plus de 100 m) ignorés, comme un point identique au précédent.
- **M2, visites d'Aiguillage** : arrêts relevés par iOS (`CLVisit` : arrivée, départ, point), envoyés par lots au
  webhook de l'app (`action: trajets`, champ `visites`), reçus par l'événement `relance_register`. Une visite revient
  deux fois (à l'arrivée sans départ, puis au départ) : la seconde complète la première.

Fonctions pures et accès SQLite, testés hors Home Assistant par `tests/test_aiguillage_trajets.py` (points fictifs).
Suivi : capteur `sensor.aiguillage_trajets` et journal AppDaemon (« Trajets : … », sans coordonnées).
"""

from datetime import date, datetime, time, timedelta
import json
import math
import re
import sqlite3
from zoneinfo import ZoneInfo

PARIS = ZoneInfo("Europe/Paris")
PRECISION_POINT_MAX = 100   # m : au-delà, le point ne dit pas grand-chose du trajet
PRECISION_VISITE_MAX = 1000  # m : iOS donne souvent 50 à 200 m pour une visite
MEME_POINT_M = 1
DEBUT_VALIDE = int(datetime(2020, 1, 1).timestamp())


def distance_m(lat1, lon1, lat2, lon2):
    """Distance à vol d'oiseau (haversine), en mètres."""
    r = 6_371_000
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def _nombre(v):
    try:
        x = float(v)
    except (TypeError, ValueError):
        return None
    return x if math.isfinite(x) else None


def _coords_valides(lat, lon):
    return lat is not None and lon is not None and -90 <= lat <= 90 and -180 <= lon <= 180


# MARK: - Points de l'app Compagnon (M1)

def point_depuis_etat(attributs, quand):
    """Attributs d'un `device_tracker` (GPS) et heure ISO de l'état → point, ou None s'il n'est pas utilisable."""
    attributs = attributs or {}
    if attributs.get("source_type") not in (None, "gps"):
        return None
    lat, lon = _nombre(attributs.get("latitude")), _nombre(attributs.get("longitude"))
    precision = _nombre(attributs.get("gps_accuracy"))
    if not _coords_valides(lat, lon) or precision is None or precision > PRECISION_POINT_MAX:
        return None
    try:
        t = int(datetime.fromisoformat(str(quand)).timestamp())
    except ValueError:
        return None
    vitesse = _nombre(attributs.get("speed"))
    return {"t": t, "lat": lat, "lon": lon, "precision": round(precision, 1),
            "vitesse": vitesse if vitesse is not None and vitesse >= 0 else None}


# MARK: - Visites d'Aiguillage (M2)

def lire_visites(brut):
    """Champ `visites` du webhook (liste, ou texte JSON selon le rendu du modèle) → visites valides."""
    if isinstance(brut, str):
        try:
            brut = json.loads(brut) if brut.strip() else []
        except json.JSONDecodeError:
            return []
    if not isinstance(brut, list):
        return []
    out = []
    for v in brut:
        if not isinstance(v, dict):
            continue
        arrivee, depart = _nombre(v.get("arrivee")), _nombre(v.get("depart"))
        lat, lon, precision = _nombre(v.get("lat")), _nombre(v.get("lon")), _nombre(v.get("precision"))
        if arrivee is None or arrivee < DEBUT_VALIDE or not _coords_valides(lat, lon):
            continue
        if precision is not None and precision > PRECISION_VISITE_MAX:
            continue
        if depart is not None and depart < arrivee:
            depart = None
        out.append({"arrivee": int(arrivee), "depart": int(depart) if depart is not None else None,
                    "lat": lat, "lon": lon, "precision": round(precision, 1) if precision is not None else None})
    return out


# MARK: - Tracés de Santé (M0)

GPX_POINT = re.compile(r'<trkpt\s+lon="([^"]+)"\s+lat="([^"]+)">(.*?)</trkpt>', re.S)
GPX_TIME = re.compile(r"<time>([^<]+)</time>")
GPX_HACC = re.compile(r"<hAcc>([^<]+)</hAcc>")
GPX_SPEED = re.compile(r"<speed>([^<]+)</speed>")


def lire_gpx(texte):
    """Tracé GPX de l'export Santé (`workout-routes/`) → points (un par seconde), triés par heure."""
    out = []
    for lon, lat, corps in GPX_POINT.findall(texte):
        quand, hacc, vit = GPX_TIME.search(corps), GPX_HACC.search(corps), GPX_SPEED.search(corps)
        lat, lon = _nombre(lat), _nombre(lon)
        if not quand or not _coords_valides(lat, lon):
            continue
        try:
            t = int(datetime.fromisoformat(quand.group(1).replace("Z", "+00:00")).timestamp())
        except ValueError:
            continue
        precision = _nombre(hacc.group(1)) if hacc else None
        if precision is not None and precision > PRECISION_POINT_MAX:
            continue
        vitesse = _nombre(vit.group(1)) if vit else None
        out.append({"t": t, "lat": lat, "lon": lon, "precision": round(precision, 1) if precision is not None else None,
                    "vitesse": round(vitesse, 2) if vitesse is not None and vitesse >= 0 else None})
    return sorted(out, key=lambda p: p["t"])


def eclaircir(points, pas_m=10):
    """Garde un point tous les `pas_m` mètres environ (plus le dernier) : assez pour une carte, 10 à 20 fois moins lourd."""
    garde = []
    for p in points:
        if not garde or distance_m(garde[-1]["lat"], garde[-1]["lon"], p["lat"], p["lon"]) >= pas_m:
            garde.append(p)
    if points and garde[-1] is not points[-1]:
        garde.append(points[-1])
    return garde


# MARK: - Base SQLite

def ouvrir(chemin):
    db = sqlite3.connect(chemin, timeout=30)
    db.executescript("""
        CREATE TABLE IF NOT EXISTS points (
            source TEXT NOT NULL, t INTEGER NOT NULL, lat REAL NOT NULL, lon REAL NOT NULL,
            precision REAL, vitesse REAL, PRIMARY KEY (source, t));
        CREATE INDEX IF NOT EXISTS points_t ON points (t);
        CREATE TABLE IF NOT EXISTS visites (
            source TEXT NOT NULL, arrivee INTEGER NOT NULL, depart INTEGER, lat REAL NOT NULL, lon REAL NOT NULL,
            precision REAL, PRIMARY KEY (source, arrivee));
        CREATE INDEX IF NOT EXISTS visites_arrivee ON visites (arrivee);
    """)
    return db


def ajouter_point(db, point, source):
    """Ajoute un point s'il est nouveau et ne répète pas le précédent (téléphone immobile). Renvoie True si ajouté."""
    avant = db.execute("SELECT lat, lon FROM points WHERE source = ? AND t <= ? ORDER BY t DESC LIMIT 1",
                       (source, point["t"])).fetchone()
    if avant and distance_m(avant[0], avant[1], point["lat"], point["lon"]) < MEME_POINT_M:
        return False
    cur = db.execute("INSERT OR IGNORE INTO points (source, t, lat, lon, precision, vitesse) VALUES (?, ?, ?, ?, ?, ?)",
                     (source, point["t"], point["lat"], point["lon"], point.get("precision"), point.get("vitesse")))
    db.commit()
    return cur.rowcount > 0


def ajouter_points(db, points, source):
    """Ajout en bloc (import d'un historique), sans doublon. Renvoie le nombre de points ajoutés."""
    avant = db.total_changes
    db.executemany("INSERT OR IGNORE INTO points (source, t, lat, lon, precision, vitesse) VALUES (?, ?, ?, ?, ?, ?)",
                   [(source, p["t"], p["lat"], p["lon"], p.get("precision"), p.get("vitesse")) for p in points])
    db.commit()
    return db.total_changes - avant


def ajouter_visites(db, visites, source):
    """Ajoute ou complète les visites (même arrivée : le départ connu et le point le plus récent gagnent)."""
    for v in visites:
        db.execute("""
            INSERT INTO visites (source, arrivee, depart, lat, lon, precision) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT (source, arrivee) DO UPDATE SET
                depart = COALESCE(excluded.depart, visites.depart),
                lat = excluded.lat, lon = excluded.lon, precision = excluded.precision
        """, (source, v["arrivee"], v["depart"], v["lat"], v["lon"], v["precision"]))
    db.commit()
    return len(visites)


def compter(db):
    points = db.execute("SELECT COUNT(*), MIN(t) FROM points").fetchone()
    visites = db.execute("SELECT COUNT(*) FROM visites").fetchone()[0]
    debut = datetime.fromtimestamp(points[1], PARIS).date().isoformat() if points[1] else None
    return {"points": points[0], "visites": visites, "depuis": debut}


def bornes_jour(jour):
    """Début et fin (exclue) d'un jour à Paris, en secondes Unix."""
    debut = datetime.combine(jour, time(0), PARIS)
    return int(debut.timestamp()), int((debut + timedelta(days=1)).timestamp())


def lire_jour(db, jour):
    """Points et visites d'un jour (pour l'écran « Mes trajets », M3), triés par heure."""
    debut, fin = bornes_jour(jour if isinstance(jour, date) else date.fromisoformat(jour))
    points = [dict(zip(("source", "t", "lat", "lon", "precision", "vitesse"), r)) for r in db.execute(
        "SELECT source, t, lat, lon, precision, vitesse FROM points WHERE t >= ? AND t < ? ORDER BY t", (debut, fin))]
    visites = [dict(zip(("source", "arrivee", "depart", "lat", "lon", "precision"), r)) for r in db.execute(
        "SELECT source, arrivee, depart, lat, lon, precision FROM visites "
        "WHERE arrivee < ? AND COALESCE(depart, arrivee) >= ? ORDER BY arrivee", (fin, debut))]
    return {"points": points, "visites": visites}


def deja_venu(db, lat, lon, rayon=150, limite=20):
    """Visites (et, à défaut, jours avec des points) dans un rayon autour d'un point, les plus récentes d'abord."""
    dlat = rayon / 111_000
    dlon = rayon / (111_000 * max(math.cos(math.radians(lat)), 0.01))
    boite = (lat - dlat, lat + dlat, lon - dlon, lon + dlon)
    visites = [dict(zip(("arrivee", "depart", "lat", "lon"), r)) for r in db.execute(
        "SELECT arrivee, depart, lat, lon FROM visites WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ? "
        "ORDER BY arrivee DESC", boite)]
    visites = [v for v in visites if distance_m(lat, lon, v["lat"], v["lon"]) <= rayon][:limite]
    jours = []
    for (t, plat, plon) in db.execute("SELECT t, lat, lon FROM points WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ? "
                                      "ORDER BY t DESC", boite):
        j = datetime.fromtimestamp(t, PARIS).date().isoformat()
        if distance_m(lat, lon, plat, plon) <= rayon and j not in jours:
            jours.append(j)
            if len(jours) >= limite:
                break
    return {"visites": visites, "jours": jours}


# MARK: - App AppDaemon

try:
    import hassapi as hass
except ImportError:  # pragma: no cover
    hass = None

if hass is not None:

    CAPTEUR = "sensor.aiguillage_trajets"

    class AiguillageTrajets(hass.Hass):

        def initialize(self):
            self._db_path = self.args.get("fichier", "/config/aiguillage_trajets.sqlite")
            self._entite = self.args.get("entite", "device_tracker.iphone_17_lex")
            self._derniere = "aucune"
            self.listen_state(self._position, self._entite, attribute="all")
            self.listen_event(self._lot, "relance_register", action="trajets")
            # Import d'un historique (M0) : événement « aiguillage_trajets_importer » {fichier, source}, fichier JSONL
            # d'un point par ligne {t, lat, lon, precision, vitesse}, préparé par homeassistant/scripts/trajets_sante.py.
            self.listen_event(self._importer, "aiguillage_trajets_importer")
            # Reprise des points encore dans le recorder (10 jours) : sans doublon, donc à chaque démarrage.
            self.run_in(self._rattraper, 20)

        def _publier(self):
            db = ouvrir(self._db_path)
            try:
                compte = compter(db)
            finally:
                db.close()
            self.set_state(CAPTEUR, state=compte["points"], attributes=dict(
                compte, derniere=self._derniere, friendly_name="Trajets gardés", icon="mdi:map-marker-path",
                unit_of_measurement="points"))

        def _position(self, entity, attribute, old, new, **kwargs):
            point = point_depuis_etat((new or {}).get("attributes"), (new or {}).get("last_updated"))
            if not point:
                return
            db = ouvrir(self._db_path)
            try:
                ajoute = ajouter_point(db, point, "compagnon")
            finally:
                db.close()
            if ajoute:
                self._derniere = f"{datetime.now():%d/%m %H:%M} point"
                self._publier()

        def _rattraper(self, **kwargs):
            try:
                historique = self.get_history(entity_id=self._entite, days=10) or []
            except Exception as exc:  # noqa: BLE001 - le suivi en direct continue sans la reprise
                self.log(f"Trajets : historique illisible ({exc!r})", level="WARNING")
                return
            etats = sorted((e for liste in historique for e in (liste or [])), key=lambda e: str(e.get("last_updated")))
            db = ouvrir(self._db_path)
            try:
                ajoutes = sum(1 for e in etats if (p := point_depuis_etat(e.get("attributes"), e.get("last_updated")))
                              and ajouter_point(db, p, "compagnon"))
            finally:
                db.close()
            self.log(f"Trajets : reprise de l'historique, {ajoutes} point(s) ajouté(s) sur {len(etats)} état(s)")
            self._publier()

        def _lot(self, event_name, data, **kwargs):
            visites = lire_visites((data or {}).get("visites"))
            if not visites:
                return
            db = ouvrir(self._db_path)
            try:
                ajouter_visites(db, visites, "aiguillage")
            finally:
                db.close()
            self._derniere = f"{datetime.now():%d/%m %H:%M} {len(visites)} visite(s)"
            self.log(f"Trajets : {len(visites)} visite(s) reçue(s) de l'app ({data.get('device') or '?'})")
            self._publier()

        def _importer(self, event_name, data, **kwargs):
            data = data or {}
            fichier, source = str(data.get("fichier") or ""), str(data.get("source") or "sante")
            if not fichier.startswith("/config/"):
                self.log(f"Trajets : import refusé, fichier hors de /config ({fichier})", level="WARNING")
                return
            try:
                with open(fichier, encoding="utf-8") as f:
                    points = [json.loads(ligne) for ligne in f if ligne.strip()]
            except (OSError, json.JSONDecodeError) as exc:
                self.log(f"Trajets : import illisible ({exc!r})", level="WARNING")
                return
            points = [p for p in points if isinstance(p, dict) and _coords_valides(_nombre(p.get("lat")), _nombre(p.get("lon")))
                      and isinstance(p.get("t"), int) and p["t"] >= DEBUT_VALIDE]
            db = ouvrir(self._db_path)
            try:
                ajoutes = ajouter_points(db, points, source)
            finally:
                db.close()
            self._derniere = f"{datetime.now():%d/%m %H:%M} import {source}"
            self.log(f"Trajets : import {source}, {ajoutes} point(s) ajouté(s) sur {len(points)}")
            self._publier()
