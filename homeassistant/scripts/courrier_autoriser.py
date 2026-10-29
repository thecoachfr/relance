#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Autorisation Gmail du courrier d'Aiguillage (plan P9-N, lot N3), à lancer UNE fois sur le Mac par Alexandre.

Flux OAuth « application de bureau » de Google, sans bibliothèque Google : serveur local sur 127.0.0.1 (port libre),
PKCE, `access_type=offline` et `prompt=consent` (pour obtenir un jeton de rafraîchissement), portée `gmail.modify`,
compte proposé `alexandre.fau@gmail.com`. Vérifie le compte par `users/me/profile`, puis écrit
`{client_id, client_secret, refresh_token, email}` (droits 600) dans le dossier d'AppDaemon sur HA, monté par le
Finder (`smb://homeassistant.local/addon_configs`). AppDaemon voit ce dossier comme `/config/`.

N'affiche jamais le secret ni les jetons. Rien n'est écrit dans un dépôt.

    uv run homeassistant/scripts/courrier_autoriser.py ~/Downloads/client_secret_XXXX.json [--agenda]

`--agenda` (29/10) : ajoute `calendar.readonly` (API Google Calendar à activer dans le projet « Relance »). Le JSON client se télécharge dans la console Google Cloud (projet « Relance ») : API et services › Identifiants ›
ID client OAuth de type « Application de bureau » › Télécharger le JSON.
"""

import argparse
import base64
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import secrets
import socket
import sys
import urllib.error
import urllib.parse
import urllib.request
import webbrowser

AUTORISATION_URL = "https://accounts.google.com/o/oauth2/v2/auth"
JETON_URL = "https://oauth2.googleapis.com/token"
PROFIL_URL = "https://gmail.googleapis.com/gmail/v1/users/me/profile"
PORTEE = "https://www.googleapis.com/auth/gmail.modify"
# Agenda Google perso en lecture seule (29/10, assistant de Courrier : Programme du jour, outil `agenda`), demandé avec
# --agenda dans le MÊME consentement : le jeton écrit couvre alors Gmail et l'agenda.
PORTEE_AGENDA = "https://www.googleapis.com/auth/calendar.readonly"
COMPTE = "alexandre.fau@gmail.com"
SORTIE = "/Volumes/addon_configs/a0d7b954_appdaemon/aiguillage_courrier_google.json"


def lire_client(chemin):
    donnees = json.loads(Path(chemin).expanduser().read_text(encoding="utf-8"))
    client = donnees.get("installed") or donnees.get("web") or donnees
    if not client.get("client_id") or not client.get("client_secret"):
        raise SystemExit(f"{chemin} : client_id ou client_secret manquant (JSON « Application de bureau » attendu).")
    return client["client_id"], client["client_secret"]


def port_libre():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def pkce():
    verificateur = secrets.token_urlsafe(64)[:96]
    defi = base64.urlsafe_b64encode(hashlib.sha256(verificateur.encode()).digest()).decode().rstrip("=")
    return verificateur, defi


def attendre_code(port, etat):
    """Sert une seule requête sur 127.0.0.1:port et renvoie le code d'autorisation."""
    resultat = {}

    class Recepteur(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802 - nom imposé par http.server
            params = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            resultat.update({k: v[0] for k, v in params.items()})
            ok = "code" in resultat and resultat.get("state") == etat
            texte = ("Autorisation reçue. Vous pouvez fermer cet onglet." if ok
                     else "Autorisation refusée ou invalide. Revenir au terminal.")
            corps = f"<html><body style='font-family:-apple-system;padding:2em'>{texte}</body></html>".encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(corps)))
            self.end_headers()
            self.wfile.write(corps)

        def log_message(self, *args):
            pass

    serveur = HTTPServer(("127.0.0.1", port), Recepteur)
    serveur.timeout = 300
    while not resultat:
        serveur.handle_request()
    serveur.server_close()
    if resultat.get("error"):
        raise SystemExit(f"Google a refusé : {resultat['error']}")
    if resultat.get("state") != etat:
        raise SystemExit("Réponse inattendue (state différent) : rien n'est écrit.")
    return resultat["code"]


