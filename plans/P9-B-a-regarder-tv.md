# P9-B — Envies « À regarder » et « Sur la TV »

*Plan du 16/10/2026. Lire d'abord `P9-00-INDEX.md`. Dépôts : `relance` (app, vigie AppDaemon), configuration HA (script). Prérequis : lot 0 (Player joignable dans HA).*

## 1. But

Ajouter un film ou une série de deux façons, et le lancer sur la TV du salon :

- **partager le lien** depuis l'app Netflix, Apple TV, Disney+, Canal+, Prime Video, YouTube… ;
- **dire ou écrire une phrase** : « regarde The Bear sur Disney+ », « Dune à regarder ».

Puis : savoir **sur quelle plateforme** le titre est disponible en France, l'ouvrir dans l'app sur l'iPhone, ou **sur la TV** (Freebox Player Pop, Android TV) en un toucher.

## 2. Existant (lu le 16/10)

- `SharedLink` classe déjà en « À regarder » les liens netflix.com, primevideo.com, disneyplus.com, tv.apple.com, canalplus.com, france.tv, arte.tv, youtube.com, etc., et lit le titre de la page.
- La routine de tri reconnaît « à regarder » dans le titre et les liens (étape K) et écrit `🎬 À regarder`.
- HA connaît le Player : `remote.freebox_player_pop` (intégration Android TV Remote).

## 3. Lots

### B1 — Plateforme et identifiant du titre depuis le lien
*En cours (16/10) : champ `envie` en service ; Netflix, Canal+ (`mycan.al`) et Disney+ figés sur de vrais liens (voir SUIVI et `Shared/Share/SharedLink.swift`) ; Apple TV, Prime Video, France TV et Arte reportés (moins courants).*
- Remplir `envie.plateforme` (`netflix`, `apple_tv`, `disney`, `canal`, `prime`, `youtube`, `france_tv`, `arte`…), `envie.id_titre` et `envie.lien` à partir de l'adresse partagée (ex. le numéro après `netflix.com/title/`).
- **Formats à figer sur de vrais liens** : Alexandre partage vers une note deux liens par plateforme (un film, une série), depuis l'app de la plateforme sur l'iPhone ; Claude Code en fait des cas de test. Ne pas supposer un format non vu.
- **Accepté quand** : chaque lien réel donne plateforme, identifiant et titre ; tests unitaires.

### B2 — Phrase seule
- Paragraphe pour la routine de tri (étape K) : quand une envie « À regarder » nomme une plateforme (« sur Netflix », « sur Apple TV »), remplir `envie.plateforme` ; remettre le titre exact de l'œuvre dans le titre de la tâche (sans « sur Netflix ») avec la ligne `🎙 Dicté : …` comme aujourd'hui. Ne jamais inventer d'identifiant ni de lien. À appliquer à la routine après B1 en service (index, section 4).

