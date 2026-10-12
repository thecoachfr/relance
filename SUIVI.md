# Relance — suivi du projet

*Mis à jour le 12 octobre 2026. Point de départ pour reprendre le projet dans une nouvelle conversation.*
*Besoin et choix de départ : [CADRAGE.md](CADRAGE.md). Installation : [README.md](README.md).*

## 1. Où on en est

### Ce qui marche (testé sur les appareils)

| Brique | État |
|---|---|
| **App iPhone** | Widget : symbole coloré de la catégorie avant l'échéance. Relances qui insistent (à l'heure, +1 h, 20 h ; en retard 7 h 30 et 20 h ; silence 22 h–7 h 30), boutons Fait / Dans 1 h / Ce soir / Demain matin, activité en direct (3 tâches max, Fait / 1 h par tâche ; vue dédiée dans le Smart Stack de la montre), widgets accueil et écran verrouillé, commande « + » (Centre de contrôle, bouton Action, écran verrouillé), Siri (« nouvelle Relance » : date dans la phrase ou « Pour quand ? », « sans date » → À trier ; « Relance en retard » après synchro), question « À quelle heure ? » immédiate pour une tâche arrivée de Google avec une date sans heure (boutons 9/12/15/18 h, sans son la nuit), écran À trier une tâche à la fois, catégories, journal de synchro dans les réglages |
| **App iPad** | Liste + détail, raccourcis clavier (↑↓, ⌘↩, ⌘L, ⌘⌫, ⌘R, ⌘N), pas de relances par défaut (réglage « Relances sur cet appareil ») |
| **App Mac** | L'app iPad « Designed for iPad », lancée depuis Xcode (⌘R) |
| **Priorité** | Urgente / Normale / Basse. Urgente : relancée toutes les 30 min jusqu'à minuit (silence 22 h–7 h 30), en retard 7 h 30 / midi / 20 h, passe le mode Concentration, sous-titre « Urgente », toujours dans l'activité en direct. Basse : un seul rappel à l'heure, puis résumé du matin ; jamais dans l'activité en direct ni le widget. Réglée dans l'app (formulaires, balayage, appui long), à la voix (« urgent », « pas pressé » : Siri, saisie rapide, dictée montre) ou par le tri. Affichage : **le rond à cocher porte la priorité** (épais et rouge = Urgente, pointillés = Basse), la catégorie reste seule en pastille (choix du 12/10 après comparaison de deux maquettes) |
| **Réglages des relances** | Réglages › Relances › Quand et comment relancer : horaires (résumé du matin, midi, soir), plage silencieuse, week-end calme ; profil par priorité (prévenir avant, relancer après / jusqu'à ce que ce soit fait, matin/midi/soir sans heure ou en retard, demander l'heure, mode Concentration, activité en direct, rétablir). Valeurs d'origine = comportement d'avant. Gardés sur l'appareil (`ReminderSettings`, App Group). **Par tâche** : ligne « Relances » du détail (prévenir avant, relancer une fois ou toutes les…), rangée dans les notes Google (`🔁 …`), respectée par le tri. Limite iOS de 64 notifications : l'heure prévue, les rappels avant, les reports et les résumés passent d'abord |
| **Partage depuis une autre app** | Extension « Relance » dans la feuille de partage (WhatsApp, Mail, Messages, Safari…) : fiche avec titre prérempli (première phrase utile : salutations, formules de politesse et en-têtes WhatsApp sautés), échéance et priorité lues dans le message, message complet dans les notes (« 📩 Message partagé »). Envoi direct chez Google (trousseau partagé `GD6W292ZXP.fr.alexandrefau.relance.shared`, rempli par l'app à chaque synchro) ; sans réseau, file d'attente envoyée à la synchro suivante. Le tri propose un meilleur titre une fois (« — titre à revoir ») si le titre n'a pas été retouché. Texte et liens seulement |
| **Apple Watch** | Testée seule (eSIM, iPhone en mode Avion) le 12/10. Liste, cocher, reporter, dictée, complication, catégorie sous l'échéance, rond de priorité, Siri (« nouvelle Relance », garde l'heure, direct chez Google) ; l'iPhone sert de relais |
| **Vigie Home Assistant** | AppDaemon rafraîchit Google Tasks chaque minute ; si le nombre de tâches change → push silencieux à l'iPhone et l'iPad (testé : push reçu et synchro en 1 s) |
| **Tri par Claude** | Routine cloud « Relance · tri » : catégorie (🏷), date/heure si explicites (⏰), sinon suggestion (💡) ; priorité (❗/🔽) seulement si « urgent » / « pas pressé » est dit ; retire du titre l'expression de date/heure ou le mot de priorité dictés ; corrige les erreurs évidentes de transcription des dictées (titre en minuscules) (titre d'origine gardé en « 🎙 Dicté : … », rien retiré en cas de doute). Tous les jours à 6 h 45 **et** 90 s après chaque nouvelle tâche (lancée par la vigie, max 20/jour). Testé le 12/10 |
| **Catégories** | Affichées sur l'iPhone et l'iPad (vérifié le 12/10) ; « 🏷 » et « ⏰ » reconnus avec ou sans sélecteur de variante (U+FE0F) |
| **Logo** | « Boucle » (flèche circulaire + coche, orange), variantes sombre / teintée / montre |

