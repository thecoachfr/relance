# Contrat du capteur `sensor.hub_ce_soir` (28/10/2026) — « Ce soir » à la TV, pour le Hub TV et le Hub iPad

Cadrage : `hub-tv/docs/CE-SOIR.md` (H46). Calculé par l'app AppDaemon `hub_ce_soir` (dépôt Rappels, à côté de la
vigie). Les vues ne font QUE l'afficher : aucun filtre ni tri dans les vues. Le Nest Hub n'a pas de Vidéo.

Ce que c'est : les films, séries, documentaires et reportages qui **commencent entre 20 h 40 et 21 h 20** sur les
chaînes d'Alexandre (abonnement Free : TNT, chaînes `has_abo` de la Freebox, plus CANAL+ Box Office). Direct
seulement. Programmes de moins de 20 min, interdits aux moins de 18 ans et déjà finis écartés ; d'une série dont
plusieurs épisodes se suivent sur la même chaîne, seul le premier est gardé.

État : nombre de programmes (entier, 0 s'il n'y en a pas, par exemple après 23 h quand tout est fini).

Attributs (exemple : `HUB-CE-SOIR-exemple.json`) :
- `maj` : ISO 8601, heure du calcul.
- `soiree` : `AAAA-MM-JJ`.
- `source` : `oqee` (guide d'OQEE) ou `freebox` (repli, sans sous-genre ni année ; `genre_texte` = « Film »…).
- `programmes` : au plus 12, dans l'ordre d'affichage : [{
  `titre` (sans « - S03E06 »), `episode` (« S3 · É6 » ou null), `genre` (`film`, `documentaire`, `reportage`,
  `serie`, `telefilm`), `genre_texte` (sous-genre d'OQEE, « Thriller », « Série policière »…), `annee` (ou null),
  `chaine` (nom affiché), `numero` (numéro Free), `oqee_id` (identifiant de chaîne qu'ouvre le Hub TV, comme
  `Applis.CHAINES`), `logo` (logo d'OQEE pour fond sombre, ou null : afficher alors le nom), `debut` et `fin`
  (ISO 8601 à la minute), `heure_texte` (« 21 h 10 »), `en_cours` (booléen, au moment du calcul), `image` (image
  paysage d'OQEE en 480 px de haut, ou null ; en repli Freebox, adresse locale `mafreebox.freebox.fr`), `resume`
  (220 caractères au plus, ou null), `envie` (vrai si le titre est une envie « À regarder » d'Aiguillage pas encore
  vue) }].

Ordre : d'abord les envies ; puis par genre (films, documentaires et reportages, séries, téléfilms) ; à genre égal,
ce qui commence à partir de 20 h 50 avant l'avant-soirée, puis les grandes chaînes (TF1, France 2, France 3,
France 5, M6, Arte) et CANAL+, puis le plus récent (année), puis l'heure. Places par genre : 6 films, 3 documentaires
ou reportages, 3 séries, 2 téléfilms (une envie passe toujours). Les notes de TMDB viendront affiner (pas encore).

## Règles d'affichage communes

1. **Rangée « Ce soir »** dans Vidéo, après « À regarder ». Rien du tout si `programmes` est vide ou le capteur absent.
2. Tuile : `image` (sinon fond ardoise), `logo` de la chaîne (sinon `chaine`), `titre`, puis
   « `heure_texte` · `genre_texte` · `annee` » ; `episode` après le titre s'il y en a un ; pastille « En cours » si
   `en_cours` ; marque d'envie (même signe que « À regarder ») si `envie`.
3. **Action** : mettre la TV sur la chaîne `oqee_id` (Hub TV : même ouverture qu'« En direct » ; Hub iPad : la
   télécommande de la TV, comme la carte « À la TV »).

## Mise en œuvre : app AppDaemon `hub_ce_soir`

Code : `homeassistant/appdaemon/apps/hub_ce_soir.py` (fonctions pures, puis la classe `HubCeSoir`), tests :
`homeassistant/appdaemon/tests/test_hub_ce_soir.py`. Déploiement : copier le module dans
`/Volumes/addon_configs/a0d7b954_appdaemon/apps/` et le bloc `hub_ce_soir` dans `apps.yaml`.

- **Guide** relu à 6 h, 17 h et 20 h 15 (réglage `relectures`), et au premier calcul de la journée : un seul appel
  à OQEE, l'heure ronde de 21 h (elle contient ce qui passe à 21 h et ce qui commence avant 22 h). Si OQEE ne répond
  pas ou ne donne rien : guide de la Freebox (`/api/v8/tv/epg/by_time/<21 h>`).
- **Capteur** recalculé toutes les 15 min (`en_cours`, programmes finis, envies), publié par l'API REST de HA (comme
  `hub_meteo`).
- **Chaînes** : table `CHAINES` (numéro Free, nom, identifiant OQEE, uuid Freebox), filtrée par
  `http://mafreebox.freebox.fr/api/v8/tv/channels` (sans jeton). Freebox muette : toute la table. Les chaînes de
  l'abonnement absentes de la table sont écrites dans le journal (« hors table ») ; info, sport, musique et jeunesse
  y sont volontairement.
- **Relier une nouvelle chaîne** : télécharger quelques heures des deux guides (OQEE `epg/all/<heure>` et Freebox
  `tv/epg/by_time/<heure>`), et pour l'uuid Freebox de la chaîne, compter les identifiants OQEE qui ont le même titre
  à 15 min près : le plus fréquent est le bon (méthode du 28/10/2026 ; France 2 et France 3 ont des doublons
  régionaux ou UHD, prendre ceux de `Applis.CHAINES`).
