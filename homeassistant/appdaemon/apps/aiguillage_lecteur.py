"""Activité en direct « En lecture sur les LS50 » du Hub (23/10/2026) : code pur, sans AppDaemon.

La vigie (`relance_vigie.py`) surveille le lecteur des LS50 et pilote l'activité sur l'écran verrouillé (et l'îlot
dynamique) de chaque appareil où le Hub est installé, iPad et iPhone, par des push APNs `liveactivity` : démarrage à
distance (`push-to-start`), mises à jour, fin. Ce module choisit l'entité, construit le `content-state`, décide quoi
envoyer à chaque appareil (Spotify Connect compris), range les jetons et compte les pushs.

Côté app : `hub-ipad/Partage/LecteurLS50.swift` (`LecteurLS50Attributes`, son `ContentState` a les mêmes champs).
"""

ENTITE_MA = "media_player.salon_ls50_5"
ENTITE_KEF = "media_player.kef_ls50_wireless_ii"
NOM = "Salon LS50"
# Nom exact du type Swift (`attributes-type` du push-to-start).
TYPE_ATTRIBUTS = "LecteurLS50Attributes"
SUJET = "fr.alexandrefau.hubipad.push-type.liveactivity"
# Anti-rafale entre deux envois, et arrêt (plus rien ne joue) avant de terminer l'activité.
RAFALE = 2
ARRET_AVANT_FIN = 5 * 60
JOUE = ("playing", "paused")
# Contenu de fin quand on ne sait plus ce qui jouait (vigie relancée) : l'app doit pouvoir le décoder.
REPOS = {"titre": NOM, "artiste": "", "source": "", "image": None, "etat": "pause", "volume": 0, "radio": False}
# Entrées de l'enceinte KEF (lecture hors Music Assistant).
SOURCES_KEF = {
    "optical": "Optique",
    "tv": "TV",
    "bluetooth": "Bluetooth",
    "coaxial": "Coaxial",
    "analog": "Analogique",
    "usb": "USB",
    "wifi": "Wi-Fi",
}


def choisir_entite(etats):
    """L'état de l'entité qui joue (ou en pause) : Music Assistant, sinon KEF, sinon None (règle du Hub)."""
    for entite in (ENTITE_MA, ENTITE_KEF):
        etat = etats.get(entite)
        if etat and etat.get("state") in JOUE:
            return etat
    return None


def spotify_connect(etat):
    """La lecture vient de Spotify Connect (lancée depuis un téléphone ou une tablette vers les LS50) ?

    Critère (états réels du 23/10/2026) : l'enceinte KEF dit `source: wifi` pour tout et n'a pas d'attribut d'appli,
    mais une lecture Spotify Connect se fait SANS Music Assistant (`media_player.salon_ls50_5` idle) ; quand Music
    Assistant joue (radios, « À écouter »), c'est lui qui est choisi. Donc : l'entité choisie est la KEF, entrée Wi-Fi.
    Un AirPlay vers l'enceinte tomberait aussi ici (indiscernable), et c'est voulu : l'appareil qui l'envoie a déjà son
    propre lecteur sur l'écran verrouillé.
    """
    if not etat or etat.get("entity_id") != ENTITE_KEF or etat.get("state") not in JOUE:
        return False
    return _texte((etat.get("attributes") or {}).get("source")).lower() == "wifi"


def _texte(valeur):
    return valeur.strip() if isinstance(valeur, str) else ""