def poster(url, champs):
    requete = urllib.request.Request(url, data=urllib.parse.urlencode(champs).encode(), method="POST")
    try:
        with urllib.request.urlopen(requete, timeout=30) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        detail = json.loads(e.read() or b"{}").get("error_description") or e.reason
        raise SystemExit(f"Échange du code refusé ({e.code}) : {detail}") from None


def profil(jeton):
    requete = urllib.request.Request(PROFIL_URL, headers={"Authorization": f"Bearer {jeton}"})
    with urllib.request.urlopen(requete, timeout=30) as r:
        return json.loads(r.read())


def main():
    parser = argparse.ArgumentParser(description="Autorisation Gmail du courrier d'Aiguillage (une fois).")
    parser.add_argument("client_json", help="JSON client OAuth (« Application de bureau ») téléchargé de la console")
    parser.add_argument("sortie", nargs="?", default=SORTIE, help=f"fichier écrit (défaut : {SORTIE})")
    parser.add_argument("--compte", default=COMPTE, help=f"compte attendu (défaut : {COMPTE})")
    parser.add_argument("--agenda", action="store_true",
                        help="ajoute la lecture de l'agenda Google (calendar.readonly) à l'accès Gmail")
    args = parser.parse_args()

    sortie = Path(args.sortie).expanduser()
    if not sortie.parent.exists():
        raise SystemExit(f"{sortie.parent} introuvable : monter d'abord smb://homeassistant.local/addon_configs "
                         "dans le Finder (ou donner un autre chemin de sortie).")
    client_id, client_secret = lire_client(args.client_json)
    port = port_libre()
    redirection = f"http://127.0.0.1:{port}"
    verificateur, defi = pkce()
    etat = secrets.token_urlsafe(24)
    url = AUTORISATION_URL + "?" + urllib.parse.urlencode({
        "client_id": client_id, "redirect_uri": redirection, "response_type": "code",
        "scope": " ".join([PORTEE] + ([PORTEE_AGENDA] if args.agenda else [])),
        "access_type": "offline", "prompt": "consent", "login_hint": args.compte, "state": etat,
        "code_challenge": defi, "code_challenge_method": "S256",
    })
    print("Ouverture du navigateur pour autoriser l'accès à Gmail…")
    print(f"(Sinon, ouvrir cette adresse à la main :\n{url}\n)")
    webbrowser.open(url)
    code = attendre_code(port, etat)

    jetons = poster(JETON_URL, {
        "code": code, "client_id": client_id, "client_secret": client_secret, "redirect_uri": redirection,
        "grant_type": "authorization_code", "code_verifier": verificateur,
    })
    if not jetons.get("refresh_token"):
        raise SystemExit("Google n'a pas donné de jeton de rafraîchissement : retirer l'accès de l'app dans "
                         "myaccount.google.com › Sécurité › Applications tierces, puis relancer.")
    accordees = (jetons.get("scope") or "").split()
    if PORTEE not in accordees:
        raise SystemExit(f"Portée accordée inattendue ({jetons.get('scope')}) : cocher l'accès à Gmail, relancer.")
    if args.agenda and PORTEE_AGENDA not in accordees:
        raise SystemExit("L'accès à l'agenda n'a pas été coché : relancer et cocher « Afficher vos agendas ». "
                         "Rien n'est écrit (l'autorisation Gmail actuelle reste en place).")
    email = (profil(jetons["access_token"]).get("emailAddress") or "").lower()
    if email != args.compte.lower():
        raise SystemExit(f"Compte autorisé : {email}, attendu : {args.compte}. Rien n'est écrit.")

    contenu = json.dumps({"client_id": client_id, "client_secret": client_secret,
                          "refresh_token": jetons["refresh_token"], "email": email}, indent=1)
    fd = os.open(sortie, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(contenu + "\n")
    try:
        os.chmod(sortie, 0o600)
    except OSError:
        pass  # partage SMB : les droits suivent ceux du montage
    print(f"OK : accès à Gmail{' et à l’agenda' if args.agenda else ''} autorisé pour {email}, écrit dans {sortie} (AppDaemon : /config/{sortie.name}).")


if __name__ == "__main__":
    sys.exit(main())
