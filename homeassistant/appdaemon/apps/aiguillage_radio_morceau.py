"""Morceau de la radio en cours (29/10/2026, contrat : homeassistant/RADIO-MORCEAU.md) : `sensor.radio_morceau`.

Quand une radio joue sur les LS50 (ou la LSX de la chambre) par Music Assistant : quel morceau passe, et ce morceau
sur Spotify, pour « ♡ Garder ce titre » (`script.radio_garder_titre` → événement `radio_garder_titre` :
titres likés par défaut, décision d'Alexandre du 29/10 à 20 h 45).

Sources : métadonnées du flux (titre + artiste, jingles écartés) ; Couleur 3 par l'API publique de la RTS (songList) ;
Radio France par `livemeta/pull/<id>` (pas `live/<id>/inter_player` : vérifié le 29/10, son `now` reste l'émission
même quand un morceau passe ; `pull` donne les pas `song` avec début et fin). Les stations qui ont une API passent
par elle d'abord (leur flux donne souvent le nom de l'émission).

Fonctions pures et classe `Suivi` (rythme, caches) ici, testées sans HA ; appels HA dans `relance_vigie.py`.
"""

from collections import OrderedDict
from datetime import datetime
import re
import unicodedata

import aiguillage_lecteur

ENTITE = "sensor.radio_morceau"
LECTEURS = (aiguillage_lecteur.ENTITE_MA, "media_player.lsx_1190fa")
EVENEMENT = "radio_garder_titre"

RTS_URL = ("https://il.srgssr.ch/integrationlayer/2.0/rts/songList/radio/byChannel/"
           "8ceb28d9b3f1dd876d1df1780f908578cbefc3d7?pageSize=3")
RF_URL = "https://api.radiofrance.fr/livemeta/pull/{}"
# Radio France : (clés dans media_content_id ou nom de station, identifiant livemeta, nom).
RADIO_FRANCE = (
    (("franceinter", "s24875", "france inter"), 1, "France Inter"),
    (("franceculture", "s2442", "france culture"), 5, "France Culture"),
    (("radiofrance.fr/fip", "/fip-", "/fip.", "s15200", "fip"), 7, "FIP"),
)
COULEUR3 = (("s15474", "couleur 3", "couleur3"), "Couleur 3")
# Couleur 3 : morceau le plus récent s'il joue (`isPlayingNow`) ou a commencé il y a moins de 6 min.
RTS_FRAICHEUR = 6 * 60

API_INTERVALLE = 30         # une API de radio interrogée au plus toutes les 30 s
REPUBLIER = 600
CACHE_MAX = 300
ENTENDUS_MAX = 200
CLE_ENTENDUS = "radio:entendus"
PLAYLIST_A_ECOUTER = "3bZ9RxcAN2UIXIhgGYHhlp"   # « À écouter » d'Alexandre (repli si config:playlist_a_ecouter manque)
# Décision d'Alexandre (29/10, 20 h 45) : « Garder » = titres likés par défaut ; « À écouter » par le paramètre.
DESTINATIONS = ("aime", "a_ecouter")
DESTINATION_DEFAUT = "aime"
URI_PISTE = re.compile(r"spotify:track:([A-Za-z0-9]{22})")


# MARK: - Textes

def _texte(valeur):
    return valeur.strip() if isinstance(valeur, str) else ""


def plier(texte):
    """Sans accents, sans casse, ponctuation en espaces, espaces simples."""
    d = unicodedata.normalize("NFD", _texte(texte))
    s = "".join(c for c in d if not unicodedata.combining(c)).casefold().replace("&", " and ")
    s = re.sub(r"[^\w]+", " ", s)
    return " ".join(s.split())


# « (feat. X) », « [ft. X] », « feat. X » en fin, « (Radio Edit) », « - Radio Edit », « (Edit) ».
_FEAT = re.compile(r"[\(\[]\s*(?:feat|ft|featuring)\b[^\)\]]*[\)\]]|\s(?:feat|ft|featuring)\.?\s.*$", re.I)
_EDIT = re.compile(r"[\(\[][^\)\]]*\b(?:radio edit|radio version|single version|edit)\b[^\)\]]*[\)\]]"
                   r"|\s-\s[^-]*\b(?:radio edit|radio version|single version|edit)\b.*$", re.I)


