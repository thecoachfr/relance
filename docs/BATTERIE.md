# Consommation de batterie d'Aiguillage

*Audit du plan P9-E ([plans/P9-E-audit-batterie.md](../plans/P9-E-audit-batterie.md)). E1 = mesure de référence avant P9 ; E2 = mesure après A4 et D3.*

## Outils en place (16/10/2026)

- **App iPhone et iPad, Réglages › Diagnostic batterie** :
  - rapports quotidiens de MetricKit, résumés : temps à l'écran et en arrière-plan, position en arrière-plan, position demandée (toutes précisions), processeur, réseau Wi-Fi et cellulaire ;
  - réveils en arrière-plan comptés par l'app, par jour : pushs de la vigie reçus, entrées dans une zone de rappel à l'approche ;
  - « Exporter les mesures » : un fichier JSON (résumés, réveils, rapports bruts de MetricKit).
  - Tout reste dans l'App Group (dossier `Metrics/`), sans réseau. iOS livre au plus un rapport par jour, le premier environ 24 h après l'installation du build.
- **App montre, Diagnostic** (en bas de la liste, depuis le 23/10) : empreinte mémoire (`phys_footprint`) actuelle, pic du jour et sur 7 jours, temps à l'écran sur 7 jours, arrêts inattendus à l'écran, erreurs récentes de la montre. Coût pour la batterie : une lecture de `task_info` toutes les 10 s, seulement app à l'écran (rien en arrière-plan), et une écriture de quelques Ko dans l'App Group au plus toutes les 30 s (ou si le pic monte de 1 Mo). Détail dans SUIVI.md, « Mémoire de la montre ».
- **Vigie** : `/config/relance_push_stats.json` dans l'add-on AppDaemon (partage `addon_configs/a0d7b954_appdaemon/`), avec par jour les **salves** par cause (`modification_ha`, `liste_google`, `apres_tri`, `test`) et les **envois** (une salve = un push à chaque appareil enregistré). Gardé 31 jours ; le total de la veille est écrit dans le journal d'AppDaemon à 0 h 00 min 30 s.
- **Réglages › Batterie de l'iPhone** : part d'Aiguillage sur 24 h et sur 10 jours, à l'écran et en arrière-plan. Relevé à la main par Alexandre, avec une capture datée.

## Revue du 03/11/2026

Revue batterie, mémoire et réseau des apps (checklist `bonnes-pratiques-apps-apple`). Corrigé :

