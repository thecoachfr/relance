# Source de la lecture dans le Hub (29/10/2026, demande d'Alexandre) — contrat commun

But : voir dans le lecteur des trois vues D'OÙ vient la musique : le nom de la playlist (ou album, radio) ET la
source technique : « Music Assistant » (le Hub ou HA a lancé une file MA) par opposition à « Spotify » (Spotify Connect
en direct depuis un téléphone / l'app Spotify). AJOUT seulement : rien d'existant ne change.

## Capteur `sensor.lecture_source` (vigie, Rappels)
État : "music_assistant" | "spotify" | "radio" | "autre" | "rien" | "unavailable".
Attributs :
- `source` : libellé court affiché : « Music Assistant », « Spotify », « Radio », « AirPlay / autre ».
- `nom` : nom de ce qui est joué en contexte : nom de la playlist, de l'album ou de la station (« Titres likés »,
  « Découvertes de la semaine », « France Inter »), ou null si inconnu.
- `type` : "playlist" | "album" | "radio" | "artiste" | "titre" | null.
- `aleatoire` : bool (MA : `shuffle` de la file / du media_player ; Spotify : `shuffle_state` si disponible).
- `ligne` : la ligne prête à afficher, construite par la vigie (les vues ne recomposent rien) :
  « Music Assistant · Titres likés · aléatoire », « Spotify · Découvertes de la semaine », « Radio · France Inter »,
  « Spotify », « Music Assistant ». Pas de « au salon ».
- `entite` : l'entité qui joue (media_player.salon_ls50_5 ou media_player.kef_ls50_wireless_ii), `maj` (ISO).
Règles :
- Music Assistant joue (salon_ls50_5 playing/paused, source « Music Assistant Queue ») → "music_assistant".
  Le nom vient du DERNIER lancement connu sur cette file : écouter les appels de service
  `music_assistant.play_media` (événement `call_service`, toutes origines : script.hub_tv_radio, script.nest_hub_radio,
  script.hub_tv_ecouter, spotify_reprendre…) vers media_player.salon_ls50_5 et garder `media_id`/`media_type` ;
  résoudre le nom (library://playlist/N → nom via music_assistant.get_library / search ; uri spotify / tunein →
  search, ou table connue des stations fixes ; cache). Le lancement n'est valable que si la file active n'a pas
  été relancée depuis (même queue, current_index cohérent ; au doute, nom null plutôt que faux).
  Si le contenu est une radio (règle radio commune : /radio/, ://radio, radiofrance, icecast, .aac, station connue)
  → état "radio", `source` « Radio », `nom` = la station.
- Spotify Connect sur les LS50 (sensor.spotify_lecture `sur_ls50` et état lecture/pause, ou KEF en source wifi alors
  que MA ne joue pas) → "spotify", `nom` = contexte de sensor.spotify_lecture (null si inconnu, playlists faites
  par Spotify comprises).
- Renommages d'affichage : « Liked Songs … » / « Titres likés … » → « Titres likés ».
- Une erreur ne casse rien : capteur "unavailable" et les vues font comme aujourd'hui.

## Affichage (Hub TV, Hub iPad/iPhone, Nest Hub : mêmes mots, même place)
- Dans le lecteur (mini-lecteur, « En cours » / Lecteur d'Audio, plein écran, bandeau du Nest), la ligne `ligne`
  remplace la mention de source actuelle quand elle existe (ex. remplace « Spotify · contexte » du capteur Spotify,
  et le « · source » du plein écran) : sous le titre, en petit, couleur secondaire. Plein écran : « artiste » puis,
  dessous ou après « · », la `ligne`. Mini-lecteur : seulement si la place le permet (sinon garder l'artiste).
- Capteur absent / unavailable / "rien" : affichage d'aujourd'hui.

## Mise en œuvre côté HA (29/10/2026, déployée vers 16 h 15)

- Code : `appdaemon/apps/aiguillage_lecture_source.py` (fonctions pures), branché dans la vigie (`relance_vigie.py`,
  section « Source de la lecture pour le Hub »). Tests : `appdaemon/tests/test_aiguillage_lecture_source.py` (25).
- Lancements : la vigie écoute `call_service` `music_assistant.play_media` et `media_player.play_media` dont
  `entity_id` contient `media_player.salon_ls50_5`, et garde `media_id` / `media_type` dans
  `/config/lecture_source.json` (AppDaemon), relu au démarrage. `enqueue` `add` / `next` / `replace_next` = ajout :
  le contexte reste, la taille de la file est réapprise. Plusieurs `media_id` d'un coup : pas de nom.
- Nom : `music/item_by_uri` de l'API du serveur MA (`music_assistant_url` d'`apps.yaml`, jeton
  `/config/music_assistant_token`, le même que les favoris radio) pour une adresse (`library://…`, `spotify:…`) ; un
  `media_id` qui n'est pas une adresse (MA accepte un nom) est pris tel quel. Échec : nouvel essai au plus toutes les
  5 min. Nom gardé avec le lancement.
- Validité : identifiant de la file (`active_queue`) et taille (`items` de `music_assistant.get_queue`, lue au plus
  une fois par minute pendant que MA joue, apprise 10 s après le lancement). Autre file, autre taille ou
  `current_index` hors de la file → `nom` null (« Music Assistant » seul).
- Priorité : MA en lecture, Spotify en lecture sur les LS50, MA en pause, Spotify en pause sur les LS50, KEF en `wifi`
  qui joue (→ « Spotify » sans nom), KEF sur une autre entrée (→ « AirPlay / autre »), sinon « rien ». La KEF garde
  parfois un vieux titre Spotify pendant que MA joue : MA passe avant.
- Radio : règle commune d'`aiguillage_lecteur.contenu` sur le `media_content_id` de `salon_ls50_5` (ou lancement de
  type `radio`) ; nom = nom résolu du lancement, sinon station reconnue (fixes et `sensor.aiguillage_radios`).
- Aléatoire : `shuffle` de `salon_ls50_5` ; Spotify : nouvel attribut `aleatoire` de `sensor.spotify_lecture`
  (`shuffle_state` de `GET /me/player`, null si absent), ajouté le même jour.
- Publication par l'API REST de HA (AppDaemon 4.5 retire les null) : calcul 1 s après un changement de
  `salon_ls50_5`, de la KEF ou de `sensor.spotify_lecture`, et toutes les 30 s ; publié si quelque chose change (hors
  `maj`) et au moins toutes les 10 min. Erreur de calcul → `unavailable` (`maj`, `erreur`).
- Sauvegardes (apps d'AppDaemon) : `relance_vigie.py.avant-source-20261029`,
  `aiguillage_spotify_lecture.py.avant-source-20261029` ; `apps.yaml` inchangé. Retour arrière : remettre ces copies,
  supprimer `aiguillage_lecture_source.py` et `/config/lecture_source.json`.
- Mémo initialisé à la main au déploiement d'après la trace de `script.hub_tv_radio` de 15 h 36
  (`library://playlist/7`, playlist) : le lancement précédait le déploiement.
- Vérifié à 16 h 15 : `music_assistant`, « Music Assistant · Titres likés · aléatoire » (file `up84171515bd80`,
  109 titres, nom résolu « Liked Songs Alexandre Fau »), alors que la KEF affichait encore « Need to say » (ELEZO).
  **Reste à voir** : un lancement réel après le déploiement (journal « Source de lecture : lancement vu »).
