# P9-P — Rappels « Pour info » (femme de ménage, poubelles…)

*Plan du 26/10/2026, demandé par Alexandre. Lire d'abord `P9-00-INDEX.md`. Dépôts : relance + HA (+ hub-ipad et
aiguillage-tv pour P3, « un Hub, trois vues »).*

## 1. Le besoin

Certains rappels ne demandent rien : ils signalent (femme de ménage le lundi, sortir les poubelles…). Aujourd'hui,
tout rappel d'Aiguillage est une tâche qui insiste jusqu'à « Fait ». Il faut un type à part.

**Décisions d'Alexandre (26/10)** :
1. Affiché **partout** : iPhone, iPad, Mac, montre, et les trois vues du Hub (TV, Nest Hub, iPad).
2. Annoncé dans le **résumé du matin** (pas de notification à heure fixe).
3. Créé **dans l'app** (pas de marqueur à taper dans Google Tasks).

## 2. Les règles

- **Marqueur** : ligne cachée `📣 Pour info` dans les notes (comme `👀 À voir`), copiée telle quelle en mode HA
  (champ `notes`, pas de nouveau champ TacheHA).
- **Aucune relance** : ni heure prévue, ni relance, ni « En retard », ni « À quelle heure ? ». Jamais dans
  « À trier » ni dans les compteurs de retard (badge, barre des menus, widgets, activité en direct).
- **Rien à cocher** : le jour venu, il est affiché à part (« Pour info aujourd'hui »), sans bouton « Fait ».
  Supprimer reste possible depuis la fiche.
- **Disparaît en fin de journée** : une info datée d'hier ou avant est « passée ». Avec une répétition (`🔄`), elle
  avance à l'occurrence suivante ≥ aujourd'hui (sans entrée dans « Fait ») ; sans répétition, elle est rangée
  dans « Fait » sans bruit.
  - L'**affichage** ne dépend pas de cette avancée : une info est « du jour » si sa date est aujourd'hui, ou si sa
    date est passée et que sa répétition tombe aujourd'hui. Le Hub reste juste même si l'app n'a pas tourné.
  - L'**écriture** (avancée, rangement) est faite par l'appareil qui relance, à l'ouverture et à chaque synchro,
    comme `spawnNext`. La vigie reste en lecture seule (pas de conflit d'écriture).
- **Résumé du matin** (« Ta journée ») : ajoute « · Pour info : femme de ménage, poubelles » (deux noms, puis « … »).
  Le résumé part aussi un jour où il n'y a que des infos.
- **Résumé du soir** (« Demain — … ») : rien de changé, les infos n'y comptent pas.

## 3. Lots

| Lot | Contenu | Dépôt |
|---|---|---|
| **P1** | Modèle `PourInfo` (marqueur, « du jour », avancée), planificateur (aucune relance, résumé du matin), exclusion de « En retard » et « À trier », tests | relance |
| **P2** | Saisie : interrupteur « Pour info, sans action » dans la saisie rapide et la fiche (avec « Répéter ») ; bloc « Pour info aujourd'hui » en tête d'À faire (iPhone, iPad, Mac) ; avancée à la synchro ; montre et widgets : exclues des listes, une ligne « Pour info » | relance |
| **P3** | Hub : la vigie publie `sensor.aiguillage_pour_info` (infos du jour, port Python de la répétition) et envoie un `script.hub_notifier` (niveau info) à l'heure du résumé du matin ; les trois vues montrent les infos du jour toute la journée | HA + hub-tv + hub-ipad |

## 4. État

- 26/10 : plan rédigé ; P1 en cours.
