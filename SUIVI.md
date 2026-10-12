# Relance — suivi du projet

*Mis à jour le 12 octobre 2026. Point de départ pour reprendre le projet dans une nouvelle conversation.*
*Besoin et choix de départ : [CADRAGE.md](CADRAGE.md). Installation : [README.md](README.md).*

## 1. Où on en est

### Ce qui marche (testé sur les appareils)

| Brique | État |
|---|---|
| **App iPhone** | Widget : symbole coloré de la catégorie avant l'échéance. Relances qui insistent (à l'heure, +1 h, 20 h ; en retard 7 h 30 et 20 h ; silence 22 h–7 h 30), boutons Fait / Dans 1 h / Ce soir / Demain matin, activité en direct (3 tâches max, Fait / 1 h par tâche ; vue dédiée dans le Smart Stack de la montre), widgets accueil et écran verrouillé, commande « + » (Centre de contrôle, bouton Action, écran verrouillé), Siri (« marque *X* comme fait », « reporte *X* » → « À quand ? », « qu'est-ce que j'ai aujourd'hui » ; tâches connues de Siri et de Spotlight ; « dans 2 heures » compris partout ; « nouvelle Relance » : date dans la phrase ou « Pour quand ? », « sans date » → À trier ; « Relance en retard » après synchro), question « À quelle heure ? » immédiate pour une tâche arrivée de Google avec une date sans heure (boutons 9/12/15/18 h, sans son la nuit), écran À trier une tâche à la fois, catégories, journal de synchro dans les réglages |
| **App iPad** | Liste + détail, raccourcis clavier (↑↓, ⌘↩, ⌘L, ⌘⌫, ⌘R, ⌘N), pas de relances par défaut (voir « Appareil qui relance ») |
| **App Mac** | App native (cible `RelanceMac`, macOS 15), testée le 12/10 avec le vrai compte Google (même identifiant et même client OAuth que l'iPhone). Fenêtre en trois colonnes : listes (À faire, À trier, Fait), catégories et tags avec leur nombre ; tâches groupées par échéance ; détail partagé avec l'iPad (contact, agenda, priorité, relances, tags, retri). Actions dans la barre d'outils et le menu Tâche (⌘↩ fait, ⌘L +1 h, ⇧⌘L demain, ⌘⌫, ⌘R), ⌘N saisie rapide, ⌘Z après avoir coché. Icône dans la barre des menus (nombre en retard) : saisie en une phrase et tâches du jour à cocher. Synchro à l'ouverture, toutes les 5 min et au réveil ; relances seulement s'il est l'appareil choisi (Réglages › Général). Pas de widgets, d'activité en direct ni d'extension de partage |
| **Priorité** | Urgente / Normale / Basse. Urgente : relancée toutes les 30 min jusqu'à minuit (silence 22 h–7 h 30), en retard 7 h 30 / midi / 20 h, passe le mode Concentration, sous-titre « Urgente », toujours dans l'activité en direct. Basse : un seul rappel à l'heure, puis résumé du matin ; jamais dans l'activité en direct ni le widget. Réglée dans l'app (formulaires, balayage, appui long), à la voix (« urgent », « pas pressé » : Siri, saisie rapide, dictée montre) ou par le tri. Affichage : **le rond à cocher porte la priorité** (épais et rouge = Urgente, pointillés = Basse), la catégorie reste seule en pastille (choix du 12/10 après comparaison de deux maquettes) |
| **Appareil qui relance** | Un seul à la fois (iPhone d'origine), choisi dans les réglages de n'importe quel appareil ; le choix est partagé par iCloud (stockage clé-valeur) et affiché partout (« Les relances sont sur ton iPhone »). L'appareil d'avant retire ses relances à sa prochaine ouverture ou synchro |
| **Réglages des relances** | Réglages › Relances › Quand et comment relancer : horaires (résumé du matin, midi, soir ; **résumé du soir** à 21 h, activé d'origine : « Demain — 3 tâches, dont 1 urgente · la première à 9 h · 1 encore en retard », rien si demain est vide), plage silencieuse, week-end calme ; profil par priorité (prévenir avant, relancer après / jusqu'à ce que ce soit fait, matin/midi/soir sans heure ou en retard, demander l'heure, mode Concentration, activité en direct, rétablir). Valeurs d'origine = comportement d'avant. Gardés sur l'appareil (`ReminderSettings`, App Group). **Par tâche** : ligne « Relances » du détail (prévenir avant, relancer une fois ou toutes les…), rangée dans les notes Google (`🔁 …`), respectée par le tri. Limite iOS de 64 notifications : l'heure prévue, les rappels avant, les reports et les résumés passent d'abord |
| **Tags et mémo de contexte** | Tags transversaux en plus de la catégorie (SCI, Micro, Photo, Syndic, Travaux, Spectacle + ceux créés), 3 max, ligne `🔖`, affichés en gris `#SCI` (pas de pastille), filtre et choix dans le détail. **Mémo de contexte** (activités, interlocuteurs, santé…) : `memo-contexte.md` (hors Git) recopié dans la consigne de la routine, qui s'en sert pour catégories, tags et contacts |
| **Lieu, contact et « à prendre »** | Le tri ajoute `📍 Nom · adresse · téléphone · lien` quand une tâche désigne un interlocuteur du mémo ; **ou à la main** : section « Lieu » du détail › Ajouter un lieu (recherche Plans avec suggestions ; téléphone et site repris quand Plans les connaît), modifier ou retirer. Le détail affiche Appeler / Itinéraire / Site web (« Prendre rendez-vous » pour Doctolib et sites de RDV). Les lignes techniques (`📍`, `📅 Dans l'agenda`, `📩 Message partagé`) sont cachées du champ Notes et gardées à l'enregistrement. Rendez-vous médical : `🎒 À prendre : carte Vitale…` |
| **Agenda** | Bouton « Ajouter au calendrier » dans le détail d'une tâche avec heure : événement d'1 h dans l'agenda par défaut d'iOS (Google principal), lieu tiré de 📍, sans alerte ; il suit l'heure et le titre de la tâche ; à la suppression, Relance demande s'il faut aussi retirer l'événement. Ligne `📅 Dans l'agenda` dans les notes ; seul l'appareil créateur gère l'événement. Tâches Google masquées dans Google Agenda pour éviter le doublon |
| **Pars maintenant** | Tâche avec heure et adresse 📍 (36 h à venir) : temps de trajet calculé par Plans depuis l'adresse de départ réglée (domicile, gardée sur l'appareil), mode transports / voiture / à pied, marge 0–15 min ; notification « Pars maintenant · 18 min en transports » avec Itinéraire et Fait, jamais coupée par la plage silencieuse. Recalcul au plus toutes les 30 min |
| **Partage depuis une autre app** | Extension « Relance » dans la feuille de partage (WhatsApp, Mail, Messages, Safari…) : fiche avec titre prérempli (première phrase utile : salutations, formules de politesse et en-têtes WhatsApp sautés), échéance et priorité lues dans le message, message complet dans les notes (« 📩 Message partagé »). Envoi direct chez Google (trousseau partagé `GD6W292ZXP.fr.alexandrefau.relance.shared`, rempli par l'app à chaque synchro) ; sans réseau, file d'attente envoyée à la synchro suivante. Le tri propose un meilleur titre une fois (« — titre à revoir ») si le titre n'a pas été retouché. Texte et liens seulement |
| **Apple Watch** | Testée seule (eSIM, iPhone en mode Avion) le 12/10. Liste, cocher, reporter, dictée, complication, catégorie sous l'échéance, rond de priorité, Siri (« nouvelle Relance », garde l'heure, direct chez Google) ; l'iPhone sert de relais |
| **Vigie Home Assistant** | AppDaemon rafraîchit Google Tasks chaque minute ; si le nombre de tâches change → push silencieux à l'iPhone et l'iPad (testé : push reçu et synchro en 1 s) |
| **Tri par Claude** | Routine cloud « Relance · tri » : catégorie (🏷), date/heure si explicites (⏰), sinon suggestion (💡) ; priorité (❗/🔽) seulement si « urgent » / « pas pressé » est dit ; retire du titre l'expression de date/heure ou le mot de priorité dictés ; corrige les erreurs évidentes de transcription des dictées (titre en minuscules) (titre d'origine gardé en « 🎙 Dicté : … », rien retiré en cas de doute). Tous les jours à 6 h 45 **et** 90 s après chaque nouvelle tâche (lancée par la vigie, max 20/jour). Testé le 12/10. Bouton **« Retrier avec Claude »** (détail d'une tâche ; « Tout retrier » dans Réglages › Relances) : retire catégorie et tags, synchronise, puis demande le tri à la vigie (webhook, `action: triage`) — côté Home Assistant pas encore déployé |
| **Catégories** | Affichées sur l'iPhone et l'iPad (vérifié le 12/10) ; « 🏷 » et « ⏰ » reconnus avec ou sans sélecteur de variante (U+FE0F) |
| **Logo** | « Boucle » (flèche circulaire + coche, orange), variantes sombre / teintée / montre |

### Conventions dans les notes Google Tasks
Google Tasks n'a ni heure (dans son API) ni étiquettes : en tête des notes, dans cet ordre :
```
⏰ 15:00
🏷 Administratif
🔖 SCI, Micro          (tags, 3 au plus)
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
2. **Pars maintenant** : vérifier le 13/10 la notification de départ pour le dentiste ; piste : partir de la position actuelle quand l'app est ouverte.
3. **Correction des transcriptions Google Home** (activée le 12/10) : vérifier sur une prochaine dictée que les erreurs évidentes sont corrigées (titre d'origine gardé en 🎙) et que les titres corrects ne bougent pas.
4. **Retrier avec Claude, côté Home Assistant** : copier `homeassistant/appdaemon/apps/relance_vigie.py` dans AppDaemon, vérifier que l'automatisation du webhook transmet le champ `action`, puis tester le bouton de bout en bout.
5. **Mémo dans Google Tasks** (validé le 12/10) : liste « Relance · mémo », une fiche par entrée, lue par la routine (lecture seule) ; écran Mémo et « Retenir pour le tri » dans l'app ; migrer `memo-contexte.md`.
6. **Mémo de contexte** (`memo-contexte.md`, hors Git) : dentiste et kiné complétés le 12/10 (horaires du kiné inconnus) ; à compléter au fil de l'eau (locataires des places, comptable, artisans), puis recopier dans la consigne de la routine.

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
- **Mac** : limiter la largeur du détail quand la fenêtre est très large.
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
| Formulaires | Le détail iPad et l'éditeur iPhone ne renvoient que les champs modifiés (`TaskFields`) et se rechargent si la tâche change ailleurs : sinon ils écrasaient les ajouts de la routine ou d'un autre appareil (bug corrigé le 12/10) |
| Mise à jour de la montre | L'app montre est intégrée à l'app iPhone : **augmenter `CFBundleVersion`** (9 au 12/10) (project.yml, toutes les cibles) pour que l'iPhone la transmette à la montre ; sinon installer directement quand Xcode voit la montre |
| Xcode 27 | fenêtre des appareils = **Device Hub** (+ → Pair Nearby Device) ; `xcodebuild` n'enregistre pas les appareils |
