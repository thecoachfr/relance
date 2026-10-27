# Contrat du capteur `sensor.hub_pour_info` (26/10/2026) — rappels « pour info » des trois vues du Hub

Plan : `plans/P9-P-pour-info.md` (lot P3). Calculé par l'app AppDaemon `hub_pour_info` (dépôt Rappels, à côté de la
vigie). Les vues (Hub TV, Hub iPad/iPhone, Nest Hub) ne font QUE l'afficher : aucun calcul de répétition dans les vues.
Rafraîchi à chaque modification de l'espace `aiguillage` de `donnees_apps` (3 s après) et toutes les 10 min (le
changement de jour à minuit compris).

Un rappel « pour info » est une tâche d'Aiguillage dont les notes ont la ligne `📣 Pour info` : il signale (femme de
ménage, poubelles…), ne demande rien, n'a ni heure ni « Fait », et disparaît le lendemain.

État : nombre d'infos du jour (entier, 0 s'il n'y en a pas).

Attributs :
- `maj` : ISO 8601, heure du calcul.
- `jour` : `AAAA-MM-JJ`, le jour des infos.
- `infos` : infos du jour, triées par titre : [{ `cle` (clé de la tâche dans `donnees_apps`), `titre` }].
- `texte` : les titres du jour joints par « · » (« Femme de ménage · Poubelles »), ou null.
- `a_venir` : la prochaine occurrence de chaque info dans les 7 jours suivants : [{ `cle`, `titre`, `jour` }], triée
  par jour. Les vues ne l'affichent pas pour l'instant.

Notification : à l'heure du résumé du matin (7 h 30, `heure_resume` dans `apps.yaml`), s'il y a des infos,
`script.hub_notifier` avec `texte` « Pour info : Femme de ménage, Poubelles », `titre` « Aiguillage », `niveau` info.

## Règles d'affichage communes (« Mêmes boutons, même ordre »)

1. **Les infos ne sont pas des tâches.** Toute tâche dont les notes ont une ligne commençant par `📣` (sélecteur de
   variante U+FE0F ignoré) est retirée des listes de tâches des vues (À faire, accueil, compteur « N à faire »,
   tâche en tête), comme les envies `👀`. Jamais de case à cocher pour elles.
2. **Bloc « Pour info »** en tête de la section **À faire**, avant les tâches (et après la phrase du lieu de travail
   si la vue l'affiche) : titre « Pour info », puis une ligne par élément de `infos` : icône mégaphone
   (mdi:bullhorn / SF `megaphone` / équivalent Compose), le titre, en couleur secondaire. Rien à toucher (pas
   d'action au toucher / OK). Rien du tout si `infos` est vide ou si le capteur est absent.
3. **Accueil** : rien de plus (la notification du matin suffit).

## Mise en œuvre : app AppDaemon `hub_pour_info`

Code : `homeassistant/appdaemon/apps/hub_pour_info.py` (fonctions pures, portage de `Recurrence.swift`, puis la
classe `HubPourInfo`) ; tests : `homeassistant/appdaemon/tests/test_hub_pour_info.py` (mêmes cas que les tests Swift
de la récurrence). Déployée le 27/10/2026 vers 7 h 08 (capteur publié, 0 info ce jour-là). Déploiement : copier `hub_pour_info.py` dans `/Volumes/addon_configs/a0d7b954_appdaemon/apps/`
et ajouter le bloc à `apps.yaml` (sauvegarde d'avant : `apps.yaml.avant-pour-info-20261026`, à la racine du dossier) :

```yaml
hub_pour_info:
  module: hub_pour_info
  class: HubPourInfo
  heure_resume: "07:30"
```