def contenu(etat, ha_url=""):
    """Le `content-state` de l'activité pour l'état d'une entité ; None si elle ne joue pas.

    Mêmes règles que le lecteur du Hub iPad (`PleinEcran.source`) : radio → nom de la station (album), sinon
    « Spotify », « Qobuz », l'album ; KEF hors Music Assistant → son entrée (« Optique »…) ou l'appli.
    """
    if not etat or etat.get("state") not in JOUE:
        return None
    a = etat.get("attributes") or {}
    entite = etat.get("entity_id", "")
    ident = _texte(a.get("media_content_id"))
    radio = "/radio/" in ident or "://radio" in ident or "radiofrance" in ident
    album = _texte(a.get("media_album_name"))
    if radio:
        source = album or "Radio"
    elif ident.startswith("spotify"):
        source = "Spotify"
    elif ident.startswith("qobuz"):
        source = "Qobuz"
    elif entite == ENTITE_KEF:
        entree = _texte(a.get("source")).lower()
        source = _texte(a.get("app_name")) or SOURCES_KEF.get(entree, _texte(a.get("source")))
    else:
        source = album
    titre = _texte(a.get("media_title")) or source or NOM
    image = _texte(a.get("entity_picture")) or None
    if image and image.startswith("/"):
        image = ha_url.rstrip("/") + image if ha_url else None
    volume = a.get("volume_level")
    return {
        "titre": titre,
        "artiste": _texte(a.get("media_artist")),
        "source": source,
        "image": image,
        "etat": "lecture" if etat.get("state") == "playing" else "pause",
        "volume": int(round(volume * 100)) if isinstance(volume, (int, float)) else 0,
        "radio": radio,
    }


def decider(actuel, envoye, en_cours, arret_depuis, maintenant):
    """Que faire : ("start" | "update" | "end" | None, priorité APNs).

    - `actuel` : contenu de ce qui joue (None : arrêté, idle, éteint) ;
    - `envoye` : dernier contenu envoyé ; `en_cours` : une activité tourne ;
    - `arret_depuis` : instant où plus rien ne joue (None si ça joue).
    Démarrage seulement sur une vraie lecture (pas une pause) ; fin après 5 min d'arrêt ; mise à jour à chaque
    changement (priorité 10 si le titre change, 5 sinon : état, volume…).
    """
    if actuel is None:
        if en_cours and arret_depuis is not None and maintenant - arret_depuis >= ARRET_AVANT_FIN:
            return "end", 10
        return None, 0
    if not en_cours:
        return ("start", 10) if actuel["etat"] == "lecture" else (None, 0)
    if actuel == envoye:
        return None, 0
    if not envoye or actuel.get("titre") != envoye.get("titre"):
        return "update", 10
    return "update", 5


def alerte(c):
    """Notification qui accompagne le démarrage (sans son)."""
    corps = " · ".join(m for m in (c["titre"], c["artiste"]) if m)
    return {"title": "En lecture sur les LS50", "body": corps}


def payload_start(c, maintenant, nom=NOM):
    return {"aps": {
        "timestamp": int(maintenant),
        "event": "start",
        "content-state": c,
        "attributes-type": TYPE_ATTRIBUTS,
        "attributes": {"nom": nom},
        "alert": alerte(c),
    }}


def payload_update(c, maintenant):
    return {"aps": {"timestamp": int(maintenant), "event": "update", "content-state": c}}


def payload_end(c, maintenant):
    """Fin : l'activité disparaît tout de suite (`dismissal-date` = maintenant)."""
    return {"aps": {"timestamp": int(maintenant), "event": "end", "content-state": c,
                    "dismissal-date": int(maintenant)}}


def entetes(priorite):
    return {"apns-push-type": "liveactivity", "apns-topic": SUJET, "apns-priority": str(priorite)}


