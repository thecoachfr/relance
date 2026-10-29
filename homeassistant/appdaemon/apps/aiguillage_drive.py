"""Pièces jointes enregistrées dans le Google Drive d'Alexandre, depuis « Demander à l'IA » de Courrier (29/10/2026,
demande d'Alexandre ; décision 80 de `courrier/docs/CADRAGE.md`). Utilisé par `aiguillage_assistant` (outils de
l'agent) et `aiguillage_agent` (exécution sur confirmation). Contrat : `homeassistant/COURRIER.md`, « Pièces jointes
dans Google Drive ».

Deux temps, comme les actions sur les mails :
1. **Proposition** (agent) : `chercher_dossiers_drive` (lecture des dossiers) puis `proposer_enregistrement_drive`
   (pièces jointes du mail, dossier choisi ou nouveau chemin) → bloc `drive` de la réponse, et la proposition gardée
   par le NUC dans `ia_drive_proposition:<id>` (métadonnées seulement : noms, tailles, dossiers). RIEN n'est écrit
   dans Drive à ce stade.
2. **Exécution** (sur le geste d'Alexandre) : l'app écrit `ia_drive_confirmation:<id>` quand il touche
   « Enregistrer » ; le NUC vérifie qu'elle correspond à SA proposition (mêmes fichiers ou moins, dossier proposé,
   ou chemin tapé par Alexandre), télécharge chaque pièce jointe par l'API Gmail **en mémoire** (jamais de fichier,
   jamais au journal), la dépose dans Drive (envoi `multipart` jusqu'à 5 Mo, `resumable` au-delà), crée les dossiers
   manquants, et écrit `ia_drive_resultat:<id>` (liens « Ouvrir dans Drive »).

Pourquoi le NUC et pas l'app : l'app n'a que `gmail.modify` (pas de portée Drive), le jeton Drive vit avec celui de
Gmail et de l'agenda sur le NUC (un seul consentement). Ce n'est pas une action sur un mail (rien n'est envoyé,
archivé ni supprimé) : c'est une copie de pièces jointes, faite seulement sur le geste explicite d'Alexandre.

Portée : `https://www.googleapis.com/auth/drive` (voir `PORTEE_DRIVE`). Le client n'utilise que `files.list`,
`files.get` (métadonnées) et `files.create` (dossier ou fichier) : ni suppression, ni corbeille, ni modification,
ni partage (`test_drive_garde_fou`).

Fonctions pures et clients testés hors Home Assistant par `tests/test_aiguillage_drive.py`.
"""

from datetime import timedelta, timezone
import base64
import json
import re
import uuid

import aiguillage_courrier as courrier

API_GMAIL = courrier.API_GMAIL
API_DRIVE = "https://www.googleapis.com/drive/v3/files"
API_ENVOI = "https://www.googleapis.com/upload/drive/v3/files"
# Portée Drive complète : la seule qui permette à la fois de LISTER les dossiers existants d'Alexandre et d'y
# DÉPOSER un fichier. `drive.file` ne voit que les fichiers créés par l'app ou choisis dans un sélecteur Google
# (le NUC n'en a pas) : un dossier existant lui est invisible (404 sur le parent). `drive.metadata.readonly` lit les
# dossiers mais n'écrit rien : ajouter un fichier dans un dossier existant reste refusé avec `drive.file`. Les deux
# sont d'ailleurs « restreintes » comme `drive` : aucun gain côté Google. Le code se limite lui-même (garde-fou).
PORTEE_DRIVE = "https://www.googleapis.com/auth/drive"
TYPE_DOSSIER = "application/vnd.google-apps.folder"
PREFIXE_PROPOSITION = "ia_drive_proposition:"
PREFIXE_CONFIRMATION = "ia_drive_confirmation:"
PREFIXE_RESULTAT = "ia_drive_resultat:"
ENVOI_SIMPLE_MAX = 5 * 1024 * 1024      # jusqu'à 5 Mo : envoi multipart ; au-delà : resumable
PIECE_MAX = 25 * 1024 * 1024            # limite des pièces jointes de Gmail
FICHIERS_MAX = 10
CANDIDATS_MAX = 8
DOSSIERS_LISTE_MAX = 30
PROFONDEUR_MAX = 8                      # remontée des parents pour écrire un chemin
SEGMENTS_MAX = 5                        # « Travaux/Alfortville/2026 » : 5 niveaux au plus pour un nouveau chemin
SEGMENT_MAX = 100
CONFIRMATION_FRAICHE_MIN = 10           # une confirmation plus ancienne (NUC arrêté) n'est plus exécutée
PROPOSITION_JOURS = 7
_UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")

