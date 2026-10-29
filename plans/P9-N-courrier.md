# P9-N — Courrier : lieu de travail, tri des mails, app Courrier, agent

*Plan du 24/10/2026, demandé par Alexandre ; remis à jour le 29/10/2026. Lire d'abord `P9-00-INDEX.md`. Dépôts :
`relance` (Aiguillage et AppDaemon du NUC), `../courrier` (app Courrier). Détail technique : contrats
`homeassistant/LIEU-TRAVAIL.md` et `homeassistant/COURRIER.md` ; app : `../courrier/docs/CADRAGE.md` et
`docs/STATUT.md` ; historique : `SUIVI.md`.*

## État par lot (29/10)

| Lot | Contenu | État |
|---|---|---|
| N0 | Source des jours de bureau | **Bloqué par l'admin de Barrière** (partage « tous les détails », Apps Script, lieu de travail absent du Calendrier d'iOS) → **semaine type** + exceptions, vérifiée par la position (24/10) |
| N1 | `sensor.aiguillage_lieu_travail` | **Fait le 24/10** : semaine type, fériés, consignes Signal (« demain télétravail »), constat par la position, Le Lab |
| N2 | Bureau / télétravail dans Aiguillage, la montre et les trois vues du Hub | **Fait le 24/10** (bandeau, écran « Lieu de travail », champ `contexte`, trois vues du Hub) ; **reste soldé le 28/10** (pastille par tâche, complication et Smart Stack, « Ta journée ») |
| N3 | Tri de la boîte perso (`aiguillage_courrier`) | **Déployé le 24/10** en ombre ; libellés `Tri/…` dans Gmail ; notifications urgent + résumés 9 h / 12 h / 18 h **validées le 26/10** ; mémo d'Aiguillage dans le tri (27/10) |
| N4 | ~~Section « Courrier » dans Aiguillage~~ | **Remplacé par l'app Courrier** (voir ci-dessous) |
| N5 | Agent | **Signal fait le 27/10** (« ? » dans la « Note à moi-même », `aiguillage_agent`) ; ~~« Demander à l'agent » dans Aiguillage~~ **remplacé** par « Demander à l'IA » de Courrier (29/10, même agent) |
| N6 | Résumé du matin | **Fait** : le résumé de 9 h commence par « Aujourd'hui » (À faire, À relancer, À venir, 28/10) ; courrier sur les trois Hubs (pastille « 📧 N mails à traiter », 28/10) |
| N7 | Boîte pro | **Bloqué** : accord d'Alexandre et de la DSI de Barrière |

## Ce qui a remplacé N4 et N5 dans Aiguillage : l'app Courrier

Décision du 26/10 : plutôt qu'une section « Courrier » dans Aiguillage, un **client mail léger** à part, `../courrier`
(iPhone, iPad, Mac ; TestFlight par Xcode Cloud), branché sur le tri du NUC par l'espace `courrier` de
`donnees_apps` : résumés et urgence, « Plus tard », corrections de classement, notifications APNs directes, pastille
de l'icône, fiche de l'expéditeur (mémo d'Aiguillage, `memo_uid` depuis le 29/10), tâches 📧 vers Aiguillage et liens
`relance://`. **Refonte façon Dove** branchée le 29/10 (dossiers et recherche Gmail, carte « Aujourd'hui »,
« Demander à l'IA » relié à `aiguillage_agent` : brouillons Gmail, actions à confirmer, agenda du jour) ; **pièces
jointes vers Google Drive** le 29/10 au soir (proposition de l'IA, « Enregistrer » d'Alexandre, dépôt par le NUC,
module `aiguillage_drive`, décision 80 de Courrier).

Règle permanente (décision d'Alexandre du 24/10, imposée par le code) : **aucun envoi, archivage ni suppression de
mail sans son geste explicite pour ce mail** ; brouillons permis.

## Reste ouvert

1. **Un seul consentement Google pour l'agenda et Drive** à donner par Alexandre : APIs Google Calendar et Google
   Drive à activer dans le projet « Relance », portées `calendar.readonly` et `drive` à ajouter à l'écran de
   consentement, puis `uv run homeassistant/scripts/courrier_autoriser.py <JSON client> --tout` (Gmail + agenda +
   Drive ; le jeton est relu par le NUC sans redémarrage). D'ici là, Programme de Courrier sans l'agenda, et
   « Demander à l'IA » répond qu'il faut l'accord pour Drive sans rien proposer.
2. **Coût de l'IA** à suivre : tri (budget 15 $/mois), agent (5 $), « Aujourd'hui » (6 $, choisi par Alexandre le 28/10,
   `aujourdhui_budget_mensuel: 6` sur le NUC).
3. **Qualité d'« Aujourd'hui »** à juger à l'usage (lignes justes, relances utiles, lignes masquées respectées).
4. Essais sur les appareils notés dans `SUIVI.md` (N2) et `../courrier/docs/STATUT.md` (Courrier).
