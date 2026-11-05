# P9-U — Une seule liste de courses, le magasin porté par chaque article

*Étude et plan du 04/11/2026, demandés par Alexandre. **U1 à U6 faits le 04/11, liste créée dans HA** (voir section 7) ; ses
décisions du jour sont en section 5. Lire d'abord `P9-00-INDEX.md`, `P9-G-listes-courses.md`, `P9-Q-magasins-des-listes.md` et
`P9-R-photo-vers-liste.md`. Dépôt : relance (public : aucune adresse ni donnée personnelle ici).*

## 1. Le besoin

Un article peut s'acheter à plusieurs endroits : un produit ménager se prend au supermarché comme en droguerie.
Aujourd'hui le magasin est porté par la **liste**, pas par l'article. Il faudrait **une seule liste**, où chaque article
dit **où on peut l'acheter**, et des notifications qui suivent.

## 2. Ce qui existe et ce qui coince

| Sujet | Aujourd'hui | Problème |
|---|---|---|
| Magasin | Par liste : action « près de… », sinon nom dans le titre, sinon Supermarchés (`MesLieux.magasin`) | Un seul lieu d'achat pour tous les articles ; lessive et huile d'olive sont dans la même liste, seuls les supermarchés préviennent |
| Plusieurs listes | « Un seul type de liste à la fois » (28/10) : une liste ouverte par magasin | Un article à deux magasins n'a pas de liste possible |
| Règle en double | Swift (`MesLieux`) et Python (`aiguillage_photos` : `ENSEIGNES`, `type_de_liste`, `destination`) | À tenir à l'identique ; la vigie déplace des articles entre listes |
| Fin de liste | Tout coché → « Fait » | Incompatible avec une liste permanente |
| Rayon | `rayon` sur l'article, posé par Claude | Dit le rayon, pas le magasin (« maison » : droguerie ? bricolage ?) |
| Notification | « N articles à prendre », toute la liste, au plus une fois toutes les 2 h par tâche et par lieu | Ne dit pas quoi prendre ; le rappel s'éteignait avec la liste |

Atouts à garder : `Article.autres` conserve les champs inconnus (un nouveau champ passe par les anciens builds), fusion
article par article (`Liste.fusion`), groupes de Mes lieux, zones choisies par `ProximityPlanner` (20 au plus), montre,
photos (P9-R), recettes (G3). Le Hub TV ne montre pas une tâche sans date hors Maison : la liste n'y apparaîtra pas.

**Risque nouveau, le principal : le bruit.** Une liste permanente a presque toujours quelque chose à acheter. Sans
changement, chaque magasin proche du domicile ou du trajet quotidien sonnerait à chaque passage, deux heures plus tard
à nouveau. Le rappel doit devenir plus sélectif (U4).

## 3. Propositions

### Forme de la liste

- **A. Une liste permanente, dans une tâche à identifiant fixe (recommandé).** Tout le socle est réutilisé (synchro,
  fusion, montre, widgets, partage) ; l'identifiant fixe évite deux listes créées hors ligne sur deux appareils.
- B. Un enregistrement dédié (`liste/courses`), hors des tâches : plus propre sur le papier, mais synchro, fusion,
  montre et vigie à refaire. Non retenu.
- C. Garder plusieurs listes et mettre le magasin sur l'article : le problème des listes reste. Non retenu.

Les listes hors Achats (valise, matériel de shooting) ne changent pas. Une tâche d'achat sans liste, datée ou urgente, reste une tâche normale ; une liste d'achats datée est versée comme les autres (décision du 04/11).

### Modèle (proposition A)

```json
"liste": {
  "permanente": true,
  "articles": [
    { "id": "uuid", "texte": "Lessive", "rayon": "maison",
      "magasins": ["supermarches", "<groupe droguerie>"], "coche": false, "maj": "…" }
  ]
}
```

- `magasins` : des **groupes de Mes lieux**. Un groupe est un type (« Droguerie ») ou une enseigne (« Leroy Merlin ») ;
  les deux marchent sans cas particulier. Absent ou vide : Supermarchés.