# Les parties d'un mail, sans le contenu : nom, type, taille, id de pièce jointe (`fields` de Gmail, 5 niveaux).
_PARTIE = "partId,filename,mimeType,body(attachmentId,size)"
CHAMPS_PARTIES = "id,threadId,payload(headers," + _PARTIE + ",parts(" + _PARTIE + ",parts(" + _PARTIE + ",parts(" + \
    _PARTIE + ",parts(" + _PARTIE + ")))))"


class Refus(Exception):
    """Une confirmation qui ne correspond pas à la proposition du NUC : rien n'est fait."""


# MARK: - Définitions des outils de l'agent

def _schema(proprietes):
    return {"type": "object", "properties": proprietes, "required": list(proprietes), "additionalProperties": False}


OUTILS_DRIVE = [
    {
        "name": "chercher_dossiers_drive",
        "description": "Cherche des dossiers dans le Google Drive d'Alexandre (lecture seule) : ceux dont le nom "
                       "contient un des mots, ou les dossiers à la racine si mots est vide. Rend {id, chemin}.",
        "strict": True,
        "input_schema": _schema({
            # Pas de paramètre nullable (anyOf) : l'API limite à 16 les unions de tous les outils strict.
            "mots": {"type": "array", "items": {"type": "string"},
                     "description": "mots du nom de dossier (ex. [\"Factures\", \"EDF\"]), 5 au plus ; [] = racine"},
        }),
    },
    {
        "name": "proposer_enregistrement_drive",
        "description": "Propose d'enregistrer des pièces jointes du mail `id` dans Google Drive. RIEN n'est enregistré "
                       "par cet outil : l'app montre les fichiers et le dossier, Alexandre touche « Enregistrer ». "
                       "Donne `dossier_id` (un dossier existant rendu par chercher_dossiers_drive) OU `nouveau_chemin` "
                       "(« Travaux/Alfortville », créé à partir de la racine, dossiers existants réutilisés), l'autre "
                       "vide (\"\"). `fichiers` : noms des pièces jointes à proposer ([] = toutes, sauf petites "
                       "images de signature). `candidats` : 0 à 3 autres dossier_id qu'il pourra choisir à la place.",
        "strict": True,
        "input_schema": _schema({
            "id": {"type": "string", "description": "id du mail (base du tri ou Gmail)"},
            "dossier_id": {"type": "string", "description": "dossier existant, ou \"\""},
            "nouveau_chemin": {"type": "string", "description": "chemin d'un nouveau dossier depuis la racine, ou \"\""},
            "fichiers": {"type": "array", "items": {"type": "string"}, "description": "noms des pièces jointes, ou []"},
            "candidats": {"type": "array", "items": {"type": "string"}, "description": "autres dossier_id possibles"},
        }),
    },
]
NOMS_OUTILS = tuple(o["name"] for o in OUTILS_DRIVE)

CONSIGNE_DRIVE = """
- Google Drive : pour enregistrer des pièces jointes d'un mail dans son Drive, appelle chercher_dossiers_drive (mots \
du sujet : Factures, le fournisseur, Travaux…), choisis le dossier existant le plus juste (ou un nouveau chemin \
clair s'il n'y en a pas), puis proposer_enregistrement_drive. Rien n'est enregistré avant qu'il touche \
« Enregistrer » dans l'app : dis « je te propose de les enregistrer dans … », jamais que c'est fait. Si un outil \
Drive répond que Drive n'est pas autorisé, dis-lui qu'il faut d'abord son accord Google pour Drive \
(courrier_autoriser.py sur le Mac) et ne propose rien."""


# MARK: - Pièces jointes d'un mail (métadonnées ; contenu seulement à l'exécution, en mémoire)

