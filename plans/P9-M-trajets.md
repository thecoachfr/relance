# P9-M — Historique de mes trajets (remplacer la Chronologie Google)

*Étude du 22/10/2026, demandée par Alexandre : retrouver ses déplacements sans Google (Chronologie impossible à
réactiver, et il ne veut plus passer par eux), sans pomper la batterie. Lire d'abord `P9-00-INDEX.md`.
Dépôts : `relance` + HA. Stockage et agrégation : à trancher avec Alexandre (section 5), le reste en dépend peu.*

## 1. Le besoin

- Voir sur une carte le trajet d'une journée, avec les arrêts (où, de quelle heure à quelle heure).
- Répondre vite à « est-ce que je suis déjà venu ici ? » (et quand).
- Tout garder chez soi (HA sur le NUC), sans durée limite.
- Coût en batterie quasi nul par défaut.

## 2. Ce qui existe déjà (constat du 22/10)

- **Aiguillage n'enregistre aucune position.** `ProximityReminders` surveille au plus 20 zones (200 m, 150 m pour
  Mes lieux) et suit les changements de position significatifs seulement quand il y a plus de 20 lieux. Rien n'est gardé.
- **L'app Compagnon de HA envoie la position GPS** : `device_tracker.iphone_17_lex` (latitude, longitude, précision,
  vitesse, cap, altitude). Sur les 24 h du 21/10 16 h au 22/10 16 h : une cinquantaine de points, groupés aux
  entrées et sorties de zones et aux changements significatifs ; de **grands trous en mouvement** (aucun point entre
  5 h 40 et 6 h 55 le 22/10, ni entre 17 h 34 et 19 h 09 le 21/10). Assez pour savoir où il était, pas pour tracer un trajet.
- **Ces points sont effacés au bout de 10 jours** : pas de bloc `recorder` dans `configuration.yaml`, donc la
  conservation par défaut de HA.
