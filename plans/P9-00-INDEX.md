# P9 — Aiguillage : lieux, « À regarder », app Android TV, actions, listes de courses

*Rédigé le 16/10/2026 dans le chat Claude, à partir de l'étude P9 du document « Idées à traiter — études et plans » et d'une lecture du code de `relance` le même jour. À donner à Claude Code avec le plan du chantier en cours. Ce fichier est commun à tous les plans P9 : il fixe l'ordre, le modèle de données partagé et les règles.*

## 1. Les plans

| Plan | Fichier | Dépôt | Temps estimé |
|---|---|---|---|
| A — Lieux sur la carte (restos, magasins, spots photo ; entrées par lien, photo, GPS ; proximité par distance) | `P9-A-lieux.md` | relance | 3–4 soirées |
| B — Envies « À regarder » (plateforme, identifiant, TMDB) et « Sur la TV » par Home Assistant | `P9-B-a-regarder-tv.md` | relance + HA | 2–3 soirées |
| C — App Android TV pour le Freebox Player Pop | `P9-C-app-android-tv.md` | nouveau dépôt privé `aiguillage-tv` | 3–5 soirées |
| D — Actions par tâche (socle, playlist Spotify, préparation de la TVA par une routine) | `P9-D-actions.md` | relance + HA + routine | 4–6 soirées |
| E — Audit de la consommation de batterie (mesure de référence, puis après P9) | `P9-E-audit-batterie.md` | relance + HA | 1–2 soirées, plus deux semaines de mesure |
| F — Présence à la maison (Hue MotionAware, puis Bermuda) | `P9-F-presence-maison.md` | HA + relance | 1 soirée (16/10) |
| G — Listes de courses (articles cochables, tout coché → Fait, recette → ingrédients) | `P9-G-listes-courses.md` | relance + routine | G1 2–3 soirées, G2 1, G3 1–2, G4 à la carte |
| H — Durée facultative d'une tâche (agenda) ; rappel près de mes lieux habituels (supermarchés) | `P9-H-duree-et-lieux.md` | relance + routine | H2 (2 soirées) puis H1 (1 soirée) |
| I — Le tri par l'API Messages (crédits API de Max au lieu du quota de messages), la routine restant en secours | `P9-I-tri-par-api.md` | relance + HA | I1 30 min, I2 1–2 soirées, I3 1 soirée + une semaine d'ombre, I4 1 soirée |
| J — Mémoire des échanges Signal avec Yoann (texte cherchable, résumé de chaque nuit, recherche depuis Claude) | `P9-J-memoire-signal.md` | HA (+ relance pour J4) | J1–J3 2–3 soirées ; J4 2 ; J5 une demi-soirée |
| K — Pièces jointes (photo, PDF, scan) rangées dans HA, texte lu sur l'appareil pour le tri, copie Drive | `P9-K-pieces-jointes.md` | relance + ha-donnees-apps + routine | fait le 18/10 (essais à faire) |
| L — Idées du 19/10 : sorties et billets (L1), « Écouté » sur la playlist TV (L2), fiche refaite (L3), rendez-vous lu dans un texte (L4) ; Nest Hub : « En ce moment » (L6), pages sans recharger (L7) ; L5 abandonné | `P9-L-idees-19-10.md` | relance + aiguillage-tv + HA | L1 à L4, L6 et L7 faits le 19/10 |
| M — Historique de mes trajets sans Google (archive des positions de l'app Compagnon, visites iOS, tracé précis en option, écran « Mes trajets », « déjà venu ici ? ») | `P9-M-trajets.md` | relance + HA | étude du 22/10 ; M1 en service le 22/10 (SQLite sur le NUC), tracés Santé importés, M2 et M3 faits, M3 validé le 23/10 |
| N — Courrier : jours de bureau / télétravail tirés de l'agenda pro (priorité), tri des mails façon Dove, agent sur Signal et dans Aiguillage, tâches 📧, résumé du matin ; boîte pro si Barrière l'autorise | `P9-N-courrier.md` | relance + HA | plan du 24/10 ; N0 fait (cas C) ; N1 et N2 faits le 24/10 ; N3 codé le 24/10 (ombre, à déployer après l'autorisation Google) ; N1 1 soirée, N2 1–2, N3 2–3, N4 2–3, N5 2, N6 1 |
| P — Rappels « pour info » (femme de ménage, poubelles) : sans relance ni « Fait », annoncés dans le résumé du matin, affichés partout le jour même | `P9-P-pour-info.md` | relance + HA + hub-tv + hub-ipad | plan du 26/10 ; P1 et P2 faits le 26/10 ; P3 (Hub) codé le 26/10, à déployer |
| O — Copropriété : mémoire du groupe WhatsApp (réception seule), ordres du jour d'AG, PV et appels de charges en brouillons de mails validés | `P9-O-copropriete-whatsapp.md` | HA + relance | plan du 24/10, pas commencé ; O1 1 soirée, O2 une demi-soirée, O3 1, O4 1, O5 1–2 |

**Ordre** : lot 0 ci-dessous (avec E1, la mesure de référence), puis A, B, C, D, et E2 après A4 et D3. C dépend de B (liens testés sur le Player, champs `envie`). D réutilise « Sur la TV » (B) comme une action. F, d'abord une piste, a été fait après D. G (ajouté le 16/10, déposé le 16/10 à 22 h) vient ensuite, indépendant des autres plans.

**État au 16/10 au soir** : lot 0 fait sauf P2 (reporté) ; A, B, C, D et F faits, avec des essais réels restants ; E1 en mesure (relevé vers le 23/10), E2 à suivre. G pas commencé. Détail de ce qui reste : SUIVI.md, section 2, « P9 : ce qui reste ».

## 2. Lot 0 — préalables (avant A)

1. **Finir P2** : les deux essais restants de la migration vers HA, notés dans SUIVI : écriture hors ligne (repli iCloud réellement déclenché sur un appareil, puis retour de HA sans doublon) et vrai conflit entre deux appareils (la modification la plus récente gagne, conflit journalisé). P9 ajoute des champs aux tâches : il faut une synchro éprouvée avant.
2. **Rendre le Freebox Player Pop joignable dans HA** : `remote.freebox_player_pop` et `media_player.freebox_player_pop_2` (intégration Android TV Remote) étaient `unavailable` le 16/10 au matin. Vérifier si le Player est en veille profonde (réglage de veille du Player) ou si l'intégration doit être réappairée. Nécessaire pour B et pour installer l'app C.
3. **Mesure de référence de la batterie** (plan E, lot E1) : à lancer avant A pour une semaine d'usage normal.
4. Noter l'état dans SUIVI.

*État au 16/10 : (1) reporté par Alexandre ; (2) fait, le Player est joignable le jour et éteint la nuit (normal) ; (3) outils en place, semaine de mesure en cours ; (4) fait.*

## 3. Modèle de données commun (TacheHA, `v: 2`)

Les tâches sont dans l'espace `aiguillage` de `donnees_apps` (`Shared/HA/TacheHA.swift`). P9 ajoute **des champs facultatifs** (`lieu`, `envie`, `actions`, `liste` pour le plan G, puis `pieces`, `duree` et `contexte`, détaillés ci-dessous). Les plans A, B, C et D utilisent les trois premiers : ne pas en créer d'autres sans mettre ce fichier à jour.

```json
{
  "v": 2,
  "titre": "Spot du pont de Charenton au couchant",
  "lieu": {
    "nom": "Pont de Charenton",
    "adresse": "Quai…, 94220 Charenton-le-Pont",
    "telephone": null,
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

- `lieu.telephone` : ajouté en A1 (16/10), le téléphone de la ligne `📍`, pour ne pas le perdre quand le champ fait foi.
- `lieu.source` : `plans`, `google`, `photo`, `gps`, `memo` (ajouté par la routine) ou `saisie`. `adresse` devient facultative : une photo ou un point GPS n'en a pas forcément.
- `envie.type` : `voir`, `lire`, `ecouter`, `regarder` (existants) et `resto`, `magasin`, `spot_photo` (nouveaux, plan A), `sortie` (plan L1, 19/10 : sortie réservée, datée par `jour` et `heure` de la tâche, ligne `🎟 Sortie`). Champs `plateforme`, `id_titre`, `tmdb`, `dispo_fr`, `dispo_maj` : plan B.
- `envie` (B1, 16/10) : l'app garde tels quels les champs qu'elle ne connaît pas (`tmdb`, `dispo_fr`, `dispo_maj`…), pour que la vigie puisse les écrire sans qu'une réécriture de l'app les efface.
- `actions` : plan D (B ajoute seulement l'action `sur_tv` déclenchée au toucher).
- `pieces` : plan K (18/10), facultatif : `[{id (SHA-256 du fichier rangé dans HA), nom, type, taille, ajoute_le, source, texte (1 500 caractères lus sur l'appareil), drive?}]` ; copie `📎 N pièces jointes` dans les notes.
- `contexte` : plan N2 (24/10), facultatif : `bureau` | `maison` (tâche à faire au bureau, ou à la maison) ; copie
  `🏢 Au bureau` / `🏠 À la maison` dans les notes (ligne cachée du champ Notes, réglée par « Où la faire » dans la
  fiche, mode HA seulement). Une tâche sans date à qui l'on donne un contexte prend la date du prochain jour qui
  correspond d'après `sensor.aiguillage_lieu_travail` (`jours` : bureau → `bureau` ; maison → `teletravail`, `off` ou
  `ferie`, aujourd'hui compris), sinon reste sans date. Connu du tri avant sa mise en service (24/10) : règle U de la
  consigne, champ recopié, déduit d'une phrase (« au bureau », « à la maison ») et daté par la vigie.
- `duree` : plan H1 (17/10), facultatif : durée en minutes (entier), seulement avec `heure` ; l'événement d'agenda dure autant.
- `liste` : plan G (16/10), facultatif : `{"articles": [{"id", "texte", "quantite", "rayon", "coche", "maj", "source"}], "parts", "recettes": [{"titre", "lien"}]}` ; quantités indicatives en texte libre ; copie lisible `🛒 Liste : 3/12 cochés` dans les notes ; fusion des coches article par article (détail et tests dans `P9-G-listes-courses.md`). La routine de tri doit connaître ce champ avant sa mise en service (section 4).
- **Compatibilité, obligatoire pendant la transition** : continuer d'écrire les lignes techniques des notes (`📍 …`, `👀 À voir`, `🎬 À regarder`… et les nouvelles `🍽 À tester`, `🛍 Magasin`, `📷 Spot photo`), car la vigie, la routine de tri, la carte du Nest Hub (`nest-hub-entree-card`) et le mode Google Tasks les lisent. Le champ structuré fait foi ; la ligne en est une copie. Lecture : si le champ manque, le déduire de la ligne (anciennes tâches), sans réécrire toutes les tâches d'un coup.
- **Mode Google Tasks** (« Revenir à Google Tasks ») : les nouveaux champs n'y existent pas. Les fonctions P9 ne sont proposées qu'en mode HA ; en mode Google, seules les lignes des notes sont gardées.
- **Taille** : 64 Ko maximum par enregistrement (limite de `donnees_apps`) ; garder `resultat` des actions court (voir D).

## 4. La routine de tri « Relance · tri »

- C'est une tâche planifiée du compte claude.ai d'Alexandre (lancée chaque matin et par la vigie à chaque nouvelle tâche). Sa consigne impose aujourd'hui : « renvoie dans valeur l'objet COMPLET lu… n'ajoute aucun autre champ ». **Avant de mettre en service un nouveau champ**, sa consigne doit le connaître, sinon elle risque de le perdre en réécrivant une tâche.
- **Plan I (17/10)** : le tri passe par l'API Messages (`tri_mode` dans `apps.yaml`). **En mode `api` depuis le 22/10/2026 à 22 h 37** (choix d'Alexandre), horaire de la routine retiré (elle reste en secours, sans horaire). Une fois en mode `api`, la consigne qui fait foi est `/config/aiguillage_tri_consigne.md` dans HA (modèle `docs/TRI-CONSIGNE.md`) ; la routine ne sert plus qu'en secours, et une nouvelle règle se met dans les deux consignes tant qu'elle existe.
- **La consigne complète n'est pas versionnée** : elle contient une copie du mémo avec des données personnelles, et `relance` est public. Claude Code rédige seulement les **paragraphes à ajouter ou à modifier** (dans le plan concerné ou dans SUIVI, sans donnée personnelle) ; Alexandre les fait appliquer à la tâche planifiée depuis le chat Claude, puis on vérifie un passage de la routine sur une tâche d'essai.

## 5. Règles de travail (toutes les sessions P9)

- Après **chaque commit** : mettre à jour la documentation (README, SUIVI, plan concerné) **et vérifier la cohérence** entre les documents. Obligatoire.
- **Pousser** chaque commit. Les commits de documentation seule portent `[ci skip]` (chaque push sur `main` lance Xcode Cloud et TestFlight).
- **Dépôt public** : aucun secret ni donnée personnelle dans `relance` (jetons, clés API TMDB ou Spotify, adresse IP locale, identifiant de la feuille Google, consigne de la routine). Ils vont dans le trousseau, l'App Group, `/config/…` sur HA ou des fichiers non versionnés.
- Toute limite découverte (format d'un lien, comportement du Player, quota d'API) est notée dans SUIVI le jour même, avec la date.
- Ne pas affirmer qu'un format ou une API se comporte d'une façon sans l'avoir vérifié (essai réel ou documentation officielle) ; sinon, écrire « à vérifier ».