_PREFIXE = re.compile(r"^\s*[\(\[][^\)\]]{1,8}[\)\]]\s*")


def titre_affiche(titre):
    """Le titre sans étiquette en tête (« (REP) As It Goes » de la RTS, 29/10/2026)."""
    return _PREFIXE.sub("", _texte(titre)).strip()


def titre_propre(titre):
    """Le titre sans étiquette en tête, ni « feat. … », ni « (Radio Edit) » (texte de recherche)."""
    t = _EDIT.sub("", _FEAT.sub("", titre_affiche(titre)))
    return " ".join(t.split()).strip(" -")


def cle_titre(titre):
    return plier(titre_propre(titre))


def cle_titre_court(titre):
    """Titre sans aucune parenthèse ni suffixe « - … » (Remastered, Live…) : comparaison de repli."""
    t = re.sub(r"[\(\[][^\)\]]*[\)\]]", "", titre_propre(titre))
    t = re.sub(r"\s-\s.*$", "", t)
    return plier(t)


_SEPARATEURS = re.compile(r"\s+(?:feat\.?|ft\.?|featuring|&|and|et|x|vs\.?|with)\s+|\s*[,;/+]\s*", re.I)


def artistes_radio(artiste):
    """Les noms d'un artiste de radio (« A feat. B », « A & B », « Dejot (CH) ») pliés, sans parenthèses."""
    a = re.sub(r"[\(\[][^\)\]]*[\)\]]", "", _texte(artiste))
    noms = [plier(n) for n in _SEPARATEURS.split(a)]
    tout = plier(a)
    return [n for n in dict.fromkeys([tout] + noms) if n]


def concorde(titre, artiste, piste):
    """Le titre Spotify `piste` correspond-il au morceau (titre et artiste, sans accents ni casse) ?"""
    if not isinstance(piste, dict):
        return False
    nom = piste.get("name")
    if not (cle_titre(nom) == cle_titre(titre) or (cle_titre_court(nom) and cle_titre_court(nom) == cle_titre_court(titre))):
        return False
    radio = set(artistes_radio(artiste))
    spot = [plier(re.sub(r"[\(\[][^\)\]]*[\)\]]", "", a.get("name") or "")) for a in piste.get("artists") or []]
    return any(s and s in radio for s in spot) or plier(", ".join(a.get("name") or "" for a in piste.get("artists") or [])) in radio


def requetes(titre, artiste):
    """Recherches Spotify, dans l'ordre : champs exacts, puis texte libre."""
    t, a = titre_propre(titre).replace('"', ""), _texte(artiste).replace('"', "")
    return [f'track:"{t}" artist:"{a}"', f"{t} {a}"]


def _image(images):
    images = [i for i in images or [] if isinstance(i, dict) and i.get("url")]
    grandes = sorted((i for i in images if (i.get("width") or 0) >= 300), key=lambda i: i.get("width") or 0)
    return (grandes[0] if grandes else images[0])["url"] if images else None


def spotify_de(piste):
    """Élément `spotify` du capteur pour une piste de `/search`."""
    return {
        "uri": piste["uri"],
        "lien": f"https://open.spotify.com/track/{piste['id']}",
        "titre": piste.get("name") or "",
        "artistes": ", ".join(a.get("name") or "" for a in piste.get("artists") or []),
        "image": _image((piste.get("album") or {}).get("images")),
    }


def choisir(titre, artiste, pistes):
    """Première piste qui concorde, au format du capteur ; None sinon."""
    for p in pistes or []:
        if isinstance(p, dict) and p.get("uri") and p.get("id") and concorde(titre, artiste, p):
            return spotify_de(p)
    return None


# MARK: - Radio en cours

def radio_en_cours(etats, ajoutees=()):
    """(entité, état, station) de la première radio qui joue (LS50 d'abord), ou None."""
    for entite in LECTEURS:
        etat = (etats or {}).get(entite)
        if not etat or etat.get("state") != "playing":
            continue
        etat = dict(etat, entity_id=entite)
        c = aiguillage_lecteur.contenu(etat, "", ajoutees)
        if c and c.get("radio"):
            return entite, etat, c.get("source") or "Radio"
    return None


