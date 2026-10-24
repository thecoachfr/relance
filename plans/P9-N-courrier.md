# P9-N — Courrier : calendrier pro, tri des mails, agent (Aiguillage + Signal)

*Plan du 24/10/2026, demandé par Alexandre. Lire d'abord `P9-00-INDEX.md`. Dépôts : `relance` + HA (AppDaemon).
**Priorité d'Alexandre : le calendrier** (lots N0 à N2) ; le courrier vient ensuite. Canaux de l'agent retenus :
Aiguillage et Signal (le chat Claude reste possible pour les gros travaux, sans rien construire).*

## 1. Le besoin

1. Voir dans Aiguillage (et sur les trois vues du Hub) les **jours de bureau et de télétravail**, tirés du
   calendrier pro.
2. Un **tri des mails façon Dove** (Canary Mail) : chaque mail rangé en *À traiter* (une personne, une demande),
   *Lettres d'info*, *Bruit* ou *Fait* ; le tri apprend de ses gestes ; notification seulement pour *À traiter*.
3. Un **agent** qui aide à traiter, trier, résumer.
4. Un **lien dans les deux sens avec Aiguillage** : un mail devient une tâche (lien vers le fil, cochée quand il a
   répondu) ; depuis une tâche, l'agent prépare un mail.
5. Plus tard, si le besoin reste : un client Mac léger (lecture, envoi, agent). Aiguillage **ne devient pas** le
   logiciel de mail : la lecture complète et l'écriture restent dans Gmail.

Règle de l'agent sur tous les canaux : **il prépare, Alexandre valide**. Aucun envoi, aucune suppression, aucun
archivage sans accord, au moins jusqu'à la fin de la période d'ombre.

## 2. Ce qui existe (constat du 24/10)

- **Deux boîtes Google** : perso `alexandre.fau@gmail.com` (tous les appareils ; connecteur Gmail de claude.ai
  actif) et pro `afau-ext@groupebarriere.com` (Google Workspace, domaine sans accent ; lue seulement sur l'iPhone et
  le PC pro). Rien de la boîte pro n'arrive dans la perso.
- **HA** : aucune entité `calendar.*`, aucune intégration mail (IMAP). Google Tasks passe par l'intégration HA ; la
  vigie n'a pas d'OAuth Google à elle (noté dans P9-I).
- **Outils à réutiliser** : la vigie et AppDaemon (`relance_vigie.py`), SQLite sur le NUC comme la mémoire Signal
  (P9-J), le tri par l'API (`aiguillage_tri.py`, P9-I : mode ombre, budget mensuel, repli), le module Signal
  (la « Note à moi-même » crée déjà des envies), `donnees_apps` (espace `aiguillage`), l'adresse Nabu Casa.
- **Aiguillage** sait déjà ajouter une tâche à l'agenda d'iOS (bouton « Ajouter au calendrier ») et publie l'agenda
  « Sorties » en iCalendar.

## 3. Lots

### N0 — Préalables (Alexandre, en cours le 24/10)

1. **Comment sont notés les jours de bureau dans l'agenda pro ?** Trois cas :
   - le **lieu de travail** de Google Agenda (Bureau / Domicile, réglé par jour) : le meilleur cas, lisible tel quel ;
   - des **événements** (« Télétravail », « Bureau ») : lisibles par leur titre ;
   - **rien** : on passe au repli (N1, cas C).
