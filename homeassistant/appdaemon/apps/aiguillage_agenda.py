"""Agenda « Sorties » d'Aiguillage (19/10, demande d'Alexandre) : les sorties réservées (`envie.type: sortie` ou ligne
`🎟 Sortie`, plan P9-L1) en fichier iCalendar, publié par la vigie dans `/homeassistant/www/aiguillage/<clé>/`
et servi par HA en `/local/…`. Google Agenda et le Calendrier d'Apple s'y abonnent (lecture seule) : une sortie
ajoutée, déplacée ou vue dans Aiguillage s'y reflète au rafraîchissement de l'abonnement.

Fonctions pures, testées hors Home Assistant par `tests/test_aiguillage_agenda.py`.
"""

from datetime import datetime, timedelta
import re
from zoneinfo import ZoneInfo

PARIS = ZoneInfo("Europe/Paris")
NOM = "Sorties"
DUREE_DEFAUT = 180  # minutes : un concert, un spectacle
SORTIE = "\U0001F39F"
# Lignes techniques des notes (lieu, type d'envie, pièces, dictée…), retirées de la description.
TECHNIQUES = ("📍", "🎟", "👀", "🍽", "🛍", "📷", "📖", "🎧", "🎬", "🗓", "🔄", "🔔", "🔕", "📅", "📎", "🎙", "📩",
              "➕", "💡", "🛒", "🍳", "💶", "↪", "🎒", "📣")
_CLE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.I)


def est_sortie(valeur):
    if (valeur.get("envie") or {}).get("type") == "sortie":
        return True
    return any(l.replace("\ufe0f", "").strip().startswith(SORTIE) for l in (valeur.get("notes") or "").split("\n"))


def sorties(records):
    """Enregistrements des sorties datées (tâches, non supprimées), faites comprises (l'agenda garde l'historique)."""
    return [r for r in records
            if _CLE.match(r.get("cle") or "") and not r.get("supprime") and isinstance(r.get("valeur"), dict)
            and est_sortie(r["valeur"]) and r["valeur"].get("jour")]


def _echappe(texte):
    return (texte or "").replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")


def _plie(ligne):
    """Lignes de 75 octets au plus, suite précédée d'une espace (RFC 5545), sans couper un caractère."""
    out, courant = [], ""
    for c in ligne:
        if len((courant + c).encode()) > (75 if not out else 74):
            out.append(courant)
            courant = c
        else:
            courant += c
    out.append(courant)
    return "\r\n ".join(out)


def _utc(d):
    return d.astimezone(ZoneInfo("UTC")).strftime("%Y%m%dT%H%M%SZ")


def description(valeur):
    """Notes sans les lignes techniques, puis le lien du billet ou de la billetterie."""
    lignes = [l for l in (valeur.get("notes") or "").split("\n")
              if l.strip() and not l.replace("\ufe0f", "").strip().startswith(TECHNIQUES)]
    lien = (valeur.get("envie") or {}).get("lien")
    if lien and lien not in "\n".join(lignes):
        lignes.append(lien)
    if valeur.get("pieces"):
        lignes.append("Billet dans Aiguillage (pièce jointe).")
    return "\n".join(lignes)


def evenement(record, horodatage):
    v = record["valeur"]
    jour = datetime.strptime(v["jour"][:10], "%Y-%m-%d")
    lignes = ["BEGIN:VEVENT", f"UID:{record['cle']}@aiguillage", f"DTSTAMP:{horodatage}",
              f"SUMMARY:{_echappe(v.get('titre') or 'Sortie')}"]
    m = re.match(r"^(\d{1,2}):(\d{2})", v.get("heure") or "")
    if m:
        debut = jour.replace(hour=int(m[1]), minute=int(m[2]), tzinfo=PARIS)
        fin = debut + timedelta(minutes=int(v.get("duree") or DUREE_DEFAUT))
        lignes += [f"DTSTART:{_utc(debut)}", f"DTEND:{_utc(fin)}"]
    else:
        lignes += [f"DTSTART;VALUE=DATE:{jour:%Y%m%d}", f"DTEND;VALUE=DATE:{jour + timedelta(days=1):%Y%m%d}"]
    lieu = v.get("lieu") or {}
    endroit = ", ".join(x for x in (lieu.get("nom"), lieu.get("adresse")) if x)
    if endroit:
        lignes.append(f"LOCATION:{_echappe(endroit)}")
    desc = description(v)
    if desc:
        lignes.append(f"DESCRIPTION:{_echappe(desc)}")
    lignes.append("END:VEVENT")
    return lignes


def ics(records, maintenant):
    """Le fichier iCalendar (texte, fins de ligne CRLF). `maintenant` : datetime avec fuseau (DTSTAMP)."""
    horodatage = _utc(maintenant)
    lignes = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Aiguillage//Sorties//FR", "CALSCALE:GREGORIAN",
              "METHOD:PUBLISH", f"X-WR-CALNAME:{NOM}", "X-WR-TIMEZONE:Europe/Paris",
              "REFRESH-INTERVAL;VALUE=DURATION:PT1H", "X-PUBLISHED-TTL:PT1H"]
    for r in sorted(sorties(records), key=lambda r: (r["valeur"]["jour"], r["valeur"].get("heure") or "")):
        lignes += evenement(r, horodatage)
    lignes.append("END:VCALENDAR")
    return "\r\n".join(_plie(l) for l in lignes) + "\r\n"


def sans_horodatage(texte):
    """Le contenu sans les DTSTAMP : sert à ne réécrire le fichier que s'il a vraiment changé."""
    return re.sub(r"DTSTAMP:\d{8}T\d{6}Z", "", texte)
