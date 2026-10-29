"""Source de la lecture dans le Hub (29/10/2026, contrat : homeassistant/LECTURE-SOURCE.md) : `sensor.lecture_source`.

D'où vient la musique des LS50 : « Music Assistant » (une file MA lancée par le Hub ou HA), « Spotify » (Spotify
Connect depuis un téléphone), « Radio », « AirPlay / autre » ; et le nom de ce qui joue (playlist, album, station).

Music Assistant ne donne pas le nom du contexte de sa file : la vigie écoute les appels de service
`music_assistant.play_media` / `media_player.play_media` vers `media_player.salon_ls50_5` (événement `call_service`)
et garde le dernier lancement (sur disque, pour survivre à un redémarrage). Le nom est résolu par l'API du serveur MA
(`music/item_by_uri`). Fonctions pures ici ; appels HA et MA dans `relance_vigie.py`.
"""

import aiguillage_lecteur

ENTITE = "sensor.lecture_source"
ENTITE_MA = aiguillage_lecteur.ENTITE_MA
ENTITE_KEF = aiguillage_lecteur.ENTITE_KEF
ENTITE_SPOTIFY = "sensor.spotify_lecture"
JOUE = ("playing", "paused")
SOURCE_MA = "Music Assistant Queue"

LIBELLES = {"music_assistant": "Music Assistant", "spotify": "Spotify", "radio": "Radio", "autre": "AirPlay / autre"}
TYPES = {"playlist": "playlist", "album": "album", "radio": "radio", "artist": "artiste", "artiste": "artiste",
         "track": "titre", "titre": "titre", "music": None, "collection": "playlist"}
# Ajouts sans changer le contexte de la file.
AJOUTS = ("add", "next", "replace_next")
# La taille de la file n'est apprise qu'une fois le lancement posé (MA remplit la file en quelques secondes).
APPRENDRE_APRES = 10
# Nom introuvable (MA injoignable) : nouvel essai au plus toutes les 5 min.
NOUVEL_ESSAI = 300
# Republication au moins toutes les 10 min, même sans changement.
REPUBLIER = 600


def _texte(valeur):
    return valeur.strip() if isinstance(valeur, str) else ""


def _entites(valeur):
    if isinstance(valeur, str):
        return [e.strip() for e in valeur.split(",")]
    if isinstance(valeur, (list, tuple)):
        return [str(e) for e in valeur]
    return []


def lancement_depuis_appel(data, maintenant_iso, t):
    """Lancement vu dans un événement `call_service`, ou None s'il ne vise pas les LS50 de Music Assistant.

    Retourne {"ajout": True} pour un ajout à la file (enqueue add / next / replace_next : le contexte ne change pas),
    sinon {media_id, media_type, quand, t, queue_id, items, nom, nom_type, nom_essai}."""
    data = data or {}
    domaine, service = data.get("domain"), data.get("service")
    if service != "play_media" or domaine not in ("music_assistant", "media_player"):
        return None
    sd = data.get("service_data") or {}
    if ENTITE_MA not in _entites(sd.get("entity_id")):
        return None
    media_id = sd.get("media_id") if domaine == "music_assistant" else sd.get("media_content_id")
    media_id = media_id or sd.get("media_id") or sd.get("media_content_id")
    media_type = sd.get("media_type") if domaine == "music_assistant" else sd.get("media_content_type")
    media_type = media_type or sd.get("media_type") or sd.get("media_content_type")
    if isinstance(media_id, (list, tuple)):
        # Plusieurs éléments d'un coup : pas de contexte unique, on garde le premier pour le type seulement.
        if not media_id:
            return None
        media_id = media_id[0] if len(media_id) == 1 else None
        if media_id is None:
            return {"media_id": None, "media_type": None, "quand": maintenant_iso, "t": t, "queue_id": None,
                    "items": None, "nom": None, "nom_type": None, "nom_essai": None}
    media_id = _texte(media_id)
    if not media_id:
        return None
    if _texte(sd.get("enqueue")).lower() in AJOUTS:
        return {"ajout": True}
    return {"media_id": media_id, "media_type": _texte(media_type).lower() or None, "quand": maintenant_iso, "t": t,
            "queue_id": None, "items": None, "nom": None, "nom_type": None, "nom_essai": None}


