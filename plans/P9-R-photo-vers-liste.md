# P9-R — Une photo de produits complète la liste de courses

*Plan du 28/10/2026, demandé par Alexandre (photo de Sanytol, Soupline et Skip). Lire d'abord `P9-00-INDEX.md`,
`P9-G-listes-courses.md` et `P9-K-pieces-jointes.md`. Dépôts : relance (app, extension de partage, vigie, Signal).*

## 1. Le besoin et les décisions d'Alexandre (28/10)

Envoyer une photo de produits à racheter : Claude lit les produits et complète une liste de courses.
- **Trois entrées** : bouton dans la fiche (section Liste), partage depuis Photos, photo dans la « Note à moi-même »
  de Signal.
- **Proposé à valider** : les articles lus arrivent marqués ✦, à garder (cocher, « Tout garder ») ou retirer.
- **La liste la plus récente** quand plusieurs listes d'achats sont ouvertes ; un texte envoyé avec la photo qui
  nomme une liste ouverte (« Leroy Merlin ») la désigne ; aucune liste ouverte : une nouvelle « Courses » (Achats).

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
| R3 | Signal : photo dans la Note à moi-même → liste la plus récente (ou nommée), sinon « Courses » | codé, testé |
| R4 | Partage depuis Photos : « Ajouter à la liste de courses » | codé, compilé |

## 4. État

- 28/10 : R1 à R4 codés (tests Swift et Python verts). **À déployer** : `aiguillage_photos.py`, `relance_vigie.py`,
  `aiguillage_signal.py` sur le NUC ; l'app part par TestFlight. Pas encore essayé avec une vraie photo.
