# P9-L — Idées du 19/10 : étude

Sept idées d'Alexandre (19/10), quatre pour Aiguillage et trois pour l'écran du Nest Hub de l'entrée. Pour chacune :
ce qui existe déjà, ce qu'on peut faire, le coût et les questions à trancher. Rien n'est commencé.

| | Idée | Verdict | Coût |
|---|---|---|---|
| L1 | Concerts et spectacles (date, billets) | **Fait le 19/10** (build à essayer) | — |
| L2 | App TV : « Écouté » sur chaque morceau de la playlist | **Fait et essayé le 19/10** | option automatique : 1 soirée |
| L3 | Tour d'UX sur le placement des boutons de la fiche | **Fait le 19/10** (à essayer) | — |
| L4 | Reconnaissance de texte (rendez-vous chez le dentiste…) | **Fait le 19/10** (à essayer) | — |
| L5 | Nest Hub : couper l'alarme du détecteur de fumée (Netatmo) en cuisinant | **Abandonné** (Alexandre, 19/10) | — |
| L6 | Nest Hub : afficher ce qui passe (TV ou musique), quelle que soit la source | Faisable : un capteur « En ce moment » | 1 soirée |
| L7 | Nest Hub : changer le contenu sans changer de dashboard | Faisable : une seule carte, pages basculées sur place | 2 soirées |

## L1 — Concerts et spectacles

**Existant** : envies `👀 À voir` avec période (`🗓 Du … au …`), tag « Spectacle », pièces jointes (P9-K : un PDF
partagé se joint et son texte est lu), lien dans les notes, ajout à l'agenda (section Agenda de la fiche), rappels
d'échéance.

**Ce qui manque** : une sortie **réservée** n'est pas une envie (elle a une date et une heure fixes, un lieu, des
billets) et elle n'a pas sa liste à elle.

**Proposition** :
- Un huitième type d'envie, **`🎟 Sortie`** (concert, spectacle, match, cinéma réservé) : date et heure obligatoires,
  lieu (`📍`, déjà géré), billets en pièces jointes (PDF, capture, et `.pkpass` ouvert dans Wallet) ou lien vers le
  billet. Fait = « Vu ».
- Dans Envies, filtre « Sorties » : **À venir** par date (« ce samedi », « dans 3 semaines »), puis **Passées** (les
  10 dernières, comme « Déjà vu »).
- Fiche : bouton **Billets** en tête (ouvre la pièce jointe ou le lien), Itinéraire, Ajouter à l'agenda (avec la
  durée H1).
- Rappels : la veille au soir, puis 2 h avant avec le billet dans la notification (la photo de notification de P9-K
  sait déjà le faire pour une image ; pour un PDF, toucher la notification ouvre la fiche sur le billet).
- Saisie : partager le PDF ou l'e-mail du billet vers Aiguillage. Le texte lu suffit au tri pour remplir le type,
  la date, l'heure, le lieu et l'artiste (nouvelle règle T de la consigne du tri). Nest Hub : ignoré comme les
  autres envies, sauf le jour même (à décider).
- Plus tard : la routine cherche dans Gmail les confirmations de billetterie (Fnac, Ticketmaster, See Tickets…) ;
  peu utile si les billets arrivent surtout par les apps.

**Choix d'Alexandre (19/10)** : nouveau type `🎟 Sortie` ; billets en PDF, dans les apps de billetterie (lien) ou en
capture ; sortie du jour sur le Nest Hub ; rappels une semaine avant, la veille au soir et 2 h avant.

**Fait le 19/10** :
- App : type `ToSee.Kind.event` (« 🎟 Sortie », `envie.type: sortie`), seule envie qui garde l'échéance de la tâche
  (`isDated`) : fiche avec Échéance et Agenda, « Ouvrir le billet » (première pièce jointe, Quick Look) et le lien des
  notes ; saisie rapide avec date et heure. Envies › Sorties : À venir (par date), Date à préciser, Passées (« Passée ·
  sam. 17 oct. », jamais « en retard ») ; une sortie passée quitte À faire et n'est pas comptée en retard.