def api_de(ident, station):
    """("rts", url) | ("radiofrance", url) | None selon la station."""
    i, s = _texte(ident).lower(), plier(station)
    if any(k in i or k == s for k in COULEUR3[0]):
        return "rts", RTS_URL
    for cles, num, _nom in RADIO_FRANCE:
        for k in cles:
            if k == "fip":
                if s == "fip" or ("radiofrance" in i and re.search(r"(?<![a-z])fip(?![a-z])", i)):
                    return "radiofrance", RF_URL.format(num)
            elif k in i or k == s:
                return "radiofrance", RF_URL.format(num)
    return None


def _jingle(texte, station):
    t = plier(texte)
    if not t:
        return True
    if t.startswith(("jg ", "jingle", "pub ", "publicite")) or t in ("jg", "pub", "en direct", "live"):
        return True
    st = plier(station)
    return bool(st) and (t == st or t == plier(re.sub(r"\bradio\b", "", station, flags=re.I)))


def morceau_du_flux(etat, station):
    """(titre, artiste) des métadonnées du flux, ou None (pas d'artiste, jingle, nom de station, titre-fichier)."""
    a = (etat or {}).get("attributes") or {}
    titre, artiste = _texte(a.get("media_title")), _texte(a.get("media_artist"))
    ident = _texte(a.get("media_content_id"))
    if not titre or not artiste or aiguillage_lecteur.titre_fichier(titre, ident):
        return None
    album = _texte(a.get("media_album_name"))
    for texte in (titre, artiste):
        if _jingle(texte, station) or (album and plier(texte) == plier(album)):
            return None
    return titre, artiste


def _epoch(iso):
    try:
        return datetime.fromisoformat(iso).timestamp()
    except (TypeError, ValueError):
        return None


def morceau_rts(donnees, epoch):
    """(titre, artiste) de la songList de la RTS : le plus récent, s'il joue ou a commencé il y a moins de 6 min."""
    chansons = [c for c in (donnees or {}).get("songList") or [] if isinstance(c, dict)]
    if not chansons:
        return None
    c = max(chansons, key=lambda c: _epoch(c.get("date")) or 0)
    debut = _epoch(c.get("date"))
    if not c.get("isPlayingNow") and (debut is None or not 0 <= epoch - debut < RTS_FRAICHEUR):
        return None
    titre, artiste = _texte(c.get("title")), _texte((c.get("artist") or {}).get("name"))
    return (titre, artiste) if titre and artiste else None


def morceau_radiofrance(donnees, epoch):
    """(titre, artiste) de Radio France : pas `song` en cours de `livemeta/pull` (interprètes, sinon auteurs) ;
    accepte aussi `now.song` de `live/<id>/inter_player` s'il existe un jour. None pendant une émission."""
    donnees = donnees or {}
    for pas in (donnees.get("steps") or {}).values():
        if not isinstance(pas, dict) or pas.get("embedType") != "song":
            continue
        debut, fin = pas.get("start"), pas.get("end")
        if isinstance(debut, (int, float)) and isinstance(fin, (int, float)) and debut <= epoch < fin:
            titre = _texte(pas.get("title"))
            artiste = _texte(pas.get("performers")) or _texte(pas.get("authors"))
            if titre and artiste:
                return titre, artiste
    song = (donnees.get("now") or {}).get("song")
    if isinstance(song, dict):
        titre = _texte(song.get("title"))
        interpretes = song.get("interpreters") or song.get("performers") or []
        artiste = ", ".join(_texte(i) for i in interpretes if _texte(i)) if isinstance(interpretes, list) \
            else _texte(interpretes)
        if titre and artiste:
            return titre, artiste
    return None


# MARK: - Capteur

def _vide(maintenant_iso):
    return {"titre": None, "artiste": None, "station": None, "origine": None, "spotify": None, "deja_garde": False,
            "maj": maintenant_iso}


