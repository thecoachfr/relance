# P9-O — Copropriété : mémoire du groupe WhatsApp, ordres du jour d'AG, envois aux propriétaires

*Plan du 24/10/2026, demandé par Alexandre (syndic bénévole de sa copropriété). Lire d'abord `P9-00-INDEX.md`.
Dépôts : HA (AppDaemon) + `relance`. **Plan préparé, pas commencé** : Alexandre y reviendra plus tard.
Aucune donnée personnelle de la copropriété dans ce dépôt public (noms, numéros, adresses, lots, montants) : tout va
dans `/config/…` sur HA.*

## 1. Le besoin

1. **Garder l'historique** de ce qui se dit dans le groupe WhatsApp de la copropriété, cherchable comme la mémoire
   Signal (P9-J).
2. **Rédiger plus facilement l'ordre du jour** des AG (et les projets de résolution) à partir de ce qui a été dit
   depuis la dernière AG.
3. **Envoyer « automatiquement »** les PV d'AG et les appels de charges aux autres propriétaires.

## 2. Ce qu'on a déjà, et deux limites

- **Recette Signal réutilisable** : `aiguillage_signal` (capture en direct), `aiguillage_memoire` (SQLite sur le NUC,
  recherche plein texte, résumés de nuit jour / semaine / mois par l'API, copie dans `donnees_apps` espace
  `memoire`), skill `memoire-signal` pour chercher depuis Claude. Brouillons Gmail : connecteur claude.ai, et le
  client Gmail en lecture seule de N3 (`aiguillage_courrier`).
- **Limite 1 — WhatsApp n'a pas d'accès officiel à un compte personnel.** L'API WhatsApp Business (Cloud API)
  demande un autre numéro et ne voit pas les groupes existants. Reste un client non officiel lié comme « appareil »
  (bibliothèques whatsmeow en Go ou Baileys en JavaScript, empaquetées en conteneur ou add-on HA ; **à vérifier** au
  moment de coder : add-on maintenu, API websocket ou webhook). Les conditions de WhatsApp l'interdisent et des
  comptes sont bannis, surtout ceux qui **envoient** ; la réception seule est peu risquée mais pas sans risque. Le
  compte en jeu est le WhatsApp personnel d'Alexandre. Session à relier (QR code) quand elle expire ; une mise à
  jour de WhatsApp peut casser la bibliothèque.
- **Limite 2 — les envois officiels ne passent pas par WhatsApp.** D'après la loi du 10 juillet 1965 et le décret
  de 1967 (**à vérifier** avant de s'y fier, mêmes règles pour un syndic bénévole) : la **notification du PV** aux
  opposants et aux absents non représentés se fait en recommandé (papier, ou électronique avec leur accord écrit) et
  fait courir leur délai de deux mois pour contester ; les **convocations** aussi. Si tout le monde est présent ou
  représenté et vote pour, un simple envoi du PV suffit. Les **appels de charges** partent par simple courrier ou
  mail. Un message WhatsApp ne vaut pas notification.

Conséquence : **WhatsApp en réception seule** ; les envois partent **par mail, en brouillons validés** (règle
permanente : aucun envoi sans l'accord explicite d'Alexandre, voir P9-N) ; le recommandé reste à part.

## 3. Lots

### O0 — Préalables (Alexandre)

- Prévenir le groupe que les messages sont gardés pour préparer les AG (ce sont les données des autres
  propriétaires) ; noter la date et les réactions.
- Liste des propriétaires (nom, lot, mail, accord pour le recommandé électronique, tantièmes) dans
  `/config/copro_proprietaires.json` sur HA, jamais dans le dépôt. Nombre de propriétaires : à donner.
- Choisir la bibliothèque WhatsApp après vérification (O1) et accepter le risque pour le compte.
- Récupérer l'historique : export de la discussion (`.txt`, depuis l'iPhone), ou base `ChatStorage.sqlite` d'une
  sauvegarde iPhone sur le Mac (plus complet, plus technique).

### O1 — Capture du groupe (1 soirée)

