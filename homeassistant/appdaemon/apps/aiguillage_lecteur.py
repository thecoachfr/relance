"""Activité en direct « En lecture sur les LS50 » du Hub iPad (23/10/2026) : code pur, sans AppDaemon.

La vigie (`relance_vigie.py`) surveille le lecteur des LS50 et pilote l'activité sur l'écran verrouillé de l'iPad
par des push APNs `liveactivity` : démarrage à distance (`push-to-start`), mises à jour, fin. Ce module choisit
l'entité, construit le `content-state`, décide quoi envoyer et range les jetons.

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

def etat_vide():
    return {"push_to_start": {}, "activites": {}, "en_cours": False, "envoye": None}


def ranger_jeton(etat, data, maintenant):
    """Range un jeton reçu par l'événement `hub_ipad_activite`. Renvoie le type rangé, ou None si refusé.

    `push_to_start` : un par appareil et environnement ; `activite` : le jeton d'une activité (son identifiant).
    """
    jeton = str(data.get("jeton", "")).strip().lower()
    if len(jeton) < 32 or not all(ch in "0123456789abcdef" for ch in jeton):
        return None
    env = data.get("environnement", "production")
    if env not in ("production", "sandbox"):
        env = "production"
    genre = data.get("type")
    if genre == "push_to_start":
        etat.setdefault("push_to_start", {})[jeton] = {"environnement": env, "maj": int(maintenant)}
        return genre
    if genre == "activite":
        ident = str(data.get("activite_id") or jeton[:16])
        activites = etat.setdefault("activites", {})
        for autre in [k for k, v in activites.items() if v.get("jeton") == jeton]:
            activites.pop(autre)
        activites[ident] = {"jeton": jeton, "environnement": env, "maj": int(maintenant)}
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
