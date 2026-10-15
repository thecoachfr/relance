# Cadrage — app de rappels qui insiste

*Version 1 — 11 octobre 2026. Nom provisoire : **Relance**, devenu **Aiguillage** le 13/10/2026.*

## 1. Le problème

- Les rappels sont dictés à Google Home mais consultés sur iPhone/iPad : deux mondes qui ne se parlent pas.
- Une notification qui sonne une fois puis disparaît = une tâche oubliée.
- Les apps actuelles obligent à programmer soi-même répétitions et rappels.
- Pas de bon endroit pour noter vite et trier plus tard.

## 2. Le principe

> **Je dis la chose et l'échéance. L'app me relance, de plus en plus fort, tant que ce n'est pas marqué « fait ».**

Aucune répétition à configurer par tâche : le rythme est global, réglé une fois.

## 3. Architecture

```
 Google Home ──(voix)──┐
                       ▼
 Siri / app ──────► Google Tasks ◄────── Home Assistant (phase 3)
                       ▲    │              surveille et réveille l'app
                       │    ▼                       │
                  ┌──────────────┐   push silencieux│
                  │  App Relance │◄─────────────────┘
                  │ iPhone / iPad│
                  └──────────────┘
                  calcule et programme les relances localement
```

- **Source de vérité : Google Tasks.** Ce que dit Google Home y arrive (vérifié). L'app lit, crée, modifie et coche via l'API REST Google Tasks.
- **L'heure** : l'API Google Tasks ne transmet que la date (limite documentée). L'app stocke l'heure dans le champ *notes* de la tâche, sur une ligne dédiée (`⏰ 15:00`), pour qu'iPhone et iPad la partagent.
- **Les relances** sont des notifications locales calculées par l'app, pas par Google.
- **Cache local** (SwiftData) pour un affichage instantané et le fonctionnement hors ligne ; les actions (« Fait », nouvelle tâche…) sont mises en file et envoyées à Google dès que possible.

## 4. Le rythme des relances (réglable)

Plage silencieuse : **22 h – 7 h 30** (aucune relance, sauf échéance tombant dedans).

Rythme volontairement **léger** : la visibilité permanente vient de l'activité en direct et du widget (§5) ; les notifications ne sonnent qu'aux moments clés.

| Situation | Relances |
|---|---|
| **Échéance avec heure H** | **à H** (time-sensitive), puis **à H + 1 h** |
| Toujours pas fait le jour même | **20 h** (time-sensitive) |
| **Échéance date seule** (dictée Google Home) | **7 h 30** : « Prévu aujourd'hui : *X*. À quelle heure ? » + boutons 9 h / 12 h / 15 h / 18 h ; une fois l'heure choisie → rythme ci-dessus ; sinon **20 h** |
| **En retard (jours suivants)** | **7 h 30** (dans le résumé du matin) puis **20 h**, avec « En retard depuis N j » |
| **Sans date** | pas de relance individuelle ; compté dans le **résumé de 7 h 30** : « N tâches à trier » |

Le **résumé de 7 h 30** liste : les tâches en retard, celles du jour, et le nombre à trier.

Boutons sur chaque notification (avec icône SF Symbol) : **Fait** · **+1 h** · **Ce soir** (20 h) · **Demain matin** (7 h 30). Toucher la notification ouvre la tâche dans l'app pour choisir une autre heure (iOS n'affiche pas de sélecteur d'heure dans une notification).
« Plus tard » décale les relances de cette tâche seulement ; l'échéance Google n'est pas modifiée (sauf « Demain », qui déplace aussi la date).

**Niveaux d'interruption** (HIG : réserver *Time Sensitive* à ce qui demande une action immédiate, sinon iOS propose à l'utilisateur de le couper) :
- *Time Sensitive* : la relance **à l'heure H** et celle de **20 h** ;
- *Active* (normal) : H + 1 h et le résumé de 7 h 30 ;
- *Passive* : aucune pour l'instant.

**Pas d'inondation du centre de notifications** : toutes les relances d'une même tâche partagent un `threadIdentifier` (elles s'empilent en un seul groupe), et chaque fois que l'app tourne elle retire les relances déjà affichées d'une tâche avant d'en montrer une nouvelle.

**Pastille sur l'icône** : nombre de tâches en retard (usage prévu par les HIG pour un compteur d'éléments à traiter).

