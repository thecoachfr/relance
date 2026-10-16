# P9-D — Actions par tâche

*Plan du 16/10/2026. Lire d'abord `P9-00-INDEX.md`. Dépôts : `relance` (app, vigie AppDaemon) ; une nouvelle tâche planifiée claude.ai pour les actions « préparer ». Prérequis : A et B en service.*

## 1. But

Chaque tâche porte une ou plusieurs **actions** personnalisables. Aujourd'hui il en existe deux, codées en dur : le **rappel** (échéance et relances) et l'**alerte de proximité**. La catégorisation par la routine est déjà une sorte d'action. On veut des actions qui **font** quelque chose :

- « À écouter » avec un lien Spotify → **ajouter à la playlist « À écouter »** ;
- « Payer TVA » → quelques jours avant l'échéance, **préparer la déclaration** (les cases à remplir et les montants) à partir de la comptabilité ;
- « À regarder » → **Sur la TV** (plan B) ;
- et d'autres plus tard (ouvrir un lien, appeler, notifier le Nest Hub).

## 2. Modèle

Champ `actions` de `TacheHA` v2 (voir l'index). Chaque action :

| Champ | Valeurs |
|---|---|
| `id` | UUID, stable (sert d'identifiant d'idempotence) |
| `type` | `ouvrir_lien`, `sur_tv`, `playlist_spotify`, `preparer`, puis d'autres |
| `executant` | `appareil`, `ha` (vigie) ou `routine` |
| `declencheur` | `{quand: "creation"}`, `{quand: "toucher"}`, `{quand: "avant_echeance", jours: 5}`, `{quand: "arrivee_lieu"}` |
| `params` | propres au type (ex. `{playlist: "a_ecouter"}`, `{modele: "tva_micro"}`) |
| `etat` | `a_faire`, `en_cours`, `faite`, `echec` |
| `resultat` | texte court (≤ 4 Ko) : ce qui a été fait, ou l'erreur |
| `maj` | horodatage ISO 8601 |

- Le **rappel** et l'**alerte de proximité** gardent leur stockage actuel (`relances`, lignes `🔔` / interrupteur de proximité) : la fiche les **affiche** dans la même section « Actions », sans migration. On pourra les déplacer dans `actions` plus tard.
- **Idempotence** : un exécutant ne relance jamais une action `faite` ; ses écritures portent `op_id` = UUID neuf et `version_attendue` ; en cas de conflit, relire, vérifier que l'action n'a pas déjà été faite, réessayer une fois.

## 3. Lots

### D1 — Socle dans l'app
- Section « Actions » de la fiche : liste, ajout, suppression, état et résultat ; actions `ouvrir_lien` et `sur_tv` (B4) exécutées sur l'appareil au toucher.
- **Accepté quand** : ajout et retrait d'actions synchronisés entre iPhone, iPad et Mac ; tests du modèle (encodage, champs inconnus conservés).

### D2 — Recettes
- Règles « si… alors ajouter l'action… », réglables dans l'app (Réglages › Actions), rangées dans l'espace `aiguillage` sous la clé non-UUID `config:recettes` (la routine de tri ignore les clés non-UUID).
- Conditions v1 : type d'envie, hôte du lien, catégorie, tag, mot du titre. Exemples livrés désactivés : « envie À écouter + lien Spotify → playlist_spotify » ; « titre contient TVA + tag Micro → preparer (modèle tva_micro), 5 jours avant l'échéance ».
- Appliquées **par la vigie** à la création ou à la modification d'une tâche (déterministe, une seule fois par recette et par tâche : garder l'identifiant de la recette dans `params`).
- **Accepté quand** : une tâche qui remplit une condition reçoit l'action une seule fois, même après plusieurs modifications.

