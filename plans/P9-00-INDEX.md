# P9 — Aiguillage : lieux, « À regarder », app Android TV, actions

*Rédigé le 16/10/2026 dans le chat Claude, à partir de l'étude P9 du document « Idées à traiter — études et plans » et d'une lecture du code de `relance` le même jour. À donner à Claude Code avec le plan du chantier en cours. Ce fichier est commun à tous les plans P9 : il fixe l'ordre, le modèle de données partagé et les règles.*

## 1. Les plans

| Plan | Fichier | Dépôt | Temps estimé |
|---|---|---|---|
| A — Lieux sur la carte (restos, magasins, spots photo ; entrées par lien, photo, GPS ; proximité par distance) | `P9-A-lieux.md` | relance | 3–4 soirées |
| B — Envies « À regarder » (plateforme, identifiant, TMDB) et « Sur la TV » par Home Assistant | `P9-B-a-regarder-tv.md` | relance + HA | 2–3 soirées |
| C — App Android TV pour le Freebox Player Pop | `P9-C-app-android-tv.md` | nouveau dépôt privé `aiguillage-tv` | 3–5 soirées |
| D — Actions par tâche (socle, playlist Spotify, préparation de la TVA par une routine) | `P9-D-actions.md` | relance + HA + routine | 4–6 soirées |
| E — Audit de la consommation de batterie (mesure de référence, puis après P9) | `P9-E-audit-batterie.md` | relance + HA | 1–2 soirées, plus deux semaines de mesure |
| F — *Piste* : présence à la maison (Hue MotionAware, puis Bermuda) | `P9-F-presence-maison.md` | HA + relance | à chiffrer après D |

**Ordre** : lot 0 ci-dessous (avec E1, la mesure de référence), puis A, B, C, D, et E2 après A4 et D3. C dépend de B (liens testés sur le Player, champs `envie`). D réutilise « Sur la TV » (B) comme une action. F reste une piste, à préciser après D.

## 2. Lot 0 — préalables (avant A)

1. **Finir P2** : les deux essais restants de la migration vers HA, notés dans SUIVI : écriture hors ligne (repli iCloud réellement déclenché sur un appareil, puis retour de HA sans doublon) et vrai conflit entre deux appareils (la modification la plus récente gagne, conflit journalisé). P9 ajoute des champs aux tâches : il faut une synchro éprouvée avant.
2. **Rendre le Freebox Player Pop joignable dans HA** : `remote.freebox_player_pop` et `media_player.freebox_player_pop_2` (intégration Android TV Remote) étaient `unavailable` le 16/10 au matin. Vérifier si le Player est en veille profonde (réglage de veille du Player) ou si l'intégration doit être réappairée. Nécessaire pour B et pour installer l'app C.
3. **Mesure de référence de la batterie** (plan E, lot E1) : à lancer avant A pour une semaine d'usage normal.
4. Noter l'état dans SUIVI.

## 3. Modèle de données commun (TacheHA, `v: 2`)

Les tâches sont dans l'espace `aiguillage` de `donnees_apps` (`Shared/HA/TacheHA.swift`). P9 ajoute **trois champs facultatifs**. Les plans A, B, C et D les utilisent tous : ne pas en créer d'autres sans mettre ce fichier à jour.

```json
{
  "v": 2,
  "titre": "Spot du pont de Charenton au couchant",
  "lieu": {
    "nom": "Pont de Charenton",
    "adresse": "Quai…, 94220 Charenton-le-Pont",
    "lat": 48.8215, "lon": 2.4123,
    "lien": "https://maps.apple.com/?ll=48.8215,2.4123&q=…",
    "source": "photo"
  },
  "envie": {
    "type": "spot_photo",
    "note": "au couchant, en automne",
    "plateforme": null, "id_titre": null, "lien": null,
    "tmdb": null, "dispo_fr": null, "dispo_maj": null
  },
  "actions": [
    { "id": "uuid", "type": "sur_tv", "executant": "ha",
      "declencheur": { "quand": "toucher" },
      "params": {}, "etat": "a_faire", "resultat": null, "maj": "2026-10-16T07:00:00Z" }
  ]
}
```

- `lieu.source` : `plans`, `google`, `photo`, `gps`, `memo` (ajouté par la routine) ou `saisie`. `adresse` devient facultative : une photo ou un point GPS n'en a pas forcément.
- `envie.type` : `voir`, `lire`, `ecouter`, `regarder` (existants) et `resto`, `magasin`, `spot_photo` (nouveaux, plan A). Champs `plateforme`, `id_titre`, `tmdb`, `dispo_fr`, `dispo_maj` : plan B.
- `actions` : plan D (B ajoute seulement l'action `sur_tv` déclenchée au toucher).
- **Compatibilité, obligatoire pendant la transition** : continuer d'écrire les lignes techniques des notes (`📍 …`, `👀 À voir`, `🎬 À regarder`… et les nouvelles `🍽 À tester`, `🛍 Magasin`, `📷 Spot photo`), car la vigie, la routine de tri, la carte du Nest Hub (`nest-hub-entree-card`) et le mode Google Tasks les lisent. Le champ structuré fait foi ; la ligne en est une copie. Lecture : si le champ manque, le déduire de la ligne (anciennes tâches), sans réécrire toutes les tâches d'un coup.
- **Mode Google Tasks** (« Revenir à Google Tasks ») : les nouveaux champs n'y existent pas. Les fonctions P9 ne sont proposées qu'en mode HA ; en mode Google, seules les lignes des notes sont gardées.
- **Taille** : 64 Ko maximum par enregistrement (limite de `donnees_apps`) ; garder `resultat` des actions court (voir D).

## 4. La routine de tri « Relance · tri »

- C'est une tâche planifiée du compte claude.ai d'Alexandre (lancée chaque matin et par la vigie à chaque nouvelle tâche). Sa consigne impose aujourd'hui : « renvoie dans valeur l'objet COMPLET lu… n'ajoute aucun autre champ ». **Avant de mettre en service un nouveau champ**, sa consigne doit le connaître, sinon elle risque de le perdre en réécrivant une tâche.
- **La consigne complète n'est pas versionnée** : elle contient une copie du mémo avec des données personnelles, et `relance` est public. Claude Code rédige seulement les **paragraphes à ajouter ou à modifier** (dans le plan concerné ou dans SUIVI, sans donnée personnelle) ; Alexandre les fait appliquer à la tâche planifiée depuis le chat Claude, puis on vérifie un passage de la routine sur une tâche d'essai.

## 5. Règles de travail (toutes les sessions P9)

- Après **chaque commit** : mettre à jour la documentation (README, SUIVI, plan concerné) **et vérifier la cohérence** entre les documents. Obligatoire.
- **Pousser** chaque commit. Les commits de documentation seule portent `[ci skip]` (chaque push sur `main` lance Xcode Cloud et TestFlight).
- **Dépôt public** : aucun secret ni donnée personnelle dans `relance` (jetons, clés API TMDB ou Spotify, adresse IP locale, identifiant de la feuille Google, consigne de la routine). Ils vont dans le trousseau, l'App Group, `/config/…` sur HA ou des fichiers non versionnés.
- Toute limite découverte (format d'un lien, comportement du Player, quota d'API) est notée dans SUIVI le jour même, avec la date.
- Ne pas affirmer qu'un format ou une API se comporte d'une façon sans l'avoir vérifié (essai réel ou documentation officielle) ; sinon, écrire « à vérifier ».
