# Mémoire des échanges Signal (plan P9-J)

État au 18/10/2026 : J1 à J3 en service sur Home Assistant pour la conversation avec Yoann (accord donné). **J5 fait
le 18/10** : historique importé depuis Signal Desktop (161 636 messages, du 6/10/2022 au 17/10/2026), résumés par la
Batch API en cours. Texte brut gardé **sans limite** (choix d'Alexandre le 18/10, après l'import). J4 (question
depuis l'app) : plus tard, le skill `memoire-signal` en tient lieu.

## Ce qui tourne

- **Capture** : l'app AppDaemon `aiguillage_signal` passe chaque notification de signal-cli à
  `aiguillage_memoire.py`. Sont gardés les messages des conversations à deux avec les numéros des `sources` (ou de
  `memoire.conversations`) de `/config/aiguillage_signal.json`, reçus comme envoyés depuis l'iPhone. Les groupes, les
  réactions et les accusés sont ignorés. Un message modifié remplace l'ancien texte, un message supprimé « pour tous »
  est retiré. La mémoire commence le 17/10/2026 au soir : un appareil lié ne reçoit pas l'historique.
- **Base** : `/config/aiguillage_memoire.sqlite` (dossier d'AppDaemon, donc dans les sauvegardes HA), avec l'index
  plein texte FTS5 (accents ignorés).
- **Chaque nuit à 3 h** : résumé de chaque jour des 7 derniers jours qui n'en a pas encore, résumé de la semaine
  passée le lundi, du mois passé le 1er (Sonnet 5.5, effort `medium`, même clé API que le tri ; budget
  `memoire_budget_mensuel`, 5 $ par défaut, coût du mois dans `/config/aiguillage_memoire_etat.json`). Chaque résumé
  est aussi copié dans `donnees_apps`, espace `memoire`, clé `yoann-jour-2026-10-17` (ou `-semaine-2026-W42`,
  `-mois-2026-10`) : `{conversation, niveau, periode, resume, faits: [{type, texte, quand}], mots_cles}`.
- **Purges, chaque nuit** : texte brut retiré après `memoire.garder_textes_jours` jours quand son jour est résumé
  (0 : jamais, réglage actuel ; 365 par défaut) ; résumés du jour retirés de `donnees_apps` après 60 jours (ils restent
  dans SQLite et sortent dans la recherche) ;
  pièces jointes de plus de 30 jours supprimées de l'add-on Signal (`DELETE /v1/attachments/<id>`). La mémoire ne
  garde des pièces jointes que leur type (« photo », « note vocale »).
- **Journal** : lignes « Signal : mémoire, … » (comptes et coûts seulement, jamais le texte des messages) ; capteur
  `sensor.aiguillage_signal`, attribut `memoire` (nombre de messages).

## Chercher depuis Claude (claude.ai ou Claude Code, connecteur Home Assistant)

Le plus simple : le **skill personnel `memoire-signal`** (il commence par la recherche, qui couvre aussi les
résumés, et ne lit jamais tout l'espace `memoire`) (hors dépôt, `~/.claude/skills/memoire-signal/` pour Claude Code ; même dossier zippé à importer dans claude.ai, Réglages › Skills) fait tout seul les appels ci-dessous ; il suffit de demander « qu'est-ce que Yoann m'a conseillé comme resto ? ». Sans le skill, deux façons, à demander telles quelles à Claude :

1. **Un résumé précis** : « Lis `donnees_apps.lire` `{"espace": "memoire", "cle": "yoann-mois-2024-07"}` et dis-moi
   ce qu'on s'est dit en juillet 2024. » (Semaines et mois depuis 2022, jours des 60 derniers jours.)
2. **Dans le texte exact des messages** : « Déclenche l'événement `aiguillage_memoire_chercher` avec
   `{"requete": "resto italien"}`, attends 3 secondes, puis lis `donnees_apps.lire` `{"espace": "memoire", "cle":
   "recherche"}` et réponds-moi en citant les dates. » Le résultat contient au plus 30 messages (les plus récents
   d'abord) qui ont **tous** les mots de la requête, chacun avec le message d'avant et d'après, plus les résumés qui
   en parlent.
3. **Les derniers messages, ou ceux d'un jour** : même événement avec `{"requete": "*"}` (30 derniers messages) ou
   `{"requete": "*", "jour": "2026-10-17"}` (tous les messages de ce jour). Les mots d'une seule lettre sont ignorés :
   une requête « a » revient à « * ».

## Importer un historique (J5, fait le 18/10/2026)

1. Relier Signal Desktop à l'iPhone **avec le transfert de l'historique** (Appareils liés › délier le Mac, puis le
   relier en choisissant « Transférer l'historique des messages » ; sauvegarder d'abord
   `~/Library/Application Support/Signal`).
2. Exporter la seule conversation avec `signal-export` (environnement à part, hors dépôt) :
   `~/.config/aiguillage/venv-sigexport/bin/sigexport ~/.config/aiguillage/export-signal --chats "<nom du contact>"
   --no-html --json --no-attachments --no-stickers` (macOS demande l'accès au trousseau : « Signal Safe Storage »).
3. Copier `…/<contact>/data.json` dans le dossier d'AppDaemon (`/config/memoire_import.jsonl`), puis déclencher
   l'événement `aiguillage_memoire_importer` avec `{"fichier": "/config/memoire_import.jsonl", "expediteur":
   "<nom dans l'export, ex. PrenomNom>", "conversation": "<nom de la mémoire, ex. Yoann>"}`. AppDaemon importe (sans
   doublon : seulement avant le premier message capturé en direct), puis lance la **Batch API** (moitié prix) : les
   jours sans résumé, puis les semaines et les mois. Suivi toutes les 10 min, état dans
   `/config/aiguillage_memoire_etat.json` (`import`, `cout_import`), journal « Signal : mémoire, batch … ».
4. Supprimer la copie `/config/memoire_import.jsonl` une fois l'import fait.

## Réglages

`/config/aiguillage_signal.json` (jamais dans un dépôt) : `"memoire": {"actif": true}` (et, au besoin,
`"conversations": {"+33…": "Nom"}`, sinon les `sources`). `apps.yaml`, app `aiguillage_signal` : `workspace_id`
(espace de travail de la clé d'utilisateur), `memoire_budget_mensuel`, et au besoin `memoire_modele`,
`memoire_effort`, `memoire_heure`. Pour arrêter : `"actif": false` (la base reste).