### D3 — Exécutant HA (vigie)
- Sur `donnees_apps_modifie` et toutes les heures (déclencheurs `avant_echeance`) : exécuter les actions `executant: "ha"` dues, écrire `etat`, `resultat`, `maj`.
- Notification push (APNs, déjà en place) quand une action échoue ou qu'une préparation est prête.
- **Accepté quand** : test de bout en bout sur une tâche d'essai ; aucune exécution en double après un redémarrage d'AppDaemon.

### D4 — Playlist Spotify
- Réutiliser l'app Spotify de `spotify-library-tool` (qui a accès à l'API Web, confirmé par Alexandre) : identifiant et secret client, plus un jeton de rafraîchissement obtenu une fois sur le Mac avec les droits `playlist-modify-private` et `playlist-modify-public`, plus `user-read-playback-state` et `user-modify-playback-state` pour la lecture sur la TV (plan B). Le tout dans `/config/spotify_aiguillage.json` sur HA, jamais dans un dépôt.
- API de février 2026 : ajout par `POST /playlists/{id}/items` ; les requêtes groupées `GET /tracks`, `/albums`… ont disparu (appels individuels) ; le contenu d'une playlist n'est lisible que si on en est propriétaire ou collaborateur (c'est le cas de « À écouter »). L'app Spotify en mode développement exige un compte Premium chez son propriétaire.
- Lien `open.spotify.com/track|album|episode/…` → URI ; un album ajoute ses titres (`GET /albums/{id}/tracks`). Vérifier d'abord que les titres ne sont pas déjà dans la playlist.
- Playlist cible : réglage (identifiant) dans `config:recettes` ou un réglage de l'app ; la créer si absente (`POST /me/playlists`, privée).
- **Accepté quand** : un morceau, un album et un épisode partagés depuis Spotify arrivent dans la playlist, sans doublon si on recommence.

### D5 — Actions « préparer » par une routine Claude
- **Nouvelle tâche planifiée** « Aiguillage · actions », distincte de « Relance · tri » (moindre privilège) : connecteur Home Assistant limité à `donnees_apps.lire` / `ecrire` sur l'espace `aiguillage`, et **Google Drive en lecture**. Lancée par la vigie (comme le tri, par l'API de déclenchement) quand une action `preparer` est due. Créée et réglée depuis le chat Claude, pas par Claude Code ; sa consigne n'est pas versionnée (identifiants de fichiers, données personnelles).
- La routine **prépare seulement** : elle ne déclare rien, ne paie rien, n'envoie rien. Elle écrit le résultat dans `resultat` (cases et montants, cellules sources, points à vérifier) et ajoute à la tâche la ligne `📝 Préparé le JJ/MM : voir les actions`.
- **Premier modèle `tva_micro`** : TVA de la micro-entreprise d'Alexandre ; les chiffres sont dans sa feuille Google de comptabilité (onglets mensuels avec TVA collectée et déductible), celle qui a servi à la déclaration du 15/10/2026 ; son emplacement est donné à la routine dans sa consigne, pas ici. Le connecteur Google Drive la lit sans pouvoir y écrire, ce qui suffit. **Avant d'écrire la consigne** : établir avec Alexandre le régime et le formulaire (périodicité, cases remplies le 15/10), à partir de sa dernière déclaration.
- Côté Claude Code : seulement l'exécutant (déclenchement par la vigie, écriture du résultat, affichage dans la fiche, notification) et un modèle de consigne générique sans donnée personnelle.
- **Accepté quand** : sur une tâche d'essai « Payer TVA » datée à J+5, la routine se lance, écrit un résultat lisible dans la fiche, et rien d'autre n'est modifié.

## 4. Hors périmètre

Actions qui envoient un message, paient ou déclarent ; actions sur la montre ; éditeur de recettes avancé (conditions combinées, OU logique).

## 5. Documentation à tenir

README (actions, recettes, Spotify, routine « actions »), SUIVI, ce plan ; la liste des types d'actions et de leurs paramètres tenue à jour dans ce fichier.