def appliquer(memo, lancement):
    """Nouveau mémo après un lancement vu : un ajout garde le contexte mais fait réapprendre la taille de la file."""
    if lancement is None:
        return memo
    if lancement.get("ajout"):
        if memo:
            memo = dict(memo, items=None)
        return memo
    return lancement


def est_uri(media_id):
    m = _texte(media_id)
    return "://" in m or m.startswith("spotify:")


def a_resoudre(memo, t):
    """Faut-il demander le nom du lancement à Music Assistant ?"""
    if not memo or not memo.get("media_id") or memo.get("nom"):
        return False
    if not est_uri(memo["media_id"]):
        return False  # un nom donné tel quel (MA accepte « Titres likés ») n'a rien à résoudre
    essai = memo.get("nom_essai")
    return essai is None or t - essai >= NOUVEL_ESSAI or t < essai


def nom_resolu(memo, item, t):
    """Mémo complété par la réponse de `music/item_by_uri` (dict, ou None si l'appel a échoué)."""
    memo = dict(memo, nom_essai=t)
    if isinstance(item, dict) and _texte(item.get("name")):
        memo["nom"] = _texte(item["name"])
        memo["nom_type"] = _texte(item.get("media_type")).lower() or None
    return memo


def nom_du_lancement(memo):
    """(nom, type) du lancement : nom résolu, ou le media_id s'il n'est pas une adresse (MA accepte un nom)."""
    if not memo or not memo.get("media_id"):
        return None, None
    genre = memo.get("nom_type") or memo.get("media_type")
    if memo.get("nom"):
        return memo["nom"], genre
    if not est_uri(memo["media_id"]):
        return memo["media_id"], genre
    return None, genre


def apprendre(memo, etat_ma, file, t):
    """Mémo complété par la file active (`music_assistant.get_queue`) : identifiant et taille, appris une fois."""
    if not memo or not etat_ma or etat_ma.get("state") not in JOUE:
        return memo
    attrs = etat_ma.get("attributes") or {}
    memo = dict(memo)
    if memo.get("queue_id") is None and attrs.get("active_queue"):
        memo["queue_id"] = attrs["active_queue"]
    if memo.get("items") is None and isinstance(file, dict) and isinstance(file.get("items"), int) \
            and t - (memo.get("t") or 0) >= APPRENDRE_APRES:
        memo["items"] = file["items"]
    return memo


def valide(memo, etat_ma, file):
    """Le lancement mémorisé décrit-il encore la file active ? Au doute, non (nom null plutôt que faux)."""
    if not memo or not memo.get("media_id") or not etat_ma:
        return False
    attrs = etat_ma.get("attributes") or {}
    if memo.get("queue_id") and attrs.get("active_queue") and attrs["active_queue"] != memo["queue_id"]:
        return False
    if isinstance(file, dict):
        if file.get("queue_id") and memo.get("queue_id") and file["queue_id"] != memo["queue_id"]:
            return False
        items, index = file.get("items"), file.get("current_index")
        if memo.get("items") is not None and isinstance(items, int) and items != memo["items"]:
            return False  # file relancée ailleurs (app MA…) ou rallongée
        if isinstance(items, int) and isinstance(index, int) and not 0 <= index < items:
            return False
    return True


def nom_affiche(nom):
    """Renommages d'affichage : « Liked Songs … » / « Titres likés … » → « Titres likés »."""
    n = _texte(nom)
    if not n:
        return None
    if n.lower().startswith(("liked songs", "titres likés", "titres likes")):
        return "Titres likés"
    return n


def type_court(genre):
    return TYPES.get(_texte(genre).lower()) if genre else None


def ligne(etat, nom, aleatoire):
    """La ligne prête à afficher : « Music Assistant · Titres likés · aléatoire », « Radio · France Inter »…"""
    morceaux = [LIBELLES[etat]]
    if nom and etat != "autre":
        morceaux.append(nom)
    if aleatoire and etat in ("music_assistant", "spotify"):
        morceaux.append("aléatoire")
    return " · ".join(morceaux)


def _sortie(etat, entite, nom, genre, aleatoire, maintenant_iso):
    if etat == "rien":
        return "rien", {"source": None, "nom": None, "type": None, "aleatoire": None, "ligne": None, "entite": None,
                        "maj": maintenant_iso}
    nom = nom_affiche(nom)
    return etat, {
        "source": LIBELLES[etat],
        "nom": nom,
        "type": type_court(genre),
        "aleatoire": aleatoire if isinstance(aleatoire, bool) else None,
        "ligne": ligne(etat, nom, aleatoire is True),
        "entite": entite,
        "maj": maintenant_iso,
    }


