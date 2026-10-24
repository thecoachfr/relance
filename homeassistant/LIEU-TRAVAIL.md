# Contrat du capteur `sensor.aiguillage_lieu_travail` (24/10/2026) — bureau ou télétravail

Calculé par l'app AppDaemon `aiguillage_lieu_travail` (plan `plans/P9-N-courrier.md`, lot N1). Aiguillage (iPhone,
iPad, Mac, montre) et les trois vues du Hub (Hub TV, Nest Hub, Hub iPad) **ne font qu'afficher ce capteur** : ils ne
recalculent rien et emploient les mêmes mots (`libelle`, `phrase`).

## Pourquoi pas l'agenda pro

Agenda Google Workspace de Barrière : partage des détails interdit par l'administrateur, Apps Script désactivé ; le
compte pro ajouté au Calendrier d'iOS montre les événements mais pas le « lieu de travail » (constaté le 24/10).

## Sources, de la plus forte à la plus faible

1. **Position** : l'iPhone (`device_tracker.iphone_17_lex`) à moins de 300 m (plus la précision GPS, plafonnée à
   300 m) d'un lieu du groupe « Travail » de Mes lieux (`config:lieux`) → `bureau` (33 rue d'Artois) ou `lab` (lieu
   dont le nom contient « Lab » : Le Lab, Saint-Ouen, moins d'une fois par mois, à ajouter dans Mes lieux) pour la
   journée ; le Lab l'emporte si les deux sont vus. À 16 h : un jour travaillé où il était à la maison à 11 h et à 15 h, sans passer au bureau → `teletravail`.
2. **Exception** (`config:lieu_travail` › `exceptions`, `{"AAAA-MM-JJ": "bureau" | "lab" | "teletravail" | "off"}`), dite :
   - sur Signal, « Note à moi-même », message fait seulement d'un jour et d'un lieu : « demain télétravail »,
     « mercredi je suis au bureau », « le 6/11 congé », « vendredi 7 bureau », « congé du 2/11 au 6/11 »,
     « jeudi au Lab », « le 5/11 à Saint-Ouen », « lundi normal » (annule). Réponse « ✅ Mardi 27/10 : 🏢 Bureau (au lieu de 🏠 Télétravail) ». Tout autre
     message est ignoré ;
   - depuis Aiguillage (lot N2, 24/10) : écran « Lieu de travail » (Réglages, ou toucher le bandeau de « À faire »),
     un toucher par jour (Bureau / Le Lab / Télétravail / Pas Barrière, ou « Comme prévu » qui retire l'exception) ;
     la semaine type (`lieu`, `certitude` `sur` ou `probable`) et `premier_vendredi` (`null` = comme la semaine type)
     se règlent au même endroit. L'app écrit par la synchro de `donnees_apps` (version attendue) en partant de la
     valeur lue : elle garde les champs qu'elle ne connaît pas ; un conflit (consigne Signal au même moment) est
     réglé en réappliquant sa modification sur la valeur de HA. Une consigne Signal garde aussi les champs de premier
     niveau inconnus.
3. **Semaine type** (`config:lieu_travail` › `semaine`) : lundi bureau (sûr), mardi télétravail, mercredi bureau
   (probable, 70 %), jeudi télétravail, vendredi `off` (4/5) ; `premier_vendredi` du mois : bureau (sûr, confirmé le 24/10) ;
   samedi, dimanche, jours fériés de métropole : `off` / `ferie`.

## État et attributs

- **État** : lieu du jour, `bureau` | `lab` | `teletravail` | `off` (pas un jour Barrière) | `ferie`.
- `aujourdhui`, `demain`, `jours` (14 jours à partir d'aujourd'hui) : `{date, jour, lieu, certitude, source, libelle}`,
  plus `prevu` quand la position a contredit la prévision.
  - `certitude` : `sur`, `probable` (le libellé finit par « ? »), `constate` (position).
  - `source` : `semaine`, `premier_vendredi`, `exception`, `ferie`, `position`.
  - `libelle` : « 🏢 Bureau », « 🏢 Bureau ? », « 🧪 Le Lab », « 🏠 Télétravail », « Pas Barrière », « Férié ».
- `phrase` : en-tête prêt à afficher, par exemple « 🏢 Bureau aujourd'hui · demain 🏠 Télétravail » ou « Pas de
  Barrière aujourd'hui · lundi 🏢 Bureau ».
- `stats` : par jour ouvré, constats des 8 dernières semaines `{bureau, teletravail}`.
- `suggestion` : une phrase quand la semaine type contredit au moins 75 % de 4 constats ou plus (« Le mercredi, tu
  étais en télétravail 4 fois sur 4 : passer le mercredi en Télétravail ? »), sinon `null`.
- `bureau` : les points « Travail » utilisés `{nom, lat, lon, lieu}` ; `maj`.

Recalcul toutes les 15 min, à minuit, à chaque passage au bureau, à chaque consigne, à chaque écriture de
`config:lieu_travail` ou de `config:lieux` (événement `donnees_apps_modifie` de l'intégration, depuis le 24/10 :
recalcul en moins d'une seconde, mesuré), et sur l'événement
`aiguillage_lieu_travail_maj`. Publication par l'API REST de HA (comme `sensor.hub_meteo`).

## Lecteurs (N2, 24/10)

- **Aiguillage** (iPhone, iPad, Mac) : bandeau `phrase` en tête de « À faire » (caché en mode Google Tasks ou si le
  capteur manque) ; lecture `GET /api/states/sensor.aiguillage_lieu_travail` (jeton `apps-perso`) à la fin d'une
  synchro, au plus une fois par quart d'heure, et juste après un réglage ; copie dans l'App Group.
- **Montre** : libellé du jour (`jours[].libelle`, jours travaillés seulement) en tête de la liste, reçu de l'iPhone
  avec l'état (aucune requête de la montre).
- **Tri et vigie** : `jours` sert à dater une tâche sans date qui reçoit un `contexte` (`aiguillage_tri.jour_pour_contexte`).

## Mise en œuvre (déployée le 24/10/2026 vers 11 h 47)

- Code : `homeassistant/appdaemon/apps/aiguillage_lieu_travail.py` ; tests :
  `homeassistant/appdaemon/tests/test_aiguillage_lieu_travail.py`.
- `aiguillage_signal` transmet chaque « Note à moi-même » sans lien par l'événement
  `aiguillage_lieu_travail_message` `{texte}` ; la réponse part par `POST /v2/send` de l'add-on Signal.
- Constats et échantillons du jour : `/config/aiguillage_lieu_travail.json` (120 jours).
- Déploiement : copier le module dans `/Volumes/addon_configs/a0d7b954_appdaemon/apps/`, bloc
  `aiguillage_lieu_travail` dans `apps.yaml` (sauvegardes d'avant : `apps.yaml.avant-lieu-travail-20261024`,
  `aiguillage_signal.py.avant-lieu-travail-20261024`, à la racine du dossier).