# MARK: - Jetons (/config/hub_ipad_activite.json)
#
# Plusieurs appareils (iPad, iPhone, 23/10/2026) : chaque jeton porte l'identifiant de son appareil (`appareil`,
# `identifierForVendor` de l'app) et son modèle (« iPad », « iPhone ») ; un nouveau jeton push-to-start remplace
# l'ancien du même appareil (iOS en change de temps en temps : sans ça, deux jetons valides démarreraient deux
# activités sur le même écran). `demarres` : appareils déjà démarrés pendant la lecture en cours (pas de second
# démarrage en attendant leur jeton d'activité) ; vidé à la fin. Jetons sans appareil (app d'avant) : rangés comme
# avant, sous leur propre jeton.
#
# « Masquer l'activité quand Spotify pilote » (réglage de chaque appareil dans le Hub, activé par défaut) : envoyé avec
# chaque jeton (`masquer_spotify`), rangé dans `reglages[appareil]`. Pendant une lecture Spotify Connect, la vigie ne
# démarre pas l'activité sur ces appareils et termine celle qui y tourne (Spotify affiche déjà son propre lecteur).
#
# Activités fermées par iOS (24/10/2026) : une mise à jour de l'app ferme les activités de l'ancienne version, mais APNs
# accepte encore (200) les mises à jour vers leurs jetons morts, et la vigie croyait l'appareil occupé pour toujours.
# L'app envoie donc avec son jeton push-to-start (à chaque nouveau jeton et à chaque passage au premier plan) le nombre
# d'activités en cours sur l'appareil (`activites`) : 0 → la vigie oublie les activités de cet appareil et son entrée
# `demarres`, il redémarre au prochain passage s'il y a lecture. Absent ou vide (app d'avant) : rien ne change. Un
# démarrage de moins de `GARDE_DEMARRAGE` s secondes est gardé (l'activité peut ne pas être encore créée sur l'appareil).
# Le même jeton push-to-start annoncé sous un autre identifiant d'appareil (`identifierForVendor` change, cas de
# l'iPhone le 24/10/2026) : c'est le même appareil, l'ancien identifiant est oublié (activités, démarrage, réglages).

def etat_vide():
    return {"push_to_start": {}, "activites": {}, "demarres": {}, "reglages": {}, "en_cours": False, "envoye": None}


def _oui_non(valeur):
    """Booléen envoyé par le script (vrai booléen, ou texte « True » / « false » rendu par le modèle) ; None si absent."""
    if isinstance(valeur, bool):
        return valeur
    texte = str(valeur if valeur is not None else "").strip().lower()
    if texte in ("true", "1", "on", "oui", "yes"):
        return True
    if texte in ("false", "0", "off", "non", "no"):
        return False
    return None


GARDE_DEMARRAGE = 60


def _nombre(valeur):
    """Entier envoyé par le script (nombre, ou texte « 0 » rendu par le modèle) ; None si absent, vide ou invalide."""
    if isinstance(valeur, bool):
        return None
    if isinstance(valeur, (int, float)):
        return int(valeur) if valeur >= 0 else None
    try:
        n = int(float(str(valeur if valeur is not None else "").strip()))
    except ValueError:
        return None
    return n if n >= 0 else None


def oublier_activites(etat, appareil, maintenant):
    """L'appareil n'a plus d'activité (iOS les a fermées) : ses activités et son démarrage (sauf récent) sont oubliés.
    Renvoie le nombre d'activités oubliées."""
    activites = etat.get("activites", {})
    idents = [k for k, v in activites.items() if v.get("appareil") == appareil]
    for ident in idents:
        activites.pop(ident)
    demarres = etat.get("demarres") or {}
    if appareil in demarres and maintenant - demarres[appareil] >= GARDE_DEMARRAGE:
        demarres.pop(appareil)
    return len(idents)


def masque_spotify(etat, appareil):
    """L'appareil masque-t-il l'activité quand Spotify pilote ? Oui par défaut (réglage absent, app d'avant)."""
    return (etat.get("reglages") or {}).get(appareil or "", {}).get("masquer_spotify", True)


def _appareil(data):
    texte = str(data.get("appareil") or "").strip()
    return texte[:64] or None


def cle_appareil(info, jeton):
    """L'appareil d'un jeton rangé ; à défaut (app d'avant), le jeton lui-même."""
    return info.get("appareil") or jeton


