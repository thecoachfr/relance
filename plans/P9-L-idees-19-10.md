# P9-L — Idées du 19/10 : étude

Sept idées d'Alexandre (19/10), quatre pour Aiguillage et trois pour l'écran du Nest Hub de l'entrée. Pour chacune :
ce qui existe déjà, ce qu'on peut faire, le coût et les questions à trancher. Rien n'est commencé.

| | Idée | Verdict | Coût |
|---|---|---|---|
| L1 | Concerts et spectacles (date, billets) | Faisable, s'appuie sur Envies et P9-K | 2 soirées |
| L2 | App TV : marquer écoutés les titres de la playlist | Pas possible aujourd'hui ; faisable | 1 soirée (+1 pour l'automatique) |
| L3 | Tour d'UX sur le placement des boutons de la fiche | Utile : les actions sont tout en bas | 1 soirée d'audit + 1–2 de reprise |
| L4 | Reconnaissance de texte (rendez-vous chez le dentiste…) | Existe en partie (partage de capture) ; à rendre immédiat | 1–2 soirées |
| L5 | Nest Hub : bouton pour couper l'alarme du détecteur de fumée | Dépend du modèle : le détecteur n'est pas dans HA | ½ soirée si compatible |
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

**Questions** : (1) les billets arrivent-ils surtout en PDF, dans Wallet ou dans les apps des billetteries ? (2) une
sortie du jour sur le Nest Hub, oui ou non ? (3) « Sortie » comme nouveau type, ou un drapeau « réservé » sur
`👀 À voir` (moins de code, mais deux idées sous un même type) ?

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

**Question** : un titre écouté est-il **retiré** de la playlist (elle reste une file d'attente), ou **gardé** et
seulement marqué ?

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

**Méthode** : captures dans le simulateur (démo), critique écrite, maquette de 2 variantes proposées en mode
interactif, puis reprise. **Question** : d'autres écrans qui te gênent, en plus de la fiche ?

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

**Question** : surtout des captures (SMS, e-mails, Doctolib) ou des photos de cartons papier ?

## L5 — Nest Hub : couper l'alarme du détecteur de fumée de l'entrée

**Vérifié dans HA (19/10)** : aucun détecteur de fumée n'y est connu (ni `smoke` ni « fumée » parmi les capteurs).
Tout dépend donc du modèle :
- **Zigbee** (Frient, Heiman, Aqara…, par Zigbee2MQTT, déjà installé) : l'alarme est un capteur et la plupart
  exposent une commande « silence » ou « alarme off ». Le bouton est simple : il apparaît en grand, en rouge, sur
  le Hub seulement pendant l'alarme (« Fumée dans l'entrée — Couper l'alarme »), avec une notification sur les
  iPhone. ½ soirée.
- **Nest Protect** : Google n'ouvre pas le Protect aux applications tierces (l'API Device Access couvre caméras,
  thermostats et sonnettes, pas le Protect, à revérifier). On ne pourrait que le couper depuis l'app Google Home.
- **Détecteur autonome sans radio** (le cas le plus courant) : impossible de le couper à distance. On pourrait le
  remplacer par un modèle Zigbee, ou en ajouter un dans l'entrée.

**Question** : quel modèle (marque, ou photo de l'étiquette) ? Et pourquoi le couper : une fausse alerte en
cuisinant ?

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
3. Nest Hub : **L7** d'abord (L6 et L5 deviennent des pages ou des bandeaux de la nouvelle carte), puis **L6**,
   puis **L5** selon le modèle du détecteur.

Le code des cartes du Nest Hub reste hors du dépôt public (fiche et cartes dans HA, dossier `claude/` de
`ha-config`) ; seule cette étude est ici.
