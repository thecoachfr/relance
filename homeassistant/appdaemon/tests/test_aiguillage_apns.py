"""Tests hors Home Assistant de `aiguillage_apns` (lot C5 de l'app Courrier, 26/10/2026) : jeton JWT simulé, choix du
serveur, en-têtes, réponses d'Apple. Aucun appel réseau, aucune clé réelle."""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import aiguillage_apns as apns  # noqa: E402


class Horloge:
    def __init__(self, t=1_000_000.0):
        self.t = t

    def __call__(self):
        return self.t


def fournisseur(horloge=None, cle_id="ABCDE12345"):
    signes = []

    def signer(revendications, cle, en_tetes):
        signes.append((revendications, cle, en_tetes))
        return f"jwt-{len(signes)}"

    f = apns.JetonFournisseur("GD6W292ZXP", cle_id, "/config/apps/AuthKey_relance.p8", horloge=horloge or Horloge(),
                              signer=signer, lire=lambda chemin: f"clé de {chemin}")
    return f, signes


def test_jeton_signe_puis_garde_50_minutes():
    h = Horloge()
    f, signes = fournisseur(h)
    assert f.jeton() == "jwt-1"
    assert signes[0] == ({"iss": "GD6W292ZXP", "iat": 1_000_000}, "clé de /config/apps/AuthKey_relance.p8",
                         {"kid": "ABCDE12345"})
    h.t += 49 * 60
    assert f.jeton() == "jwt-1" and len(signes) == 1
    h.t += 60                                   # 50 minutes : nouvelle signature
    assert f.jeton() == "jwt-2" and signes[1][0]["iat"] == 1_000_000 + 50 * 60


def test_jeton_sans_key_id_refuse():
    f, signes = fournisseur(cle_id=None)
    try:
        f.jeton()
    except ValueError as e:
        assert "key_id" in str(e)
    else:
        raise AssertionError("un Key ID absent doit être refusé")
    assert signes == []


def test_vraie_signature_es256_lisible():
    """Avec pyjwt et cryptography (présents dans l'add-on, comme pour la vigie) : une clé EC P-256 de test."""
    import jwt
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ec

    cle = ec.generate_private_key(ec.SECP256R1())
    pem = cle.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                            serialization.NoEncryption()).decode()
    f = apns.JetonFournisseur("GD6W292ZXP", "ABCDE12345", "x.p8", horloge=Horloge(), lire=lambda _: pem)
    jeton = f.jeton()
    assert jwt.get_unverified_header(jeton) == {"alg": "ES256", "kid": "ABCDE12345", "typ": "JWT"}
    assert jwt.decode(jeton, cle.public_key(), algorithms=["ES256"]) == {"iss": "GD6W292ZXP", "iat": 1_000_000}


def test_serveur_selon_l_environnement():
    assert apns.hote("sandbox") == "https://api.sandbox.push.apple.com"
    assert apns.hote("production") == "https://api.push.apple.com"
    assert apns.hote("autre") == "https://api.push.apple.com"


def test_refus_definitifs():
    assert apns.refus_definitif(410, "Unregistered") and apns.refus_definitif(400, "BadDeviceToken")
    assert not apns.refus_definitif(400, "BadCollapseId") and not apns.refus_definitif(403, "ExpiredProviderToken")
    assert not apns.refus_definitif(0, "ConnectError") and not apns.refus_definitif(429, "TooManyRequests")


class Reponse:
    def __init__(self, statut, corps=None, texte=""):
        self.status_code, self._corps, self.text = statut, corps, texte

    def json(self):
        if self._corps is None:
            raise ValueError("pas du JSON")
        return self._corps


class Client:
    def __init__(self, reponse=None, erreur=None):
        self.reponse, self.erreur, self.appels = reponse, erreur, []

    def post(self, url, headers, json):
        self.appels.append((url, headers, json))
        if self.erreur:
            raise self.erreur
        return self.reponse


def test_envoyer_en_tetes_et_reponses():
    f, _ = fournisseur()
    client = Client(Reponse(200))
    charge = {"aps": {"alert": {"title": "t", "body": "b"}}}
    assert apns.envoyer(client, f, "ab" * 32, "sandbox", charge, "fr.alexandrefau.courrier", "x" * 80) == (200, "")
    url, h, corps = client.appels[0]
    assert url == "https://api.sandbox.push.apple.com/3/device/" + "ab" * 32 and corps == charge
    assert h["authorization"] == "bearer jwt-1" and h["apns-topic"] == "fr.alexandrefau.courrier"
    assert h["apns-push-type"] == "alert" and h["apns-priority"] == "10" and h["apns-collapse-id"] == "x" * 64
    assert "apns-collapse-id" not in apns.en_tetes(f, "s")
    # Pastille seule (28/10) : même type `alert`, priorité 5.
    apns.envoyer(client, f, "ab" * 32, "production", {"aps": {"badge": 3}}, "s", priorite="5")
    assert client.appels[-1][1]["apns-priority"] == "5" and client.appels[-1][1]["apns-push-type"] == "alert"
    assert apns.envoyer(Client(Reponse(410, {"reason": "Unregistered"})), f, "t", "production", {}, "s") == \
        (410, "Unregistered")
    assert apns.envoyer(Client(Reponse(500, None, "panne")), f, "t", "production", {}, "s") == (500, "panne")
    statut, raison = apns.envoyer(Client(erreur=OSError("réseau")), f, "t", "production", {}, "s")
    assert statut == 0 and "réseau" in raison
    # Clé absente : l'envoi échoue proprement (pas d'exception), l'appelant journalise.
    sans, _ = fournisseur(cle_id=None)
    assert apns.envoyer(Client(Reponse(200)), sans, "t", "production", {}, "s")[0] == 0