- Groupes hors courses (Domicile, Travail) jamais proposés.
- Article pris : coché, barré 24 h pour pouvoir annuler, puis retiré. La liste n'est jamais « Faite ».

### Qui choisit le magasin

- **Claude à l'ajout, plus une mémoire des corrections (recommandé).** La vigie remplit `magasins` d'après les groupes
  existants ; toute correction à la main est retenue (`config:articles`) et prime au prochain ajout du même article.
- Table rayon → magasins : gratuite et simple, mais trop grossière (« maison » ne tranche pas).
- À la main seulement : fiable, mais trop de gestes.

### Notifications

- Une notification **par magasin**, avec **seulement ses articles** : « Tu es près de Monoprix · Adoucissant, lessive,
  vinaigre ». L'ouvrir montre la liste filtrée sur ce magasin.
- Un lieu ne sonne que si un article l'attend, **au plus une fois par jour**, plus tôt seulement si un article a été
  ajouté depuis le dernier rappel de ce lieu. Bouton « Pas aujourd'hui ».
- Chaque autre magasin garde son propre rappel (demande du 17/10).

### Écran

- Une entrée unique **Courses** : articles restants, avec un filtre par magasin en tête, et le magasin de chaque article
  en petit.
- Un appui sur l'article (ou menu) : « Où l'acheter », plusieurs choix possibles.
- Recette, photo, dictée, Signal : tout arrive dans cette liste, plus aucun tri entre listes.

## 4. Lots

| Lot | Contenu |
|---|---|
| **U1** | Modèle : `Article.magasins`, liste permanente à identifiant fixe, plus de « Fait », retrait des cochés, `groupesDeLieux` par article, tests de fusion |
| **U2** | Écran Courses (iPhone, iPad, Mac) : filtre par magasin, « Où l'acheter », saisie rapide |
| **U3** | Vigie : attribution par Claude, mémoire `config:articles`, photos, recettes (consigne du tri, règles P et Q) |
| **U4** | Notifications : articles du magasin, règle anti-bruit, « Pas aujourd'hui », ouverture filtrée |
| **U5** | Migration : sauvegarde, liste ouverte versée dans la liste permanente, listes faites intactes ; retrait du code devenu inutile (ligne « Magasin », `destination`, `_photos_deplacer`, déplacement entre listes) |
| **U6** | Montre et widgets : compteur, articles du magasin proche. Hubs : vérifier que rien ne coche la liste (règle « un Hub, trois vues ») |
| **U7** (à la carte) | Dictée et Siri : « ajoute du lait » → article de la liste (reprend G4) ; liste affichée sur les Hubs |

Ordre : U1, U3, U2, U4, puis U5 (bascule réelle), U6. Tant que U5 n'est pas passé, les listes actuelles fonctionnent
comme aujourd'hui.

## 5. Décisions d'Alexandre (04/11)

1. **Liste unique** : tous les achats en magasin, y compris ceux d'un projet. Valise et matériel gardent leurs listes.
2. **Article pris** : barré 24 h, puis retiré ; son magasin reste en mémoire.
3. **Magasin d'un article** : proposé par Claude, modifiable, toute correction retenue pour ce produit.
4. **Rappels** : une fois par jour et par magasin, plus tôt seulement si un article a été ajouté depuis.

Groupes Droguerie et Pharmacie à créer dans Mes lieux (accord du 04/11) ; reste à choisir leurs magasins.

## 6. Hors périmètre

Prix, stock à la maison, drive, partage de la liste avec d'autres personnes, rachat automatique.

## 7. État

