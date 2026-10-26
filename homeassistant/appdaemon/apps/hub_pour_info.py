"""Rappels « pour info » du Hub (P9-P3, 26/10/2026) : `sensor.hub_pour_info`, les infos du jour pour les trois vues
(Hub TV, Hub iPad/iPhone, Nest Hub), et une notification `script.hub_notifier` à l'heure du résumé du matin.

Une info est une tâche d'Aiguillage (espace `aiguillage` de `donnees_apps`) dont les notes ont la ligne
`📣 Pour info` (`Shared/Model/PourInfo.swift`). Elle tombe un jour si c'est sa date (`jour`), ou si sa date est
passée et que sa répétition (ligne `🔄`, `Shared/Model/Recurrence.swift`, portée ici) tombe ce jour-là : le Hub reste
juste même si l'iPhone n'a pas encore avancé l'info. Lecture seule : seule l'app écrit.

Contrat : `homeassistant/HUB-POUR-INFO.md`. Fonctions pures, testées hors Home Assistant par
`tests/test_hub_pour_info.py` ; l'app AppDaemon est en fin de fichier.
"""

import calendar
import re
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

PARIS = ZoneInfo("Europe/Paris")
ENTITE = "sensor.hub_pour_info"
LIGNE = "📣 Pour info"
REPETITION = "🔄"
CLE_TACHE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.I)
JOURS = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]  # 1 = dimanche (Calendar)
A_VENIR_JOURS = 7


def _propre(ligne):
    return ligne.replace("️", "").strip()


def est_pour_info(notes):
    return any(_propre(l) == LIGNE for l in (notes or "").split("\n"))


# MARK: - Répétition (portage de Recurrence.swift)

def repetition(notes):
    """La règle de la ligne 🔄 des notes, en tuple, ou None. Mêmes formes que `Recurrence.init(line:)`."""
    ligne = next((_propre(l) for l in (notes or "").split("\n") if _propre(l).startswith(REPETITION)), None)
    if ligne is None:
        return None
    texte = ligne[len(REPETITION):].strip().lower()

    def nombre(motif):
        m = re.search(motif, texte)
        return int("".join(c for c in m.group(0) if c.isdigit())) if m else None

    if "après avoir été faite" in texte:
        unite = "mois" if "mois" in texte else "semaine" if "semaine" in texte else "jour"
        return ("apres", nombre(r"^\d+") or 1, unite)
    if texte.startswith("tous les ans"):
        m = re.search(r"\d{1,2}/\d{1,2}", texte)
        if not m:
            return None
        jour, mois = (int(x) for x in m.group(0).split("/"))
        return ("an", mois, jour)
    if "mois" in texte:
        tous = nombre(r"^tous les \d+") or 1
        jour_semaine = next((i + 1 for i, nom in enumerate(JOURS) if texte.endswith(nom)), None)
        if jour_semaine:
            rang = -1 if "dernier" in texte else (nombre(r"le \d") or 1)
            return ("mois_jour_semaine", tous, rang, jour_semaine)
        if "dernier jour" in texte:
            return ("mois_jour", tous, 0)
        jour = nombre(r"le \d{1,2}")
        return ("mois_jour", tous, jour) if jour else None
    if "semaine" in texte:
        tous = nombre(r"^toutes les \d+") or 1
        return ("semaine", tous, tuple(i + 1 for i, nom in enumerate(JOURS) if nom in texte))
    if "jour" in texte:
        return ("jour", nombre(r"^tous les \d+") or 1)
    return None


def _jour_cal(d):
    """Jour de la semaine façon Calendar : 1 = dimanche … 7 = samedi."""
    return (d.weekday() + 1) % 7 + 1


def _index_lundi(jour_cal):
    return (jour_cal + 5) % 7