- Conteneur ou add-on WhatsApp sur le NUC, lié au compte d'Alexandre, **sans fonction d'envoi branchée**.
- Nouvelle source dans la mémoire (`aiguillage_memoire`) : conversation « Copro », seulement le groupe désigné
  (identifiant du groupe dans `/config/…`), auteur = nom du contact ou numéro masqué. Pièces jointes purgées comme
  pour Signal ; les PDF (devis, factures) gardés à part si Alexandre le veut (décision O5).
- Capteur `sensor.aiguillage_whatsapp` (connexion, dernier message, session à relier) ; notification quand la
  session tombe.

### O2 — Import de l'historique (une demi-soirée)

- Lecture de l'export `.txt` (format des dates de l'iPhone en français, messages sur plusieurs lignes, « <pièce
  jointe absente> ») ou de `ChatStorage.sqlite` ; sans doublon avec la capture (clé tirée de l'heure, de l'auteur et
  du texte).
- Résumés de l'historique par la Batch API, comme J5.

### O3 — Résumés orientés AG (1 soirée)

- Consigne de résumé propre à la copro : faits de type `sujet_ag` (travaux, devis, sinistres, nuisances, demandes
  d'un propriétaire, vote à prévoir), `decision`, `devis` (montant, entreprise), `promesse`, en plus des types
  existants.
- Liste vivante « Sujets pour la prochaine AG » (espace `memoire`, clé `copro-sujets-ag`), mise à jour chaque nuit,
  chaque sujet avec ses messages d'origine (date, auteur).
- Recherche depuis Claude : skill `memoire-signal` élargi (ou skill `memoire-copro`).

### O4 — Préparer l'AG (1 soirée)

- À la demande (« prépare l'AG du … ») : projet d'ordre du jour et de résolutions (majorité indicative à vérifier par
  Alexandre), à partir des sujets depuis la dernière AG ; cite les messages qui fondent chaque point.
- Document à relire (Google Docs ou fichier), tâche Aiguillage « Préparer l'AG » avec échéance (délai de
  convocation : 21 jours, **à vérifier**).

### O5 — Envois aux propriétaires (1 à 2 soirées)

- Entrée : le PV signé ou l'appel de charges (PDF), déposé en pièce jointe d'une tâche Aiguillage (plan K) ou dans un
  dossier Drive.
- Brouillons Gmail personnalisés par propriétaire (nom, lot, montant de l'appel), PDF joint ; Alexandre valide, puis
  envoi (bouton dans Aiguillage ou « ok » sur Signal, comme N5). Journal des envois (date, destinataire).
- PV : liste des opposants et des absents non représentés à notifier en recommandé (électronique pour ceux qui l'ont
  accepté, par un prestataire du type AR24 : **à étudier**, sinon papier) ; tâche Aiguillage par envoi recommandé.
- Message de courtoisie dans le groupe WhatsApp (« PV de l'AG envoyé par mail ») : **écrit par Alexandre** tant que
  l'envoi par le client non officiel n'est pas décidé (risque de bannissement).

## 4. Coûts (estimation du 24/10, à recalculer au moment de coder)

- Temps : O1 1 soirée, O2 une demi-soirée, O3 1, O4 1, O5 1 à 2.
- Crédits API : un groupe de copropriété parle bien moins que la conversation avec Yoann ; résumés de nuit de
  l'ordre de quelques centimes par mois ; import de l'historique, une fois, selon sa taille.
- Recommandé électronique : payant à l'envoi (prix du prestataire à relever).

## 5. À trancher avec Alexandre

1. Nombre de propriétaires et où sont leurs mails aujourd'hui.
2. Accepter le risque d'un client WhatsApp non officiel sur son compte personnel (réception seule).
3. Garder les PDF reçus dans le groupe (devis, factures) au-delà de 30 jours ?
4. Format du projet d'ordre du jour (Google Docs, PDF, modèle existant de la copro ?).
5. Recommandé électronique : déjà utilisé ? Propriétaires qui l'ont accepté par écrit ?
