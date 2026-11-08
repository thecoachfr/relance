# Contrat du capteur `sensor.hub_ce_soir` (28/10/2026) — « Ce soir » à la TV, pour le Hub TV et le Hub iPad

Cadrage : `hub-tv/docs/CE-SOIR.md` (H46). Calculé par l'app AppDaemon `hub_ce_soir` (dépôt Rappels, à côté de la
vigie). Les vues ne font QUE l'afficher : aucun filtre ni tri dans les vues. Le Nest Hub n'a pas de Vidéo.

Ce que c'est : les films, séries, documentaires et reportages qui **commencent entre 20 h 40 et 21 h 20** sur les
chaînes d'Alexandre (liste fixe validée par lui le 28/10/2026 : TNT, CANAL+ 40, 45 et 46, et ses chaînes cinéma,
séries et documentaires). Direct
seulement. Programmes de moins de 20 min, interdits aux moins de 18 ans et déjà finis écartés ; d'une série dont
plusieurs épisodes se suivent sur la même chaîne, seul le premier est gardé. Écartés aussi : séries d'animation,
jeunesse, téléréalité (`EXCLUS`) ; **les films d'animation sont gardés** depuis le 08/11/2026 (*Super Mario Galaxy le
film*, CANAL+ Box Office, 07/11 à 21 h, manquait : OQEE le classe « Film d'animation »).

État : nombre de programmes (entier, 0 s'il n'y en a pas, par exemple après 23 h quand tout est fini).

Attributs (exemple : `HUB-CE-SOIR-exemple.json`) :
- `maj` : ISO 8601, heure du calcul.
- `soiree` : `AAAA-MM-JJ`.
- `source` : `oqee` (guide d'OQEE) ou `freebox` (repli, sans sous-genre ni année ; `genre_texte` = « Film »…).
- `genres` (01/11/2026) : les boutons, dans l'ordre, seulement les familles qui ont des programmes : [{`code` (`film`,
  `serie`, `documentaire`, `telefilm`), `nom` (« Films », « Séries », « Docs et reportages », « Téléfilms »), `nombre`}].
- `programmes` : rangés par famille dans l'ordre de `genres`, 10 au plus par famille (`PAR_GENRE`), dans l'ordre
  d'affichage : [{
  `titre` (sans « - S03E06 »), `episode` (« S3 · É6 » ou null), `genre` (`film`, `documentaire`, `reportage`,
  `serie`, `telefilm`), `famille` (01/11/2026 : le bouton, `code` de `genres` ; un reportage est de la famille
  `documentaire`), `genre_texte` (sous-genre d'OQEE, « Thriller », « Série policière »…), `annee` (ou null),
  `chaine` (nom affiché), `numero` (numéro Free), `oqee_id` (identifiant de chaîne qu'ouvre le Hub TV, comme
  `Applis.CHAINES`), `logo` (logo d'OQEE pour fond sombre, ou null : afficher alors le nom), `debut` et `fin`
  (ISO 8601 à la minute), `heure_texte` (« 21 h 10 »), `fin_texte` (« 23 h 20 »), `duree_texte` (« 2 h 10 », « 50 min »), `en_cours` (booléen, au moment du calcul), `image` (image
  paysage d'OQEE en 480 px de haut, ou null ; en repli Freebox, adresse locale `mafreebox.freebox.fr`), `image_grande` (même image
  en 1080 px, pour la fiche, ou null), `resume` (600 caractères au plus, ou null ; 220 avant le 28/10 au soir), `envie` (vrai si le titre est une envie « À regarder » d'Aiguillage pas encore
  vue), `imdb_id` (« tt0119174 » ou null), `note_imdb` (7.7 ou null), `note_texte` (« 7,7 » ou null ; null aussi
  sous 100 votes), `votes_imdb` (entier, null sans note) }]. Notes IMDb ajoutées le 28/10/2026 au soir (films, séries et téléfilms).

Ordre, dans chaque famille : d'abord les envies ; puis (chez les docs) les documentaires avant les reportages ;
ce qui commence à partir de 20 h 50 avant l'avant-soirée, puis la note IMDb (sans note : après), puis les grandes chaînes (TF1, France 2, France 3,
France 5, M6, Arte) et CANAL+, puis le plus récent (année), puis l'heure. 10 programmes au plus par famille (une envie passe toujours). Jusqu'au
01/11/2026 : une seule rangée de 12 au plus, avec des places par genre (6 films, 3 docs, 3 séries, 2 téléfilms), qui
cachait par exemple les films de TF1 et de France 2 ; remplacée par les boutons à la demande d'Alexandre (maquette
validée le 01/11/2026).

## Règles d'affichage communes (revues le 28/10/2026 au soir, après la photo d'Alexandre : trop petit, note coupée)