def _ajouter_mois(d, n):
    total = d.year * 12 + d.month - 1 + n
    return date(total // 12, total % 12 + 1, 1)


def _pas(regle, jour):
    """Occurrence suivante strictement après `jour` (`Recurrence.step`)."""
    genre = regle[0]
    if genre == "jour":
        return jour + timedelta(days=regle[1])
    if genre == "semaine":
        tous, voulus = regle[1], regle[2]
        actuel = _jour_cal(jour)
        voulus = voulus or (actuel,)
        for decalage in range(1, 7):
            suivant = jour + timedelta(days=decalage)
            j = _jour_cal(suivant)
            if j in voulus and _index_lundi(j) > _index_lundi(actuel):
                return suivant
        debut_semaine = jour - timedelta(days=_index_lundi(actuel))
        return debut_semaine + timedelta(weeks=tous, days=min(_index_lundi(j) for j in voulus))
    if genre == "mois_jour":
        mois = _ajouter_mois(jour, regle[1])
        longueur = calendar.monthrange(mois.year, mois.month)[1]
        return mois.replace(day=longueur if regle[2] == 0 else min(regle[2], longueur))
    if genre == "mois_jour_semaine":
        mois = _ajouter_mois(jour, regle[1])
        rang, jour_semaine = regle[2], regle[3]
        candidats = [mois.replace(day=n) for n in range(1, calendar.monthrange(mois.year, mois.month)[1] + 1)
                     if _jour_cal(mois.replace(day=n)) == jour_semaine]
        return candidats[-1] if rang == -1 else candidats[min(rang, len(candidats)) - 1]
    if genre == "an":
        mois, quantieme = regle[1], regle[2]
        for annee in (jour.year, jour.year + 1, jour.year + 2, jour.year + 3, jour.year + 4):
            try:
                candidat = date(annee, mois, quantieme)
            except ValueError:  # 29/02 une année non bissextile
                continue
            if candidat > jour:
                return candidat
    return jour


def jour_suivant(regle, echeance, fait):
    """`Recurrence.nextDay(after:done:)` : première occurrence après `fait` (jamais avant)."""
    if regle[0] == "apres":
        quantite, unite = regle[1], regle[2]
        if unite == "mois":
            d = _ajouter_mois(fait, quantite)
            return d.replace(day=min(fait.day, calendar.monthrange(d.year, d.month)[1]))
        return fait + timedelta(days=quantite * (7 if unite == "semaine" else 1))
    jour = _pas(regle, echeance)
    garde = 0
    while jour <= fait and garde < 1000:
        jour = _pas(regle, jour)
        garde += 1
    return jour


def tombe(jour, echeance, regle):
    """`PourInfo.tombe` : sa date, ou sa date est passée et sa répétition tombe ce jour-là."""
    if jour == echeance:
        return True
    if echeance > jour or regle is None:
        return False
    return jour_suivant(regle, echeance, jour - timedelta(days=1)) == jour


# MARK: - Capteur

def infos(enregistrements, aujourdhui):
    """Infos actives : liste de (cle, titre, echeance, regle), dans l'ordre des titres."""
    trouvees = []
    for e in enregistrements or []:
        v = e.get("valeur") or {}
        if not CLE_TACHE.match(e.get("cle", "")) or v.get("fait") or not est_pour_info(v.get("notes")):
            continue
        try:
            echeance = date.fromisoformat(str(v.get("jour") or "")[:10])
        except ValueError:
            continue
        trouvees.append((e["cle"], v.get("titre") or "", echeance, repetition(v.get("notes"))))
    return sorted(trouvees, key=lambda i: i[1].lower())


def calculer(enregistrements, maintenant):
    """(état, attributs) de `sensor.hub_pour_info` (contrat : HUB-POUR-INFO.md)."""
    aujourdhui = maintenant.date()
    toutes = infos(enregistrements, aujourdhui)
    du_jour = [{"cle": c, "titre": t} for c, t, e, r in toutes if tombe(aujourdhui, e, r)]
    a_venir = []
    for c, t, e, r in toutes:
        for n in range(1, A_VENIR_JOURS + 1):
            jour = aujourdhui + timedelta(days=n)
            if tombe(jour, e, r):
                a_venir.append({"cle": c, "titre": t, "jour": jour.isoformat()})
                break
    a_venir.sort(key=lambda i: (i["jour"], i["titre"].lower()))
    return len(du_jour), {
        "maj": maintenant.isoformat(timespec="seconds"),
        "jour": aujourdhui.isoformat(),
        "infos": du_jour,
        "texte": " · ".join(i["titre"] for i in du_jour) or None,
        "a_venir": a_venir,
    }


def texte_notification(attributs):
    """« Pour info : Femme de ménage, Poubelles » (tous les titres : l'écran a la place), ou None si rien."""
    titres = [i["titre"] for i in attributs.get("infos") or []]
    return "Pour info : " + ", ".join(titres) if titres else None


# MARK: - App AppDaemon

try:
    import hassapi as hass
except ImportError:  # pragma: no cover
    hass = None

if hass is not None:
    import os
    from datetime import time as heure_du_jour

    import httpx

    CORE_API = "http://supervisor/core/api"

    class HubPourInfo(hass.Hass):

        def initialize(self):
            self._espace = self.args.get("espace", "aiguillage")
            self._attente = None
            h, m = (int(x) for x in str(self.args.get("heure_resume", "07:30")).split(":"))
            self.run_daily(self._resume, heure_du_jour(h, m, 0))
            # Toutes les 10 min : le changement de jour à minuit, et un filet si un événement se perd.
            self.run_every(self._maj, "now+5", int(self.args.get("refresh_seconds", 600)))
            self.listen_event(self._modifie, "donnees_apps_modifie", espace=self._espace)

        def _api(self, chemin, donnees, reponse=False):
            url = f"{CORE_API}/{chemin}" + ("?return_response" if reponse else "")
            reply = httpx.post(url, json=donnees, timeout=15,
                               headers={"Authorization": f"Bearer {os.environ['SUPERVISOR_TOKEN']}"})
            reply.raise_for_status()
            return reply.json() if reponse else None

        def _modifie(self, event, data, kwargs):
            if self._attente is not None:
                try:
                    self.cancel_timer(self._attente)
                except Exception:  # noqa: BLE001 - minuterie déjà passée
                    pass
            self._attente = self.run_in(self._maj, 3)

        def _maj(self, **kwargs):
            """Publie le capteur ; renvoie ses attributs (None si HA est illisible)."""
            self._attente = None
            try:
                lu = self._api("services/donnees_apps/lire", {"espace": self._espace}, reponse=True)
                enregistrements = (lu.get("service_response") or {}).get("enregistrements", [])
                etat, attributs = calculer(enregistrements, datetime.now(PARIS))
                # Par l'API REST et non `set_state` : AppDaemon retire les listes vides des attributs (voir hub_meteo).
                # Publié à chaque passage : après un redémarrage de HA, le capteur revient au plus tard en 10 min.
                self._api(f"states/{ENTITE}", {"state": etat, "attributes": dict(
                    attributs, friendly_name="Pour info du Hub", icon="mdi:bullhorn")})
                return attributs
            except Exception as exc:  # noqa: BLE001 - le capteur garde sa dernière valeur
                self.log(f"Pour info : calcul impossible ({exc!r})", level="WARNING")
                return None

        def _resume(self, **kwargs):
            attributs = self._maj()
            texte = attributs and texte_notification(attributs)
            if not texte:
                return
            try:
                self._api("services/script/hub_notifier", {"texte": texte, "titre": "Aiguillage", "niveau": "info"})
                self.log(f"Pour info : {texte}")
            except Exception as exc:  # noqa: BLE001
                self.log(f"Pour info : notification impossible ({exc!r})", level="WARNING")
