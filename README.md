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
par le paquet Swift `DonneesHA` (dépôt privé `thecoachfr/ha-donnees-apps`, étiquette `0.1.0`). Hors connexion,
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
`relance_vigie.py` dans `a0d7b954_appdaemon/apps/` (AppDaemon la recharge seul).

Audit de batterie (plan P9-E) : la vigie compte les pushs envoyés par jour et par cause dans
`/config/relance_push_stats.json` de l'add-on, et l'app iPhone et iPad garde les rapports MetricKit
(Réglages › Diagnostic batterie). Voir [docs/BATTERIE.md](docs/BATTERIE.md).

Avec les tâches dans Home Assistant (`ha_espace: aiguillage` et `inbox: true` dans `apps.yaml`, à activer **après** la
migration de l'app) : push à chaque événement `donnees_apps_modifie` de l'espace, liste Google vidée dans Home
Assistant à chaque rafraîchissement (état dans `/config/relance_inbox.json`), et routine de tri lancée dès qu'une
nouvelle tâche apparaît dans l'espace (créée dans l'app ou reprise de Google). La routine lit et écrit elle-même
l'espace `aiguillage` (`donnees_apps.lire` / `ecrire`). La vigie appelle `donnees_apps` par l'API interne de Home Assistant (jeton de l'add-on).

Déjà en place sur Home Assistant : l'app **AppDaemon** (avec `httpx[http2]` et `pyjwt[crypto]`)
et l'automatisation **« Relance : enregistrer un appareil »** (déclencheur webhook).

Reste à faire :

1. **Clé APNs** : developer.apple.com → Keys → + → « Apple Push Notifications service (APNs) »,
   Sandbox & Production. Télécharger le `.p8`, noter le Key ID.
2. **Identifiant Google « Web »** (Google Cloud, projet Relance → Clients → Créer → Application Web),
   URI de redirection `https://my.home-assistant.io/redirect/oauth`.
3. **Intégration Google Tasks** dans HA (Paramètres → Appareils et services → Ajouter → Google Tasks),
   avec l'ID et le secret de l'étape 2. Noter l'entité créée pour « Mes tâches ».
4. **AppDaemon** : copier `homeassistant/appdaemon/apps/relance_vigie.py` et le contenu de `apps.yaml`
   dans `/addon_configs/a0d7b954_appdaemon/apps/`, y déposer le `.p8` sous le nom `AuthKey_relance.p8`,
   puis renseigner `key_id` et `todo_entity`.
5. **URL du webhook** : ouvrir l'automatisation « Relance : enregistrer un appareil », copier l'URL
   du déclencheur webhook (lien Home Assistant Cloud), et la mettre dans `RELANCE_WEBHOOK_URL`
   de `Secrets.xcconfig` (en écrivant `https:/$()/` au lieu de `https://`). Recompiler l'app.
