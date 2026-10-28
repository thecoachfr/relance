# P9-Q — Le bon magasin pour chaque liste (Leroy Merlin, pharmacie…)

*Plan du 28/10/2026, demandé par Alexandre. Lire d'abord `P9-00-INDEX.md` et `P9-H-duree-et-lieux.md` (groupes de
lieux, P9-H2). Dépôt : relance.*

## 1. Le besoin

Toute liste de la catégorie « Achats » était rattachée d'office au groupe « Supermarchés » : « Courses a Leroy merlin »
(double face, gouttière, rendre bloc porte) prévenait près d'un Franprix, jamais près d'un Leroy Merlin.

**Décision d'Alexandre (28/10)** : une enseigne nommée dans le titre → rappel **seulement près de cette enseigne**.

## 2. Les règles (dans l'ordre)

1. **Choix explicite** : une action « Me le rappeler près de… » (`rappel_groupe`) fait foi, et elle seule (avant :
   « Supermarchés » s'ajoutait en plus).
2. **Groupe nommé dans le titre** : un groupe de Mes lieux dont le nom est dans le titre (casse et accents ignorés,
   mots entiers) : « Courses a Leroy merlin » → groupe « Leroy Merlin ».
3. **Enseigne connue sans groupe** (liste d'enseignes de l'app) : pas de rappel près des supermarchés ; la fiche
   propose « Créer « Leroy Merlin » » : recherche Plans des magasins de l'enseigne autour du domicile et des lieux de
   travail, à cocher, puis groupe créé (la règle 2 le prend aussitôt).
4. Sinon **Supermarchés**, comme avant.

La fiche montre une ligne **« Magasin »** dans la section Liste : le groupe retenu (« auto » s'il vient du titre ou
du défaut), un menu pour en choisir un autre (crée l'action explicite) ou revenir à l'automatique.

## 3. Lots

| Lot | Contenu |
|---|---|
| **Q1** | Règles 1 à 4 dans `TaskItem.groupesDeLieux` (`MesLieux.groupeNomme`, `MesLieux.enseigne`), tests |
| **Q2** | Ligne « Magasin » de la fiche, création d'un groupe d'enseigne par recherche Plans |
| **Q3** (plus tard, à valider) | Sans enseigne : le tri par Claude choisit un groupe par type d'articles (gouttière → « Bricolage ») s'il existe |

## 4. État

- 28/10 : **Q1 et Q2 faits** (247 tests verts, app Mac compilée), pas encore vus à l'écran : section « Magasin » de
  la fiche (listes d'achats, mode HA), feuille « Créer « Leroy Merlin » » (recherche Plans autour du domicile et du
  groupe « Travail », 30 km, magasins à moins de 8 km cochés d'office, 4 au plus). Q3 à valider avec Alexandre.
