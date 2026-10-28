# P9-R — Une photo de produits complète la liste de courses

*Plan du 28/10/2026, demandé par Alexandre (photo de Sanytol, Soupline et Skip). Lire d'abord `P9-00-INDEX.md`,
`P9-G-listes-courses.md` et `P9-K-pieces-jointes.md`. Dépôts : relance (app, extension de partage, vigie, Signal).*

## 1. Le besoin et les décisions d'Alexandre (28/10)

Envoyer une photo de produits à racheter : Claude lit les produits et complète une liste de courses.
- **Trois entrées** : bouton dans la fiche (section Liste), partage depuis Photos, photo dans la « Note à moi-même »
  de Signal.
- **Proposé à valider** : les articles lus arrivent marqués ✦, à garder (cocher, « Tout garder ») ou retirer.
- **Un seul type de liste à la fois** (précisé le 28/10, remplace « la plus récente ») : au plus une liste ouverte
  par magasin (groupe de Mes lieux, enseigne nommée, sinon Supermarchés, même règle que l'app, P9-Q). Le type d'une
  photo : celui que nomme le texte envoyé avec elle, sinon celui que Claude voit (champ `magasin`, choisi parmi
  « Supermarchés » et les groupes de Mes lieux). Pas de liste de ce type : « Courses » ou « Courses <magasin> ».
  Une photo prise depuis la fiche reste dans cette liste (choix explicite).

## 2. Le circuit

1. L'entrée range la photo comme **pièce jointe** de la tâche (`pieces`, fichiers `donnees_apps`) et la note à lire
   dans `liste.photos` : `{"piece": <sha>, "a_lire": true, "ajoute_le": …, "note": …}`.
2. La **vigie** (`photos_pass`, 5 s après une modification ; 3 photos par passage) lit le fichier, l'envoie à Claude
   (vision, sortie structurée, même clé API et même budget mensuel que le tri, modèle `photos_modele` ou celui du
   tri), puis ajoute les articles lus sans doublon (`source: "photo"`, `propose: true`) et note la photo lue
   (`lue_le`, `articles`) ou en échec (`echec`). Fichier pas encore arrivé : nouvel essai chaque minute, 5 au plus.
3. L'**app** montre « Claude lit la photo… » tant que la photo est à lire, puis les articles ✦ ; « Tout garder »
   retire la marque, cocher un article le garde. En conflit entre appareils, une photo lue d'un côté l'est des deux.

Code : `homeassistant/appdaemon/apps/aiguillage_photos.py` (fonctions pures : consigne, schéma, contenu, fusion,
liste visée), `relance_vigie.photos_pass`, `aiguillage_signal._photos_vers_liste` et `images_note_a_soi` ;
`TacheHA.Liste.ajouterPhoto` / `photosALire` / `Article.propose`, `TaskStore.ajouterPhotosDeCourses` /
`garderProposes`, `PhotoDeCoursesBouton` (ListeSection), `ShareComposeView.ajouterAuxCourses`.

## 3. Lots

| Lot | Contenu | État |
|---|---|---|
| R1 | Lecture par la vigie (module `aiguillage_photos`, `photos_pass`) | codé, testé |
| R2 | Bouton « Lire des produits sur une photo » dans la fiche (appareil photo, Photos) ; ✦ et « Tout garder » | codé, testé |
| R3 | Signal : photo dans la Note à moi-même → liste du magasin nommé, sinon Supermarchés (puis déplacée selon ce que voit Claude) | codé, testé |
| R4 | Partage depuis Photos : « Ajouter à la liste de courses » | codé, compilé |

## 4. État

- 28/10 vers 17 h 20 : le partage d'une photo plantait (vu par Alexandre) : la réduction ajoutée à 16 h 50 décodait
  l'image entière (UIImage), au-delà de la mémoire d'une extension ; remplacée par `PiecesJointes.reduire` (ImageIO).
  Plantage non confirmé par un rapport (iPhone pas joignable depuis le Mac).
- 28/10 vers 17 h : la saisie rapide (Liste d'articles) propose aussi « Lire des produits sur une photo » : une
  liste se crée directement d'une photo (titre « Courses » par défaut, catégorie Achats), remarque d'Alexandre.
- 28/10 vers 16 h 50 : vu par Alexandre, une photo partagée depuis Photos ne montrait ni « Ajouter à la liste de
  courses » ni « Pièce jointe » (proposée en « Spots photo », la photo ayant une position). Cause probable : photo de
  plus de 10 Mo écartée par l'extension ; elle est maintenant réduite (3 000 px, JPEG). Le bouton passe en tête de
  la feuille.
- 28/10 : R1 à R4 codés (tests Swift et Python verts), puis règle « un seul type de liste à la fois » :
  Signal range la photo dans la liste du type nommé (sinon Supermarchés) ; après lecture, la vigie déplace pièce et
  articles vers la liste du magasin vu (`destination`, `_photos_deplacer`, `sans_piece`) ; origine `fiche` jamais
  déplacée. **Déployé sur le NUC le 28/10 vers 16 h 16** (`aiguillage_photos.py`,
  `relance_vigie.py`, `aiguillage_signal.py` ; sauvegardes `*.avant-photos-20261028`) ; l'app part par TestFlight. Pas encore essayé avec une vraie photo.
