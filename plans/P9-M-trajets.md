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
  **Export reçu le 22/10** (121 Mo, iCloud Drive › Téléchargements) : **1 919 tracés GPX, du 08/10/2021 au
  22/10/2026**, tous enregistrés par l'Apple Watch (marches et courses ; les 3 002 marches de Pacer sont dans Santé,
  mais **sans tracé**). 1,44 million de points (un par seconde, avec précision, vitesse et cap), 619 par tracé en
  médiane. **Importé le 22/10 à 23 h 53** : `homeassistant/scripts/trajets_sante.py` (lit les GPX, retire les points
  à plus de 100 m de précision, garde un point tous les 10 m environ et le dernier) → JSONL copié dans
  `/config/trajets_import.jsonl`, puis événement `aiguillage_trajets_importer` {fichier, source: "sante"} (fichier
  hors de `/config` refusé, import rejouable sans doublon), copie retirée ensuite. **159 381 points gardés** (sur
  1 440 643), base à 14 Mo. Les marches Pacer (heures et distances, sans tracé) ne sont pas importées : à voir avec M3.
- Si un fichier existe : un script d'import qui le ramène au format de la section 5 (visites et points), avec sa source.
- Limite commune : ces historiques ne couvrent que les sorties enregistrées volontairement, pas les déplacements de tous les jours.

### M1 — Archiver ce que HA reçoit déjà (S1)
- App AppDaemon `aiguillage_trajets` : à chaque changement de `device_tracker.iphone_17_lex` (attributs compris),
  écrire le point (heure, lat, lon, précision, vitesse, source `compagnon`). Ignorer les doublons (même point à la
  seconde près, comme les rafales du 21/10 à 23 h 33) et les précisions au-delà de 100 m.
- Rattrapage de l'historique encore présent (les 10 derniers jours) au premier lancement.
- **Accepté quand** : les points d'une journée sont dans le stockage, sans doublon, et y restent après 10 jours.

