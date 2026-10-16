# P9-G — Listes de courses : tâche avec articles cochables, recette → ingrédients

*Plan du 16/10/2026, idée d'Alexandre, mis à jour le 16/10 à 22 h (A à D et F faits). Lire d'abord `P9-00-INDEX.md` (modèle de données, compatibilité, routine de tri, règles). Dépôt : `relance`. Déposé dans `plans/` depuis le chat le 16/10 à 22 h, avec la ligne G et le champ `liste` ajoutés à l'index (section 3).*

**Acquis à réutiliser (état du 16/10 au soir)** : l'app conserve les champs de premier niveau qu'elle ne connaît pas (`TacheHA.autres`, D1) ; actions et recettes (D1 à D3, `config:recettes`, Réglages › Actions automatiques) ; rappel dans une pièce et à la maison (F1 à F4) ; la montre écrit directement dans HA (mémo du tri) ; extension de partage (A3, B1).

## 1. But

Une tâche peut contenir une **liste d'articles cochables** (courses, mais aussi valise, matériel de shooting…).

1. D'abord, simplement : un titre et une liste.
2. Quand **tous les articles sont cochés**, la tâche passe en « Fait ».
3. Si Alexandre envoie une **recette**, Claude aide à générer la liste des ingrédients, avec des **quantités seulement indicatives**.

## 2. Modèle

Nouveau champ facultatif `liste` de `TacheHA` (`v: 2`) :

```json
"liste": {
  "articles": [
    { "id": "uuid", "texte": "Œufs", "quantite": "6", "rayon": "frais",
      "coche": false, "maj": "2026-10-16T12:00:00Z", "source": "recette" }
  ],
  "parts": 4,
  "recettes": [ { "titre": "Risotto aux champignons", "lien": "https://…" } ]
}
```

- `quantite` : texte libre (« 200 g », « 1 bouquet », « 6 »), toujours indicatif, affiché comme tel.
- `rayon` : facultatif (`fruits_legumes`, `frais`, `epicerie`, `boissons`, `hygiene`, `maison`, `autre`).
- `source` : `saisie`, `recette`, `dictee`, `routine`.
- Article retiré : supprimé de la liste (pas de marque de suppression), sauf pendant une fusion (section 3).
- **Compatibilité** : copie lisible dans les notes pour les lecteurs qui ne connaissent pas le champ (Nest Hub, mode Google) : une ligne `🛒 Liste : 3/12 cochés` ; le champ fait foi. Les anciens builds gardent déjà le champ grâce à `TacheHA.autres` (D1), mais **la routine de tri doit le connaître avant sa mise en service** (index, section 4) : rédiger le paragraphe de consigne, à faire appliquer par Alexandre depuis le chat.

## 3. Point technique principal : deux appareils qui cochent en même temps

La règle actuelle de C2 (« la modification la plus récente gagne ») s'applique **à l'enregistrement entier**. Cocher les œufs sur la montre pendant que l'iPhone coche le pain ferait perdre une des deux coches.

- **Fusion article par article** côté app : en cas de conflit (`version_attendue` refusée) ou au retour hors ligne, relire la version de HA et fusionner par `id` d'article, en gardant pour chaque article la modification la plus récente (`maj`), puis réécrire.
- Articles ajoutés des deux côtés : on garde les deux. Article supprimé d'un côté et modifié de l'autre : la modification gagne (on ne perd pas un article par erreur).
- Tests obligatoires : deux appareils simulés, coches croisées, ajout et suppression simultanés, écriture hors ligne puis retour.

## 4. Lots

