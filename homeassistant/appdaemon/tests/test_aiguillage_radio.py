"""Tests hors Home Assistant de `aiguillage_radio` : python3 -m pytest homeassistant/appdaemon/tests"""

from datetime import date
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import aiguillage_radio as r  # noqa: E402

TODAY = date(2026, 10, 22)
MAINTENANT = "2026-10-22T19:30:00+00:00"
RADIO = {"titre": "Radio Tsugi", "fait": False, "envie": {"type": "ecouter", "plateforme": "tunein", "note": "radio"}}
# Réponses réelles de music_assistant.search du 22/10.
TSUGI = [{"uri": "tunein--aPad5vVY://radio/s257284", "name": "Tsugi Radio", "image": "https://cdn-radiotime-logos.tunein.com/s257284q.png"},
         {"uri": "tunein--aPad5vVY://radio/s126780", "name": "The Disco Palace"}]
SUNSHINE = [{"uri": "tunein--aPad5vVY://radio/s118816", "name": "Sunshine Radio"},
            {"uri": "tunein--aPad5vVY://radio/s325460", "name": "Sunshine Radio"},
            {"uri": "tunein--aPad5vVY://radio/s184797", "name": "Mallorca Sunshine Radio"}]
OXIGENIO = [{"uri": "tunein--aPad5vVY://radio/s83943", "name": "Rádio Oxigénio"},
            {"uri": "tunein--aPad5vVY://radio/s244711", "name": "OXIGENO RADIO"}]


def test_requete():
    assert r.requete("Écouter radio tsugi") == "radio tsugi"
    assert r.requete("écouter la radio Tsugi") == "radio Tsugi"
    assert r.requete("Rádio Oxigénio (radio portugaise)") == "Rádio Oxigénio"
    assert r.requete("Sunshine Radio sur TuneIn") == "Sunshine Radio"


def test_a_chercher():
    assert r.a_chercher(RADIO, TODAY)
    assert not r.a_chercher({**RADIO, "fait": True}, TODAY)
    assert not r.a_chercher({**RADIO, "envie": {"type": "ecouter", "plateforme": "spotify"}}, TODAY)
    vue = {**RADIO, "envie": {**RADIO["envie"], "radio": {"statut": "introuvable", "maj": "2026-10-20", "requete": "Radio Tsugi"}}}
    assert not r.a_chercher(vue, TODAY)
    assert r.a_chercher(vue, date(2026, 10, 27))
    assert r.a_chercher({**vue, "titre": "Tsugi Radio"}, TODAY)
    ajoutee = {**RADIO, "envie": {**RADIO["envie"], "radio": {"statut": "ajoutee"}}}
    assert not r.a_chercher(ajoutee, date(2027, 1, 1))


def test_choisir():
    assert r.choisir(TSUGI, "radio tsugi")["uri"].endswith("s257284")
    assert r.choisir(TSUGI, "Tsugi")["uri"].endswith("s257284")
    # Deux stations du même nom : la première de TuneIn.
    assert r.choisir(SUNSHINE, "Sunshine Radio")["uri"].endswith("s118816")
    assert r.choisir(OXIGENIO, "Rádio Oxigénio")["uri"].endswith("s83943")
    assert r.choisir(OXIGENIO, "Oxigenio")["uri"].endswith("s83943")
    assert r.choisir(TSUGI, "Couleur 3") is None
    assert r.choisir([], "Tsugi") is None
    assert r.choisir(TSUGI, "radio") is None


def test_station_et_tache_cochee():
    st = r.station(TSUGI[0])
    assert st == {"id": "tunein_s257284", "nom": "Tsugi Radio", "uri": "tunein--aPad5vVY://radio/s257284",
                  "image": "https://cdn-radiotime-logos.tunein.com/s257284q.png"}
    t = r.avec_station(RADIO, st, MAINTENANT)
    assert t["fait"] and t["fait_le"] == MAINTENANT and t["v"] == 2
    assert t["envie"]["radio"]["statut"] == "ajoutee" and t["envie"]["note"] == "radio"
    assert RADIO["fait"] is False  # l'objet lu n'est pas modifié


def test_statut_et_suggestion_une_fois():
    t = r.avec_statut(RADIO, "introuvable", [], TODAY)
    assert t["envie"]["radio"]["statut"] == "introuvable" and t["notes"] == r.SUGGESTION
    t2 = r.avec_statut(t, "introuvable", [], date(2026, 10, 29))
    assert t2["notes"] == r.SUGGESTION and not t2["fait"]


def test_liste_et_etat():
    st = r.station(TSUGI[0])
    liste = r.ajouter(None, st, "325e59c0", MAINTENANT)
    assert liste["radios"][0]["tache"] == "325e59c0"
    assert r.ajouter(liste, st, "autre", MAINTENANT) is None
    etat, attributs = r.etat(liste)
    assert etat == "1" and attributs["radios"] == [{k: st[k] for k in ("id", "nom", "uri", "image")}]