1. **Rangée « Ce soir »** dans Vidéo, après « À regarder ». Rien du tout si `programmes` est vide ou le capteur absent.
   **Boutons par genre (01/11/2026)** sous le titre « Ce soir » : un par entrée de `genres`, « `nom` `nombre` » (pastille ;
   choisie : fond craie, texte nuit ; les autres : fond surface, texte ballast). Le premier est choisi d'office. La
   rangée de tuiles dessous ne montre que les programmes dont `famille` = le bouton choisi. Hub TV : Gauche / Droite
   sur les boutons changent de genre (la rangée suit tout de suite), Bas descend aux tuiles, Haut remonte aux boutons.
   Hub iPad : toucher un bouton. Un seul genre : les boutons restent (ils disent ce que c'est et combien).
2. **Tuile** : `image` (sinon fond ardoise), `logo` de la chaîne en haut à gauche (sinon `chaine`), « En cours » (vert) si
   `en_cours`, sinon « Envie » (jaune) si `envie`, en haut à droite ; **pastille « IMDb `note_texte` » en bas à droite
   de l'image** (jaune IMDb, texte sombre), toujours lisible ; dessous, `titre` (et `episode`), puis
   « `heure_texte` · `genre_texte` · `annee` » (plus de note dans cette ligne : elle était coupée).
3. **Action : la fiche détaillée** (OK au Hub TV, toucher sur l'iPad) : `image_grande` (sinon `image`), logo ou nom de
   la chaîne, `titre`, `episode`, « `heure_texte` – `fin_texte` · `duree_texte` » (« En cours » si `en_cours`),
   « `genre_texte` · `annee` », « IMDb `note_texte` » et le nombre de votes (« 420 000 votes »), « Dans tes envies » si
   `envie`, `resume` en entier. Boutons : **« Regarder »** (sélectionné d'office au Hub TV : OK puis OK met la chaîne),
   qui met la TV sur la chaîne `oqee_id` (Hub TV : même ouverture qu'« En direct » ; Hub iPad : la télécommande de la TV,
   comme la carte « À la TV »), et **« Fermer »** (Retour au Hub TV).

## Mise en œuvre : app AppDaemon `hub_ce_soir`

Code : `homeassistant/appdaemon/apps/hub_ce_soir.py` (fonctions pures, puis la classe `HubCeSoir`), tests :
`homeassistant/appdaemon/tests/test_hub_ce_soir.py`. Déploiement : copier le module dans
`/Volumes/addon_configs/a0d7b954_appdaemon/apps/` et le bloc `hub_ce_soir` dans `apps.yaml`.

- **Guide** relu à 6 h, 17 h et 20 h 15 (réglage `relectures`), et au premier calcul de la journée : un seul appel
  à OQEE, l'heure ronde de 21 h (elle contient ce qui passe à 21 h et ce qui commence avant 22 h). Si OQEE ne répond
  pas ou ne donne rien : guide de la Freebox (`/api/v8/tv/epg/by_time/<21 h>`).
- **Capteur** recalculé toutes les 15 min (`en_cours`, programmes finis, envies), publié par l'API REST de HA (comme
  `hub_meteo`).
- **Chaînes** : table `CHAINES` (numéro Free, nom, identifiant OQEE, uuid Freebox), **liste fixe** des chaînes
  d'Alexandre (42, validée par lui le 28/10/2026 ; info, sport, musique et jeunesse laissées de côté ; **Gulli (12) ajoutée le 01/11/2026** à sa demande, 43 chaînes : *Beetlejuice* y passait le 31/10 et manquait). Pas de filtre
  par la Freebox (retiré le 28/10 au soir) : son `has_abo` veut dire « chaîne payante », pas « dans l'abonnement »
  (CANAL+ Cinéma(s) 47 et CANAL+ Docs 48 marquées oui alors qu'Alexandre ne les a pas, CANAL+ Box Office 45 marquée
  non alors qu'il l'a). Changement d'abonnement : modifier la table à la main. **Revue le 08/11/2026** avec la page
  « abonnements télévision » de Free (packs Universal+ et TV by Canal) : rien à changer. RTL9, AB1, TLC, National
  Geographic et Comedy Central, absents de ces packs, sont bien reçus (confirmé par Alexandre) ; CANAL+ 40, 45, 46 hors
  de cette page (abonnement CANAL+) ; Love Nature, dans le pack, pas voulue.
- **Relier une nouvelle chaîne** : télécharger quelques heures des deux guides (OQEE `epg/all/<heure>` et Freebox
  `tv/epg/by_time/<heure>`), et pour l'uuid Freebox de la chaîne, compter les identifiants OQEE qui ont le même titre
  à 15 min près : le plus fréquent est le bon (méthode du 28/10/2026 ; France 2 et France 3 ont des doublons
  régionaux ou UHD, prendre ceux de `Applis.CHAINES`).