- Outils à réutiliser : `EnergyMetrics` (MetricKit, plan E) pour mesurer le coût ; `donnees_apps` (64 Ko par
  enregistrement, fichiers jusqu'à 10 Mo, 1 Go par espace) ; AppDaemon sur le NUC (comme la mémoire Signal, P9-J, en SQLite).

## 3. Les trois sources possibles

| Source | Ce qu'elle donne | Batterie | Où |
|---|---|---|---|
| **S1 — Archiver l'app Compagnon** | Les points déjà reçus par HA, gardés au-delà de 10 jours | Rien en plus | HA (AppDaemon) |
| **S2 — Visites iOS** (`CLVisit` / `startMonitoringVisits`) + changements significatifs | Arrivée, départ et point de chaque arrêt ; un point tous les ~500 m en déplacement | Quasi nul (iOS les calcule de toute façon) | Aiguillage |
| **S3 — Tracé précis en mouvement** | Un point tous les 50 à 100 m, seulement en marche, vélo ou voiture (`CMMotionActivity`), coupé à l'arrêt | Quelques % par jour selon les déplacements (à mesurer) | Aiguillage |

Recommandation : **S1 et S2 d'abord** (lot M1, M2), **S3 en option** coupée par défaut, à activer par exemple en
voyage ou en balade photo (lot M4), puis mesurée avec le protocole du plan E.

## 4. Lots

### M0 — Récupérer l'ancien historique (si possible)
- Vérifier avec Alexandre si la Chronologie a été active sur un de ses téléphones : Google Maps permet alors
  d'exporter un fichier depuis l'appareil (réglages de localisation › Chronologie › Exporter). Les anciennes archives
  Takeout (« Historique des positions ») sont une autre piste, à chercher dans Drive.
- **Pacer** (22/10, piste d'Alexandre) : Pacer ne garde un tracé GPS que pour les activités lancées avec son GPS ; le
  reste n'est que des pas, sans position. Export d'après son aide : Profil › Réglages › Data Export, un zip de CSV
  envoyé par e-mail (pas, poids, sessions GPS) ; GPX annoncé pour les activités GPS. **Export reçu le 22/10** :
  quatre CSV, **aucune coordonnée**. `ActivitySessions` : 5 224 sessions du 08/10/2021 au 22/10/2026, dont
  3 003 « GPS Walk » (début, fin, pas, distance, durée) et 2 221 venues de Santé ; `DetailedSteps` : pas par quart
  d'heure depuis le 08/09/2022 ; `DailySteps` : pas par jour. Les tracés restent dans le compte Pacer : à voir si
  l'app exporte un GPX par activité (une à une, donc peu pratique pour 3 000) ou si elle les écrit dans Santé.
  Utile quand même : heures et distances des marches, à montrer dans la journée sans carte. Source `pacer`.
- **Santé d'Apple** : l'export de Santé (`export.zip`) contient un fichier GPX par entraînement avec tracé
  (`workout-routes/`), par exemple les marches et sorties enregistrées par la montre. Source `sante`.
- Si un fichier existe : un script d'import qui le ramène au format de la section 5 (visites et points), avec sa source.
- Limite commune : ces historiques ne couvrent que les sorties enregistrées volontairement, pas les déplacements de tous les jours.

### M1 — Archiver ce que HA reçoit déjà (S1)
- App AppDaemon `aiguillage_trajets` : à chaque changement de `device_tracker.iphone_17_lex` (attributs compris),
  écrire le point (heure, lat, lon, précision, vitesse, source `compagnon`). Ignorer les doublons (même point à la
  seconde près, comme les rafales du 21/10 à 23 h 33) et les précisions au-delà de 100 m.
- Rattrapage de l'historique encore présent (les 10 derniers jours) au premier lancement.
- **Accepté quand** : les points d'une journée sont dans le stockage, sans doublon, et y restent après 10 jours.

### M2 — Visites et changements significatifs dans Aiguillage (S2)
- Nouveau `TrajetsRecorder` (séparé de `ProximityReminders`, même `CLLocationManager` partagé ou un second) :
  `startMonitoringVisits()` et `startMonitoringSignificantLocationChanges()`, seulement si l'interrupteur
  **Réglages › Mes trajets** est activé et la localisation à « Toujours ».
- Points et visites mis en file sur l'appareil (App Group), envoyés **par lots** : au passage au premier plan, et au
  plus une fois par jour en arrière-plan (`BGProcessingTask`, de préférence en charge et en Wi-Fi). Pas d'appel réseau
  à chaque point.
- Visite = `{arrivee, depart, lat, lon, precision}` ; nom du lieu proposé par Plans à l'affichage, pas à l'enregistrement.
- **Accepté quand** : une journée de déplacements donne ses arrêts avec heures d'arrivée et de départ ; la part
  d'Aiguillage dans Réglages › Batterie ne bouge pas de façon visible (comparaison avec E1).

### M3 — Écran « Mes trajets » (iPhone, iPad, Mac)
- **Jour** : carte avec le tracé (points S1 + S2 + S3, triés par heure, lissés), les arrêts en épingles, et la liste
  des arrêts (lieu, de … à …, durée). Jour précédent / suivant, calendrier.
- **« Déjà venu ici ? »** : toucher un point de la carte, une tâche ou un lieu de Mes lieux → les visites dans un rayon
  de 150 m, les plus récentes d'abord. Aussi depuis la fiche d'une tâche avec lieu (« Déjà venu le 12/03 »).
- Lien avec l'existant : les arrêts peuvent servir de source au lieu d'une tâche (« Ma position » à l'heure d'un arrêt).
- Plus tard, au choix : vue sur le Hub (les trois vues : Hub TV, Nest Hub, Hub iPad, voir la règle commune).

### M4 — Tracé précis en mouvement (S3, option)
- Interrupteur **Tracé précis** (coupé par défaut, ou « pendant 24 h ») : `CLLocationUpdate.liveUpdates` (ou
  `CLBackgroundActivitySession`) déclenché quand `CMMotionActivityManager` signale marche, vélo ou voiture ; filtre de
  distance 50 m à pied, 100 m en voiture ; arrêt après 3 min sans mouvement. Indicateur de position bleu visible
  pendant le tracé (exigence d'iOS).
- Mesure avec `EnergyMetrics` (heures de GPS actif) sur une semaine avec et sans ; seuil fixé avec Alexandre.

## 5. Stockage et agrégation (à décider avec Alexandre)

Pistes, sans choix pour l'instant :

- **SQLite sur le NUC** (comme la mémoire Signal) : `points(t, lat, lon, precision, vitesse, source)` et
  `visites(arrivee, depart, lat, lon, source)` ; volume estimé : 50 points par jour avec S1 + S2, quelques milliers
  avec S3 les jours de sortie, soit quelques dizaines de Mo par an. L'app lit par une action HA « jour » et
  « déjà venu », avec réponse. Recherche de proximité simple (boîte lat/lon puis distance).
- **`donnees_apps`, espace `trajets`** : un enregistrement par jour (64 Ko suffisent pour S1 + S2, pas toujours avec
  S3 : compresser ou passer par un fichier). Avantage : synchro et repli iCloud déjà faits ; inconvénient : la
  recherche « déjà venu » doit tout relire.
- Agrégation à prévoir dans les deux cas : fusion des sources par heure, retrait des points aberrants, regroupement
  des arrêts (S1 n'a pas de visites : les déduire des points immobiles plus de 5 min), puis un résumé par jour
  (distance, lieux) qui reste léger même si les points bruts sont un jour élagués.
- Copie de sauvegarde : comprise dans les sauvegardes HA ; à vérifier qu'elles ne grossissent pas trop.

## 6. Vie privée

- Tout reste sur l'iPhone et le NUC ; rien chez un tiers (pas d'API externe, Plans seulement pour nommer un arrêt à l'affichage).
- Interrupteur pour tout couper, et « Effacer une journée » / « Tout effacer » dans l'écran.
- Le dépôt `relance` est public : aucune coordonnée réelle dans les tests ni dans la doc (prendre des points de démo).

## 7. Questions pour Alexandre

1. La Chronologie a-t-elle été active à un moment (M0) ? Faire un export Pacer et un export Santé pour voir ce qu'ils contiennent.
2. Stockage : SQLite sur le NUC ou `donnees_apps` (section 5) ?
3. M4 : utile tout de suite, ou seulement si S1 + S2 ne suffisent pas ?
4. Seulement l'iPhone, ou aussi la montre en sortie sans téléphone ?