### G1 — Liste cochable
*Commencé le 16/10 au soir : modèle `TacheHA.Liste` (`Shared/HA/TacheHA+Liste.swift`, champs inconnus gardés, ligne `🛒`), copie locale `TaskItem.listeRaw` et ancêtre commun `listeBaseRaw` (dernière liste reçue de HA), fusion à trois voies article par article (`Liste.fusion`), tests `ListeTests`. Reste : brancher la fusion au moment du conflit (le paquet `DonneesHA` règle les conflits par « dernier écrit gagne » sur l'enregistrement entier : il faut un point d'accroche, à faire dans `ha-donnees-apps` avec l'accord d'Alexandre), écran, compteur, tout coché → Fait, consigne de la routine.*
- Fiche : cases à cocher, ajout d'un article d'une ligne (Retour = article suivant), réordonner en glissant, supprimer en balayant ; compteur « 3/12 » dans la liste des tâches et le widget.
- Création : « Nouvelle liste » dans la saisie rapide ; une tâche existante peut recevoir une liste.
- **Tout coché → Fait**, avec le « Annuler » habituel ; ajouter un article à une liste faite la rouvre ; décocher un article d'une liste faite la rouvre aussi.
- Fusion article par article (section 3).
- **Accepté quand** : création, cochage et clôture automatique sur iPhone, iPad et Mac ; tests de fusion verts ; essai réel sur deux appareils sans perte de coche.

### G2 — Montre
- Liste ouverte sur la montre, cocher au toucher (écriture directe dans HA comme le mémo, file d'attente si HA est injoignable).
- **Accepté quand** : liste de 15 articles cochée en entier depuis la montre, tâche passée en Fait, aucune coche perdue.

### G3 — Recette → ingrédients
Entrées par la feuille de partage :

1. **Lien d'une page de recette** : beaucoup de sites décrivent la recette en données structurées schema.org `Recipe` (JSON-LD) avec `recipeIngredient` et `recipeYield`. **À vérifier** sur les sites qu'utilise Alexandre (il en fournit quelques liens). Si présent, l'extension lit les ingrédients et le nombre de parts, sans IA.
2. **Texte de recette** collé ou partagé.
3. **Photo d'une page de livre** : texte lu sur l'appareil (reconnaissance de texte de Vision), rien de l'image n'est gardé.
4. **Phrase seule** (« courses pour un risotto aux champignons ») : liste proposée par la routine.

Les ingrédients bruts vont dans les notes (`🍳 Recette : …` suivi du texte) et la tâche est marquée à préparer.

**La routine de tri** (paragraphe à ajouter à sa consigne, sans donnée personnelle, appliqué depuis le chat) :
- transforme les ingrédients bruts en articles : texte court, quantité indicative pour `parts` (4 par défaut ou celui de la recette), rayon ;
- fusionne les doublons quand une deuxième recette est ajoutée à la même liste (« 2 oignons » + « 1 oignon » → « 3 oignons ») ;
- met à part les produits de la fiche « Placard » du mémo (sel, poivre, huile…) en `rayon: "placard"`, non cochés, pour vérification ;
- ne coche jamais rien, ne supprime jamais un article ajouté par Alexandre, n'invente pas d'ingrédient absent de la recette (sauf entrée 4, où toute la liste est une proposition).
- **Accepté quand** : trois recettes réelles (un lien avec données structurées, un texte, une photo) donnent des listes correctes ; deux recettes fusionnées sans doublon ; aucune modification des articles saisis à la main.

### G4 — Confort (après G1 à G3, au choix)
- **Siri et dictée** : « ajoute du lait à la liste de courses » ajoute un article à la liste ouverte au lieu de créer une tâche (s'il n'y en a pas, en crée une).
- **Lieu** : supermarché attaché à la liste (champ `lieu`, A1) ; l'alerte de proximité (A4) prévient en passant devant.
- **Recette d'action (D2)** : par exemple « liste de courses non finie → rappel à la maison le samedi matin » (déclencheur `presence`, F2) ou « rappel dans l'entrée » (F3).
- **Nest Hub** : liste de courses ouverte affichée dans l'entrée.
- **Tri par rayon** dans la fiche, ordre des rayons réglable selon le magasin.

## 5. Temps

G1 : 2–3 soirées (dont la fusion) ; G2 : 1 soirée ; G3 : 1–2 soirées plus la consigne de la routine ; G4 : à la carte.

## 6. Hors périmètre

Prix, commande en ligne ou drive, partage de liste avec d'autres personnes, inventaire du placard tenu automatiquement.

## 7. Documentation à tenir

README (listes, recettes), SUIVI, index P9 (ligne G et champ `liste`), ce plan.
