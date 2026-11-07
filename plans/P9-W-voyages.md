# P9-W — Billets de train : rendez-vous aller et retour, repère sur la durée du voyage

*Plan et code du 07/11/2026, demandés par Alexandre (« J'ai acheté des billets de train et Aiguillage ne sait pas
comment gérer ça »). Lire d'abord `P9-00-INDEX.md`, `P9-T-rendez-vous.md` et `P9-P-pour-info.md`. Dépôt : relance
(NUC et app). Contrat NUC : `homeassistant/COURRIER.md`, « Billets de train ».*

*Dépôt public : aucun nom, adresse ni donnée personnelle dans ce plan.*

## 1. Le besoin

Avant : un mail de billet donnait au mieux une tâche « SNCF Connect : Votre e-billet », datée du jour du mail, à
cocher. Voulu : **un rendez-vous pour l'aller, un pour le retour, et un élément sur toute la durée du voyage.**

## 2. Choix d'Alexandre (07/11)

1. Le séjour est un **repère sans relance** : « En voyage à Lyon », affiché chaque jour du départ au retour, sans case,
   ni retard, ni relance (une info, `📣`, sur plusieurs jours).
2. Le **billet PDF est joint aux deux rendez-vous** (section Pièces jointes de la fiche).
3. **Aller et retour reçus dans deux mails** : le second complète le voyage déjà créé.
4. Coder directement (pas de plan à valider avant).

## 3. Ce qui est fait (07/11)

| Lot | Contenu | État |
|---|---|---|
| W1 | NUC : `aiguillage_voyages.py` (filtre, lecture par Haiku 5.5, table `voyages`, fusion, rendez-vous, repère, billets joints) ; branchement dans la relève de `aiguillage_courrier` ; `ClientGmail.piece_jointe` (lecture seule) | Codé, 16 tests ; **pas déployé** |
| W2 | Champ `fin` (index P9, section 3) : `sensor.hub_pour_info` montre le repère chaque jour du séjour dans les trois Hubs, annoncé le premier matin seulement | Codé, testé (Python) ; **pas déployé** |
| W3 | App : info sur plusieurs jours (`PourInfo.tombe` avec `fin`, `TaskItem.finDay`, rangée après sa fin), « jusqu'au … » dans Pour info, « Du … au … » dans À venir, agenda « journée entière » sur la période | Codé, tests Swift ajoutés ; **non compilé** (pas de Xcode dans la session) |
| W4 | Consigne du tri : règle W (ne pas toucher aux voyages, garder `fin`) dans `docs/TRI-CONSIGNE.md` | **À recopier dans la consigne réelle** (`/config/aiguillage_tri_consigne.md`) |

Choix en codant :
- **Le repère n'est pas dans le résumé du matin de l'iPhone chaque jour** : le planificateur ne reçoit que son premier
  jour (comme la notification du Hub, `deja_annoncee`).
- **L'app ne sait pas modifier `fin`** : elle le garde tel quel. Changer la date du repère dans la fiche au-delà de
  sa fin le ramène à un seul jour (fin ignorée).
- **Les rendez-vous ont la catégorie Perso** : le tri ne les reclasse pas (règle V : seulement sans catégorie).

## 4. Déploiement (à faire)

1. Compiler et lancer les tests sur le Mac (hook `pre-push`), puis fusionner dans `main`.
2. Copier `aiguillage_voyages.py`, `aiguillage_courrier.py` et `hub_pour_info.py` dans le dossier des apps
   d'AppDaemon (`addon_configs` monté dans le Finder) ; rien à ajouter à `apps.yaml` (`voyages` vrai par défaut).
3. Ajouter la règle W à la consigne réelle du tri.
4. Essai : se transférer un mail de billet (ou attendre le prochain), vérifier les deux rendez-vous (heure, billet
   joint), le repère dans l'app et sur les trois Hubs, puis le retour dans un second mail.

## 5. Risques et limites

- **Mauvaise lecture** (heure, gare) : chaque rendez-vous se corrige à la main ; une correction n'est jamais
  écrasée (`version_attendue: 0`).
- **Retour acheté avant l'aller** : le voyage prend la ville de départ comme destination ; à corriger à la main.
- **Annulation** : rien n'est retiré automatiquement (journalisé seulement).
- **Coût** : un appel Haiku par mail candidat (quelques par mois), dans le budget du courrier.