def sortie(etat, maintenant_iso, titre=None, artiste=None, station=None, origine=None, spotify=None, deja=False):
    attrs = _vide(maintenant_iso)
    if etat != "rien":
        attrs.update({"titre": titre, "artiste": artiste, "station": station, "origine": origine})
    if etat == "trouve":
        attrs.update({"spotify": spotify, "deja_garde": bool(deja)})
    return etat, attrs


def indisponible(motif, maintenant_iso):
    return "unavailable", {"maj": maintenant_iso, "erreur": motif}


def sans_maj(resultat):
    etat, attributs = resultat
    return etat, {k: v for k, v in attributs.items() if k != "maj"}


def a_publier(ancien, nouveau, t_ancien, t):
    if ancien is None:
        return True
    return sans_maj(ancien) != sans_maj(nouveau) or t - t_ancien >= REPUBLIER


class Suivi:
    """Rythme et caches. `lire_json(url)` → dict ; `chercher(q)` → liste de pistes de `/search` ; tous deux lèvent
    une exception en cas d'erreur (le capteur passe alors à « unavailable », rien n'est écrit)."""

    def __init__(self, lire_json, chercher, contient=None):
        self._lire_json = lire_json
        self._chercher = chercher
        self._api = {}                 # url → (données, instant)
        self.cache = OrderedDict()     # (titre plié, artiste plié) → spotify | None
        self._contient = contient      # uri → bool : déjà dans les titres likés (lève en cas d'erreur)
        self.likes = OrderedDict()     # uri → bool, en cache par morceau
        self.gardes = set()            # uris gardées depuis le démarrage (likées ou mises dans « À écouter »)
        self.dernier = None            # (état, attributs) du dernier calcul

    def _donnees(self, url, t):
        deja = self._api.get(url)
        if deja and 0 <= t - deja[1] < API_INTERVALLE:
            return deja[0]
        donnees = self._lire_json(url)
        self._api[url] = (donnees, t)
        return donnees

    def spotify(self, titre, artiste):
        cle = (cle_titre(titre), plier(artiste))
        if cle in self.cache:
            self.cache.move_to_end(cle)
            return self.cache[cle]
        trouve = None
        for q in requetes(titre, artiste):
            trouve = choisir(titre, artiste, self._chercher(q))
            if trouve:
                break
        self.cache[cle] = trouve
        while len(self.cache) > CACHE_MAX:
            self.cache.popitem(last=False)
        return trouve

    def calculer(self, etats, ajoutees, t, epoch, maintenant_iso):
        """(état, attributs) du capteur ; une erreur d'API (radio ou Spotify) → « unavailable »."""
        try:
            resultat = self._calculer(etats, ajoutees, t, epoch, maintenant_iso)
        except Exception as erreur:  # noqa: BLE001 - réseau, HTTP, JSON : capteur indisponible, rien d'écrit
            resultat = indisponible(type(erreur).__name__, maintenant_iso)
        self.dernier = resultat
        return resultat

    def _calculer(self, etats, ajoutees, t, epoch, maintenant_iso):
        en_cours = radio_en_cours(etats, ajoutees)
        if not en_cours:
            return sortie("rien", maintenant_iso)
        _entite, etat, station = en_cours
        ident = (etat.get("attributes") or {}).get("media_content_id")
        api = api_de(ident, station)
        morceau, origine = None, None
        if api:
            origine, url = api
            donnees = self._donnees(url, t)
            morceau = morceau_rts(donnees, epoch) if origine == "rts" else morceau_radiofrance(donnees, epoch)
        if not morceau:
            flux = morceau_du_flux(etat, station)
            if flux:
                morceau, origine = flux, "flux"
        if not morceau:
            return sortie("emission", maintenant_iso, station=station, origine=origine)
        titre, artiste = titre_affiche(morceau[0]) or morceau[0], morceau[1]
        sp = self.spotify(titre, artiste)
        if not sp:
            return sortie("inconnu_spotify", maintenant_iso, titre, artiste, station, origine)
        return sortie("trouve", maintenant_iso, titre, artiste, station, origine, sp, self.deja(sp["uri"]))

    def deja(self, uri):
        """Déjà liké (`/me/library/contains`, en cache par morceau) ou gardé depuis le démarrage. Une erreur ne rend
        pas le capteur indisponible : False, et nouvel essai au passage suivant."""
        if uri in self.gardes:
            return True
        if uri not in self.likes and self._contient:
            try:
                self.likes[uri] = bool(self._contient(uri))
            except Exception:  # noqa: BLE001
                return False
            while len(self.likes) > CACHE_MAX:
                self.likes.popitem(last=False)
        return self.likes.get(uri, False)

    def garde(self, uri, dest):
        self.gardes.add(uri)
        if dest == "aime":
            self.likes[uri] = True


