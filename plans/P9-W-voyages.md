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
| W1 | NUC : `aiguillage_voyages.py` (filtre, lecture par Haiku 5.5, table `voyages`, fusion, rendez-vous, repère, billets joints) ; branchement dans la relève de `aiguillage_courrier` ; `ClientGmail.piece_jointe` (lecture seule) | Codé, 16 tests ; **déployé le 07/11 à 22 h 17** |
| W2 | Champ `fin` (index P9, section 3) : `sensor.hub_pour_info` montre le repère chaque jour du séjour dans les trois Hubs, annoncé le premier matin seulement | Codé, testé (Python) ; **déployé le 07/11 à 22 h 17** |
| W3 | App : info sur plusieurs jours (`PourInfo.tombe` avec `fin`, `TaskItem.finDay`, rangée après sa fin), « jusqu'au … » dans Pour info, « Du … au … » dans À venir, agenda « journée entière » sur la période | Compilé sans correction le 07/11 au soir, 299 tests Swift verts, app Mac construite ; dans `main` (TestFlight) |
| W4 | Consigne du tri : règle W (ne pas toucher aux voyages, garder `fin`) dans `docs/TRI-CONSIGNE.md` | Recopiée dans la consigne réelle (`/config/aiguillage_tri_consigne.md`, après V) le 07/11 au soir |

Choix en codant :
- **Le repère n'est pas dans le résumé du matin de l'iPhone chaque jour** : le planificateur ne reçoit que son premier
  jour (comme la notification du Hub, `deja_annoncee`).
- **L'app ne sait pas modifier `fin`** : elle le garde tel quel. Changer la date du repère dans la fiche au-delà de
  sa fin le ramène à un seul jour (fin ignorée).
- **Les rendez-vous ont la catégorie Perso** : le tri ne les reclasse pas (règle V : seulement sans catégorie).

## 4. Déploiement

1. ✅ 07/11 au soir : compilé et testé sur le Mac (299 tests Swift, app Mac construite, 485 tests Python), fusionné
   dans `main` et poussé (hook `pre-push` vert).
2. ✅ 07/11, 22 h 17 : `aiguillage_voyages.py`, `aiguillage_courrier.py` et `hub_pour_info.py` copiés dans le dossier
   des apps d'AppDaemon (`addon_configs`) ; rien ajouté à `apps.yaml` (`voyages` vrai par défaut). Journal :
   `aiguillage_courrier` et `hub_pour_info` redémarrés sans erreur, `error.log` vide depuis. Retour arrière : copies
   `aiguillage_courrier.py.avant-voyages-20261107` et `hub_pour_info.py.avant-voyages-20261107` à la racine du
   dossier d'AppDaemon (et retirer `aiguillage_voyages.py`).
3. ✅ 07/11 au soir : règle W ajoutée à la consigne réelle du tri (après V ; copie d'avant
   `aiguillage_tri_consigne.md.avant-voyages-20261107`, copie de travail du Mac mise à jour). Relue à chaque tri.
4. À faire : essai, se transférer un mail de billet (ou attendre le prochain), vérifier les deux rendez-vous (heure, billet
   joint), le repère dans l'app et sur les trois Hubs, puis le retour dans un second mail.

## 5. Risques et limites

- **Mauvaise lecture** (heure, gare) : chaque rendez-vous se corrige à la main ; une correction n'est jamais
  écrasée (`version_attendue: 0`).
- **Retour acheté avant l'aller** : le voyage prend la ville de départ comme destination ; à corriger à la main.
- **Annulation** : rien n'est retiré automatiquement (journalisé seulement).
- **Coût** : un appel Haiku par mail candidat (quelques par mois), dans le budget du courrier.
