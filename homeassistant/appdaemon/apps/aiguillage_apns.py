"""Envoi de notifications APNs depuis le NUC (lot C5 de l'app Courrier, 26/10/2026).

Même méthode que la vigie d'Aiguillage (`relance_vigie.py`, `_send` et `_provider_token`) : HTTP/2 par `httpx`
(`http2=True`, paquet `h2` déjà présent dans l'add-on AppDaemon), jeton du fournisseur JWT ES256 signé par `pyjwt`
avec la clé « auth key » `.p8` de l'équipe (une clé vaut pour toutes les apps de l'équipe `GD6W292ZXP`), renouvelé
toutes les 50 minutes (Apple le refuse au-delà d'une heure, et en dessous de 20 minutes s'il change trop souvent).
Recopiée ici plutôt qu'importée : la vigie est une app AppDaemon (elle importe `appdaemon` dès le chargement) et elle
ne doit pas changer. Ce module n'est pas une app : il n'a pas de bloc dans `apps.yaml`.

Rien n'est envoyé ni signé à l'import : les tests simulent le client HTTP, l'horloge et la signature.
"""

import time

HOTES = {
    "sandbox": "https://api.sandbox.push.apple.com",
    "production": "https://api.push.apple.com",
}
DUREE_JETON = 50 * 60
# Refus qui veulent dire « ce jeton ne servira plus » : l'enregistrement de l'appareil est retiré.
RAISONS_DEFINITIVES = ("BadDeviceToken", "Unregistered")


def hote(environnement):
    """Serveur d'Apple selon l'environnement de l'appareil : `sandbox` (builds Debug, profil de développement) ou
    `production` (TestFlight, App Store). Tout autre texte va en production."""
    return HOTES["sandbox"] if environnement == "sandbox" else HOTES["production"]


def refus_definitif(statut, raison):
    """410 (`Unregistered` : app désinstallée) ou 400 `BadDeviceToken` (jeton d'un autre environnement ou abîmé)."""
    return statut == 410 or raison in RAISONS_DEFINITIVES


def _signer_es256(revendications, cle, en_tetes):
    import jwt  # pyjwt, comme la vigie ; importé ici pour que les tests puissent s'en passer

    return jwt.encode(revendications, cle, algorithm="ES256", headers=en_tetes)


class JetonFournisseur:
    """Jeton d'authentification du fournisseur (« provider token ») : `{iss: équipe, iat}` signé ES256, `kid` = Key ID.
    Gardé 50 minutes, puis signé à nouveau. La clé est relue à chaque signature (une clé remplacée est prise sans
    redémarrer)."""

    def __init__(self, equipe, cle_id, chemin_cle, horloge=time.time, signer=_signer_es256, lire=None):
        self.equipe, self.cle_id, self.chemin_cle = equipe, cle_id, chemin_cle
        self._horloge, self._signer = horloge, signer
        self._lire = lire or (lambda chemin: open(chemin, encoding="utf-8").read())
        self._jeton, self._signe_le = None, 0.0

    def jeton(self):
        maintenant = self._horloge()
        if self._jeton and maintenant - self._signe_le < DUREE_JETON:
            return self._jeton
        if not self.cle_id:
            raise ValueError("Key ID de la clé APNs absent (key_id)")
        self._jeton = self._signer({"iss": self.equipe, "iat": int(maintenant)}, self._lire(self.chemin_cle),
                                   {"kid": self.cle_id})
        self._signe_le = maintenant
        return self._jeton


def en_tetes(fournisseur, sujet, collapse_id=None, priorite="10"):
    """En-têtes d'une notification `alert` (bannière, son ou pastille : la doc d'Apple range la pastille seule dans
    ce type). Priorité 10 = tout de suite ; 5 = « selon l'énergie de l'appareil », pour une pastille seule (28/10).
    `apns-collapse-id` : 64 octets au plus ; une nouvelle notification du même identifiant remplace l'ancienne."""
    h = {"authorization": f"bearer {fournisseur.jeton()}", "apns-topic": sujet, "apns-push-type": "alert",
         "apns-priority": str(priorite)}
    if collapse_id:
        h["apns-collapse-id"] = collapse_id.encode("utf-8")[:64].decode("utf-8", "ignore")
    return h


def envoyer(client, fournisseur, jeton_appareil, environnement, charge, sujet, collapse_id=None, priorite="10"):
    """Une notification vers un appareil. `client` : `httpx.Client(http2=True)` (ou un faux dans les tests).
    Renvoie (statut HTTP, raison) ; (0, texte de l'erreur) si Apple n'a pas pu être joint."""
    try:
        reponse = client.post(f"{hote(environnement)}/3/device/{jeton_appareil}",
                              headers=en_tetes(fournisseur, sujet, collapse_id, priorite), json=charge)
    except Exception as erreur:  # noqa: BLE001 - réseau, clé illisible : journalisé par l'appelant
        return 0, f"{type(erreur).__name__} : {erreur}"[:200]
    if reponse.status_code == 200:
        return 200, ""
    try:
        return reponse.status_code, (reponse.json() or {}).get("reason", "")
    except ValueError:
        return reponse.status_code, (reponse.text or "")[:80]