def _ma_joue(etat_ma, statut):
    return bool(etat_ma) and etat_ma.get("state") == statut \
        and (_texte((etat_ma.get("attributes") or {}).get("source")) in (SOURCE_MA, "")
             or (etat_ma.get("attributes") or {}).get("app_id") == "music_assistant")


def _spotify_ls50(etat_sp, statut):
    if not etat_sp or etat_sp.get("state") != statut:
        return False
    return (etat_sp.get("attributes") or {}).get("sur_ls50") is True


def calculer(etats, memo, memo_valide, ajoutees, maintenant_iso):
    """(état, attributs) du capteur. `etats` : {entité: état HA (dict avec state / attributes)}.

    Priorité : MA en lecture, Spotify en lecture sur les LS50, MA en pause, Spotify en pause sur les LS50, KEF en
    Wi-Fi qui joue (Spotify Connect sans capteur), KEF sur une autre entrée (« AirPlay / autre »), sinon « rien ».
    La KEF peut garder un vieux titre Spotify pendant que MA joue : MA passe toujours avant elle."""
    ma, kef, sp = etats.get(ENTITE_MA), etats.get(ENTITE_KEF), etats.get(ENTITE_SPOTIFY)
    for statut_ma, statut_sp in (("playing", "lecture"), ("paused", "pause")):
        if _ma_joue(ma, statut_ma):
            return _depuis_ma(ma, memo, memo_valide, ajoutees, maintenant_iso)
        if _spotify_ls50(sp, statut_sp):
            return _depuis_spotify(sp, maintenant_iso)
    if kef and kef.get("state") in JOUE:
        entree = _texte((kef.get("attributes") or {}).get("source")).lower()
        if entree == "wifi":
            return _sortie("spotify", ENTITE_KEF, None, None, None, maintenant_iso)
        return _sortie("autre", ENTITE_KEF, None, None, None, maintenant_iso)
    return _sortie("rien", None, None, None, None, maintenant_iso)


def _depuis_ma(ma, memo, memo_valide, ajoutees, maintenant_iso):
    attrs = ma.get("attributes") or {}
    aleatoire = attrs.get("shuffle") if isinstance(attrs.get("shuffle"), bool) else None
    nom, genre = nom_du_lancement(memo) if memo_valide else (None, None)
    contenu = aiguillage_lecteur.contenu(ma, "", ajoutees) or {}
    radio_lancee = memo_valide and (type_court(genre) == "radio")
    if contenu.get("radio") or radio_lancee:
        station = contenu.get("source") if contenu.get("source") not in (None, "", "Radio") else None
        return _sortie("radio", ENTITE_MA, nom or station, "radio", None, maintenant_iso)
    return _sortie("music_assistant", ENTITE_MA, nom, genre, aleatoire, maintenant_iso)


def _depuis_spotify(sp, maintenant_iso):
    attrs = sp.get("attributes") or {}
    contexte = attrs.get("contexte") or {}
    return _sortie("spotify", ENTITE_KEF, contexte.get("nom"), contexte.get("type"), attrs.get("aleatoire"),
                   maintenant_iso)


def indisponible(motif, maintenant_iso):
    return "unavailable", {"maj": maintenant_iso, "erreur": motif}


def sans_maj(resultat):
    etat, attributs = resultat
    return etat, {k: v for k, v in attributs.items() if k != "maj"}


def a_publier(ancien, nouveau, t_ancien, t):
    """Publier si l'état ou un attribut (hors `maj`) change, ou si la dernière publication a plus de 10 min."""
    if ancien is None:
        return True
    return sans_maj(ancien) != sans_maj(nouveau) or t - t_ancien >= REPUBLIER


def memo_disque(memo):
    """Ce qui est gardé sur disque : `t` (horloge monotone) n'a pas de sens après un redémarrage."""
    if not memo:
        return None
    return {k: v for k, v in memo.items() if k not in ("t", "nom_essai")}


def memo_charge(donnees, t):
    """Mémo relu au démarrage : la taille de la file est réapprise si elle manque, le nom réessayé tout de suite."""
    if not isinstance(donnees, dict) or not donnees.get("media_id"):
        return None
    return dict(donnees, t=t - APPRENDRE_APRES, nom_essai=None)