# MARK: - « ♡ Garder ce titre »

def uri_valide(uri):
    m = URI_PISTE.fullmatch(_texte(uri))
    return m.group(1) if m else None


def destination(valeur):
    v = _texte(valeur).lower() or DESTINATION_DEFAUT
    return v if v in DESTINATIONS else DESTINATION_DEFAUT


def infos_garde(uri, dernier, cache):
    """{titre, artiste, station} du titre gardé : le capteur s'il montre cette uri, sinon le cache de recherche."""
    if dernier and dernier[0] == "trouve" and ((dernier[1].get("spotify") or {}).get("uri") == uri):
        a = dernier[1]
        return {"titre": a.get("titre"), "artiste": a.get("artiste"), "station": a.get("station")}
    for sp in (cache or {}).values():
        if sp and sp.get("uri") == uri:
            return {"titre": sp.get("titre"), "artiste": sp.get("artistes"), "station": None}
    return {"titre": None, "artiste": None, "station": None}


def entendus_apres(valeur, entree):
    """Valeur de `radio:entendus` avec `entree` en tête (200 au plus)."""
    liste = [e for e in ((valeur or {}).get("entendus") or []) if isinstance(e, dict)] if isinstance(valeur, dict) else []
    return {"entendus": ([entree] + liste)[:ENTENDUS_MAX]}


def uris_entendus(valeur):
    if not isinstance(valeur, dict):
        return set()
    return {e["uri"] for e in valeur.get("entendus") or [] if isinstance(e, dict) and e.get("uri")}


def texte_garde(infos, dest=DESTINATION_DEFAUT):
    """« Liké : titre — artiste » (titres likés) ou « Gardé : titre — artiste » (« À écouter »)."""
    mot = "Liké" if dest == "aime" else "Gardé"
    titre, artiste = _texte(infos.get("titre")), _texte(infos.get("artiste"))
    if titre and artiste:
        return f"{mot} : {titre} — {artiste}"
    return f"{mot} : {titre}" if titre else ("Titre liké" if dest == "aime" else "Titre gardé")


def garder(client, playlist_id, uri, dest=DESTINATION_DEFAUT):
    """Ajoute le titre aux titres likés (par défaut, `aimer` d'aiguillage_spotify), ou à « À écouter » (`playlist_id`,
    jamais créée ici) s'il n'y est pas déjà.
    Renvoie True si quelque chose a été ajouté. Les erreurs remontent."""
    ident = uri_valide(uri)
    if not ident:
        raise ValueError("uri Spotify de titre invalide")
    if dest == "aime":
        client.aimer("track", ident)
        return True
    if not playlist_id:
        raise ValueError("playlist « À écouter » inconnue")
    if uri in client.contenu(playlist_id):
        return False
    client._call("POST", f"/playlists/{playlist_id}/items", json={"uris": [uri]})
    return True


def contient(client, uri):
    """Le titre est-il dans les titres likés ? API de février 2026 `GET /me/library/contains`, repli sur
    `GET /me/tracks/contains` (même logique que `aimer`). Les erreurs remontent."""
    import httpx

    try:
        reponse = client._call("GET", "/me/library/contains", params={"uris": uri})
    except httpx.HTTPStatusError as erreur:
        if erreur.response.status_code not in (404, 405):
            raise
        reponse = client._call("GET", "/me/tracks/contains", params={"ids": uri_valide(uri)})
    return bool(reponse and reponse[0] is True)