def ranger_jeton(etat, data, maintenant):
    """Range un jeton reçu par l'événement `hub_ipad_activite`. Renvoie le type rangé, ou None si refusé.

    `push_to_start` : un par appareil (le dernier reçu), avec le nombre d'activités en cours sur l'appareil
    (`activites`, 0 → `oublier_activites`) ; `activite` : le jeton d'une activité (son identifiant), avec son appareil.
    """
    jeton = str(data.get("jeton", "")).strip().lower()
    if len(jeton) < 32 or not all(ch in "0123456789abcdef" for ch in jeton):
        return None
    env = data.get("environnement", "production")
    if env not in ("production", "sandbox"):
        env = "production"
    appareil = _appareil(data)
    info = {"environnement": env, "maj": int(maintenant)}
    if appareil:
        info["appareil"] = appareil
    modele = str(data.get("modele") or "").strip()[:32]
    if modele:
        info["modele"] = modele
    genre = data.get("type")
    masquer = _oui_non(data.get("masquer_spotify"))
    if genre in ("push_to_start", "activite") and appareil and masquer is not None:
        etat.setdefault("reglages", {}).setdefault(appareil, {})["masquer_spotify"] = masquer
    if genre == "push_to_start":
        jetons = etat.setdefault("push_to_start", {})
        if appareil:
            # Les jetons sans appareil viennent de l'app d'avant le 23/10/2026, installée seulement sur l'iPad : ils
            # partent quand l'iPad envoie son jeton avec appareil (sinon deux activités sur son écran).
            for autre in [j for j, i in jetons.items() if j != jeton and (
                    i.get("appareil") == appareil or (not i.get("appareil") and modele == "iPad"))]:
                jetons.pop(autre)
        ancien = (jetons.get(jeton) or {}).get("appareil")
        if appareil and ancien and ancien != appareil:
            oublier_activites(etat, ancien, maintenant + GARDE_DEMARRAGE)
            (etat.get("reglages") or {}).pop(ancien, None)
        jetons[jeton] = info
        if _nombre(data.get("activites")) == 0:
            oublier_activites(etat, appareil, maintenant)
        return genre
    if genre == "activite":
        ident = str(data.get("activite_id") or jeton[:16])
        activites = etat.setdefault("activites", {})
        for autre in [k for k, v in activites.items() if v.get("jeton") == jeton]:
            activites.pop(autre)
        activites[ident] = {"jeton": jeton, **info}
        # Une activité qui annonce son jeton existe : elle est en cours (démarrée par la vigie ou restée affichée).
        etat["en_cours"] = True
        return genre
    return None


def retirer_jeton(etat, jeton):
    """Retire un jeton refusé par APNs (périmé, inconnu)."""
    etat.get("push_to_start", {}).pop(jeton, None)
    activites = etat.get("activites", {})
    for ident in [k for k, v in activites.items() if v.get("jeton") == jeton]:
        activites.pop(ident)


def a_demarrer(etat, actuel, spotify=False):
    """Les jetons push-to-start des appareils sans activité : [(jeton, environnement, appareil)].

    Seulement sur une vraie lecture. Un appareil qui a déjà une activité (ou déjà démarré pour cette lecture) est
    sauté. Activité d'une app d'avant (sans appareil) en cours : on ne sait pas de quel écran elle est, rien de plus
    n'est démarré tant qu'elle dure (comportement d'avant). Spotify Connect : pas d'activité sur les appareils qui la
    masquent.
    """
    if not actuel or actuel.get("etat") != "lecture":
        return []
    activites = etat.get("activites", {}).values()
    if etat.get("en_cours") and any(not a.get("appareil") for a in activites):
        return []
    occupes = {a["appareil"] for a in activites if a.get("appareil")} | set(etat.get("demarres") or {})
    return [(j, i.get("environnement", "production"), cle_appareil(i, j))
            for j, i in etat.get("push_to_start", {}).items()
            if cle_appareil(i, j) not in occupes and not (spotify and masque_spotify(etat, i.get("appareil")))]