*Fait le 22/10 (stockage choisi par Alexandre : SQLite sur le NUC)* : `homeassistant/appdaemon/apps/aiguillage_trajets.py`
(app `aiguillage_trajets` dans `apps.yaml`, `entite: device_tracker.iphone_17_lex`), base `/config/aiguillage_trajets.sqlite`
(tables `points` et `visites`, clé source + heure), capteur `sensor.aiguillage_trajets` (points, visites, depuis), journal
« Trajets : … ». Point ignoré au-delà de 100 m de précision ou s'il répète le précédent (moins de 1 m). Reprise de
l'historique à chaque démarrage (sans doublon). Déployé le 22/10 à 18 h 46 : **73 points repris, du 12/10 au 22/10**
(presque rien avant le 20/10 : l'app Compagnon renvoyait le même point à la maison). Fonctions `lire_jour` et
`deja_venu` déjà prêtes pour M3. Tests : `tests/test_aiguillage_trajets.py` (6).

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

*Code fait le 22/10, à installer (build) et à essayer sur l'iPhone* : **visites seulement**, pas de changements
significatifs dans Aiguillage (l'app Compagnon les envoie déjà, M1 les garde). `Relance/App/TrajetsRecorder.swift`
(`startMonitoringVisits` si Réglages › Mes trajets › « Relever mes arrêts » et localisation « Toujours » ; lancé au
démarrage dans `AppDelegate`), file des arrêts dans l'App Group (`trajets.file`, 500 au plus ; même arrivée = même
arrêt, le départ connu gardé), envoi au **webhook de l'app** (`action: trajets`, champ `visites` : `{arrivee, depart?,
lat, lon, precision}` en secondes Unix) au plus toutes les 3 h en arrière-plan et à chaque retour au premier plan,
« Envoyer maintenant » dans l'écran. Automatisation « Relance : enregistrer un appareil » : champ `visites` ajouté à
l'événement `relance_register` (22/10) ; la vigie ignore `action: trajets`. Compteur MetricKit « arrêt » dans le
Diagnostic batterie. Tests : `RelanceTests/TrajetsTests.swift` (4). Essai du webhook local le 22/10 à 18 h 50 : arrêt
reçu et rangé (une visite réelle, gardée).

### M3 — Écran « Mes trajets » (iPhone, iPad, Mac)
- **Jour** : carte avec le tracé (points S1 + S2 + S3, triés par heure, lissés), les arrêts en épingles, et la liste
  des arrêts (lieu, de … à …, durée). Jour précédent / suivant, calendrier.
- **« Déjà venu ici ? »** : toucher un point de la carte, une tâche ou un lieu de Mes lieux → les visites dans un rayon
  de 150 m, les plus récentes d'abord. Aussi depuis la fiche d'une tâche avec lieu (« Déjà venu le 12/03 »).
- Lien avec l'existant : les arrêts peuvent servir de source au lieu d'une tâche (« Ma position » à l'heure d'un arrêt).
- Plus tard, au choix : vue sur le Hub (les trois vues : Hub TV, Nest Hub, Hub iPad, voir la règle commune).

*Fait le 22–23/10, validé par Alexandre sur l'iPhone le 23/10* : `Relance/Views/TrajetsCarteView.swift`, ouvert depuis l'onglet Carte (bouton
sous le « + », si Home Assistant est réglé) ou Réglages › Mes trajets › Voir mes trajets (iPhone et iPad ; pas sur Mac).
Tracé bleu coupé aux trous de plus de 10 min ou aux sauts de plus de 2 km, arrêts numérotés et nommés par Plans (10 au
plus), « 17,3 km · 1 arrêt », heures et durée de chaque arrêt ; jour précédent ou suivant **avec des données** (sinon
±1 jour), calendrier, Aujourd'hui. Toucher la carte : « Déjà venu ici ? » (arrêts à moins de 150 m, puis jours où un
point est passé tout près ; toucher une date ouvre ce jour). **Échange avec HA** (`TrajetsService`) : l'app écrit
`demande` `{id, type: "jour", jour}` ou `{id, type: "venu", lat, lon, rayon}` dans l'espace `trajets` de `donnees_apps`
(jeton `apps-perso`) ; `aiguillage_trajets` répond dans `reponse` (même id ; points `[t, lat, lon]` éclaircis pour
tenir dans 64 Ko, distance par source sans double compte, jours voisins) ; l'app relit toutes les 0,5 s, 15 s au plus.
Rien n'est gardé sur l'appareil. Essai réel par l'API le 23/10 vers 0 h : journée du 22/10 → 388 points, 17,3 km,
1 arrêt, jour précédent 21/10. Tests : Python 2 de plus, Swift `TrajetsCarteTests` (3). Pas encore vu à l'écran
(le simulateur n'a pas Home Assistant).

### M4 — Tracé précis en mouvement (S3, option)
- Interrupteur **Tracé précis** (coupé par défaut, ou « pendant 24 h ») : `CLLocationUpdate.liveUpdates` (ou
  `CLBackgroundActivitySession`) déclenché quand `CMMotionActivityManager` signale marche, vélo ou voiture ; filtre de
  distance 50 m à pied, 100 m en voiture ; arrêt après 3 min sans mouvement. Indicateur de position bleu visible
  pendant le tracé (exigence d'iOS).
- Mesure avec `EnergyMetrics` (heures de GPS actif) sur une semaine avec et sans ; seuil fixé avec Alexandre.

*Fait le 29/10 (demande d'Alexandre), côté HA déployé le 29/10 à 10 h 45, à essayer sur l'iPhone* : `Relance/App/TraceRecorder.swift`, Réglages › Mes trajets ›
« Tracé précis » (Coupé / Pendant 24 h / Toujours, coupé par défaut). `CLLocationUpdate.liveUpdates(.fitness)` avec
`CLBackgroundActivitySession` et `CLServiceSession(.always)` (mode d'arrière-plan `location` ajouté) : iOS suspend les
positions à l'arrêt (`stationary`) et relance l'app au départ, plutôt que `CMMotionActivity` prévu au plan. Point gardé
s'il est précis à 50 m près et à 50 m du précédent (100 m au-delà de 30 km/h). File dans l'App Group (20 000 au plus),
envoi par lots de 400 dans l'espace `trajets` de `donnees_apps` (`lot:<id>`, au plus tous les quarts d'heure, et au
retour au premier plan) ; `aiguillage_trajets` les range (source `precis`), supprime le lot, reprend au démarrage ceux
restés là. Sur la carte, là où le tracé précis existe, les points des autres sources sont retirés
(`priorite_au_trace_precis`). Batterie : temps de GPS par MetricKit, compteur « tracé » dans Diagnostic batterie.
Tests : Swift `TraceTests`, Python 2 de plus.
*30/10, remarque d'Alexandre (flèche de localisation affichée en permanence)* : `CLBackgroundActivitySession` garde
l'indicateur tant qu'elle vit, même à l'arrêt. Remplacé par le mécanisme classique : au repos, changements de position
importants seulement (aucun indicateur), qui réveillent l'app au départ, comme le départ d'une visite (`TrajetsRecorder`) ;
GPS `startUpdatingLocation` (`.fitness`, 10 m, filtre 25 m, indicateur visible) jusqu'à la pause automatique d'iOS à
l'arrêt, où l'app l'éteint. Prix : les 300 à 500 premiers mètres d'un trajet ne sont pas tracés finement.
Puis, même jour : `showsBackgroundLocationIndicator = false` (Pacer ne montre pas la flèche bleue : avec « Toujours »,
iOS ne l'affiche que si l'app la demande ; seule reste la petite flèche près de l'heure).
Alexandre voit pourtant encore la flèche bleue app en arrière-plan (« Toujours » confirmé, c'est bien Aiguillage) : cause
non comprise (règle d'iOS 26 ?). Ajouté une sécurité : sans 50 m parcourus en 5 min, l'app éteint le GPS elle-même
(la pause automatique d'iOS peut tarder). À observer : la flèche ne devrait plus rester à l'arrêt.

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
