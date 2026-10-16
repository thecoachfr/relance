# Liens sur la TV (Freebox Player Pop)

*Plan P9-B5. Quelle forme de lien ouvre quoi sur le Player (Android TV), envoyée par `remote.turn_on` avec `activity`
(script `script.aiguillage_sur_tv`). Rempli pendant des essais réels, avec Alexandre devant la TV. Aucune donnée
personnelle.*

Documentation de l'intégration Android TV Remote de Home Assistant (lue le 16/10/2026) : `activity` accepte un
identifiant d'app, une URL ou un schéma ; YouTube (`https://www.youtube.com`), Netflix (un titre précis seulement si le
lien finit par `?source=30`), Prime Video, Disney+ (ouverture de l'app). Apple TV, myCANAL et Spotify n'y figurent pas.

Résultat : **titre** (la page du titre s'ouvre), **app** (l'app s'ouvre, sans le titre), **rien**.

| Plateforme | Forme du lien | Résultat | Date |
|---|---|---|---|
| Netflix | `https://www.netflix.com/title/<id>?source=30` | **titre**, après l'écran de choix du profil (imposé par Netflix) | 16/10 |
| Disney+ | lien partagé `https://disneyplus.com/fr-FR/browse/entity-<uuid>?sharesource=iOS` | **rien** : « Aucune application ne peut effectuer cette action » | 16/10 |
| Disney+ | `https://www.disneyplus.com/fr-fr/browse/entity-<uuid>` | **titre** (2e envoi, Player déjà allumé ; au 1er il sortait de veille, résultat non relevé) | 16/10 |
| Canal+ | lien partagé `https://mycan.al/series/<titre>/h/<id>` | **titre** | 16/10 |
| YouTube | `https://www.youtube.com/watch?v=<id>` | **titre** (la vidéo s'ouvre) | 16/10 |
| Spotify | `https://open.spotify.com/track/<id>` | **titre affiché, pas lu** (comme l'annonce la documentation Android de Spotify) | 16/10 |

Spotify : pour **lire** sur la TV, il faudra passer par Spotify Connect (API Web, compte Premium, droit
`user-modify-playback-state`), comme le prévoit le plan B5 ; à faire avec le jeton de l'app Spotify de D4.

Ce que fait le script : Player injoignable → arrêt « TV injoignable » ; éteint → allumage, attente (15 s au plus) puis
2 s ; ensuite `remote.turn_on` avec `activity: <lien>`. L'app transforme le lien selon ce tableau (`TVRemote.link`).
