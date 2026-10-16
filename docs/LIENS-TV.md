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
| Netflix | `https://www.netflix.com/title/<id>?source=30` | à essayer | |
| Netflix | lien partagé tel quel | à essayer | |
| Disney+ | lien partagé (`disneyplus.com/fr-FR/browse/entity-<uuid>`) | à essayer | |
| Canal+ | lien partagé (`canalplus.com/series/<titre>/h/<id>`) | à essayer | |
| YouTube | `https://www.youtube.com/watch?v=<id>` | à essayer | |
| Spotify | `https://open.spotify.com/track/<id>` | à essayer | |
| Spotify | `spotify:track:<id>` | à essayer | |

Ce que fait le script : Player injoignable → arrêt « TV injoignable » ; éteint → allumage, attente (15 s au plus) puis
2 s ; ensuite `remote.turn_on` avec `activity: <lien>`. L'app transforme le lien selon ce tableau (`TVRemote.link`).