def pieces_jointes(message):
    """Les pièces jointes d'un message Gmail (`CHAMPS_PARTIES`) → [{partie, nom, type, taille, piece}]. Une partie
    sans nom de fichier ou sans `attachmentId` (texte du mail, image intégrée sans nom) est ignorée."""
    out = []

    def parcourir(p):
        corps = p.get("body") or {}
        nom = " ".join(str(p.get("filename") or "").split())
        if nom and corps.get("attachmentId"):
            out.append({"partie": str(p.get("partId") or ""), "nom": nom[:200],
                        "type": str(p.get("mimeType") or "application/octet-stream")[:100],
                        "taille": int(corps.get("size") or 0), "piece": corps["attachmentId"]})
        for enfant in p.get("parts") or []:
            parcourir(enfant)

    parcourir(message.get("payload") or {})
    return out


def objet_du_message(message):
    for h in (message.get("payload") or {}).get("headers") or []:
        if str(h.get("name", "")).lower() == "subject":
            return " ".join(str(h.get("value") or "").split())[:300]
    return ""


def petite_image(p):
    """Logo de signature (image001.png…) : image de moins de 30 Ko."""
    return p["type"].startswith("image/") and p["taille"] < 30_000


class PiecesGmail:
    """Lecture des pièces jointes d'un mail. `parties` : métadonnées seulement (`fields`) ; `contenu` : les octets
    d'UNE pièce jointe, rendus en mémoire à l'appelant (jamais écrits, jamais journalisés)."""

    def __init__(self, jeton):
        self._jeton = jeton

    def message(self, message_id):
        return self._jeton.appeler("get", f"{API_GMAIL}/messages/{message_id}",
                                   params={"format": "full", "fields": CHAMPS_PARTIES})

    def contenu(self, message_id, piece):
        d = self._jeton.appeler("get", f"{API_GMAIL}/messages/{message_id}/attachments/{piece}")
        donnees = str(d.get("data") or "")
        return base64.urlsafe_b64decode(donnees + "=" * (-len(donnees) % 4))


# MARK: - Client Drive (files.list, files.get, files.create SEULEMENT)

def _q(texte):
    """Chaîne entre apostrophes pour la recherche de Drive (`\\` et `'` échappés)."""
    return "'" + str(texte).replace("\\", "\\\\").replace("'", "\\'") + "'"


def lien_dossier(ident):
    return f"https://drive.google.com/drive/folders/{ident}"


