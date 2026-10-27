# Lecture Spotify dans le Hub (27/10/2026) — contrat commun

Principe (validé par Alexandre) : AJOUT seulement. Rien de l'existant ne change (lecteur sur l'entité qui joue,
binary_sensor.lecture_*, commandes par Music Assistant / KEF, script.nest_hub_radio, masquage de l'activité quand
Spotify pilote). Le Nest Hub n'est PAS touché avant qu'Alexandre ait testé le Hub TV et l'iPad une journée.

## Capteur `sensor.spotify_lecture` (vigie, lecture seule de l'API Spotify)
- Interrogé seulement quand c'est utile : toutes les 15 s quand les LS50 (KEF) sont en source `wifi` ou qu'une vue
  l'a demandé récemment ; sinon toutes les 2 min (pour savoir si Spotify joue sur un autre appareil). Aucune écriture.
- État : "lecture" | "pause" | "rien" | "unavailable" (API en erreur : les vues font comme aujourd'hui).
- Attributs : `appareil` (nom Spotify : « Salon LS50 », « iPhone »…), `sur_ls50` (bool : appareil = « Salon LS50 »),
  `titre`, `artistes` (texte « A, B »), `album`, `image` (URL https de la pochette), `lien` (https://open.spotify.com/track/…),
  `contexte` : { `type` (playlist/album/artist/null), `nom` (nom de la playlist ou de l'album, via un GET mis en
  cache), `lien` }, `duree_s`, `position_s`, `position_le` (ISO), `ls50_visible` (bool : « Salon LS50 » dans
  /me/player/devices), `maj` (ISO).

## Scripts HA (appelés par les vues)
- `script.spotify_sur_ls50` : transfère la lecture Spotify en cours (autre appareil) vers « Salon LS50 »
  (PUT /me/player, play true). Si les LS50 ne sont pas visibles : les réveiller d'abord (media_player.turn_on sur
  media_player.kef_ls50_wireless_ii, attendre jusqu'à 20 s qu'elles apparaissent), sinon échec propre (notification
  « LS50 introuvables pour Spotify » par script.hub_notifier si c'est le mécanisme commun).
- `script.spotify_reprendre` : rien ne joue → relancer sur les LS50 le dernier contexte écouté
  (GET /me/player/recently-played → context uri ; à défaut le dernier titre), même réveil.
- « J'aime » sur le morceau Spotify en cours : réutiliser script.aiguillage_spotify_aime {lien} (existant).

## Affichage (Hub TV et iPad/iPhone ; Nest plus tard)
- Quand `sur_ls50` et lecture/pause : sous le titre du lecteur, « Spotify · <nom du contexte> » ; bouton « J'aime »
  (même mot et même place que dans le plein écran) ; la pochette/titre/artiste du capteur priment sur ceux de la KEF.
  Commandes inchangées (KEF / Music Assistant), volume inchangé.
- Section Audio, en tête des rangées : un bouton « Mettre sur les LS50 » (icône Spotify + flèche) visible SEULEMENT
  si Spotify joue sur un autre appareil (état lecture, `sur_ls50` false) — avec le nom de l'appareil (« Spotify joue
  sur l'iPhone · Mettre sur les LS50 ») ; et « Reprendre Spotify » visible SEULEMENT si rien ne joue sur les LS50
  (ni Music Assistant ni KEF) et que Spotify est à « rien »/« pause ». Jamais pendant une radio Music Assistant.
- Capteur absent / unavailable : rien de nouveau ne s'affiche (comportement d'aujourd'hui).

## Mise en œuvre côté HA (27/10/2026, déployée vers 17 h 47)

- Code : `appdaemon/apps/aiguillage_spotify_lecture.py` (fonctions pures, rythme, cache, erreurs ; client
  `ClientLecture` = celui d'`aiguillage_spotify`, sans nouvel essai sur coupure, délai 8 s, jeton renouvelé sur un 401),
  branché dans la vigie (`relance_vigie.py`, section « Lecture Spotify pour le Hub »). Tests :
  `appdaemon/tests/test_aiguillage_spotify_lecture.py` (18).
- Identifiants : `/config/spotify_aiguillage.json` d'AppDaemon (le même que la playlist « À écouter »), client à part
  (lecture seule, aucun appel à la playlist).
- Rythme : la vigie regarde toutes les 5 s (sans appel) ; interrogation toutes les 15 s si la KEF est en entrée
  `wifi` ou si une vue a demandé depuis moins de 5 min, sinon toutes les 2 min ; **jamais deux interrogations à moins
  de 15 s**. Une interrogation = `GET /me/player` ; plus `GET /me/player/devices` au plus une fois par minute et
  seulement si la lecture n'est pas déjà sur les LS50 ; plus le nom du contexte s'il n'est pas en cache.
- Demande d'une vue (facultatif) : événement `spotify_lecture_demande` (rythme rapide 5 min). Les scripts comptent
  aussi comme demande.
- Nom du contexte : lu dans le morceau quand c'est possible (album, artiste, émission ; `collection` → « Titres
  likés »), sinon `GET /playlists/{id}?fields=name` (ou `/artists/{id}`), gardé 6 h. **Les playlists de Spotify
  (« Daily Mix », « Découvertes de la semaine », ids `37i9dQZ…`) répondent 404 aux apps** : `nom` reste `null`
  (gardé 1 h) ; la vue affiche alors « Spotify » seul. `contexte.type` peut aussi valoir `collection` ou `show`.
- Erreurs : 5xx, délai, coupure, 429, 401/403 du jeton → état `unavailable` (attributs `maj`, `erreur` seulement),
  pause avant le prochain appel (429 : `Retry-After`, 30 s s'il manque, 1 h au plus ; 5xx et réseau 30 s ; jeton
  refusé 5 min). Un 404/403 sur le seul nom du contexte ne rend pas le capteur indisponible. Le capteur n'écrit et
  ne crée jamais rien chez Spotify.
- Publication par l'API REST de HA (AppDaemon 4.5 retire les 0/null) : à chaque changement (titre, état, appareil…
  ou saut de position de plus de 3 s), et au moins toutes les 10 min ; la position qui avance normalement ne republie
  pas (`position_le` + `position_s` permettent de l'extrapoler).
- Scripts : `script.spotify_sur_ls50` et `script.spotify_reprendre` (scripts.yaml, `mode: single`) émettent les
  événements `spotify_sur_ls50` / `spotify_reprendre`, traités par la vigie. « Salon LS50 » absent de
  `/me/player/devices` : `media_player.turn_on` sur la KEF, relecture toutes les 4 s pendant 20 s, sinon
  `script.hub_notifier` « LS50 introuvables pour Spotify » (titre « Spotify »). Erreur Spotify pendant un script :
  « Spotify ne répond pas, réessaie dans un moment ».
  - Transfert : rien si rien ne joue ou si la lecture est déjà sur les LS50.
  - Reprendre : une lecture **en pause** (sur n'importe quel appareil) reprend sur les LS50 là où elle en était
    (`PUT /me/player`, play true) ; sinon le dernier contexte de `/me/player/recently-played` (à défaut le dernier
    titre) ; sinon le dernier contexte vu par le capteur depuis le démarrage de la vigie ; sinon notification
    « Rien à reprendre sur Spotify ».
  - **Droit `user-read-recently-played` pas encore accordé** : ajouté à `scripts/spotify_jeton.py`, à relancer une
    fois par Alexandre sur le Mac ; d'ici là, la vigie saute cet appel et se sert de la mémoire du capteur.
- Sauvegardes : `relance_vigie.py.avant-spotify-lecture-20261027`, `apps.yaml.avant-spotify-lecture-20261027` (apps
  d'AppDaemon, inchangé) et `/config/scripts.yaml.avant-spotify-lecture-20261027`. Retour arrière : remettre ces
  copies, supprimer `aiguillage_spotify_lecture.py` des apps, recharger les scripts.
- Vérifié à 17 h 47 : capteur `lecture`, « Salon LS50 », « Nowhere » (WILL FERRO), contexte playlist `37i9dQZ…`
  (nom `null`, 404), `ls50_visible` true. Scripts testés en unitaire seulement (pas déclenchés : ils couperaient la
  musique).
