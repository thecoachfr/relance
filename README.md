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
| `Relance/Reminders/ReminderPlanner.swift` | Règles des relances (fonction pure, testée) |
| `Relance/Reminders/ReminderScheduler.swift` | Traduction en notifications iOS, boutons d'action |
| `Relance/Google/` | Connexion Google, API REST Tasks, heure rangée dans les notes |
| `Relance/Model/` | Cache local SwiftData et synchronisation |
| `Relance/Views/` | Écrans SwiftUI |
| `RelanceTests/` | Tests (Swift Testing) |