### Conventions dans les notes Google Tasks
Google Tasks n'a ni heure (dans son API) ni étiquettes : en tête des notes, dans cet ordre :
```
⏰ 15:00
🏷 Administratif
❗ Urgente            (ou « 🔽 Basse » ; rien pour Normale)
🔁 Prévenir 1 jour avant · Relancer toutes les 15 min   (relances propres à la tâche)
🎙 Dicté : … (titre d'origine, si le tri l'a nettoyé)
Notes libres…
💡 Suggestion : … (ajoutée par le tri)
```
Catégories fixes : Administratif, Maison, Santé, Achats, Travail, Famille, Perso (`Shared/Model/TaskCategory.swift` et prompt de la routine).

### Limites connues
- **Google Home garde l'heure pour lui** : il comprend « vendredi à 15 h », retire l'expression du titre et ne transmet que la date (l'API Google Tasks n'expose pas l'heure). Constaté le 12/10. Contournements : la question « À quelle heure ? » de l'iPhone juste après la dictée, ou Siri (iPhone, montre), qui garde l'heure.
- La vigie ne détecte que les **changements du nombre** de tâches (ajout, coche), pas les modifications de date d'une tâche existante.
- iOS ne livre pas les push silencieux si l'app a été **fermée de force** (balayée dans le sélecteur).
- L'activité en direct ne peut **démarrer** qu'app ouverte (elle se met ensuite à jour seule).
- Applis installées en **développement** (Xcode) : à réinstaller quand le profil de développement expire (environ 1 an) ; APNs en environnement « sandbox ».

## 2. Reste à faire / à vérifier

1. **Premier tri automatique du matin** : demain 6 h 45 (vérifier dans [la routine](https://claude.ai/code/routines/trig_01GFD6vBExCUvTYDbx9KePm7)).
2. **Correction des transcriptions Google Home** (activée le 12/10) : vérifier sur une prochaine dictée que les erreurs évidentes sont corrigées (titre d'origine gardé en 🎙) et que les titres corrects ne bougent pas.
3. **Siri, suite** : agir sur une tâche existante (« marque *garage* comme fait », « reporte *garage* à demain », via une entité Tâche, aussi cherchable dans Spotlight) ; « qu'est-ce que j'ai aujourd'hui » ; comprendre « dans 2 heures ».

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
- Extension de partage : accepter photos et messages vocaux.
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
| Mise à jour de la montre | L'app montre est intégrée à l'app iPhone : **augmenter `CFBundleVersion`** (project.yml, toutes les cibles) pour que l'iPhone la transmette à la montre ; sinon installer directement quand Xcode voit la montre |
| Xcode 27 | fenêtre des appareils = **Device Hub** (+ → Pair Nearby Device) ; `xcodebuild` n'enregistre pas les appareils |