**Demande d'autorisation** au moment utile, pas au premier lancement : après la création de la première tâche, avec une phrase qui explique pourquoi (« Pour te relancer tant que ce n'est pas fait »).

**Contrainte iOS** : 64 notifications locales programmées maximum par app. L'app garde une fenêtre glissante (les ~60 plus proches) et reprogramme à chaque ouverture, action sur une notification, ou rafraîchissement en arrière-plan.

**iPhone et iPad** : par défaut, **seul l'iPhone relance** (sinon les deux sonnent, et un « Fait » sur l'un ne coupe pas l'autre avant synchro). L'iPad sert à consulter et trier. La phase 3 lève cette limite.

## 5. Écrans

**Navigation** : barre d'onglets à 3 onglets — **À faire**, **À trier** (avec pastille du nombre), **Fait**. Les réglages s'ouvrent depuis un bouton en haut d'*À faire* (ce n'est pas une destination fréquente, HIG). Sur iPad, la même barre devient automatiquement une barre latérale (`TabView` adaptable, iPadOS 18).

1. **À faire** (accueil) — sections *En retard*, *Aujourd'hui*, *Bientôt*. Le retard n'est pas signalé que par la couleur rouge : texte « En retard · 2 j » + symbole (accessibilité). État vide : « Rien d'urgent. »
   - Glisser vers la droite = **Fait** (glissement complet possible), vers la gauche = **Reporter** — même logique que Mail et Rappels.
   - Appui long = menu contextuel (Fait, Reporter, Modifier, Supprimer).
   - Après « Fait » : retour haptique + bandeau **Annuler** pendant quelques secondes plutôt qu'une confirmation (HIG : préférer l'annulation).
   - Bouton **Nouvelle tâche** en bas de l'écran, comme dans Rappels ; ⌘N sur iPad avec clavier.
2. **À trier** — tâches sans date ou sans heure (depuis le 13/10 : sans date, ou datées d'aujourd'hui ou d'avant sans heure ; une tâche datée plus tard sans heure reste dans À faire), présentées une à une avec des boutons rapides (Aujourd'hui, Demain, heure, Supprimer). Chaque geste a son bouton équivalent (VoiceOver, Contrôle de sélection).
3. **Ajout rapide** (feuille) — un champ texte avec la date reconnue dans la phrase (« appeler le garage vendredi 15 h ») surlignée, + puces Aujourd'hui / Demain / heure. La reconnaissance du français sera testée tôt ; les puces servent de solution de repli.
4. **Fait** — historique récent, pour annuler une erreur.
5. **Réglages** — compte Google, liste(s) Google suivie(s), plage silencieuse, rythme, appareil qui relance.

