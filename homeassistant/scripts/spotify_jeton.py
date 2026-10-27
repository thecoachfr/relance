"""Connexion Spotify d'Aiguillage (plan P9-D4), à lancer UNE fois sur le Mac par Alexandre.

Réutilise l'app Spotify de `spotify-library-tool` (identifiant et secret dans son `.env`, redirect URI
`http://127.0.0.1:8888/callback` déjà déclaré). Ouvre le navigateur pour accorder les droits, puis écrit
`spotify_aiguillage.json` (identifiant, secret, jeton de rafraîchissement) dans le dossier d'AppDaemon sur HA,
monté par le Finder. N'affiche jamais le secret ni les jetons. Rien n'est écrit dans un dépôt.

    ../spotify-library-tool/.venv/bin/python homeassistant/scripts/spotify_jeton.py
"""

import json
import os
from pathlib import Path

from spotipy.oauth2 import SpotifyOAuth

OUTIL = Path(__file__).resolve().parents[3] / "spotify-library-tool"
CIBLE = Path("/Volumes/addon_configs/a0d7b954_appdaemon/spotify_aiguillage.json")
SCOPES = (
    "playlist-read-private playlist-read-collaborative playlist-modify-private playlist-modify-public "
    "user-read-playback-state user-modify-playback-state user-library-modify "
    # 27/10/2026 : « Reprendre Spotify » du Hub (dernier contexte écouté), voir homeassistant/SPOTIFY-LECTURE.md.
    "user-read-recently-played"
)


def lire_env(chemin):
    valeurs = {}
    for ligne in chemin.read_text().splitlines():
        if "=" in ligne and not ligne.lstrip().startswith("#"):
            cle, valeur = ligne.split("=", 1)
            valeurs[cle.strip()] = valeur.strip().strip('"')
    return valeurs


def main():
    if not CIBLE.parent.exists():
        raise SystemExit("Monter d'abord smb://homeassistant.local/addon_configs dans le Finder.")
    env = lire_env(OUTIL / ".env")
    cache = Path.home() / ".config/aiguillage-tv/.cache-spotify-aiguillage"
    cache.parent.mkdir(parents=True, exist_ok=True)
    auth = SpotifyOAuth(
        client_id=env["SPOTIPY_CLIENT_ID"], client_secret=env["SPOTIPY_CLIENT_SECRET"],
        redirect_uri=env.get("SPOTIPY_REDIRECT_URI", "http://127.0.0.1:8888/callback"),
        scope=SCOPES, cache_path=str(cache), open_browser=True,
    )
    jeton = auth.get_access_token(as_dict=True, check_cache=False)
    accordes = set((jeton.get("scope") or "").split())
    manquants = set(SCOPES.split()) - accordes
    if manquants:
        raise SystemExit(f"Droits non accordés : {', '.join(sorted(manquants))}")
    donnees = {"client_id": env["SPOTIPY_CLIENT_ID"], "client_secret": env["SPOTIPY_CLIENT_SECRET"],
               "refresh_token": jeton["refresh_token"], "scopes": SCOPES}
    CIBLE.write_text(json.dumps(donnees))
    os.chmod(CIBLE, 0o600)
    cache.unlink(missing_ok=True)
    print(f"Connexion Spotify enregistrée pour Aiguillage ({len(accordes)} droits) : {CIBLE.name} sur HA.")


if __name__ == "__main__":
    main()