class ClientDrive:
    """Le Drive d'Alexandre : lire des dossiers, créer un dossier, déposer un fichier. AUCUNE suppression, mise à la
    corbeille, modification ni partage (`test_drive_garde_fou` vérifie la source)."""

    def __init__(self, jeton):
        self._jeton = jeton
        self._racine = None
        self._noeuds = {}

    def autorise(self):
        return self._jeton.a_la_portee(PORTEE_DRIVE)

    def racine(self):
        if self._racine is None:
            self._racine = self._jeton.appeler("get", f"{API_DRIVE}/root", params={"fields": "id"})["id"]
        return self._racine

    def _noeud(self, ident):
        if ident not in self._noeuds:
            self._noeuds[ident] = self._jeton.appeler("get", f"{API_DRIVE}/{ident}",
                                                      params={"fields": "id,name,parents,mimeType,trashed"})
        return self._noeuds[ident]

    def chemin(self, ident):
        """« Factures/EDF » (depuis la racine de Mon Drive) ; un dossier partagé hors de Mon Drive : son nom seul."""
        racine, noms, courant = self.racine(), [], ident
        for _ in range(PROFONDEUR_MAX):
            if courant == racine:
                break
            n = self._noeud(courant)
            noms.append(str(n.get("name") or ""))
            parents = n.get("parents") or []
            if not parents:
                break
            courant = parents[0]
        return "/".join(reversed(noms))

    def lister(self, q, limite=DOSSIERS_LISTE_MAX):
        rep = self._jeton.appeler("get", API_DRIVE, params={
            "q": q, "pageSize": limite, "fields": "files(id,name,parents)", "orderBy": "modifiedTime desc",
            "spaces": "drive"})
        return rep.get("files") or []

    def dossiers(self, mots=None):
        """[{id, chemin}] des dossiers dont le nom contient un des mots ; sans mot : ceux de la racine."""
        base = f"mimeType = '{TYPE_DOSSIER}' and trashed = false"
        mots = [m.strip() for m in (mots or []) if m and m.strip()][:5]
        if mots:
            q = base + " and (" + " or ".join(f"name contains {_q(m[:60])}" for m in mots) + ")"
        else:
            q = base + " and 'root' in parents"
        out = []
        for f in self.lister(q):
            self._noeuds.setdefault(f["id"], {**f, "mimeType": TYPE_DOSSIER})
            out.append({"id": f["id"], "chemin": self.chemin(f["id"])})
        return out

    def dossier(self, ident):
        """Le dossier `ident` s'il existe et n'est pas à la corbeille : {id, chemin}, sinon None."""
        try:
            n = self._noeud(ident)
        except courrier.Introuvable:
            return None
        if n.get("mimeType") != TYPE_DOSSIER or n.get("trashed"):
            return None
        return {"id": ident, "chemin": self.chemin(ident)}

    def enfant(self, parent, nom):
        r = self.lister(f"mimeType = '{TYPE_DOSSIER}' and trashed = false and name = {_q(nom)} "
                        f"and {_q(parent)} in parents", limite=1)
        return r[0]["id"] if r else None

    def creer_dossier(self, nom, parent):
        d = self._jeton.appeler("post", API_DRIVE, params={"fields": "id"},
                                json={"name": nom, "mimeType": TYPE_DOSSIER, "parents": [parent]})
        return d["id"]

    def deposer(self, nom, type_, donnees, parent):
        """`files.create` d'un fichier dans `parent` → {id, lien}. Jusqu'à 5 Mo : envoi multipart (une requête) ;
        au-delà : session resumable (métadonnées, puis les octets en une fois)."""
        meta = {"name": nom, "parents": [parent]}
        if len(donnees) <= ENVOI_SIMPLE_MAX:
            frontiere = "courrier-" + uuid.uuid4().hex
            corps = (f"--{frontiere}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"
                     f"{json.dumps(meta, ensure_ascii=False)}\r\n--{frontiere}\r\nContent-Type: {type_}\r\n\r\n"
                     ).encode("utf-8") + donnees + f"\r\n--{frontiere}--\r\n".encode("ascii")
            d = self._jeton.appeler("post", API_ENVOI, params={"uploadType": "multipart", "fields": "id,webViewLink"},
                                    content=corps,
                                    entetes={"Content-Type": f"multipart/related; boundary={frontiere}"})
        else:
            r = self._jeton.requete("post", API_ENVOI, params={"uploadType": "resumable", "fields": "id,webViewLink"},
                                    json=meta, entetes={"X-Upload-Content-Type": type_,
                                                        "X-Upload-Content-Length": str(len(donnees))})
            session = r.headers.get("Location") or r.headers.get("location")
            if not session or not session.startswith(API_ENVOI):
                raise courrier.ErreurGmail("Drive : session d'envoi absente")
            d = self._jeton.appeler("put", session, content=donnees, entetes={"Content-Type": type_})
        return {"id": d["id"], "lien": d.get("webViewLink") or f"https://drive.google.com/file/d/{d['id']}/view"}


# MARK: - Proposition (agent)

def segments(chemin):
    """« /Travaux / Alfortville/ » → ["Travaux", "Alfortville"] ; vide, trop profond ou « . » / « .. » : erreur."""
    parts = [" ".join(s.split())[:SEGMENT_MAX] for s in str(chemin or "").replace("\\", "/").split("/")]
    parts = [s for s in parts if s]
    if not parts or len(parts) > SEGMENTS_MAX or any(s in (".", "..") for s in parts):
        raise ValueError("chemin illisible (1 à 5 dossiers séparés par « / »)")
    return parts


