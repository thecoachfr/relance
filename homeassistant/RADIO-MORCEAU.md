# Reconnaissance radio, niveau 1 (29/10/2026, validé par Alexandre) — contrat commun

But : quand une radio joue sur les LS50, savoir quel morceau passe et pouvoir le garder sur Spotify d'un toucher
(« ♡ Garder ce titre »), sur les trois vues. AJOUT seulement.

## Capteur `sensor.radio_morceau` (vigie, Rappels)
État : "trouve" (morceau connu ET trouvé sur Spotify) | "inconnu_spotify" (morceau connu, pas sur Spotify) |
"emission" (pas de morceau : parole, émission) | "rien" (pas de radio en cours) | "unavailable".
Attributs : `titre`, `artiste`, `station` (nom), `origine` ("flux" | "rts" | "radiofrance"),
`spotify` : { `uri`, `lien` (https://open.spotify.com/track/…), `titre`, `artistes`, `image` } ou null,
`deja_garde` (bool : déjà dans « À écouter » ou déjà gardé), `maj` (ISO).
Sources, dans cet ordre :
1. Métadonnées du flux Music Assistant (salon_ls50_5 ou lsx_1190fa en lecture radio) : media_artist présent et
   media_title différent du nom de la station / d'un jingle (« JG … », « Jingle … », nom de station) → morceau.
2. Couleur 3 (tunein s15474 ou nom « Couleur 3 ») : API RTS publique
   https://il.srgssr.ch/integrationlayer/2.0/rts/songList/radio/byChannel/8ceb28d9b3f1dd876d1df1780f908578cbefc3d7?pageSize=3
   → morceau le plus récent si `isPlayingNow` ou s'il a commencé il y a moins de 6 min.
3. Radio France (Inter = 1, Culture = 5 ; flux icecast radiofrance franceinter / franceculture) :
   https://api.radiofrance.fr/livemeta/live/<id>/inter_player → `now.song` s'il existe (titre / interprètes) ; sinon
   "emission". Vérifier la forme réelle de `song` quand de la musique passe (FIP = 7 en passe souvent : s'en servir pour
   tester le décodage).
Interrogation : seulement quand une radio joue, au plus toutes les 30 s ; recherche Spotify (`/search?type=track`,
« track:… artist:… », puis sans guillemets) une seule fois par morceau (cache) ; correspondance acceptée si titre et
artiste concordent (comparaison sans accents ni casse, « feat. » et « (Radio Edit) » ignorés).

## Script `script.radio_garder_titre` (champ `uri` : l'uri Spotify affichée au moment du toucher)
Émet un événement traité par la vigie : ajoute le titre à la playlist « À écouter » (id configuré, `3bZ9RxcAN2UIXIhgGYHhlp`,
réutiliser le client d'aiguillage_spotify ; ne jamais créer de playlist), s'il n'y est pas déjà ; note dans la liste
« Entendu à la radio » (donnees_apps, espace aiguillage, clé `radio:entendus`, 200 derniers : date, station, titre,
artiste, uri) ; notification « Gardé : <titre> — <artiste> » par script.hub_notifier. Erreur Spotify : notification
« Spotify ne répond pas, réessaie ». Destination par défaut « aime » : TITRES LIKÉS (choix d'Alexandre le 29/10, 20 h 45 ; PUT /me/tracks, droit user-library-modify ; « À écouter » reste possible par le paramètre) (paramètre
garder un paramètre `destination` = "a_ecouter" | "aime").

## Affichage (Hub TV, iPad/iPhone, Nest : même mot, même place)
Dans le lecteur (Audio « En cours » / Lecteur, plein écran, bandeau du Nest), quand la lecture est une radio et que
`sensor.radio_morceau` = "trouve" : sous la ligne de la source, « ♪ <titre> — <artiste> » (si le flux ne le montre
pas déjà), et un bouton « ♡ Garder ce titre » à côté de « J'aime » / « Écouté » / « Éteindre la LSX seule » (même
style). Au toucher : « Gardé ✓ » 5 s (ou dès `deja_garde`), pas de double appui. "inconnu_spotify" : texte « Pas sur
Spotify », pas de bouton. Autres états : rien de nouveau.

## Mise en œuvre côté HA (29/10/2026, déployée vers 20 h 40)

- Code : `appdaemon/apps/aiguillage_radio_morceau.py` (fonctions pures, classe `Suivi` : rythme et caches), branché
  dans la vigie (`relance_vigie.py`, section « Morceau de la radio en cours »). Tests :
  `appdaemon/tests/test_aiguillage_radio_morceau.py` (24).
- **Destination de « Garder » : titres likés par défaut** (décision d'Alexandre, 29/10 vers 20 h 45) : `aimer`
  d'`aiguillage_spotify` (`PUT /me/library`, repli `PUT /me/tracks`). `destination: a_ecouter` reste possible : ajout
  à « À écouter » (id de `config:playlist_a_ecouter`, sinon `3bZ9RxcAN2UIXIhgGYHhlp`) s'il n'y est pas déjà, par un
  `POST /playlists/{id}/items` direct (jamais `Client.playlist()` ni création ; copie pour la TV remise à jour).
  Notification « Liké : <titre> — <artiste> » (« Gardé : … » pour « À écouter »), titre « Radio ».
- `deja_garde` : déjà dans les titres likés (`GET /me/library/contains?uris=…`, repli `/me/tracks/contains` ; les
  deux répondent avec le jeton actuel, vérifié le 29/10), en cache par morceau, ou gardé depuis le démarrage. Une
  erreur sur ce seul appel ne rend pas le capteur indisponible (false, nouvel essai au passage suivant).
- Lecteurs : `salon_ls50_5` puis `lsx_1190fa`, état `playing` seulement (pause = « rien »), radio selon la règle
  commune d'`aiguillage_lecteur.contenu` ; station = station reconnue (fixes et `sensor.aiguillage_radios`), sinon
  l'album, sinon « Radio ».
- **Ordre des sources, écart au contrat** : une station qui a une API (Couleur 3, Radio France) passe par l'API
  d'abord, le flux ensuite (leur flux donne souvent le nom de l'émission avec un « artiste ») ; les autres : flux.
  Jingles écartés : titre ou artiste vide, « JG … », « Jingle … », « Pub … », égal à la station (avec ou sans
  « Radio ») ou à l'album du flux, titre-fichier.
- **Radio France, écart au contrat** : `livemeta/live/<id>/inter_player` ne donne PAS le morceau (vérifié le 29/10
  vers 20 h 34 sur FIP = 7 : `now` = l'émission « Live à Fip » pendant que « Divorce me C.O.D. » passait ; les
  webradios FIP 64-78 ne donnent que « Le direct »). La vigie lit `https://api.radiofrance.fr/livemeta/pull/<id>` :
  `steps` dont `embedType` = `song` et `start` ≤ maintenant < `end` ; artiste = `performers`, sinon `authors`
  (`performers` est souvent vide). `now.song` d'`inter_player` reste décodé s'il apparaît un jour. Stations : Inter 1,
  Culture 5, FIP 7 (flux icecast `franceinter` / `franceculture` / `fip`, ou TuneIn s24875 / s2442 / s15200).
- Couleur 3 : étiquette en tête du titre retirée (« (REP) As It Goes » → « As It Goes », vu le 29/10).
- Correspondance Spotify : `/search?type=track&limit=10`, « track:"…" artist:"…" » puis texte libre ; titre égal sans
  accents, casse, ponctuation, « feat. … », « (Radio Edit) » (repli : sans parenthèses ni « - … », ex. « - 2002
  Remaster ») ; un artiste Spotify égal à l'artiste radio ou à l'un de ses noms (« A & B », « A feat. B »,
  « Dejot (CH) » → « dejot »). Cache de 300 morceaux (« pas sur Spotify » compris) ; une erreur n'est pas mise en
  cache. Essais réels du 29/10 : Patricia (Orquesta Aragon), Newtown Chips (Dejot (CH)), Divorce me C.O.D., Valley of
  tangled eyes (Asagaya), As It Goes (Joe Yorke) trouvés.
- Rythme : calcul 1 s après un changement d'un lecteur et toutes les 10 s ; une API de radio interrogée au plus toutes
  les 30 s (réponse gardée 30 s) ; aucune API ni Spotify quand aucune radio ne joue. Client Spotify à part (lecture
  seule, `ClientLecture`) ; après une erreur Spotify, pause selon `classer` (429 : `Retry-After`).
- Erreurs (API radio, recherche Spotify, HA) → `unavailable` (`maj`, `erreur`), rien n'est écrit.
- Publication par l'API REST de HA (AppDaemon 4.5 retire les null), si quelque chose change (hors `maj`) et au moins
  toutes les 10 min. Journal : « Radio : <état> (<station>, <origine>) titre — artiste » à chaque changement.
- `radio:entendus` (donnees_apps, espace aiguillage) : `{"entendus": [{date, station, titre, artiste, uri,
  destination}, …]}`, plus récent en tête, 200 au plus ; écrit seulement par « Garder » (conflit rejoué une fois).
- Script : `script.radio_garder_titre` (scripts.yaml, `mode: queued`, max 5 ; champs `uri`, `destination` = `aime`
  par défaut) → événement `radio_garder_titre`.
- Sauvegardes : `relance_vigie.py.avant-radio-morceau-20261029` (apps d'AppDaemon) et
  `/config/scripts.yaml.avant-radio-morceau-20261029` ; `apps.yaml` inchangé. Retour arrière : remettre ces copies,
  supprimer `aiguillage_radio_morceau.py` des apps, recharger les scripts.
- Vérifié à 20 h 40 : vigie rechargée sans erreur (journal « Radio : rien »), `sensor.radio_morceau` = `rien` (aucune
  radio ne jouait), `script.radio_garder_titre` présent. Le script n'a PAS été appelé en vrai (testé en unitaire).
  **Reste à voir** : une radio réelle (« trouve » sur Tsugi / Couleur 3, « emission » sur Inter).
