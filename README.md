# Relance

App iOS/iPadOS de rappels qui insistent jusqu'à ce que ce soit fait, branchée sur Google Tasks.
Voir [CADRAGE.md](CADRAGE.md) pour le besoin et les choix.

## Mise en route

### 1. Accès Google Tasks (une seule fois)

Sur [console.cloud.google.com](https://console.cloud.google.com), avec ton compte Google :

1. **Créer un projet** nommé « Relance ».
2. **API et services → Bibliothèque** : chercher « Google Tasks API » → **Activer**.
3. **Google Auth Platform** (écran de consentement OAuth) :
   - *Branding* : nom « Relance », ton e-mail comme adresse d'assistance et de contact.
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

Puis ouvrir `Relance.xcodeproj`, choisir ton iPhone et lancer (⌘R).

## Organisation du code

| Dossier | Rôle |
|---|---|
| `Shared/Reminders/ReminderPlanner.swift` | Règles des relances (fonction pure, testée) |
| `Shared/Reminders/ReminderScheduler.swift` | Traduction en notifications iOS, boutons d'action |
| `Shared/Google/` | API REST Google Tasks, heure rangée dans les notes |
| `Shared/Model/` | Cache local SwiftData (App Group) et synchronisation |
| `Shared/Intents/` | Actions Siri, widgets et activité en direct |
| `Relance/` | App : connexion Google, écrans SwiftUI, activité en direct, push |
| `RelanceWidgets/` | Widgets, activité en direct, commande « Nouvelle tâche » |
| `homeassistant/` | Vigie AppDaemon (phase 3) |
| `RelanceTests/` | Tests (Swift Testing) |

## Vigie Home Assistant (phase 3)

La vigie réveille l'app dès qu'une tâche est dictée à Google Home ou cochée ailleurs.

```
Google Tasks ──(1 min)── HA : intégration Google Tasks ── AppDaemon relance_vigie ──APNs──► Relance
                                                              ▲
Relance ──(jeton push)──► webhook HA ──► événement relance_register ┘
```

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
