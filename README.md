# Aiguillage

*Anciennement « Relance ». Le code, les cibles Xcode, l'identifiant `fr.alexandrefau.relance` et les noms côté Home Assistant gardent l'ancien nom.*

App iPhone, iPad, Apple Watch et Mac qui aiguille les tâches (à faire, à trier, à voir) et insiste jusqu'à ce que ce soit fait, branchée sur Google Tasks, et bientôt sur Home Assistant (voir « Tâches dans Home Assistant »).
Voir [CADRAGE.md](CADRAGE.md) pour le besoin et les choix, [SUIVI.md](SUIVI.md) pour l'état du projet.

## Mise en route

### 1. Accès Google Tasks (une seule fois)

Sur [console.cloud.google.com](https://console.cloud.google.com), avec ton compte Google :

1. **Créer un projet** nommé « Relance ».
2. **API et services → Bibliothèque** : chercher « Google Tasks API » → **Activer**.
3. **Google Auth Platform** (écran de consentement OAuth) :
   - *Branding* : nom « Aiguillage », ton e-mail comme adresse d'assistance et de contact.
   - *Audience* : type **Externe**.
   - *Accès aux données* : ajouter le champ d'application `https://www.googleapis.com/auth/tasks`.
   - *Audience* → **Publier l'application** (statut « En production »). Sinon Google coupe la connexion tous les 7 jours. Pas besoin de demander la validation Google : tu verras juste un écran « application non vérifiée » à la première connexion (Paramètres avancés → Accéder à Relance).
4. **Clients → Créer un client** : type **iOS**, ID du bundle `fr.alexandrefau.relance`.
5. Copier l'**ID client** et le **schéma d'URL iOS** dans `Relance/Resources/Secrets.xcconfig` :

```
GOOGLE_CLIENT_ID = 1234567890-abcdef.apps.googleusercontent.com
GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.1234567890-abcdef
```

Ce fichier n'est pas versionné (`.gitignore`).

### 2. Générer et lancer

```bash
xcodegen generate
```

Puis ouvrir `Relance.xcodeproj`, choisir ton iPhone et lancer (⌘R). Schéma `RelanceMac` pour l'app Mac (macOS 15),
`RelanceWatch` pour la montre.

### 3. Tâches dans Home Assistant (en essai, désactivé par défaut)

Les tâches peuvent quitter Google Tasks pour l'intégration `donnees_apps` de Home Assistant (espace `aiguillage`),
par le paquet Swift `DonneesHA` (dépôt privé `thecoachfr/ha-donnees-apps`, étiquette `0.2.0`, avec la fusion des conflits pour les listes d'articles). Hors connexion,
les écritures restent sur l'appareil et une copie part dans iCloud (conteneur `iCloud.fr.alexandrefau.relance`) ;
tout repart vers Home Assistant dès qu'il répond, la modification la plus récente gagnant en cas de conflit.

Sur chaque appareil (iPhone, iPad, Mac) : **Réglages › Home Assistant** :

1. Adresse de Home Assistant (URL Nabu Casa) et jeton de l'utilisateur non administrateur `apps-perso`
   (ils restent sur l'appareil : App Group et trousseau, jamais dans ce dépôt public).
2. **Enregistrer et tester**, puis **Passer les tâches dans Home Assistant** : une dernière synchro Google,
   puis toutes les tâches de l'appareil partent dans Home Assistant (avec leur identifiant Google).
3. « Revenir à Google Tasks » renvoie les tâches de l'appareil dans Google en cas de souci.

Format des tâches (`Shared/HA/TacheHA.swift`) : version 2 dès qu'une tâche a un **lieu** (plans P9, `plans/`) :
`lieu = {nom, adresse, telephone, lat, lon, lien, source}`, tous facultatifs sauf `nom`. Le champ fait foi ; la ligne `📍`
des notes en est une copie, toujours écrite, pour la vigie, la routine de tri, l'écran du Nest Hub et le mode Google.
Un lieu sans adresse (photo, point GPS) a pour ligne `📍 Nom · https://maps.apple.com/?ll=lat,lon&q=Nom`.
Les envies ont aussi leur champ `envie = {type, note, plateforme, id_titre, lien, …}` (version 2 ; champs inconnus gardés) ; leur ligne reste écrite : `👀 À voir`, `🎟 Sortie` (sortie réservée : la seule envie datée, par l'échéance de la tâche, P9-L1), `🍽 À tester`, `🛍 Magasin`, `📷 Spot photo · note`, `📖 À lire`, `🎧 À écouter`, `🎬 À regarder`.

Google Tasks n'est plus que la **boîte d'entrée** des dictées Google Home (la vigie les reprend dans Home Assistant, puis
les retire de Google). Le **mémo** de la routine de tri est dans Home Assistant depuis le 15/10 : liste Local To-do
« Aiguillage · mémo » (`todo.aiguillage_memo`), qu'on modifie aussi dans Home Assistant (panneau **Listes de tâches**, titre
= sujet, description = détails). La montre y écrit directement (URL et jeton transmis par l'iPhone).
La montre passe alors par l'iPhone pour les tâches ; l'extension de partage écrit dans la base locale partagée.

## Déploiement automatique (Xcode Cloud + TestFlight)

Chaque push sur `main` compile l'app dans le cloud d'Apple et l'envoie sur TestFlight :
iPhone, iPad, montre (incluse dans l'app iPhone) et Mac se mettent à jour depuis l'app TestFlight.

- `ci_scripts/ci_post_clone.sh` recrée `Secrets.xcconfig` (absent du dépôt public) et donne
  le numéro de build de Xcode Cloud à l'app et à toutes ses extensions, et le commit compilé (clé `AiguillageCommit`,
  affichée dans Réglages › À propos, sur le Mac et sur la montre).
- `ci_scripts/signaler_build.sh` (appelé au début du build et par `ci_post_xcodebuild.sh` après chaque archive) signale
  « build N = commit X, étape » au webhook de l'app (`action: build`) ; la vigie garde la correspondance dans
  `relance_builds.json` (add-on AppDaemon), pour savoir quel build TestFlight contient quelle modification.
- Variables du workflow (Xcode › Cloud › Workflow › Environnement), toutes **secrètes** :
  `GOOGLE_CLIENT_ID`, `RELANCE_WEBHOOK_URL` (URL complète, avec `https://`). Le schéma d'URL Google
  (`GOOGLE_REVERSED_CLIENT_ID`) est déduit de l'ID client par le script ; une variable de ce nom est ignorée.
- Workflow iOS : déclencheur « push sur main », action « Archiver » schéma `Relance` (iOS),
  post-action « TestFlight (test interne) ». Workflow Mac : idem avec le schéma `RelanceMac`.
- Les builds TestFlight utilisent les notifications push de production : l'app l'annonce
  au webhook (`environment: production`) et la vigie choisit le bon serveur APNs.
- L'installation directe (Xcode ou `devicectl`) reste possible pour essayer une correction sur le moment.
- Le paquet `DonneesHA` vient d'un dépôt **privé** : Xcode Cloud doit avoir reçu l'accès à `thecoachfr/ha-donnees-apps`
  (App Store Connect › Xcode Cloud › Réglages › Dépôts, ou Xcode le propose au premier build qui échoue).

## Organisation du code

| Dossier | Rôle |
|---|---|
| `Shared/Reminders/ReminderPlanner.swift` | Règles des relances (fonction pure, testée) |
| `Shared/Reminders/ReminderScheduler.swift` | Traduction en notifications iOS, boutons d'action |
| `Shared/Google/` | API REST Google Tasks, heure rangée dans les notes |
| `Shared/Model/` | Cache local SwiftData (App Group) et synchronisation (`TaskStore+HA.swift` : Home Assistant) |
| `Shared/HA/` | Réglages Home Assistant (URL, jeton, appareil) et format JSON d'une tâche (`TacheHA`) |
| `Shared/Intents/` | Actions Siri, widgets et activité en direct |
| `Relance/` | App iPhone/iPad : connexion Google, écrans SwiftUI, activité en direct, push |
| `RelanceMac/` | App Mac native : fenêtre en trois colonnes, barre des menus, menus et raccourcis (reprend `Shared/` et les vues de tâche de `Relance/Views/`) |
| `RelanceWidgets/` | Widgets, activité en direct, commande « Nouvelle tâche » |
| `RelanceShare/` | Extension de partage (WhatsApp, Mail, Safari…) |
| `RelanceWatch/`, `RelanceWatchWidgets/` | App et complications Apple Watch |
| `homeassistant/` | Vigie AppDaemon (phase 3) : push, tri, boîte d'entrée Google → Home Assistant |
| `RelanceTests/` | Tests (Swift Testing) |

## Vigie Home Assistant (phase 3)

La vigie réveille l'app dès qu'une tâche est dictée à Google Home ou cochée ailleurs.

```
Google Tasks ──(1 min)── HA : intégration Google Tasks ── AppDaemon relance_vigie ──APNs──► Relance
                                                              ▲
Relance ──(jeton push)──► webhook HA ──► événement relance_register ┘
```

Sans tâches dans HA, elle rafraîchit aussi la liste Google du mémo (`todo.relance_memo`) ; elle lance la routine après chaque nouvelle tâche
et à la demande de l'app (« Retrier avec Claude », champ `action: triage` du webhook).
Pour la mettre à jour : monter le partage `smb://homeassistant.local/addon_configs` dans le Finder et copier
`relance_vigie.py` et les modules `aiguillage_*.py` dans `a0d7b954_appdaemon/apps/` (AppDaemon la recharge seul).
Tests des modules : `python3 -m pytest homeassistant/appdaemon/tests`.

Actions des tâches (plan P9-D) : la vigie applique les recettes (`config:recettes`), exécute les actions
`executant: ha` (playlist Spotify « À écouter »), lance la routine « Aiguillage · actions » pour les actions
`preparer` ([docs/ROUTINE-ACTIONS.md](docs/ROUTINE-ACTIONS.md)) et envoie une notification visible aux iPhone quand
une action échoue ou qu'une préparation est prête. Présence (plan P9-F) : rappels « à la maison »
(`presence_entity`, `domicile_entity`) et « dans une pièce » (`piece_entity`, pièce dominante sur 2 minutes,
liste des pièces publiée dans `config:pieces`). Clés d'exemple : `homeassistant/appdaemon/apps/apps.yaml`.

Radios (22/10) : une envie À écouter de plateforme `tunein` (« Radio Tsugi », rangée par le tri) est cherchée sur
TuneIn par Music Assistant (`aiguillage_radio.py`, réglage `music_assistant_entry`), ajoutée à `config:radios` et la
tâche cochée ; la liste est publiée dans `sensor.aiguillage_radios` pour le Hub, qui la lance par `script.nest_hub_radio`
(`station` = id, `uri`). Essai à la main : événement `aiguillage_radio_pass`.

Activité en direct du Hub iPad (23/10) : « En lecture sur les LS50 » sur l'écran verrouillé de l'iPad
(`../hub-ipad`). Module `aiguillage_lecteur.py` (choix de l'entité : Music Assistant `media_player.salon_ls50_5` s'il
joue ou est en pause, sinon l'enceinte KEF ; `content-state`, décision start / update / end, jetons ; tests
`tests/test_aiguillage_lecteur.py`). L'app envoie ses jetons par `script.hub_ipad_activite` (événement
`hub_ipad_activite` ; un utilisateur non administrateur ne peut pas émettre d'événement par REST), rangés dans
`/config/hub_ipad_activite.json`. Lecture qui démarre sans activité : push-to-start (APNs `liveactivity`, sujet
`fr.alexandrefau.hubipad.push-type.liveactivity`, même clé `.p8` et même JWT que pour Aiguillage) ; changement de
titre, d'état ou de volume : `update` (2 s d'anti-rafale, priorité 10 si le titre change, sinon 5) ; plus rien ne joue
depuis 5 min : `end`. Réglage `ha_url` (adresse locale de HA, pour les pochettes relatives).

Tri par l'API Messages (plan P9-I, [plans/P9-I-tri-par-api.md](plans/P9-I-tri-par-api.md)) : réglage `tri_mode`
(`routine` par défaut, `ombre`, `api`). Module `aiguillage_tri.py` : la vigie choisit les tâches à trier, fait **un**
appel à sortie structurée (Sonnet 5.5, sans outil), puis applique elle-même les changements avec les règles absolues
(champs seulement si absents, notes existantes intactes, listes jamais cochées). En mode `ombre`, la routine trie
comme avant et les propositions de l'API vont dans `/config/aiguillage_tri_ombre.jsonl` ; en mode `api`, la routine
ne sert plus qu'en secours (erreur, refus, budget `tri_budget_mensuel` atteint). Clé API Console dans
`/config/anthropic_api_key`, consigne dans `/config/aiguillage_tri_consigne.md` (hors dépôt, modèle dans
[docs/TRI-CONSIGNE.md](docs/TRI-CONSIGNE.md)), état et coût du mois dans `/config/aiguillage_tri_etat.json`.

Mémoire des échanges Signal (plan P9-J) : `aiguillage_memoire.py`, branché dans l'app `aiguillage_signal` (capture,
résumés la nuit, purges, recherche par l'événement `aiguillage_memoire_chercher`). Mode d'emploi :
[docs/MEMOIRE-SIGNAL.md](docs/MEMOIRE-SIGNAL.md).

Historique des trajets (plan P9-M) : app AppDaemon `aiguillage_trajets` (`aiguillage_trajets.py`), base
`/config/aiguillage_trajets.sqlite` : points GPS de l'app Compagnon (gardés au-delà des 10 jours du recorder) et arrêts
relevés par l'app (Réglages › Mes trajets), envoyés au webhook avec `action: trajets`. Détail : [plans/P9-M-trajets.md](plans/P9-M-trajets.md).

Pièces jointes (plan P9-K) : les fichiers d'une tâche (photo, PDF, scan) sont rangés dans Home Assistant par
l'API `fichiers` de `ha-donnees-apps` 0.3.0 (`/api/donnees_apps/fichiers/aiguillage`, même jeton) ; la tâche garde leurs
métadonnées et le début du texte lu sur l'appareil (champ `pieces`), que la routine de tri utilise.

« Sur la TV » (plan P9-B4) : le bouton de la fiche d'une envie appelle le script HA `script.aiguillage_sur_tv`
(champ `lien`), qui allume le Freebox Player Pop si besoin et ouvre le lien (`remote.turn_on`, `activity`). Formes de
liens par plateforme : [docs/LIENS-TV.md](docs/LIENS-TV.md).

Audit de batterie (plan P9-E) : la vigie compte les pushs envoyés par jour et par cause dans
`/config/relance_push_stats.json` de l'add-on, et l'app iPhone et iPad garde les rapports MetricKit
(Réglages › Diagnostic batterie). Voir [docs/BATTERIE.md](docs/BATTERIE.md).

Avec les tâches dans Home Assistant (`ha_espace: aiguillage` et `inbox: true` dans `apps.yaml`, à activer **après** la
migration de l'app) : push à chaque événement `donnees_apps_modifie` de l'espace, liste Google vidée dans Home
Assistant à chaque rafraîchissement (état dans `/config/relance_inbox.json`), et routine de tri lancée dès qu'une
nouvelle tâche apparaît dans l'espace (créée dans l'app ou reprise de Google). La routine lit et écrit elle-même
l'espace `aiguillage` (`donnees_apps.lire` / `ecrire`). La vigie appelle `donnees_apps` par l'API interne de Home Assistant (jeton de l'add-on).

Déjà en place sur Home Assistant : l'app **AppDaemon** (avec `httpx[http2]`, `pyjwt[crypto]` et `anthropic`)
et l'automatisation **« Relance : enregistrer un appareil »** (déclencheur webhook).

Reste à faire :

1. **Clé APNs** : developer.apple.com → Keys → + → « Apple Push Notifications service (APNs) »,
   Sandbox & Production. Télécharger le `.p8`, noter le Key ID.
2. **Identifiant Google « Web »** (Google Cloud, projet Relance → Clients → Créer → Application Web),
   URI de redirection `https://my.home-assistant.io/redirect/oauth`.
3. **Intégration Google Tasks** dans HA (Paramètres → Appareils et services → Ajouter → Google Tasks),
   avec l'ID et le secret de l'étape 2. Noter l'entité créée pour « Mes tâches ».
4. **AppDaemon** : copier `homeassistant/appdaemon/apps/relance_vigie.py`, les modules `aiguillage_*.py` et le contenu de `apps.yaml`
   dans `/addon_configs/a0d7b954_appdaemon/apps/`, y déposer le `.p8` sous le nom `AuthKey_relance.p8`,
   puis renseigner `key_id` et `todo_entity`.
5. **URL du webhook** : ouvrir l'automatisation « Relance : enregistrer un appareil », copier l'URL
   du déclencheur webhook (lien Home Assistant Cloud), et la mettre dans `RELANCE_WEBHOOK_URL`
   de `Secrets.xcconfig` (en écrivant `https:/$()/` au lieu de `https://`). Recompiler l'app.