- Rappels : `eventWeek` (J−7 à l'heure des envies), `eventEve` (veille à l'heure du soir), `eventSoon` (2 h avant, avec
  l'image jointe ; sans heure, le matin du jour), ni relance ni retard. Tests `SortieTests` (183 tests verts).
- Nest Hub : les deux cartes montrent une sortie le jour même seulement, jamais en retard (`?v=5d63e00e`,
  `?v=a16c16ed`).
- Tri : règle T (billet ou réservation datée, y compris le texte d'une pièce jointe → `🎟 Sortie`, `envie.type:
  sortie`, `jour` et `heure` de l'événement, salle, titre « Artiste à salle », tag Spectacle) dans la routine (relue
  identique) et dans la consigne du tri par API ; `aiguillage_tri.py` accepte `sortie` et montre `pieces` (nom, texte).
- Reste : essai réel (partager un billet PDF, laisser le tri le ranger, recevoir les rappels, voir le Hub le jour J).

## L2 — App TV : marquer écoutés les titres de la playlist

**Vérifié dans le code de `aiguillage-tv`** : la rangée « Dans la playlist « À écouter » » montre les titres recopiés
par la vigie (`config:playlist_a_ecouter`), mais leur fiche n'a **ni « Écouté » ni « Pas maintenant »** : ce ne
sont pas des tâches (choix du 16/10). « Écouté » n'existe que pour les envies À écouter (des tâches). On ne peut donc
pas, aujourd'hui, marquer écoutés tous les titres de la playlist depuis la TV.

**Proposition** :
- **« Écouté »** dans la fiche d'un titre de la playlist : l'app TV écrit une demande dans HA ; la vigie retire le
  titre de la playlist Spotify et coche l'envie liée s'il y en a une (même lien).
- **« Tout marquer écouté »** en bout de rangée, avec confirmation (« Retirer les 23 titres de la playlist ? »).
- **Option automatique** : la vigie lit l'historique d'écoute Spotify (droit `user-read-recently-played`, à ajouter
  en relançant `spotify_jeton.py`) et marque écouté un titre de la playlist joué jusqu'au bout. Plus rien à faire à
  la main ; 1 soirée de plus.

**Précision d'Alexandre (19/10)** : il veut dire « fait » sur chacun des morceaux qu'il voit ; seul le dernier le
permet. Explication (19/10) : la playlist compte 10 morceaux (copie de la vigie) ; la rangée « Dans la playlist »
les montre tous, sans « Écouté » ; le bouton n'existe que sur les envies encore à faire, rangées plus bas, et
sans doute une seule l'est encore (les autres morceaux viennent d'envies déjà faites, d'albums ou d'ajouts directs
dans Spotify). Retenu par défaut : « Écouté » sur chaque morceau **retire le morceau de la playlist** (une file
d'attente) et coche l'envie liée s'il y en a une.

**Fait le 19/10** : bouton « Écouté » dans la fiche d'un titre de la playlist (app TV 14d8528) → script
`script.aiguillage_spotify_ecoute` → événement `aiguillage_spotify_ecoute` → la vigie retire le titre (`DELETE
/playlists/{id}/items`, corps `items`), coche les envies liées (`envies_ecoutees`, tests dans
`tests/test_aiguillage_spotify.py`) et recopie la playlist. Essai réel réussi le 19/10 à 18 h 24 (4 titres retirés, une envie cochée). Option
automatique (historique d'écoute) pas faite.

## L3 — Tour d'UX : placement des boutons de la fiche

**Constat dans le code** (`TaskDetailView`) : sur iPhone, **Marquer fait, Reporter d'une heure, Demain matin et
Supprimer sont tout en bas de la fiche**, après une douzaine de sections (échéance, liste, pièces jointes, agenda,
priorité, catégorie, actions, tri…). Plus la fiche est riche, plus il faut faire défiler pour l'action la plus
courante. Sur Mac, elles sont dans la barre d'outils.

**Pistes** (à confirmer par un audit avec les guidelines d'Apple et des captures, iPhone et iPad) :
- **Barre du bas** de la fiche (`bottomBar`, comme Mail ou Rappels) : Fait à gauche, menu **Reporter** (1 h, ce
  soir, demain matin, choisir…) au centre, menu **…** à droite (Supprimer, Partager, Retrier). Toujours visible.
- Ordre des sections selon l'usage : titre, échéance, puis ce que la tâche a (liste, pièces, lieu) ; les réglages
  rares (priorité, rappels, catégorie, tags, actions) regroupés plus bas, ou derrière « Plus d'options ».
- Les sections vides ne prennent qu'une ligne « Ajouter… » (pièces jointes, liste, durée) au lieu d'un bloc.
- Vérifier aussi : la saisie rapide, les menus contextuels des lignes, la barre de la carte, l'iPad en deux colonnes.

**Choix d'Alexandre (19/10)** : barre du bas Fait · Reporter · ⋯ ; enregistrement immédiat avec « Fermer » ; l'essentiel
d'abord, le reste dans « Plus d'options ».

**Fait le 19/10** (critique avec le skill design-critique et les règles d'Apple, captures avant et après dans le
simulateur) :
- Une seule fiche (`TaskDetailView`) pour l'iPhone et l'iPad : sur iPhone, `TaskEditor` n'est plus qu'une feuille
  qui l'enveloppe, avec « Fermer » ; plus d'Annuler / OK (chaque changement est enregistré, comme sur iPad).
- Barre du bas (iOS) : **Fait** (bouton principal), **Reporter** (Dans 1 h, Ce soir si l'heure du soir est à plus de
  30 min, Demain matin), **⋯** (Partager, Supprimer avec confirmation si un événement d'agenda suit la tâche). Une
  action ferme la feuille. Raccourcis de l'iPad gardés : ⌘↩ Fait, ⌘L Reporter d'une heure, ⌘⌫ Supprimer.
- Ordre : titre, notes ; échéance ; lieu ; liste, pièces jointes, envie (si c'en est une) ; actions ; puis « Plus
  d'options » replié (mémorisé) avec un résumé (catégorie, priorité, tags) : priorité et relances, catégorie et tags,
  agenda, « Envie, sans échéance » pour une tâche ordinaire, retrier avec Claude et mémo. Une tâche simple tient en
  un écran et demi (4,5 avant).
- Correction : sous Relances, une sortie dit « rappel une semaine avant, la veille au soir et 2 h avant ».
- Mac inchangé (barre d'outils).

## L4 — Reconnaissance de texte (rendez-vous, convocations)

**Existant** : partager une capture ou une photo vers Aiguillage → le texte est lu sur l'appareil (Vision) ; P9-K
joint désormais la pièce et garde 1 500 caractères de texte ; le tri en tire l'échéance (règle S). Mais la date
n'arrive qu'**au passage du tri**, et l'appareil photo n'est pas proposé dans la saisie rapide.

**Proposition** :
- **Lecture immédiate sur l'appareil** : `DateDetection` (déjà utilisé par la saisie rapide) et le détecteur d'Apple
  (adresses, téléphones) appliqués au texte lu : la feuille de partage pré-remplit date, heure, lieu et téléphone
  (« Dentiste — mardi 4 nov. 14 h 30 », modifiable avant d'enregistrer). Le tri garde le dernier mot (titre propre,
  catégorie, contact).
- **« Scanner du texte »** dans la saisie rapide : l'appareil photo avec le Texte en direct d'iOS (VisionKit
  `DataScannerViewController`) ; on touche la date ou le bloc voulu, la tâche se remplit. La photo devient une
  pièce jointe.
- Un rendez-vous avec une heure propose **Ajouter à l'agenda** d'office (avec une durée, H1).
- Coût faible : tout est sur l'appareil, sans API ; la détection en français est à vérifier sur de vraies
  convocations (cartes de rendez-vous, SMS de rappel, e-mails de Doctolib).

**Fait le 19/10** :
- `SharedAppointment` (pur, testé par `RendezVousTests`) : un texte est un rendez-vous s'il contient un indice
  (RDV, rendez-vous, convocation, Doctolib, Dr, cabinet, séance, examen, dentiste, kiné…) et une date à venir. Il en
  tire un titre (« Rendez-vous chez le dentiste », « Séance de kiné », « Assemblée générale »…), la date et l'heure
  (formes françaises « mardi 4 novembre 2026 à 14h30 », « 06/11 à 9h », sans année → la prochaine, puis le détecteur
  d'Apple), l'adresse, le téléphone (mis en forme « 01 43 78 87 05 ») et le praticien (« Dr … »).
- Feuille de partage : une capture ou une photo dont le texte est un rendez-vous n'est plus un spot photo ; la date,
  l'heure et le lieu (nom, adresse, téléphone) sont remplis, la capture est jointe. Même chose pour un texte partagé
  sans lien.
- Saisie rapide : « Scanner un rendez-vous » (scanner de documents d'iOS) remplit la tâche de la même façon et joint
  le scan en PDF (mode HA). Le bouton n'apparaît pas dans le simulateur (pas d'appareil photo).
- Le tri garde le dernier mot (catégorie, contact du mémo, titre).
- Reste : essai réel (capture d'un SMS Doctolib partagée, carton du dentiste scanné).

## L5 — Nest Hub : couper l'alarme du détecteur de fumée de l'entrée

**Modèle (Alexandre, 19/10)** : Détecteur de Fumée Intelligent **Netatmo**, dans l'app Netatmo Sécurité ; but :
cuisiner sans qu'il sonne. Le compte Netatmo est déjà relié à HA (caméra Welcome, stations), mais le détecteur n'y
crée aucune entité.

Ce qu'on sait (sources publiques, 19/10) :
- La **mise en sourdine** depuis l'app passe par **Bluetooth** entre le téléphone et le détecteur, pas par le
  cloud ; un appui sur le bouton du détecteur le fait taire 15 min.
- Dans HA, les alarmes Netatmo n'arrivent que comme **événements de webhook** (fumée, sourdine…), sans entité ni
  commande ; aucune commande « sourdine » documentée dans l'API publique (à revérifier sur dev.netatmo.com).
- Dans Apple Maison (HomeKit), il n'apparaît que comme un capteur de fumée, sans commande.

Donc **pas de bouton « couper l'alarme » sur le Hub**, et on ne désactive pas un détecteur de fumée à l'avance (c'est
un appareil de sécurité). Ce qu'on peut faire :
- Un **bandeau rouge** sur le Hub et une notification pendant l'alarme (événement de webhook à capter dans HA) :
  « Fumée dans l'entrée — appuie sur le bouton du détecteur pour 15 min de silence ».
- Pour les fausses alertes en cuisinant : allumer la hotte plus tôt, ou demander à Netatmo si une sourdine
  préventive existe ; le placement du détecteur (distance à la cuisine) est la vraie solution.

## L6 — Nest Hub : ce qui passe en ce moment, quelle que soit la source

**Existant** : le lecteur de la carte suit `binary_sensor.lecture_salon` / `lecture_chambre` (musique) ; la fenêtre
TV connaît la chaîne (`sensor.freebox_player_chaine` : chaîne ou application, par exemple « Accueil OQEE »).
Constaté le 19/10 : les enceintes LS50 jouaient un morceau Spotify (source `wifi`, titre et artiste connus) tandis
que `lecture_salon` disait seulement « Direct ».

**Proposition** : un capteur unique **« En ce moment »** (modèle HA ou vigie), qui choisit dans cet ordre :
1. TV allumée : chaîne + programme en cours (« TMC — Les Mystères de l'amour », si le guide OQEE donne le programme,
   à vérifier dans `oqee_etat.py`), ou application (Netflix, YouTube, Spotify sur la TV) ;
2. LS50 sur `wifi` : titre, artiste, pochette (Spotify Connect ou Music Assistant) ; sur `tv` / `optical` : « Son de
   la TV » + ce qui passe à la TV ;
3. Chambre, salle de bain, Cast : idem.

La carte n'affiche plus qu'une tuile, avec la pièce, la pochette ou le logo de la chaîne, et les boutons qui
conviennent (volume des LS50, chaîne suivante). Les lecteurs en double dans HA (`entryway_2`, `salon_ls50_5`,
`freebox_player_pop_4`…) sont à trier en passant. 1 soirée.

**Question** : la TV d'abord, ou la musique d'abord, quand les deux jouent ?

## L7 — Nest Hub : changer le contenu sans changer de dashboard

**Existant** : deux vues (complète et légère), deux cartes de ~47 Ko chacune presque identiques ; on change par
`input_select.nest_hub_vue`, ce qui relance l'affichage Cast (`cast.show_lovelace_view`) : écran noir, son coupé,
une dizaine de secondes, et parfois l'« état fantôme » noté dans la fiche du Hub.

**Proposition** : **une seule carte, plusieurs pages** préconstruites (Accueil, Musique, TV, Aiguillage, Maison :
lumières et volets), basculées sur place par une classe, sans rechargement (comme la fenêtre TV du 17/10 :
11 à 32 ms à l'ouverture). On passe d'une page à l'autre par des boutons en bas, ou un balayage s'il est fiable sur
le Hub (à essayer). La page peut aussi suivre HA : `input_select.nest_hub_vue` lu par la carte (« Musique » quand
une lecture démarre, « Accueil » après 2 min sans toucher). On ne recaste qu'une fois, au démarrage.

Bonus : une seule base de code au lieu de deux copies. 2 soirées, mesures de fluidité sur le Hub comprises (photos
d'Alexandre).

**Question** : quelles pages veux-tu, et laquelle par défaut ?

## Ordre proposé

1. **L2** (petit, vérifié, utile tout de suite), puis **L4** (sur l'appareil, sans risque) et **L1**, qui utilise
   L4 et P9-K.
2. **L3**, avant d'ajouter d'autres sections à la fiche.
3. Nest Hub : **L7** d'abord, puis **L6** (L5 abandonné le 19/10).

Le code des cartes du Nest Hub reste hors du dépôt public (fiche et cartes dans HA, dossier `claude/` de
`ha-config`) ; seule cette étude est ici.