2. **Test du partage** : Google Agenda pro › Paramètres › l'agenda › Partager avec des personnes ›
   `alexandre.fau@gmail.com`, droit **« Voir tous les détails des événements »**. Option grisée ou limitée à
   « disponible / occupé » = partage externe bloqué par Barrière. *Disponible / occupé ne suffit pas : le lieu de
   travail n'y figure pas.*
   **Résultat du 24/10 : bloqué** (« Voir tous les détails » interdit par l'administrateur). Cas A exclu. Pistes
   suivantes, dans l'ordre : compte pro ajouté au Calendrier d'iOS (lecture sur l'iPhone par EventKit) ; script
   Google Apps Script dans le compte pro qui n'envoie que « bureau / télétravail » par jour à un webhook HA ; repli
   semaine type (cas C).
   **Suite du 24/10** : compte pro ajouté au Calendrier d'iOS : les événements passent, **pas le lieu de travail** ;
   **Apps Script désactivé** par l'administrateur. Reste l'OAuth direct (cas B), très probablement bloqué lui aussi.
   **Décision proposée : cas C**, semaine type + exceptions, vérifié par la position : zone HA « Bureau » (à créer,
   seule `zone.home` existe), un jour noté télétravail où l'iPhone entre dans la zone devient « bureau » (et
   inversement), et l'écart répété propose de corriger la semaine type.
3. **Test de l'accès direct** (seulement si 2 échoue, ou pour le mail pro plus tard) : se connecter avec le compte pro
   au client OAuth du projet Google Cloud « Relance ». « Accès bloqué : votre organisation doit approuver
   l'application » = applications extérieures interdites.
4. **Charte informatique de Barrière** : vérifier qu'elle permet de lire l'agenda (et plus tard les mails) depuis un
   outil perso. L'agenda seul est le cas le moins sensible.

### N1 — Le calendrier pro dans HA (1 soirée)

Source selon N0 :

| Cas | Source | Comment |
|---|---|---|
| **A** — partage accepté | Agenda pro partagé dans le compte perso | OAuth Google Agenda en lecture seule (`calendar.readonly`) sur le compte **perso**, dans le projet Google Cloud « Relance » |
| **B** — partage bloqué, OAuth pro accepté | Compte pro directement | Même app, jeton du compte pro |
| **C** — tout bloqué | Semaine type + exceptions | Réglage « semaine type » (ex. bureau mardi et jeudi) ; exceptions dites à l'agent Signal (« demain télétravail ») ou dans Aiguillage |

- **App AppDaemon `aiguillage_agenda_pro.py`** (ou extension de `aiguillage_agenda.py`) : toutes les 30 min et à
  6 h, lit les 14 prochains jours (`events.list`, `eventTypes=workingLocation` puis repli sur les titres) et publie
  `sensor.aiguillage_lieu_travail` : état du jour (`bureau`, `teletravail`, `inconnu`, `conge`), attributs `demain`,
  `jours` (14 × `{date, lieu, source}`), `maj`, `source` (`lieu_travail`, `evenements`, `semaine_type`). Publication
  par l'API REST (comme `sensor.hub_meteo`, pour garder les null).
- *Pas l'intégration Google Agenda de HA* : à vérifier, mais elle ne montre pas le lieu de travail (type
  d'événement à part) ; l'app AppDaemon garde la main sur les types. On pourra quand même l'ajouter pour les autres
  agendas si besoin.
- Les jetons OAuth restent sur le NUC (`/config/secrets/`), jamais dans le dépôt.
- Tests : lieu de travail, événements par titre, semaine type + exception, journée de congé, agenda injoignable
  (garder la dernière valeur, `source: cache`).

### N2 — Bureau / télétravail dans Aiguillage et les trois vues (1 à 2 soirées)

- **Aiguillage (iPhone, iPad, Mac)** : bandeau en tête de « À faire » : « 🏢 Bureau aujourd'hui · demain télétravail ».
  Dans la vue par jours, la pastille du lieu à côté de chaque date.
- **Tâches « au bureau » / « à la maison »** : nouveau champ facultatif `contexte` (`bureau` | `maison`), ligne
  `🏢 Au bureau` / `🏠 À la maison` dans les notes. Une tâche sans date avec un contexte reçoit le **prochain jour qui
  correspond**, et la relance du matin de ce jour la pousse en tête. Exemple : « rendre le badge » → prochain jour de
  bureau. *Avant la mise en service* : la consigne de la routine de tri et `aiguillage_tri.py` doivent connaître
  `contexte` (règle de l'index, section 4), et l'index (section 3) le recenser.
- **Montre** : la complication et le Smart Stack affichent 🏢 / 🏠.
- **Les trois vues du Hub** (Hub TV, Nest Hub, Hub iPad : toute modification va sur les trois) : pastille du jour en
  en-tête, avec les mêmes mots et le même ordre. Ils lisent `sensor.aiguillage_lieu_travail`.
- Le réveil (`script.sequence_reveil`) peut s'en servir plus tard (heure différente les jours de bureau) : à
  proposer, pas dans ce lot.

### N3 — Le cerveau du courrier (boîte perso) (2 à 3 soirées)

- **App AppDaemon `aiguillage_courrier.py`** : OAuth Gmail sur le compte perso (`gmail.readonly` pour commencer ;
  `gmail.compose` pour les brouillons en N5 ; `gmail.modify` seulement si Alexandre veut que l'agent archive).
  Relève toutes les 2 minutes par l'historique Gmail (`history.list`) ; la notification immédiate de Google (Pub/Sub
  vers un webhook Nabu Casa) viendra plus tard si le délai gêne.
- **Base** : `/config/aiguillage_courrier.sqlite` (fil, expéditeur, sujet, date, extrait, catégorie, résumé, état,
  gestes d'Alexandre). Le corps complet n'est pas gardé : seulement l'extrait utile au tri et le résumé.
- **Tri** : un appel Haiku 5.5 par mail (sortie structurée : catégorie, résumé en une phrase, demande, échéance,
  confiance), avec des règles sûres d'abord (expéditeurs connus, libellés Gmail, `List-Unsubscribe`). **Apprentissage**
  : les gestes d'Alexandre (ouvert, répondu, passé en Fait, recatégorisé) font une règle par expéditeur, prioritaire
  sur l'IA.
- **Ombre une semaine**, comme P9-I : tri calculé et journalisé, rien affiché ni notifié ; Alexandre compare avec sa
  boîte, puis on ouvre.
- **Budget** : `courrier_budget_mensuel` (15 $ par défaut). Au-delà, le tri ne garde que les règles sûres et prévient.

### N4 — Courrier dans Aiguillage (2 à 3 soirées)

- **Section « Courrier »** (iPhone, iPad, Mac ; pas sur la montre au début) : seulement les mails *À traiter*. Chaque
  carte : expéditeur, résumé, demande, échéance ; boutons **En faire une tâche**, **Répondre** (brouillon de l'agent,
  N5), **Ouvrir dans Gmail**, **Fait**, et le champ **« Demander à l'agent »**. Texte du mail en lecture seule dans la
  fiche, au besoin.
- **Tâches nées d'un mail** : champ facultatif `courrier` (`{compte, fil, lien, de, sujet}`), ligne `📧 Mail de X`
  dans les notes. Cochée d'elle-même quand Alexandre a répondu dans le fil (vu par N3). Même règle que `contexte` :
  la routine de tri et l'index d'abord.
- **Notifications** : seulement *À traiter*, groupées (pas plus d'une par quart d'heure, silence 22 h–7 h 30 comme les
  relances), boutons Tâche / Plus tard / Fait, aussi sur la montre.
- Les données passent par l'espace `aiguillage` de `donnees_apps` (un enregistrement par mail à traiter, 64 Ko max) :
  l'app ne parle jamais à Gmail elle-même.

### N5 — L'agent sur Signal et dans Aiguillage (2 soirées)

- **Signal, « Note à moi-même »** : un message qui n'est pas un lien part à l'agent (les liens gardent leur rôle
  actuel : envies). Préfixe à trancher (section 5).
- **Agent** : Sonnet 5.5, outils limités : chercher dans la base et dans Gmail, lire un fil, résumer, préparer un
  brouillon (dans les Brouillons Gmail), créer ou dater une tâche Aiguillage, lire `sensor.aiguillage_lieu_travail`.
  **Envoi seulement après « ok » d'Alexandre** sur Signal ou dans Aiguillage.
- Le champ « Demander à l'agent » d'Aiguillage appelle le même agent, avec le mail de la carte comme contexte ; la
  réponse revient dans la fiche.

### N6 — Le résumé du matin (1 soirée)

- À 7 h 30 : ce qui attend une réponse, ce qui est arrivé, les lettres d'info en trois lignes, le lieu du jour.
  Envoyé sur Signal ; affiché sur les trois vues du Hub (mêmes blocs, même ordre).

### N7 — La boîte pro (si N0 l'autorise)

- Même cerveau, second compte, tri séparé (pastille « Pro »). Option de **tri sur l'appareil** (modèle d'Apple
  intégré au Mac) pour qu'aucun mail pro ne parte vers une IA extérieure, au prix d'un tri moins fin.

### Plus tard — client Mac léger

- À décider après quelques semaines de N4 : lecture, envoi, agent, lien Aiguillage, rien d'autre.

## 4. Coût prévisionnel (tarifs du 24/10)

| Poste | Modèle | Estimation |
|---|---|---|
| Calendrier (N1, N2) | aucun | 0 $ |
| Tri (≈ 100 mails par jour) | Haiku 5.5 (0,10 $ / 0,50 $ par million de jetons) | ≈ 1,5 $/mois |
| Résumé du matin | Sonnet 5.5 (2 $ / 10 $) | ≈ 2,5 $/mois |
| Agent à la demande | Sonnet 5.5 | 2 à 5 $/mois |

Total ≈ 5 à 10 $/mois, pris sur les crédits API de Max (comme P9-I). Plafond conseillé : 15 $/mois.

## 5. À trancher avec Alexandre

1. Résultat des tests N0 (cas A, B ou C) et façon dont les jours de bureau sont notés.
2. Préfixe des messages à l'agent sur Signal (aucun, ou « ? » au début) pour ne pas mélanger avec les liens.
3. Droits Gmail de l'agent : brouillons seulement (proposé), ou aussi archiver et libeller.
4. Faut-il ranger aussi les mails *Lettres d'info* et *Bruit* dans des libellés Gmail (visibles dans Gmail sur tous
   les appareils), ou les garder seulement dans la base ?