class OutilsDrive:
    """Les deux outils Drive de l'agent. `drive` / `gmail` : fonctions sans argument qui rendent `ClientDrive` /
    `PiecesGmail` (ou None). Garde la proposition faite (`blocs`) : c'est elle que le NUC enregistre, et seule une
    confirmation qui lui correspond sera exécutée."""

    def __init__(self, drive=None, gmail=None):
        self.drive, self.gmail = drive, gmail
        self.blocs = []

    def _clients(self):
        from aiguillage_agent import ErreurOutil
        drive = self.drive() if self.drive else None
        gmail = self.gmail() if self.gmail else None
        if drive is None or gmail is None:
            raise ErreurOutil("Google Drive indisponible (autorisation Google absente)")
        if not drive.autorise():
            raise ErreurOutil("Google Drive n'est pas autorisé : il faut d'abord l'accord Google d'Alexandre pour "
                              "Drive (courrier_autoriser.py sur le Mac). Ne propose rien.")
        return drive, gmail

    def chercher_dossiers_drive(self, mots=None):
        drive, _ = self._clients()
        trouves = drive.dossiers(mots)
        return {"nombre": len(trouves), "dossiers": trouves}

    def proposer_enregistrement_drive(self, id, dossier_id=None, nouveau_chemin=None,  # noqa: A002
                                      fichiers=None, candidats=None):
        from aiguillage_agent import ErreurOutil
        drive, gmail = self._clients()
        if bool(dossier_id) == bool(nouveau_chemin):
            raise ErreurOutil("donne dossier_id OU nouveau_chemin (un seul des deux)")
        try:
            message = gmail.message(id)
        except courrier.Introuvable:
            raise ErreurOutil(f"mail inconnu dans Gmail : {id}")
        pieces = pieces_jointes(message)
        if not pieces:
            raise ErreurOutil("ce mail n'a pas de pièce jointe")
        if fichiers:
            voulus = {" ".join(str(f).split()).lower() for f in fichiers}
            choisies = [p for p in pieces if p["nom"].lower() in voulus]
            if not choisies:
                raise ErreurOutil("aucun de ces noms parmi les pièces jointes : " + ", ".join(p["nom"] for p in pieces))
        else:
            choisies = [p for p in pieces if not petite_image(p)] or pieces
        choisies = [p for p in choisies if p["taille"] <= PIECE_MAX][:FICHIERS_MAX]
        if not choisies:
            raise ErreurOutil("pièces jointes trop lourdes (25 Mo au plus)")
        if dossier_id:
            dossier = drive.dossier(dossier_id)
            if dossier is None:
                raise ErreurOutil(f"dossier inconnu dans Drive : {dossier_id}")
            dossier = {**dossier, "nouveau": False}
        else:
            try:
                dossier = {"id": None, "chemin": "/".join(segments(nouveau_chemin)), "nouveau": True}
            except ValueError as exc:
                raise ErreurOutil(str(exc))
        autres = []
        for c in list(candidats or [])[:3]:
            d = drive.dossier(c) if c and c != dossier.get("id") else None
            if d and all(x["id"] != d["id"] for x in autres):
                autres.append({**d, "nouveau": False})
        bloc = {"type": "drive", "id": str(uuid.uuid4()), "mail": id, "objet": objet_du_message(message),
                "fichiers": [{k: p[k] for k in ("partie", "nom", "type", "taille")} for p in choisies],
                "dossier": dossier, "candidats": autres[:CANDIDATS_MAX]}
        self.blocs.append(bloc)
        return {"proposition": f"{len(choisies)} fichier(s) vers « {dossier['chemin']} » montré(s) à Alexandre ; "
                               "RIEN n'est enregistré avant qu'il touche « Enregistrer »",
                "fichiers": [p["nom"] for p in choisies]}


def valeur_proposition(bloc, maintenant):
    """`ia_drive_proposition:<id>` : la proposition telle que montrée (métadonnées seulement)."""
    return {"v": 1, "mail": bloc["mail"], "fichiers": bloc["fichiers"], "dossier": bloc["dossier"],
            "candidats": bloc["candidats"], "propose_le": maintenant.astimezone(timezone.utc).isoformat(timespec="seconds")}


# MARK: - Exécution (sur la confirmation d'Alexandre)

