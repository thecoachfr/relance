# P9-H — Étude : durée d'une tâche, et rappel près d'un lieu habituel (supermarchés)

*Étude du 17/10/2026, demandée par Alexandre. Lire d'abord `P9-00-INDEX.md`. Dépôt : `relance` (app, consigne du tri).
Choix faits par Alexandre le 17/10 (voir la fin) : plan à exécuter, H2 d'abord.*

## H1 — Durée facultative d'une tâche

### Existant (lu le 17/10)

- « Ajouter à l'agenda » (`Relance/App/CalendarLink.swift`) crée un événement d'**une heure fixe**
  (`CalendarLink.duration = 3600`) à l'heure de la tâche ; `reconcile` ne recale que le début et le titre.
- Une tâche sans heure ne peut pas aller à l'agenda avec une durée utile (journée entière ou rien).

### Proposition

- Champ facultatif `duree` (minutes, entier) dans `TacheHA`, comme `lieu` ou `liste` (index P9, section 3 : à
  ajouter au modèle commun) ; copie locale `TaskItem.dureeMinutes`.
- **Fiche** : sous l'heure, une ligne « Durée » (menu : 15 min, 30 min, 45 min, 1 h, 1 h 30, 2 h, 3 h, Autre…),
  visible seulement quand la tâche a une heure ; « Aucune » par défaut.
- **Agenda** : l'événement dure `duree` (1 h sans durée, comme aujourd'hui) ; `reconcile` recale aussi la fin
  quand la durée change.
- **Ailleurs, à étudier ensuite** : « Pars maintenant » et l'activité en direct pourraient finir à la fin de la
  tâche ; le planificateur de relances ne change pas.
- **Routine de tri** : reconnaît une durée explicite dans le titre (« réunion de 2 h », « 30 min de vélo ») et
  remplit `duree` en la retirant du titre ; recopie le champ tel quel sinon (paragraphe de consigne à ajouter).
- **Mode Google Tasks** : pas de durée (champ HA seulement).
- Coût estimé : une soirée (modèle, fiche, agenda, tests, consigne).

## H2 — Rappel près d'un de mes lieux habituels (« liste de lieux »)

*Fait le 17/10 : `MesLieux` (`config:lieux`, cache App Group, groupe « Supermarchés » par défaut), Réglages › Mes lieux (`MesLieuxView` : groupes libres, ajout par la recherche de Plans, la position ou la carte, balayer pour retirer), action `rappel_groupe` (« Me le rappeler près de… », `params.groupe`, `nom`), rattachement automatique d'une liste d'achats pas finie (catégorie Achats) à Supermarchés (`TaskItem.groupesDeLieux`), une zone de 150 m par lieu d'un groupe attendu, dans les 20 de `ProximityPlanner` (`ProximityReminders`, préfixe `g-`), notification « Tu es près de <lieu> · N articles à prendre », au plus une fois toutes les 2 h par tâche, discrète pendant la plage silencieuse. Mention dans la section Liste de la fiche. Test `mesLieux`. À essayer en vrai : renseigner ses supermarchés, puis passer devant avec une liste d'Achats.*

### Besoin

Une liste de courses ne dépend pas d'un magasin précis : n'importe lequel de « mes » supermarchés fait l'affaire.
En passant près de l'un d'eux, Aiguillage rappelle la liste (« 12 articles sur Courses »).

### Existant (lu le 17/10)

- Rappels à l'approche (`ProximityReminders`, rayon 200 m) : une zone par tâche qui a une ligne `📍`, 20 zones au
  plus pour toute l'app (limite d'iOS), choisies par `ProximityPlanner` (5 places réservées aux urgentes, puis
  les plus proches).
- Les lieux sont propres à chaque tâche ; il n'existe pas de lieux « à moi » réutilisables.

### Proposition

1. **Mes lieux** : une liste de lieux nommés et groupés, rangée dans HA sous une clé non UUID (ex.
   `config:lieux` : `{"groupes": [{"id": "supermarches", "nom": "Supermarchés", "lieux": [{nom, adresse, lat,
   lon}]}]}`), comme `config:abonnements`. Réglages › Mes lieux : ajouter un lieu par la recherche de Plans
   (déjà dans l'app, `PlaceSearchView`), « Ma position » ou « Choisir sur la carte » ; les ranger en groupes
   (Supermarchés, Pharmacies, Bricolage…).
2. **Sur la tâche** : dans la section Actions, « Me le rappeler près de… › Supermarchés » (action
   `rappel_groupe`, `params.groupe`), sur le modèle de « Me le rappeler dans… » (F4). Option automatique, à
   valider : toute tâche avec une liste non finie et la catégorie Achats est rattachée au groupe Supermarchés.
3. **Zones** : chaque lieu du groupe devient une zone (rayon 150 à 200 m), qui compte dans les 20 de
   `ProximityPlanner`. Une seule zone par lieu, même si plusieurs tâches y sont rattachées ; seuls les lieux les
   plus proches de la position actuelle sont surveillés (déjà le principe d'A4), donc un groupe de 30
   supermarchés reste possible.
4. **Notification** en entrant dans la zone : « Courses : 12 articles à prendre · Carrefour City », avec
   l'ouverture de la liste ; une fois par passage et au plus toutes les 2 h par tâche ; rien si la liste est
   finie ou la tâche faite ; pas la nuit (22 h – 7 h).
5. **Montre** : rien de plus (la notification de l'iPhone s'y affiche) ; la liste s'ouvre sur la montre (G2).
6. **Batterie** (plan E) : la surveillance de zones est peu coûteuse (pas de GPS continu) ; à mesurer dans E2.

Coût estimé : 2 soirées (mes lieux et réglages, action, zones et notification, tests), plus l'essai réel en
passant devant un magasin.

## Choix d'Alexandre (17/10)

- H1 : durées du menu validées (15, 30, 45 min, 1 h, 1 h 30, 2 h, 3 h, Autre) ; durée seulement avec une heure.
- H2 : rattachement **automatique** (liste pas finie, catégorie Achats → groupe Supermarchés) **et manuel**
  (« Me le rappeler près de… ») ; rayon **150 m** ; au plus un rappel toutes les **2 h** par tâche ; groupes
  **libres** ; **H2 d'abord**, H1 ensuite.