- 04/11 : **U1 fait** : `Article.magasins`, `Liste.permanente`, identifiant fixe `Liste.idCourses`,
  `TaskStore.listeDeCourses()` (rien ne l'appelle encore), `setMagasins`, retrait à 24 h au début de chaque synchro HA,
  « Fait » refusé sur la liste permanente, `MesLieux.groupes(de:)` et `articles(de:dans:)`, `groupesDeLieux` par
  article. Tant que U5 n'a pas créé la liste, rien ne change pour Alexandre.
- 04/11 : **U3 fait, déployé le 04/11 à 20 h 13** : module `aiguillage_courses.py` et passe `courses_pass` de la vigie (20 s après une
  modification, et chaque heure ; rien sans la liste unique). Toute liste d'achats non datée, sans recette ni photo en
  attente et inchangée depuis 10 min **verse** ses articles dans la liste unique, puis passe en « Fait » (`versee_le`).
  Ce versement vaut aussi pour les recettes, les photos et la migration de U5, qui se réduit à créer la liste. Mémoire
  par produit dans `config:articles` (`par: alexandre` prime sur `par: claude`), Haiku pour le reste (`courses_modele`,
  budget du tri). Liste unique sortie du tri ; photos de Signal envoyées directement vers elle. L'app marque le choix à
  la main en retirant `magasins_claude`.
- 04/11 : **U2 fait** : `CoursesView` remplace la fiche pour cette tâche (iPhone, iPad, Mac) : filtre par magasin
  mémorisé, section « Pris », feuille « Où l'acheter » (plusieurs magasins, Domicile et Travail exclus), ligne
  `CoursesLigne` dans À faire à la place d'un rond « Fait ». Un article ajouté pendant un filtre va à ce magasin. Vu au
  simulateur iPhone en mode `-demo` ; sur iPad la ligne est vue, l'ouverture non ; Mac compilé, pas ouvert.
- 04/11 : **U4 fait** : `RappelCourses` (une fois par jour et par lieu, plus tôt si un article à y prendre apparaît ;
  « Pas aujourd'hui » coupe tous les magasins jusqu'à demain), notification « Courses · Tu es près de … » avec les
  articles de ce magasin (quatre, puis « et N autres »), ouverture filtrée sur ce magasin. Testé sans notification
  réelle : les rappels ne se déclenchent que sur un appareil en passant devant un lieu.
- 04/11 : U1 à U4 poussés sur `main` (`120a6c1`).
- 04/11 : **U6 fait** : montre : ligne « N à prendre », ni « Fait » ni report, une section par magasin (Supermarchés
  d'abord, puis « Pris »), la liste ne quitte plus la montre une fois tout coché. Les noms des magasins sont envoyés par
  l'iPhone ; la montre ne sait pas de quel magasin on est proche, d'où les sections plutôt qu'un filtre. Widgets et
  activité en direct : rien à changer, ils ne montrent que des tâches datées. Hubs : les trois vues ne montrent que les
  tâches du jour et les tâches Maison sans date (code lu) : la liste n'y apparaît pas, donc rien ne peut la cocher.
- 04/11 vers 21 h 45 : **U5** : build 126 installé, groupes Droguerie et Pharmacies créés par Alexandre, sauvegarde
  hors dépôt. Liste unique créée dans HA avec les trois articles restants de l'ancienne liste, fermée à la main
  (`versee_le`) : elle était datée, la vigie ne l'aurait pas versée. Premier appel réel à Claude : réussi, trois
  articles classés, mémoire `config:articles` créée. **Ancien code gardé** (ligne « Magasin », `destination`,
  `_photos_deplacer`) : à retirer à part, les listes versées passent encore par lui pendant leurs 10 minutes.
- 05/11 : **horaires, renommage** (demande d'Alexandre) : `MesLieux.Horaires` sur chaque lieu (lundi à dimanche, créneaux
  en minutes, saisis à la main : Apple Plans ne les donne pas aux apps). Tout rappel de passage (`notifyGroup`) se tait
  magasin fermé, sans consommer le rappel du jour ni se rattraper à l'ouverture ; lieu sans horaires : prévient à toute
  heure (décision d'Alexandre). Jours fériés inconnus. Mes lieux : toucher un lieu pour son nom et ses horaires
  (copie sur les jours, sur le groupe), « Renommer le groupe » (identifiant inchangé, Domicile et Travail exclus car
  reconnus par leur nom). Pré-rempli dans HA depuis des annuaires web, à vérifier ; un build plus ancien efface les
  horaires s'il modifie Mes lieux.
- À surveiller : le bruit des magasins très proches du domicile (un groupe a un lieu pratiquement à la porte, dans la
  zone de 150 m).