def plan(proposition, confirmation, maintenant, fraiche_min=CONFIRMATION_FRAICHE_MIN):
    """Vérifie que la confirmation de l'app correspond à la proposition du NUC → {mail, fichiers, dossier}. Lève
    `Refus` sinon : pas de proposition, confirmation trop ancienne, fichier non proposé, dossier ni proposé ni tapé."""
    if not isinstance(proposition, dict) or proposition.get("v") != 1:
        raise Refus("aucune proposition du NUC pour cette confirmation")
    if not isinstance(confirmation, dict) or confirmation.get("v") != 1:
        raise Refus("confirmation illisible")
    propose_le = courrier._instant(proposition.get("propose_le"))
    if propose_le is None or maintenant - propose_le > timedelta(days=PROPOSITION_JOURS):
        raise Refus("proposition trop ancienne")
    quand = courrier._instant(confirmation.get("quand"))
    if quand is None or maintenant - quand > timedelta(minutes=fraiche_min) or quand - maintenant > timedelta(minutes=5):
        raise Refus("confirmation trop ancienne")
    proposes = {f["partie"]: f for f in proposition.get("fichiers") or [] if isinstance(f, dict) and f.get("partie")}
    voulus = [str(x) for x in confirmation.get("fichiers") or []]
    if not voulus or any(x not in proposes for x in voulus):
        raise Refus("fichiers non proposés")
    fichiers = [proposes[x] for x in dict.fromkeys(voulus)]
    d = confirmation.get("dossier") or {}
    connus = {x["id"]: x for x in [proposition.get("dossier") or {}] + list(proposition.get("candidats") or [])
              if isinstance(x, dict) and x.get("id")}
    if d.get("id"):
        if d["id"] not in connus:
            raise Refus("dossier non proposé")
        dossier = {"id": d["id"], "chemin": connus[d["id"]].get("chemin") or "", "nouveau": False}
    else:
        try:
            dossier = {"id": None, "chemin": "/".join(segments(d.get("chemin"))), "nouveau": True}
        except ValueError as exc:
            raise Refus(str(exc))
    return {"mail": proposition["mail"], "fichiers": fichiers, "dossier": dossier}


def executer(p, drive, gmail):
    """Dépose les fichiers du plan dans Drive → résultat {dossier: {id, chemin, lien}, fichiers: [{nom, id, lien}],
    crees, octets}. Chaque pièce jointe est relue chez Gmail (l'id de pièce jointe de Gmail change d'une lecture à
    l'autre : on retrouve la partie par son numéro et son nom), gardée en mémoire le temps de l'envoi, puis oubliée."""
    if not drive.autorise():
        raise Refus("Google Drive n'est pas autorisé (accord Google à donner sur le Mac)")
    crees = 0
    if p["dossier"]["id"]:
        parent = p["dossier"]["id"]
    else:
        parent = drive.racine()
        for nom in segments(p["dossier"]["chemin"]):
            existant = drive.enfant(parent, nom)
            if existant is None:
                existant, crees = drive.creer_dossier(nom, parent), crees + 1
            parent = existant
    pieces = {(x["partie"], x["nom"]): x for x in pieces_jointes(gmail.message(p["mail"]))}
    deposes, octets = [], 0
    for f in p["fichiers"]:
        piece = pieces.get((f["partie"], f["nom"]))
        if piece is None:
            raise Refus("pièce jointe introuvable dans le mail")
        donnees = gmail.contenu(p["mail"], piece["piece"])
        try:
            if len(donnees) > PIECE_MAX:
                raise Refus("pièce jointe trop lourde")
            octets += len(donnees)
            deposes.append({"nom": f["nom"], **drive.deposer(f["nom"], piece["type"], donnees, parent)})
        finally:
            del donnees   # jamais gardé : ni fichier, ni journal, ni état
    return {"dossier": {"id": parent, "chemin": p["dossier"]["chemin"], "lien": lien_dossier(parent)},
            "fichiers": deposes, "crees": crees, "octets": octets}


def valeur_resultat(statut, maintenant, resultat=None, raison=None):
    """`ia_drive_resultat:<id>` = {v, statut: en_cours | ok | echec, raison, dossier, fichiers, fait_le}."""
    r = resultat or {}
    return {"v": 1, "statut": statut, "raison": raison, "dossier": r.get("dossier"), "fichiers": r.get("fichiers") or [],
            "fait_le": maintenant.astimezone(timezone.utc).isoformat(timespec="seconds")}


def journal(appareil, resultat=None, raison=None):
    """Ligne du journal : nombres et taille seulement ; JAMAIS le contenu, ni les noms de fichiers ou de dossiers."""
    qui = f"Drive (Courrier{', ' + appareil if appareil else ''})"
    if raison:
        return f"{qui} : rien d'enregistré ({raison})"
    n, mo = len(resultat["fichiers"]), resultat["octets"] / 1_048_576
    dossier = f"{resultat['crees']} dossier(s) créé(s)" if resultat["crees"] else "dossier existant"
    return f"{qui} : {n} pièce(s) jointe(s) enregistrée(s) ({mo:.1f} Mo), {dossier}"