def envois(etat, actuel, arret_depuis, maintenant, spotify=False):
    """Ce que la vigie envoie à ce passage : (action, [(genre, jeton, environnement, appareil, payload, priorité)]).

    `action` vient de `decider` (start, update, end ou None) ; s'y ajoutent les démarrages des appareils arrivés en
    cours de lecture (un iPhone ouvert pendant que l'activité tourne déjà sur l'iPad). `spotify` : la lecture vient de
    Spotify Connect (`spotify_connect`) ; les appareils qui masquent l'activité dans ce cas reçoivent une fin (genre
    `fin`) au lieu de la mise à jour, et aucun démarrage.
    """
    action, priorite = decider(actuel, etat.get("envoye"), etat.get("en_cours"), arret_depuis, maintenant)
    liste = []
    fin = payload_end({**(etat.get("envoye") or REPOS), "etat": "pause"}, maintenant)
    for a in etat.get("activites", {}).values():
        env, appareil = a.get("environnement", "production"), a.get("appareil")
        if actuel is not None and spotify and masque_spotify(etat, appareil):
            liste.append(("fin", a["jeton"], env, appareil, fin, 10))
        elif action == "update":
            liste.append(("activite", a["jeton"], env, appareil, payload_update(actuel, maintenant), priorite))
        elif action == "end":
            liste.append(("activite", a["jeton"], env, appareil, fin, priorite))
    if action != "end":
        for jeton, env, appareil in a_demarrer(etat, actuel, spotify):
            liste.append(("start", jeton, env, appareil, payload_start(actuel, maintenant), 10))
    return action, liste


def apres_envois(etat, action, actuel, demarres, reussis, perimes, maintenant, finis=()):
    """Met l'état à jour après les envois : jetons périmés retirés, activités terminées pour Spotify retirées (leur
    appareil pourra redémarrer quand Spotify ne pilotera plus), appareils démarrés notés, fin ou lecture en cours."""
    for jeton in perimes:
        retirer_jeton(etat, jeton)
    activites = etat.get("activites", {})
    for jeton in finis:
        for ident in [k for k, v in activites.items() if v.get("jeton") == jeton]:
            appareil = activites.pop(ident).get("appareil")
            (etat.get("demarres") or {}).pop(appareil, None)
    if action == "end":
        etat.update(en_cours=False, envoye=None, activites={}, demarres={})
        return
    marques = etat.setdefault("demarres", {})
    for appareil in demarres:
        marques[appareil] = int(maintenant)
    if reussis:
        etat.update(en_cours=True, envoye=actuel)


# MARK: - Compte des pushs par appareil (/config/hub_ipad_push_stats.json, suivi batterie)

JOURS_GARDES = 31


def nom_appareil(etat, appareil):
    """« iPhone 1A2B3C4D » : le modèle (s'il est connu) et le début de l'identifiant ; « ancien » sans appareil."""
    if not appareil:
        return "ancien"
    modele = ""
    for info in [*etat.get("push_to_start", {}).values(), *etat.get("activites", {}).values()]:
        if info.get("appareil") == appareil and info.get("modele"):
            modele = info["modele"]
            break
    return f"{modele or 'appareil'} {appareil[:8]}"


def compter_pushs(stats, jour, envoyes):
    """Ajoute les pushs d'activité de ce passage : `envoyes` = [(nom de l'appareil, genre)] avec genre start, update,
    end ou fin_spotify (fin pour Spotify Connect) ; `echec` compté à part. Garde les 31 derniers jours."""
    if not envoyes:
        return stats
    jour_stats = stats.setdefault(jour, {})
    for nom, genre in envoyes:
        compte = jour_stats.setdefault(nom, {})
        compte[genre] = compte.get(genre, 0) + 1
    for ancien in sorted(stats)[:-JOURS_GARDES]:
        stats.pop(ancien)
    return stats
