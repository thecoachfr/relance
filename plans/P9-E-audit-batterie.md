# P9-E — Audit de la consommation de batterie d'Aiguillage

*Plan du 16/10/2026, demandé par Alexandre. Lire d'abord `P9-00-INDEX.md`. Dépôt : `relance`. Deux temps : une **mesure de référence** avant P9 (E1, dans le lot 0), puis une **mesure après** les ajouts les plus coûteux (E2, après A4 et D3).*

## 1. Pourquoi maintenant

P9 ajoute des sources de consommation : surveillance de position plus large (A4 : changements de position significatifs, zones recalculées), appels réseau de la vigie déclenchant des pushs (B3, D3), actions en arrière-plan. Sans mesure de départ, impossible de savoir ce qui coûte.

## 2. Ce qui peut consommer aujourd'hui (à vérifier par la mesure, pas à supposer)

D'après le code lu le 16/10 :

- **Position** : `ProximityReminders` (jusqu'à 20 zones, localisation « Toujours ») ; `TravelTimes` et `PlaceLocator` (recherches MapKit).
- **Réseau** : synchro `DonneesHA` (au lancement, au premier plan, après écriture, sur push), repli iCloud, Google Tasks en boîte d'entrée.
- **Pushs** : APNs de la vigie à chaque `donnees_apps_modifie` ; un push qui réveille l'app pour synchroniser coûte à chaque fois.
- **Arrière-plan** : rafraîchissement en arrière-plan, Live Activity, widgets iPhone et montre (fréquence des rechargements de timeline), complications.
- **Montre** : WatchConnectivity, écritures directes dans HA depuis la montre.
- **Notifications planifiées** : relances, suggestions d'envies.

## 3. Outils

- **Réglages › Batterie** de l'iPhone : part d'Aiguillage sur 24 h et 10 jours, à l'écran et en arrière-plan (relevé par Alexandre, capture datée).
- **MetricKit** (`MXMetricManager`) : rapports quotidiens sur l'appareil (temps CPU, position, réseau, temps en arrière-plan, réveils) ; les écrire dans un fichier de l'App Group et les afficher dans un écran de diagnostic (Réglages › Diagnostic), avec export.
- **Xcode Organizer › Énergie** (rapports remontés par TestFlight si le partage d'analyses est activé) et **Instruments** (profileur d'énergie / de puissance) en session sur l'iPhone branché.
- Côté HA : compter les pushs envoyés par la vigie par jour (journal AppDaemon).

## 4. Lots

### E1 — Mesure de référence (lot 0, avant A)
*En cours (16/10) : collecte, écran de diagnostic et comptage des pushs faits ; semaine de mesure à partir de l'installation du build.*
- Ajouter la collecte MetricKit et l'écran de diagnostic (sans réseau supplémentaire).
- Compter dans la vigie les pushs envoyés par jour et par cause.
- Une semaine d'usage normal ; relevé de Réglages › Batterie à J+7.
- Rapport dans `docs/BATTERIE.md` : part de batterie, temps en arrière-plan, nombre de réveils par push, position (heures de GPS actif), réseau, avec les premières causes probables.

### E2 — Corrections et nouvelle mesure (après A4 et D3)
- Pistes à évaluer selon E1 : regrouper les pushs de la vigie (anti-rebond, pushs silencieux seulement si quelque chose change pour cet appareil), limiter les rechargements de widgets, éviter les recherches MapKit répétées, préférer la surveillance de zones et les changements significatifs au GPS continu, couper la position quand aucune alerte n'est active.
- Même protocole qu'E1, rapport comparatif dans `docs/BATTERIE.md`.
- **Accepté quand** : la part d'Aiguillage dans Réglages › Batterie ne dépasse pas celle mesurée en E1 de plus d'un seuil fixé avec Alexandre après E1, malgré les ajouts de P9.

## 5. Documentation à tenir

`docs/BATTERIE.md`, SUIVI, ce plan.
