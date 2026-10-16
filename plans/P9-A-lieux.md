# P9-A — Lieux sur la carte : restos, magasins, spots photo

*Plan du 16/10/2026. Lire d'abord `P9-00-INDEX.md` (modèle de données, compatibilité, règles). Dépôt : `relance`.*

## 1. But

Aujourd'hui la carte (`Relance/Views/TaskMapView.swift`, Mac : `MacRootView`) montre les tâches qui ont une ligne `📍` et les sorties « À voir ». On veut aussi :

- **restaurants et bars** à tester (`envie.type = resto`, ligne `🍽 À tester`) ;
- **magasins** (`magasin`, ligne `🛍 Magasin`) ;
- **spots photo**, des endroits où revenir pour faire une photo (`spot_photo`, ligne `📷 Spot photo`), avec une note facultative de lumière ou de saison (« au couchant », « en automne », « par temps de brume »).

Et pouvoir les ajouter sans rien taper : depuis un **lien Plans ou Google Maps partagé**, une **photo géolocalisée**, ou des **coordonnées GPS** envoyées en texte.

## 2. Existant à réutiliser (lu le 16/10)

- `TaskContact` (ligne `📍 Nom · adresse · téléphone · lien`) ; `PlaceLocator` géocode une adresse avec `MKLocalSearch` et garde les coordonnées dans l'App Group ; `PlaceSearchView` (recherche de lieu avec `MKLocalSearchCompleter`).
- `ProximityReminders` : surveillance de **20 zones** de 200 m au plus (`maxRegions = 20`), triées par priorité puis échéance ; seulement sur l'appareil qui relance.
- `ToSee` (types d'envie et lignes des notes), `SharedLink` (type d'envie deviné d'après l'hôte d'un lien partagé), extension `RelanceShare`.
- L'extension de partage n'accepte aujourd'hui que **texte et lien web** (`NSExtensionActivationSupportsText`, `NSExtensionActivationSupportsWebURLWithMaxCount = 1` dans `project.yml`) : pas d'image.

## 3. Lots

### A1 — Champ `lieu` et coordonnées stockées
*Fait le 16/10 (tests verts, épingle vérifiée dans le simulateur ; paragraphe pour la routine proposé dans SUIVI, à appliquer). Le lieu porte aussi `telephone` (repris de la ligne 📍).*
- Ajouter `lieu` à `TacheHA` (`v: 2`, voir l'index) et au modèle de l'app ; `TaskContact` se lit depuis `lieu` s'il existe, sinon depuis la ligne `📍`.
- À l'écriture : `lieu` + la ligne `📍` (compatibilité). Si `lieu` a des coordonnées mais pas d'adresse, la ligne `📍` porte le nom et le lien Plans.
- Les coordonnées connues par `PlaceLocator` (cache par adresse) remplissent `lat`/`lon` quand la tâche est réécrite pour une autre raison : pas de migration massive.
- **Accepté quand** : une tâche avec `lieu` sans adresse s'affiche sur la carte (iPhone, iPad, Mac) ; une ancienne tâche avec seulement `📍` s'affiche comme avant ; la routine de tri, la vigie et la carte du Nest Hub voient toujours la ligne `📍` ; tests unitaires de lecture/écriture dans les deux sens.

### A2 — Trois nouveaux types d'envie
*Fait le 16/10 (tests verts, vu dans le simulateur, Nest Hub à jour). La note du spot est sur la ligne du type (`📷 Spot photo · au couchant`) ; le champ `envie` de HA arrivera avec B1. Paragraphe de la routine prêt dans SUIVI, à appliquer une fois le build installé.*
- `ToSee.Kind` : `resto`, `magasin`, `spotPhoto` avec marqueur, symbole SF, libellé du filtre, bouton « Fait » (`Testé`, `Vu`, `Photographié`) et section d'historique.
- Carte : un filtre par type, couleurs distinctes, regroupement des points proches comme aujourd'hui.
- Fiche d'un spot photo : champ `note` (lumière, saison).
- Paragraphe à ajouter à la consigne de la routine de tri (étape K, envies) : reconnaître ces trois types d'après le titre, les notes ou le lien (ex. « resto italien rue X à tester » → `🍽 À tester` ; « revenir photographier le pont au couchant » → `📷 Spot photo`), sans date. **Ne pas appliquer à la routine avant A1 et A2 en service** (index, section 4).
- **Accepté quand** : création manuelle des trois types depuis l'app, filtres de la carte, tests des marqueurs et du format des notes.

### A3 — Entrées par la feuille de partage
*Avancé le 16/10 : « Ma position » et « Choisir sur la carte » dans la recherche de lieu (point exact dans le lien Plans `ll=`) ; liens Plans et Google Maps (1 et 2) lus par l'extension de partage, formats réels dans `Shared/Share/SharedPlace.swift` et SUIVI ; catégorie demandée à Plans (type d'envie proposé) ; photo (3) et coordonnées en texte (4) faits le même jour. A3 terminé et validé sur l'iPhone (build 29). Photos inclut la position par défaut (« Location Included », Options › Lieu pour la retirer).*
Toutes passent par `RelanceShare`, qui propose ensuite le type (resto, magasin, spot photo, à voir, tâche) avant d'enregistrer.

1. **Lien Apple Plans** : lire coordonnées et nom dans l'adresse (`ll=`, `q=`, `address=`). Les liens courts de Plans sont à suivre jusqu'à l'adresse longue. Formats exacts **à vérifier sur de vrais liens** partagés depuis Plans sous iOS 26 (Alexandre en fournit quelques-uns), puis figés dans les tests.
2. **Lien Google Maps** : les liens courts `maps.app.goo.gl` redirigent vers l'adresse longue ; y lire les coordonnées (`@lat,lon`, `!3d…!4d…`, `q=lat,lon`) et le nom (`/place/<nom>/`). Si la redirection mène à une page de consentement Google (cas possible en Europe, à vérifier) ou échoue, se rabattre sur le **texte partagé**, qui contient en général le nom et l'adresse, et le retrouver avec `MKLocalSearch`. Garder le lien Google tel quel dans `lieu.lien`.
3. **Photo** : ajouter `NSExtensionActivationSupportsImageWithMaxCount = 1` ; lire la position dans les métadonnées (`CGImageSource`, dictionnaire GPS). Si la photo n'a pas de position, le dire clairement. **À vérifier** : le partage depuis Photos retire-t-il la position par défaut ou selon l'option « Lieu » des Options de la feuille de partage ? Noter le résultat dans SUIVI. Garder une vignette ? Non pour v1 (taille des enregistrements) : seulement la date de prise de vue dans les notes.
4. **Coordonnées en texte** : reconnaître le décimal (« 48.8215, 2.4123 », virgule ou point décimal) et les degrés-minutes-secondes (« 48°49'17.4"N 2°24'44.3"E ») ; rejeter les valeurs hors bornes.
5. Pour 3 et 4, retrouver une adresse lisible par géocodage inverse (MapKit sur iOS 26, `CLGeocoder` sur iOS 18 ; l'app vise iOS 18) ; si rien, garder seulement les coordonnées.
- **Accepté quand** : un lien Plans, un lien Google Maps (court et long), une photo avec position et un texte de coordonnées créent chacun une envie placée au bon endroit (écart < 50 m avec le lieu réel) ; tests unitaires de tous les formats sur des exemples réels.

### A4 — Proximité par distance
- Avec des dizaines de lieux, les 20 zones triées par priorité ne suffisent plus : choisir **les plus proches de la position actuelle**, en réservant quelques places aux tâches urgentes qui ont déjà l'alerte (proposition : 5), et recalculer à chaque **changement de position significatif** (`startMonitoringSignificantLocationChanges`) et à chaque modification des tâches.
- L'alerte de proximité reste un choix par tâche (« Me le rappeler en passant à côté ») ; ajouter un réglage par type pour l'activer par défaut (ex. spots photo : oui, magasins : non).
- Spot photo : le texte de la notification reprend la `note` (« Pont de Charenton : au couchant »).
- Respecter la plage silencieuse et « une fois par jour et par lieu », comme aujourd'hui.
- **Accepté quand** : test avec 40 lieux simulés (simulateur, positions GPX) : les zones surveillées suivent le déplacement ; une notification arrive en entrant dans une zone ; aucune au-delà de 20 zones demandées à iOS.

### A5 — Tri et enrichissement
- Paragraphes pour la routine de tri (A2) : choix du type, ajout du lien Plans si absent.
- Horaires d'ouverture : hors périmètre v1 (la routine n'a que l'outil Home Assistant).

## 4. Hors périmètre

Itinéraires, partage de listes de lieux avec d'autres personnes, photos stockées dans HA, montre (la carte reste sur iPhone, iPad et Mac).

## 5. Documentation à tenir

README (nouveaux types, entrées par partage), SUIVI (formats de liens vérifiés, comportement de la position dans Photos), ce plan (lots cochés avec date).