- **Tracé précis** (premier poste probable de « position en arrière-plan ») : faux départs ignorés (changement de position important à moins de 400 m du dernier arrêt, sans vitesse), GPS éteint après 2 min sans bouger (5 min avant), file des points en ajout de ligne dans un fichier (avant : jusqu'à 1 Mo de JSON relu et réécrit à chaque point).
- **Mémoire de l'iPhone et de l'iPad** mesurée (`phys_footprint`, sessions à l'écran, arrêts inattendus) : Réglages › Diagnostic batterie › Mémoire.

Restent, repérés mais pas faits : au-delà de 20 lieux de rappel, iOS suit aussi les changements de position importants en continu, et les adresses introuvables sont recherchées dans Plans à chaque réveil (échecs oubliés à la fermeture, `PlaceLocator`) ; boucle de 60 s sur le Mac même fenêtre fermée ; `DriveCopie` sur `URLSession.shared` (60 s) ; `MKLocalSearch` sans délai de garde.

## Point mémoire, réseau et processeur du 11/11/2026

Relevé par copie de l'App Group (`xcrun devicectl … --domain-type appGroupDataContainer`, lecture seule, rien installé) le 11/11 vers 11 h 30. Copies hors dépôt (dossier temporaire de la session). Périodes : **avant** = 16/10 au 02/11, **après** = 03/11 au 10/11 (revue batterie du 03/11 ; mémoire de l'iPhone et de l'iPad suivie depuis).

**Ce qui manque** : aucun dossier `Metrics/` sur l'iPhone ni sur l'iPad, donc **aucun rapport MetricKit gardé depuis le 16/10** (ni processeur, ni temps en arrière-plan, ni position, ni réseau en Mo), alors que `EnergyMetrics.shared.start()` est bien appelé au lancement. Cause probable : partage des analyses avec les développeurs coupé sur ces appareils (iOS ne livre alors rien à `MXMetricManager`) ; à vérifier dans Réglages › Confidentialité et sécurité › Analyse et améliorations. Les widgets et l'extension de partage n'ont pas d'abonné MetricKit. Aucun compteur de requêtes ni de nouveaux essais dans `Reseau` : seul le journal des erreurs renseigne le réseau. **Montre** : injoignable (tunnel `devicectl` refusé, erreur 4000), pas de chiffres. **Mac** : app non lancée au moment du relevé et App Group illisible depuis le terminal (protection macOS), pas de chiffres.

| Mesure | Seuil | iPhone avant | iPhone après | iPad avant | iPad après |
|---|---|---|---|---|---|
| Processeur, arrière-plan, position, réseau (MetricKit) | < 15 min / < 30 min par jour | non mesuré | non mesuré | non mesuré | non mesuré |
| Pushs de la vigie reçus par jour (moyenne / max) | ≤ 30 | 18,9 / 51 (3 jours > 30) | 14,5 / 27 | 27,2 / 103 (5 jours > 30) | 19,9 / 41 (2 jours > 30 : 03 et 04/11) |
| Autres réveils par jour (arrêts relevés, zones, lots du tracé) | — | 15,6 | 36,4 | 0 | 0 |
| Temps à l'écran par jour (sessions suivies) | — | — | 1 à 7 min | — | 1 à 17 min |
| Mémoire à l'écran : médiane des pics / 90 % des sessions sous | à surveiller | — | 71 Mo / 121 Mo | — | 90 Mo / 129 Mo |
| Mémoire : pic maximal | à surveiller | — | **643 Mo** (08/11) | — | **895 Mo** (09/11) |
| Arrêts inattendus à l'écran | 0 par semaine | — | 0 (61 sessions) | — | 0 (62 sessions) |
| Erreurs réseau gardées (journal, 30 au plus) | — | — | 30, toutes vers Home Assistant | — | 1 (TLS, 10/11, 4 fois) |

**Anomalies** (causes probables, rien de corrigé) :

1. **Pics de mémoire de 270 à 900 Mo** en sessions courtes (20 à 150 s, départ à 40-90 Mo) : iPhone 04/11 18 h 40 (274), 05/11 17 h 01 (481), 08/11 21 h 37 (643) ; iPad 04/11 21 h 08 à 21 h 42 (834, puis 509, 339, 279), 09/11 20 h 40 (895). Pas d'arrêt, mais 900 Mo approche la limite d'un iPhone. Les données ne disent pas quel écran ; candidats dans le code : lecture du texte des pièces jointes (Vision, reconnaissance précise avec correction, deuxième passe par étiquette, `SharedPhoto.text`), scan de documents (`imageOfPage` en pleine définition, puis JPEG, puis `UIImage`, `PiecesSection`), photos chargées entières (`loadTransferable(type: Data.self)`, jusqu'à 4). Correctif proposé : demander à Alexandre ce qu'il faisait à ces heures, mesurer avec Instruments ; libérer chaque page du scan (`autoreleasepool`) et lire le texte d'une photo à la fois.
2. **iPhone, envois à Home Assistant en échec** : `NSURLErrorDomain -1200` (TLS) sur « Envoi des trajets » et « Lecture du lieu de travail », et « Envoi du tracé précis : ErreurHA 0 » aux mêmes minutes (03/11 23 h 47-52, 23 fois ; 04/11 9 h 50-11 h 28 ; 06/11 13 h 31 ; 10/11 19 h 48, 8 fois ; 11/11 11 h 03-11 h 07). Cause probable : réseau qui intercepte TLS ou portail captif (même erreur sur trois requêtes indépendantes vers Nabu Casa). Pas de tempête : -1200 n'est pas réessayé (`Reseau.attente`) et le tracé s'arrête au premier lot raté. Mais `ErreurHA 0` (paquet `DonneesHA`) cache l'erreur réelle, et chaque nouveau point du tracé relance un envoi voué à l'échec. Correctif proposé : garder l'erreur d'origine dans `ErreurHA`, et attendre quelques minutes après un échec TLS avant de renvoyer.
3. **iPad, pushs de la vigie** : 103 le 16/10 (jour des essais), encore 35 et 41 les 03 et 04/11, pour un iPad qui n'en fait rien d'autre que se réveiller. À rapprocher de `relance_push_stats.json` (non relu ici). Correctif proposé : ne pas envoyer à l'iPad les salves qui ne changent rien à l'écran, ou les regrouper.
4. **Mac, boucle de 60 s (B1 partiel), confirmée dans le code** : `MacAppDelegate` lance `while true { sleep 60 s ; status.update ; toutes les 5 min store.sync() }`, qui tourne tant que l'app vit, fenêtre fermée comprise (l'app reste dans la barre des menus). Coût réel non mesuré. Correctif proposé : synchro régulière par `NSBackgroundActivityScheduler` (5 min, avec tolérance, que macOS peut différer) et compteur de la barre des menus par un minuteur avec tolérance.
5. Ancien, plus vu depuis le 27/10 : « Démarrage de l'activité en direct : Target is not foreground », 57 fois sur l'iPad.

**Bilan** : pushs ≤ 30 par jour tenus sur l'iPhone depuis le 03/11, pas encore sur l'iPad. Aucun arrêt à l'écran. Les réveils de l'iPhone montent (34,6 → 50,9 par jour) avec les trajets et le tracé précis « Toujours », sans MetricKit pour dire ce qu'ils coûtent : premier point à mesurer une fois le partage des analyses vérifié.

## Correctifs du 11/11/2026 (suite du point du 11/11, validés par Alexandre)

**a. Mémoire par écran** : chaque session à l'écran garde l'écran ou l'action en cours au moment de son pic (`picContexte`, `Shared/Divers/ActiviteEcran.swift`), libellés fixes sans contenu : onglets (À faire, À trier, Envies, Carte), Fiche d'une tâche, Saisie rapide, Scan de document, Scan mis en PDF, Appareil photo, Chargement de photos, Préparation d'une pièce jointe, Lecture du texte d'une image (Vision), Lecture du texte d'un PDF, Aperçu d'une pièce jointe. Ex. « À faire › Fiche d'une tâche › Scan de document ». Une action relève aussi l'empreinte en finissant : un pic bref entre deux mesures (10 s) est rattrapé avec sa cause. Visible dans Réglages › Diagnostic batterie (pics de plus de 250 Mo des 7 jours, avec l'écran) et dans l'export JSON (`sessions_ecran`). **Pics non corrigés** : pas de cause évidente et sûre dans le code (les photos sont déjà réduites par ImageIO à 2 048 px avant décodage, C2 en place) ; le scan garde ses pages en pleine définition le temps de faire le PDF, à revoir une fois les relevés lus (le scanner ne marche pas dans le simulateur, rien de mesurable ici).

**b. Envois vers Home Assistant (TLS -1200)** : `ErreurHA` a un texte (`Shared/HA/ErreurHA+Texte.swift`) : le journal dit « Envoi du tracé précis : DonneesHA.ErreurHA 0 : Home Assistant injoignable : Une erreur SSL s'est produite… » au lieu de « ErreurHA 0 » (le paquet garde le texte de l'erreur réseau, pas son code ; rien de changé dans DonneesHA). Tracé précis : après un échec, plus de nouvel essai à chaque point mais après 2, 4, 8, 16 puis 30 min au plus (`AttenteApresEchec` dans `Reseau.swift`, gardée dans l'App Group), sauf un essai à l'ouverture de l'app (le réseau a pu changer) ; les points restent dans la file locale (`trace-en-attente.csv`). Appliqué à tout échec d'envoi du tracé, pas seulement TLS (un jeton refusé ne se répare pas non plus point par point). Le 03/11 : 23 envois ratés en 5 min ; maintenant 1 puis au plus 1 toutes les 2 à 30 min.

**c. Pushs vers l'iPad** : `relance_push_stats.json` relu le 11/11 : les salves de la vigie vers l'app sont **toutes** `modification_ha` (35 le 03/11, 42 le 04/11 : les chiffres de l'iPad ; les `hub_ipad_*` sont pour l'app Hub). Elles partent de la vigie (`relance_vigie.on_data_changed`, 3 s de regroupement), pas de l'app. Correctif **préparé, pas déployé** : nouveau module `aiguillage_salves.py` (9 tests) et `relance_vigie.py` : à chaque salve, la vigie relit les enregistrements modifiés et (1) n'envoie **rien** si rien de ce que l'app lit n'a changé (même valeur réécrite, ou seulement des champs que l'app ignore, comme `recettes`) ; (2) ne réveille pas l'appareil auteur de toutes les modifications (écho : l'iPad n'est plus réveillé pour ce qu'il vient d'écrire). Salves et envois évités comptés dans `relance_push_stats.json` (`evitees` : `rien_de_visible`, `echo`) et dans le bilan de minuit. L'app envoie maintenant son nom d'émetteur (`appareil` = `HAConfig.device`) à l'inscription aux push (renvoyée une fois). Gain non chiffrable d'avance (les journaux ne disent pas qui a écrit quoi) : à relever une semaine après le déploiement. **Déployé le 11/11/2026 à 12 h 29** (accord d'Alexandre) : `aiguillage_salves.py` et `relance_vigie.py` copiés par le partage `addon_configs` (copie d'avant : `relance_vigie.py.avant-salves-20261111`), vigie relancée sans erreur (18 appareils) ; automatisation « Relance : enregistrer un appareil » : champ `appareil` ajouté à 12 h 30. À relever vers le 18/11 : `evitees` dans `relance_push_stats.json`. **À déployer, après accord d'Alexandre** : (1) copier `aiguillage_salves.py` et `relance_vigie.py` dans `addon_configs/a0d7b954_appdaemon/apps/` (copie d'avant : `relance_vigie.py.avant-salves-2026MMJJ`) ; (2) automatisation « Relance : enregistrer un appareil » : ajouter `appareil: "{{ trigger.json.appareil | default('') }}"` aux données de l'événement `relance_register` (sans elle, le champ n'arrive pas et seul le filtre « rien de visible » joue).

**d. Mac** : plus de boucle de 60 s. Synchro régulière par `NSBackgroundActivityScheduler` (5 min fenêtre ouverte ou Mac qui relance, **15 min** avec la seule barre des menus, tolérance de la moitié, sautée si une synchro a eu lieu dans les 2 min) ; compteur de la barre des menus recalculé quand les tâches changent et à la prochaine échéance seulement (un minuteur unique, 30 s de tolérance), plus chaque minute. Fenêtre fermée : 4 réveils par heure au lieu de 60. **Mesure** (`ps -o cputime`, Release, 120 s, fenêtre fermée, app non signée donc sans compte Google) : avant 0,00 s, après 0,01 s, sous la résolution de `ps` : le coût de la boucle n'était pas mesurable ainsi, sans compte connecté ; le gain est dans les réveils évités.

## E1 — Mesure de référence

**Protocole** : installer le build qui contient le diagnostic, puis une semaine d'usage normal sans fonction P9. À J+7 :

1. Capture de Réglages › Batterie (10 jours, part d'Aiguillage, à l'écran et en arrière-plan).
2. Export de Réglages › Diagnostic batterie (iPhone).
3. Copie de `relance_push_stats.json`.

| Mesure | Valeur E1 |
|---|---|
| Début de la semaine de mesure (build) | à remplir |
| Part d'Aiguillage, 10 jours (Réglages › Batterie) | à remplir |
| Temps en arrière-plan par jour (MetricKit) | à remplir |
| Position en arrière-plan par jour | à remplir |
| Réveils par push reçus par jour (app) | à remplir |
| Salves de la vigie par jour, par cause | à remplir |
| Réseau par jour | à remplir |
| Premières causes probables | à remplir |

**Constat de départ** (16/10) : 9 appareils sont enregistrés auprès de la vigie, qui envoie donc 9 pushs par salve. Vérifier si des jetons sont périmés (anciens builds, appareils réinstallés) : un jeton refusé par Apple est retiré tout seul, mais pas un jeton encore valide qui ne sert plus.

## E2 — Après A4 et D3

À faire : même protocole et comparaison avec E1.

## Seuils d'acceptation (validés par Alexandre le 23/10/2026)

| Mesure | Seuil |
|---|---|
| Part d'Aiguillage, 10 jours (Réglages › Batterie) | ≤ 3 % |
| Temps en arrière-plan | < 15 min par jour |
| Position en arrière-plan | < 30 min par jour |
| Pushs de la vigie reçus | ≤ 30 par jour |
| Jetons push enregistrés par la vigie | = nombre d'appareils réels (9 le 16/10) |
| Montre : pic mémoire à l'écran | < 60 Mo (rien de mesuré encore) |
| Arrêts inattendus à l'écran (montre) | 0 par semaine |

Pour les quatre apps : **0 arrêt inattendu à l'écran par semaine** (un seul suffit pour regarder) ; une mémoire qui monte de jour en jour à usage égal = fuite probable, à regarder. Seuils **provisoires**, à revoir avec Alexandre après la première semaine de relevés.