Au-delà de l'app, pour que les tâches soient **visibles sans ouvrir quoi que ce soit** (le vrai problème de départ) :
- **Activité en direct** (écran verrouillé + Dynamic Island) pour la tâche la plus en retard ou celle de l'heure qui vient, avec un bouton **Fait** directement dessus. Les HIG la réservent aux choses en cours avec une fin claire : c'est le cas ici (la fin, c'est « fait »). iOS la limite à 8 h affichées : l'app la relance chaque matin.
- **Widgets interactifs** : écran d'accueil (liste avec case à cocher Fait) et écran verrouillé (nombre en retard + prochaine tâche).
- **Commande du Centre de contrôle** (iOS 18) « Nouvelle tâche », assignable aussi au **bouton Action** de l'iPhone : capture en une pression.
- **Siri / Raccourcis** (App Shortcuts, le nom de l'app doit figurer dans la phrase) : « Ajoute une tâche dans Relance », « Qu'est-ce qui est en retard dans Relance ? ».

**Accessibilité et apparence** : polices système avec Dynamic Type jusqu'aux tailles d'accessibilité, couleurs système (mode sombre géré automatiquement), cibles tactiles d'au moins 44 pt, libellés VoiceOver sur toutes les actions et les gestes de balayage.

**Textes des notifications** : le titre = la tâche elle-même ; le corps = le contexte (« Prévu à 15 h · en retard de 30 min »). Pas de nom d'app ni de formule creuse ; le ton se fait plus direct avec le retard, sans culpabiliser.

## 6. Technique

- SwiftUI, **iOS / iPadOS 18 minimum**, Swift 6.
- Connexion Google : SDK **GoogleSignIn** (Swift Package), scope `https://www.googleapis.com/auth/tasks`.
- Appels API : `URLSession` + `async/await`, sans autre dépendance.
- SwiftData (cache + file d'actions en attente), `UserNotifications`, `BackgroundTasks`, `WidgetKit`, `ActivityKit`, `AppIntents`.
- Capacités Xcode : Push Notifications, Background Modes (fetch, remote notifications), Time Sensitive Notifications, App Groups (widget, activité en direct).

**À préparer côté Google Cloud** (je guiderai) : un projet, l'API Tasks activée, un identifiant OAuth iOS.
⚠️ Si l'écran de consentement reste en mode « Test », Google **fait expirer la connexion tous les 7 jours**. Il faudra le passer « En production » ; sans validation Google, on verra juste un avertissement « application non vérifiée » à la première connexion (sans conséquence pour un usage perso).

## 7. Découpage

**Phase 1 — le cœur (iPhone)**
Connexion Google, synchro, écran *À faire*, ajout rapide, moteur de relances, notifications avec boutons.
→ *Utilisable au quotidien dès la fin de cette phase.*

**Phase 2 — confort**
Écran *À trier*, demande d'heure pour les dictées Google Home, activité en direct, widgets, commande du Centre de contrôle, Siri, mise en page iPad.

**Phase 3 — vigie Home Assistant**
Intégration Google Tasks dans HA ; à chaque tâche créée ou cochée, HA envoie un push silencieux (APNs) qui réveille l'app → les dictées Google Home sont prises en compte en quelques minutes, et un « Fait » sur un appareil coupe les relances de l'autre.

**Au-delà (réalisé le 12/10)**
Apple Watch autonome, extension de partage, priorités et relances réglables, tri par Claude (routine) avec catégories, tags,
lieu et mémo de contexte, agenda, « Pars maintenant », app Mac native avec barre des menus, résumé du soir.
Détail et suite dans [SUIVI.md](SUIVI.md).

## 8. Décisions (validées le 11/10/2026)

1. Nom : **Relance** (renommée **Aiguillage** le 13/10/2026, quand l'app a dépassé les simples relances : tri, à voir, carte, répétitions).
2. Liste suivie : **« Mes tâches »** pour commencer.
3. Rythme : **à l'heure, à +1 h, puis 20 h** si pas fait ; en retard : **7 h 30 et 20 h** chaque jour.
4. Plage silencieuse : **22 h – 7 h 30**.
5. Résumé du matin : **7 h 30**.

### Décisions du 12/10/2026
6. **Un seul appareil relance** (iPhone d'origine), choisi dans les réglages de n'importe quel appareil, partagé par iCloud.
7. **L'heure n'est pas propagée à Google** : l'API Google Tasks ne la gère pas, et ce serait doubler les rappels. Pour la voir dans Google Agenda, bouton « Ajouter au calendrier ».
8. **Mémo de contexte** de la routine dans une liste Google Tasks à part (« Relance · mémo »), lue en lecture seule par la routine. *Remplacé le 15/10/2026 : liste Local To-do « Aiguillage · mémo » dans Home Assistant (éditable depuis HA).*
9. **App Mac native** (SwiftUI) plutôt que l'app iPad sur Mac : trois colonnes, barre des menus, raccourcis.

### Décision du 15/10/2026
10. **Tâches dans Home Assistant, découpage hybride** : les tâches passent dans l'intégration `donnees_apps` (espace `aiguillage`) par le paquet `DonneesHA` (fallback iCloud, dernier écrit gagne), pas dans une liste Local To-do (sans identifiant renvoyé à la création, ni idempotence, ni date de modification). Google Tasks reste la boîte d'entrée des dictées Google Home, vidée par la vigie ; le mémo reste dans Google pour l'instant.