### B3 — Disponibilité en France par TMDB (vigie AppDaemon)
- Pourquoi la vigie : elle tourne dans HA, a accès à Internet et réagit déjà à `donnees_apps_modifie` ; la routine n'a que l'outil Home Assistant.
- Quand une tâche a `envie.type = regarder` sans `tmdb` (ou `dispo_maj` de plus de 7 jours) : chercher le titre dans TMDB (`/search/multi`, `language=fr-FR`, année si connue), garder `tmdb = {id, type: movie|tv, titre, annee, affiche}` ; puis `/{movie|tv}/{id}/watch/providers` → `dispo_fr` = fournisseurs pour la France, par mode (abonnement, location, achat), et `dispo_maj`.
- TMDB fournit ces disponibilités grâce à JustWatch et **impose de citer JustWatch** : afficher « Disponibilités : JustWatch » dans la fiche. TMDB **ne donne pas de lien direct** vers l'app (documentation : « This is not going to return full deep links ») : le lien reste celui partagé, ou à défaut la plateforme seule.
- Si plusieurs résultats plausibles : ne rien écrire et ajouter `💡 Suggestion : préciser l'année` (une seule fois).
- Si `envie.plateforme` est vide : la déduire de `dispo_fr` (abonnement d'abord).
- Abonnements d'Alexandre : liste réglable dans l'app (Réglages › Envies), rangée dans l'espace `aiguillage` sous une clé non-UUID (`config:abonnements`, que la routine ignore). Badge « inclus dans ton abonnement » / « plus disponible sur Netflix » dans la fiche ; notification passive quand un titre quitte une plateforme à laquelle Alexandre est abonné.
- Clé TMDB (jeton d'accès en lecture) dans `/config/tmdb_token` sur HA, jamais dans le dépôt. Écritures de la vigie : `donnees_apps.ecrire` avec `version_attendue`, `modifie_par: "vigie"`, `op_id` neuf ; en cas de conflit, relire et réessayer une fois.
- **Accepté quand** : 10 titres d'essai (films et séries, dont un homonyme) : bons `tmdb` et `dispo_fr`, ambiguïté signalée, pas de boucle d'écriture (la vigie ignore ses propres modifications).

### B4 — « Sur la TV » par Home Assistant
- Script HA `script.aiguillage_sur_tv` (champ `lien`, mode `queued`) : allumer le Player s'il est éteint (`remote.turn_on` sans activité, courte attente), puis `remote.turn_on` avec `activity: <lien>`. Le créer dans HA (par l'interface ou le chat Claude) et le décrire dans le README ; vérifier que l'utilisateur non administrateur `apps-perso` peut l'appeler.
- App : bouton « Sur la TV » dans la fiche des envies « À regarder » et « À écouter » qui ont un lien ; il appelle le script par l'API REST (même URL et même jeton que `DonneesHA`). Retour visible : « Envoyé à la TV » ou l'erreur.
- Les liens envoyés sont ceux validés en B5 (transformation par plateforme, ex. Netflix : ajouter `?source=30`).

### B5 — Essais des liens sur le Player (avec Alexandre devant la TV)
*16/10 : Netflix, Canal+, Disney+ et YouTube ouvrent le titre ; Spotify l'affiche sans le lire (formes dans `docs/LIENS-TV.md`). Reste la lecture Spotify par Spotify Connect.*
- Documentation de HA (intégration Android TV Remote, lue le 16/10) : `remote.turn_on` + `activity` accepte un identifiant d'app, une URL ou un schéma ; YouTube (`https://www.youtube.com`), Netflix (un titre précis seulement si le lien finit par `?source=30`), Prime Video, Disney+ (ouverture de l'app). Apple TV, myCANAL et Spotify n'y figurent pas ; le guide communautaire des liens profonds non plus pour ces plateformes. L'app Apple TV est disponible sur le Player Pop depuis mars 2022 (Univers Freebox).
- Tableau à remplir dans `docs/LIENS-TV.md` (fichier du dépôt, sans donnée personnelle) : plateforme × forme du lien (lien web du titre, schéma d'app, identifiant de paquet) × résultat (ouvre l'app / ouvre le titre / rien). Plateformes : Netflix, Apple TV, Disney+, myCANAL, Prime Video, YouTube, Spotify, France TV, Arte.
- **Spotify (demande d'Alexandre du 16/10 : lire les morceaux sur la TV, l'app Spotify existe sur Android TV)** :
  - ouvrir : essayer un lien `https://open.spotify.com/…` et un URI `spotify:album:…` en `activity`. La documentation Android de Spotify dit qu'un lien de contenu « brings Spotify to the foreground with the selected content » ; elle ne parle pas de lecture automatique ;
  - **lire** : par Spotify Connect, avec l'API Web (démarrer ou transférer la lecture sur l'appareil « TV » d'après son `device_id`). Exige un compte Premium et le droit `user-modify-playback-state` ; jeton de l'app Spotify de `spotify-library-tool` (voir D4), gardé dans HA. **À vérifier** : le Player n'apparaît sans doute dans la liste des appareils Spotify (`GET /me/player/devices`) que si l'app Spotify y est ouverte ; d'où l'enchaînement « ouvrir l'app, attendre qu'elle apparaisse, lancer la lecture ».
  - script HA `script.aiguillage_spotify_sur_tv` (champ `lien`) : ouvrir Spotify sur le Player, puis demander à la vigie de lancer la lecture (événement ou service AppDaemon), avec un message clair si l'appareil n'apparaît pas.
- **Accepté quand** : tableau rempli ; B4 utilise pour chaque plateforme la meilleure forme trouvée.

## 4. Hors périmètre

Lecture automatique des films et séries (la TV ouvre la page du titre ; Alexandre lance la lecture ; seule la musique Spotify est lancée à distance), suivi des épisodes vus, The Frame (Samsung, Tizen : pas d'Android TV).

## 5. Documentation à tenir

README (« Sur la TV », clé TMDB, script HA), `docs/LIENS-TV.md`, SUIVI, ce plan.
