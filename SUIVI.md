# Relance — suivi du projet

*Mis à jour le 12 octobre 2026. Point de départ pour reprendre le projet dans une nouvelle conversation.*
*Besoin et choix de départ : [CADRAGE.md](CADRAGE.md). Installation : [README.md](README.md).*

## 1. Où on en est

### Ce qui marche (testé sur les appareils)

| Brique | État |
|---|---|
| **App iPhone** | Relances qui insistent (à l'heure, +1 h, 20 h ; en retard 7 h 30 et 20 h ; silence 22 h–7 h 30), boutons Fait / Dans 1 h / Ce soir / Demain matin, activité en direct (3 tâches max, Fait / 1 h par tâche), widgets accueil et écran verrouillé, commande « + » (Centre de contrôle, bouton Action, écran verrouillé), Siri (« nouvelle Relance », « Relance en retard »), écran À trier une tâche à la fois, catégories, journal de synchro dans les réglages |
| **App iPad** | Liste + détail, raccourcis clavier (↑↓, ⌘↩, ⌘L, ⌘⌫, ⌘R, ⌘N), pas de relances par défaut (réglage « Relances sur cet appareil ») |
| **App Mac** | L'app iPad « Designed for iPad », lancée depuis Xcode (⌘R) |
| **Apple Watch** | Liste, cocher, reporter, dictée, complication ; l'iPhone sert de relais |
| **Vigie Home Assistant** | AppDaemon rafraîchit Google Tasks chaque minute ; si le nombre de tâches change → push silencieux à l'iPhone et l'iPad (testé : push reçu et synchro en 1 s) |
| **Tri par Claude** | Routine cloud « Relance · tri » : catégorie (🏷), date/heure si explicites (⏰), sinon suggestion (💡). Tous les jours à 6 h 45 **et** 90 s après chaque nouvelle tâche (lancée par la vigie, max 20/jour). Testé le 12/10 |
| **Logo** | « Boucle » (flèche circulaire + coche, orange), variantes sombre / teintée / montre |

### Conventions dans les notes Google Tasks
Google Tasks n'a ni heure (dans son API) ni étiquettes : en tête des notes, dans cet ordre :
```
⏰ 15:00
🏷 Administratif
Notes libres…
💡 Suggestion : … (ajoutée par le tri)
```
Catégories fixes : Administratif, Maison, Santé, Achats, Travail, Famille, Perso (`Shared/Model/TaskCategory.swift` et prompt de la routine).

### Limites connues
- **Google Home ne transmet pas l'heure** d'un rappel dicté (limite de l'API Google). Contournement : dire l'heure dans le titre (« ajoute appeler le garage vendredi à 15 h à ma liste de tâches ») → le tri la met en ⏰.
- La vigie ne détecte que les **changements du nombre** de tâches (ajout, coche), pas les modifications de date d'une tâche existante.
- iOS ne livre pas les push silencieux si l'app a été **fermée de force** (balayée dans le sélecteur).
- L'activité en direct ne peut **démarrer** qu'app ouverte (elle se met ensuite à jour seule).
- Applis installées en **développement** (Xcode) : à réinstaller quand le profil de développement expire (environ 1 an) ; APNs en environnement « sandbox ».

## 2. Reste à faire / à vérifier

1. **Montre autonome (eSIM)** — codée et installée, **pas encore testée** : couper l'iPhone (mode Avion), ouvrir Relance sur la montre, tirer la liste (« Mis à jour à l'instant »), cocher une tâche, rallumer l'iPhone et vérifier qu'elle est cochée là aussi.
2. **Catégories dans l'app** : vérifier que les étiquettes apparaissent sur l'iPhone et l'iPad après le tri du 12/10.
3. **Tâches de test** à cocher : « [test] appeler le garage… », « [test] renouveler le passeport », « [test] envoyer le dossier ».
4. **Premier tri automatique du matin** : demain 6 h 45 (vérifier dans [la routine](https://claude.ai/code/routines/trig_01GFD6vBExCUvTYDbx9KePm7)).
5. **Décision en attente** : autoriser la routine à **nettoyer le titre** (retirer « vendredi à 15 h » une fois la date et l'heure rangées) ?
6. Catégories pas encore affichées dans le **widget** ni sur la **montre**.

## 3. Idées et pistes (non faites)

### Assistance par Claude dans l'app (« option 1 »)
- Boutons **« Suggérer »** (dans À trier : date, heure, titre propre) et **« M'aider »** (dans le détail : étapes, brouillon de message, recherche web).
- Passerelle conseillée : **Home Assistant** (intégration Anthropic + service *AI Task* aux réponses structurées), la clé API reste chez HA.
- Modèles : Haiku 5.5 pour Suggérer, Sonnet 5.5 pour M'aider, recherche web à la demande.
- Coût estimé : **≈ 1 à 4 $/mois** (Haiku 0,10 $ / 0,50 $ par million de jetons ; Sonnet 2 $ / 10 $ ; recherche web 10 $ / 1 000). Plafond conseillé : 10 $/mois. Nécessite une clé API Anthropic (facturation séparée de l'abonnement).

### Voix : « ajoute une relance » avec questions
- **Impossible directement sur Google Home** : Google a fermé les *Conversational Actions* (juin 2023) ; une routine Google Home peut lancer un script HA mais sans transmettre le titre ni l'heure.
- **Dès maintenant** : « Ok Google, ajoute *appeler le garage vendredi à 15 h* à ma liste de tâches » → le tri range la date et l'heure.
- **Assist (Home Assistant)** : phrase personnalisée « ajoute une relance {titre} à {heure} » → `todo.add_item` avec ⏰. Utilisable depuis l'app Home Assistant (iPhone, montre). Pour qu'il **pose des questions**, il faut un agent de conversation IA (Claude via clé API, ou Gemini).
- **Enceinte Home Assistant Voice Preview Edition** (Nabu Casa, ≈ 59 €) : micro dédié pour Assist, mot d'éveil « Okay Nabu » ; français bon via Home Assistant Cloud (déjà actif).
- **Transformer un Nest Mini 2ᵉ génération** : carte open source **MiciMike** (2026, livrée avec ESPHome, prête pour Assist) ou **Onju Voice** (plus maintenue, carte à faire fabriquer). Démontage, sans retour à Google.
- Nest Hub : seulement une faille de recherche de 2022 (Ubuntu), corrigée par Google, sans lien avec HA → déconseillé.

### Autres pistes
- **App Mac native** avec icône dans la barre des menus (nombre en retard, liste à un clic).
- Activité en direct **démarrée à distance** (push-to-start) par la vigie, sans ouvrir l'app.
- Faire **sonner la montre** quand l'iPhone est absent (écarté pour l'instant : doublons quand les deux sont ensemble).
- Distribution **TestFlight** pour ne plus dépendre de Xcode (passerait les push en « production »).
- Connecteur claude.ai **Ha-MCP** désactivé : la routine utilise le connecteur « MCP » et son outil générique `call_service` (accès à toute la maison, limité seulement par la consigne). Si Ha-MCP revient, revenir à ses outils dédiés `ha_get_todo` / `ha_set_todo_item`.

## 4. Repères techniques

| Élément | Valeur |
|---|---|
| Dépôt | github.com/thecoachfr/relance (public ; `Secrets.xcconfig` non versionné) |
| Bundle | `fr.alexandrefau.relance` (+ `.widgets`, `.watchkitapp`, `.watchkitapp.widgets`), équipe GD6W292ZXP |
| Projet Xcode | généré par XcodeGen (`xcodegen generate`) ; schémas `Relance` et `RelanceWatch` |
| Google Cloud | projet « Relance », publié « En production » ; clients OAuth iOS (app) et Web (Home Assistant) |
| Home Assistant | 192.168.1.36, accès externe Nabu Casa ; entité `todo.mes_taches` |
| AppDaemon | app `a0d7b954_appdaemon` ; partage Samba `addon_configs/a0d7b954_appdaemon` (apps, logs, `relance_tokens.json`, `relance_routine_token`) ; clé APNs `AuthKey_relance.p8`, Key ID MC2JQ5SU9Y |
| Webhook | automatisation « Relance : enregistrer un appareil » → événement `relance_register` ; test : événement `relance_test_push` |
| Routine | `trig_01GFD6vBExCUvTYDbx9KePm7` « Relance · tri », Sonnet 5.5, 4 h 45 UTC + déclencheur API |
| Appareils | iPhone 17 Pro Max, iPad Pro M4, Apple Watch Ultra 2, Mac Studio (tous enregistrés sur le compte) |
| Xcode 27 | fenêtre des appareils = **Device Hub** (+ → Pair Nearby Device) ; `xcodebuild` n'enregistre pas les appareils |
