# Demande à Claude (projet « Comptabilité Micro Entreprise »)

*À coller dans une conversation du projet claude.ai « Comptabilité Micro Entreprise », qui a accès à la note
`claude/methode-tva-micro-photo.md` et à la mission « Déclaration de TVA mensuelle ». Le résultat est à rapporter
dans la session Claude Code d'Aiguillage (plan P9-D5). Il ne sera pas mis dans un dépôt.*

---

Bonjour. Je confie la préparation de ma CA3 mensuelle à une **routine automatique** (une tâche planifiée Claude
lancée par Home Assistant, cinq jours avant le 15). Elle travaillera **seule, en lecture seule** : elle lira le
classeur « Comptabilité » et mes e-mails (Gmail), puis écrira une proposition dans ma tâche « Payer la TVA ». Elle
n'aura **pas** accès à ce projet, ni à ses fichiers, ni à notre historique : tout ce qu'elle doit savoir doit être
écrit noir sur blanc.

Rassemble pour elle, **dans un seul document Markdown** (un seul bloc de code, que je pourrai copier), tout ce qui
suit. Recopie les textes en entier plutôt que de les résumer. Si une information manque ou est incertaine, écris
`À CONFIRMER : …` au lieu de deviner. N'y mets **aucun mot de passe ni code d'accès**.

## 1. Les textes existants, en entier

- La mission « Déclaration de TVA mensuelle (micro-entreprise photo) », complète (sections 0 à 5 et au-delà).
- La note `claude/methode-tva-micro-photo.md`, complète.

## 2. La carte du classeur

Pour l'onglet d'un mois (« <Mois> AAAA ») :

- les quatre tableaux (CA · Dépenses Récurrentes · Paiement effectué durant le mois · À déclarer) : leurs plages de
  cellules ;
- **la carte des lignes jusqu'à août 2026 et à partir de septembre 2026** : pour chaque ligne, le numéro de ligne,
  le libellé, le fournisseur ;
- les colonnes : laquelle reçoit le montant TTC (G), lesquelles sont des formules (HT, TVA, TVA déductible), où
  sont « Total Récurrent » et « Déduction TVA » ;
- comment repérer les montants et libellés hérités du mois précédent (onglet dupliqué).

## 3. Les règles

Ce qui est déductible ou non, les taux de TVA par fournisseur, les dépenses passées au portage (hors micro), les
cas particuliers (abonnements en devise, avoirs, remboursements, factures à cheval sur deux mois), les arrondis.

## 4. Les fournisseurs et leurs factures dans Gmail

Un tableau, une ligne par fournisseur actif :

| Fournisseur | Ligne du classeur | Expéditeur du mail de facture | Mots de l'objet | Facture en pièce jointe ou par lien ? | Fréquence et jour habituel | Montant TTC habituel | Taux de TVA | Nom du fichier à donner |
|---|---|---|---|---|---|---|---|---|

Ajoute les fournisseurs dont la facture **n'arrive pas par e-mail** (à télécharger sur un site) : la routine les
signalera comme « à récupérer par Alexandre ».

## 5. Le calcul de la CA3

- Chaque ligne du formulaire CA3 à remplir : son numéro, son libellé, et la cellule du classeur (ou le calcul) d'où
  vient le montant.
- **La ligne 22** (crédit de la déclaration précédente) : où la routine peut-elle le trouver (cellule d'un onglet,
  ligne de la CA3 du mois d'avant) ?
- Le crédit à reporter : son calcul et la ligne où il apparaît.
- Les contrôles à faire avant de proposer (totaux qui doivent tomber juste, montants à zéro attendus…).

## 6. Un exemple réel

La déclaration déposée le **15/10/2026** (mois de septembre 2026) : les montants de chaque fournisseur, et les lignes
CA3 saisies avec leurs montants. La routine s'en servira comme exemple, et pour vérifier son calcul.

## 7. La forme de la proposition

Comment je veux recevoir la proposition chaque mois (4 000 caractères au plus) : par exemple, un tableau
« fournisseur · montant TTC · justificatif trouvé (mail du JJ/MM) · ligne », puis les lignes CA3 à saisir, puis les
points à vérifier.
