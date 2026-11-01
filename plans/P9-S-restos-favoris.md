# P9-S — Restaurants favoris, carte filtrée, note Apple et suggestion

*Plan du 01/11/2026, demandé par Alexandre. Lire d'abord `P9-00-INDEX.md` et `P9-A-lieux.md` (envies de lieu,
carte, partage depuis Plans). Dépôt : relance (app iPhone, iPad, Mac ; consigne du tri).*

**État au 01/11** : plan validé dans ses choix, rien de codé.

## 1. Le besoin et les décisions d'Alexandre (01/11)

Aujourd'hui un resto n'existe qu'« À tester » (`envie.type = resto`, ligne `🍽 À tester`) : une fois testé, il passe
en Fait et sort de la carte. On veut aussi des **favoris** :

- un favori **n'a pas de date de fin** et ne passe jamais en Fait ; on peut seulement le **retirer des favoris** ;
- les favoris sont recopiés dans **Apple Notes**, dans une note dédiée : **écrite par l'app Mac** (choix du 01/11),
  rangée **par ville ou quartier** ;
- favoris et à tester apparaissent sur la **carte**, avec un **filtre** ;
- **sur demande**, une suggestion de resto près de ma position ou près d'un endroit choisi : **mes restos d'abord,
  puis des restaurants de Plans** autour (choix du 01/11 : ni IA ni coût).

## 2. Lots

### S1 — Modèle et fiche

- `envie.statut` : `a_tester` (absent = à tester, compatible avec l'existant) ou `favori`. Ligne cachée des notes
  `⭐ Favori` (avec la sorte de lieu comme aujourd'hui : `⭐ Favori · bar`).
- Un favori : ni période, ni « Testé », ni rappel d'envie datée. Menu et fiche : « Retirer des favoris » (la tâche
  passe en Fait, comme un resto testé, et reste retrouvable dans « Déjà testé »).
- « Testé » sur un à tester propose « Garder en favori ? » (Oui → `favori`, Non → Fait).
- Ajout direct en favori : sélecteur de type dans la saisie et dans le partage depuis Plans ou Google Maps
  (« 🍽 À tester » / « ⭐ Favori »).
- Onglet Envies : filtre Resto › À tester / Favoris ; les favoris rangés par ville.
- Tri par Claude, règle K (paragraphe à ajouter à la consigne, sans donnée personnelle) : « mon resto préféré »,
  « resto favori », « à garder » pour un lieu où manger ou boire → ligne `⭐ Favori`, `envie` {"type": "resto",
  "statut": "favori"}.
- Le Nest Hub et l'app TV ignorent déjà les envies de lieu : rien à changer sur les trois vues du Hub (à vérifier).

### S2 — Carte

- Épingle étoile pour un favori, l'épingle carrée actuelle pour un à tester.
- Filtre Resto en deux niveaux : Tous / À tester / Favoris (iPhone, iPad, Mac). Le garde-fou actuel (filtre qui ne
  correspond plus à rien) reste.

### S3 — Note Apple « 🍽 Restaurants favoris » (app Mac)

- L'app Mac réécrit une seule note quand la liste des favoris change (et au lancement) : une rubrique par ville
  (quartier ou arrondissement pour Paris, d'après l'adresse ; géocodage inverse si besoin), puis pour chaque resto :
  nom, sorte de lieu, adresse, lien Plans.
- La note appartient à l'app : le texte qu'on y ajoute à la main est écrasé (à dire en tête de note).
- Par AppleScript vers Notes. **À vérifier** : droit Apple Events dans le bac à sable (exception pour
  `com.apple.Notes`), demande d'autorisation macOS au premier envoi, rendu des titres de rubrique (HTML de Notes).
- Mac éteint : la note se met à jour au prochain lancement. Réglage pour couper (Mac › Réglages › Envies).

### S4 — Suggestion « Un resto près de… »

- Bouton dans Envies (filtre Resto) et sur la carte, raccourci Siri « Trouve-moi un resto près de… ».
- Point de départ : « Ma position » ou un lieu choisi (recherche existante `PlaceSearchView`, Mes lieux).
- Résultat : mes favoris puis mes à tester dans un rayon (1 km par défaut, élargi si rien), triés par distance ;
  ensuite « Autour » : restaurants de Plans (`MKLocalPointsOfInterestRequest`, catégories restaurant, café,
  boulangerie, bar). Chaque ligne : distance, Itinéraire ; un resto de Plans peut devenir « À tester » ou
  « Favori » en un geste.
- Pas d'horaires d'ouverture au départ (**à vérifier** ce que MapKit donne en France).

## 3. Ordre et essais

S1 → S2 → S4 → S3 (S3 dépend des droits du Mac, le plus incertain). Tests unitaires du modèle (lecture et écriture
de `statut`, ligne `⭐`, compatibilité des envies existantes) ; essais réels par Alexandre : un favori ajouté depuis
Plans, filtre de la carte, suggestion dans la rue, note Apple après un ajout.
