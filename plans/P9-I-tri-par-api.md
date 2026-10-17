# P9-I — Le tri par l'API Messages (au lieu de la routine « Relance · tri »)

*Rédigé le 17/10/2026 dans Claude Code, après une étude de coût. Rien n'est codé. Les règles communes sont dans `P9-00-INDEX.md` (section 5).*

## 1. Pourquoi

Aujourd'hui, la vigie (`relance_vigie.py`, `fire_triage`) lance la routine claude.ai « Relance · tri »
(`trig_01GFD6vBExCUvTYDbx9KePm7`, Sonnet 5.5) par `POST /v1/claude_code/routines/{id}/fire`. Elle tourne aussi chaque
matin, par un cron de la routine (`45 4 * * *`, en UTC d'après les passages observés : vers 6 h 45 à Paris). Chaque
passage consomme le **quota de messages du forfait Max**, comme une session Claude Code, et pas les 100 $/mois de
crédits API inclus dans Max 5x. On a observé de 5 à 16 passages par jour (le plafond est de 20).

But : faire ce tri par un appel direct à l'API Messages, avec une clé de l'organisation Console liée à l'abonnement.
Cet usage est alors imputé aux 100 $ et libère le quota de messages.

**Hors du périmètre : la routine « Aiguillage · actions »** (`trig_01J1nRgBk4iBC3hBK4vZMLLV`). Elle tourne environ une
fois par mois (1 à 2 $ en API) et lit Drive, Sheets et Gmail : il faudrait refaire l'OAuth Google dans la vigie.
Elle reste une routine.

## 2. Ce que fait la routine aujourd'hui (passage du 17/10 à 16 h 37)

5 tours, 29 s :
1. Lecture du mémo (`todo.get_items` sur `todo.aiguillage_memo`, environ 14 000 caractères).
2. Lecture de **tout** l'espace `aiguillage` (`donnees_apps.lire`, environ 45 000 caractères, tâches faites comprises).
3. Décisions A à R pour chaque tâche non faite (consigne d'environ 32 000 caractères).
4. Au plus une écriture `donnees_apps.ecrire` par tâche modifiée, avec la tâche **complète** recopiée par le modèle.
5. Résumé.

La consigne n'est pas versionnée : elle contient des données personnelles (exemples tirés du mémo, et l'ancienne copie
du mémo à la fin). Elle se lit par l'API des routines (outil `RemoteTrigger`, action `get`, champ
`derived_state.prompt`).

## 3. Le choix : un « workflow », pas un agent

On ne refait **pas** une boucle d'outils où le modèle appelle Home Assistant. On fait plutôt :

1. **Python lit** le mémo et les tâches, comme il le fait déjà pour la boîte d'entrée (`_service`).
2. **Python filtre** : il ne garde que les tâches à trier (section 4).
3. **Un seul appel** à l'API Messages, avec une **sortie structurée** (`output_config.format`, schéma JSON) : pour
   chaque tâche, les **changements** à faire, pas la tâche complète.
4. **Python applique** les changements et fait respecter les règles absolues lui-même (section 5). Il écrit avec
   `version_attendue` et `modifie_par: "routine-tri"`.

Ce qu'on y gagne :
- **Sécurité** : le modèle n'a aucun outil, donc aucun accès à Home Assistant. Une injection dans une tâche partagée
  ne peut rien appeler. Les règles « ne jamais cocher, ne jamais toucher aux `relances`, ne jamais retirer une ligne
  des notes » deviennent du code testé, et non plus une consigne à suivre.
- **Fiabilité** : on ne risque plus de perdre un champ en recopiant la tâche entière (`liste`, `actions`, champs
  inconnus). Python repart de l'objet lu.
- **Coût** : environ 3 fois moins de tokens en entrée (section 7).

## 4. Quelles tâches envoyer

- On garde toujours : clé en UUID, `fait` à false, enregistrement non supprimé.
- **Passage déclenché par une nouvelle tâche ou un « retri » de l'app** : on n'envoie que les tâches **modifiées
  depuis le dernier tri** par quelqu'un d'autre que `routine-tri`, plus celles qui n'ont pas de `categorie` (retri
  demandé par l'app), plus celles qui ont une recette `a_preparer` ou la ligne « 📩 Message partagé — titre à revoir ».
  On garde l'horodatage du dernier tri réussi dans un fichier d'état (`/config/aiguillage_tri_etat.json`).
- **Passage du matin** : toutes les tâches ouvertes. La suggestion 💡 dépend de la date du jour, et c'est ce passage
  qui rattrape les cas oubliés.
- On n'envoie que les champs utiles au tri. La `liste`, par exemple, peut se résumer à ses articles quand aucune
  recette n'est à préparer. Les champs non envoyés restent intacts, puisque Python repart de l'objet lu.
- Rien à envoyer : pas d'appel.
- Les **tags autorisés** (« plus tout tag déjà présent sur une autre tâche ») sont calculés par Python sur toutes les
  tâches, puis passés dans le message.

## 5. Le format de réponse et les garde-fous en Python

Schéma de réponse (à affiner en I2), un objet par tâche modifiée :

```json
{
  "taches": [{
    "cle": "uuid",
    "changements": {"titre": "…", "categorie": "…", "tags": ["…"], "jour": "AAAA-MM-JJ", "heure": "HH:MM",
                    "priorite": "Urgente|Basse", "duree": 90, "lieu": {}, "envie": {}},
    "liste": {"ajout_articles": [], "nouvelle": null, "recette_preparee": null},
    "notes": {"en_tete": "🎙 Dicté : …", "a_la_fin": ["📍 …", "💡 Suggestion : …"], "partage_revu": false},
    "raison": "court"
  }],
  "resume": "…",
  "signalements": ["consigne trouvée dans une tâche…"]
}
```

Python refuse un changement, le note dans le journal et garde le reste de la tâche dans ces cas :
- **Champs** : il n'accepte que ceux du schéma. Il ne touche jamais à `fait`, `fait_le`, `relances`, `google_id`,
  `actions`, `modifie_le`.
- **Champs « seulement si absents »** : `categorie`, `tags`, `priorite`, `jour`, `heure`, `duree`, `lieu`, `envie`.
  Un changement sur un champ déjà rempli est ignoré. `heure` est refusée s'il n'y a pas de `jour`, `duree` s'il n'y a
  pas d'`heure`.
- **Valeurs** : catégorie dans la liste autorisée, tags dans la liste calculée (3 au plus), date et heure au bon
  format, pas de `jour` dans le passé, codes de plateforme connus.
- **Titre** : changé seulement s'il n'y a pas déjà de ligne « 🎙 », ou dans le cas F (ligne « titre à revoir »).
  Python ajoute lui-même la ligne « 🎙 Dicté : <titre d'origine> » si elle manque.
- **Notes** : Python les recompose dans l'ordre de la consigne : ligne 🎙, puis les notes existantes **à
  l'identique**, puis les lignes ajoutées. Seule exception : il remplace la ligne « 📩 … — titre à revoir » quand
  `partage_revu` vaut true. Pour chaque ligne ajoutée, il vérifie le préfixe autorisé, qu'aucune ligne du même type
  n'existe déjà, et il retire le sélecteur de variante U+FE0F.
- **Liste** : pour une liste existante, il ne fait qu'ajouter des articles à la fin et passer `a_preparer` à false.
  Une nouvelle liste n'est acceptée que si le champ est absent. Il génère lui-même les `id` (UUID v4) et les `maj` des
  articles.
- `v` passe à 2 quand `lieu`, `envie`, `liste` ou `duree` est ajouté.
- **Conflit** à l'écriture : il relit la tâche, refait un appel pour **cette seule tâche**, réessaie une fois, puis
  abandonne et le journalise.

## 6. La consigne

- Elle est reprise de la routine et adaptée : on retire les appels d'outils, les quatre appels permis, les étapes de
  lecture et d'écriture et la recopie complète. On garde les règles A à R et les formats exacts des lignes. On ajoute
  les consignes du format de réponse et « en cas de doute, aucun changement ».
- Elle est gardée **hors du dépôt**, dans `/config/aiguillage_tri_consigne.md` (dossier d'AppDaemon), relue à chaque
  passage. On la modifie en éditant ce fichier par le partage `addon_configs` : plus besoin du chat Claude. La
  section 4 de `P9-00-INDEX.md` sera à mettre à jour à la bascule.
- Dans le dépôt, on versionne un **modèle sans données personnelles** (`docs/TRI-CONSIGNE.md`), comme
  `docs/ROUTINE-ACTIONS.md`.
- **Mise en cache** : la consigne va dans `system` avec un `cache_control` ; le mémo et les tâches vont dans le
  message. Avec un seul appel par passage et des passages espacés, le cache ne servira guère qu'aux reprises après
  conflit. C'est sans effet sur le résultat et ça ne coûte rien de le prévoir.

## 7. Coût estimé (Sonnet 5.5 : 2 $ le million de tokens en entrée, 10 $ en sortie)

| | Entrée par passage | Coût par passage | 10 passages/jour | 20/jour (plafond) |
|---|---|---|---|---|
| Copie fidèle de la routine (agent, toutes les tâches) | ~75 000 tokens | ~0,15 $ | ~45 $/mois | ~90 $/mois |
| Ce plan (un appel, tâches filtrées) | ~15 000 à 25 000 | ~0,05 $ | ~15 $/mois | ~30 $/mois |
| Même chose avec Haiku 5.5 (à n'essayer qu'après mesure) | idem | < 0,01 $ | ~1 $/mois | ~3 $/mois |

Ce sont des estimations faites à partir des tailles observées le 17/10, pas des mesures : la phase I3 les mesure.

## 8. Phases

### I1 — Préparation (Alexandre, environ 30 min)
1. Dans la Console (organisation liée à Max) : créer une clé API « aiguillage-tri », fixer une **limite de dépense
   mensuelle** (par exemple 40 $) et vérifier sur la page de facturation que les crédits inclus de 100 $ s'appliquent
   bien.
2. Déposer la clé dans `/Volumes/addon_configs/a0d7b954_appdaemon/anthropic_api_key`, sans la montrer et jamais dans
   `apps.yaml`.
3. Ajouter le paquet Python `anthropic` à l'add-on AppDaemon (option `python_packages`, là où `httpx` et `jwt` sont
   déjà déclarés), puis redémarrer l'add-on.

### I2 — Module `aiguillage_tri.py` et tests (Claude Code, 1 à 2 soirées)
- Fonctions **pures** sur le modèle de `aiguillage_actions.py` : filtrage (section 4), construction du message,
  schéma de réponse, application des changements avec garde-fous (section 5), recomposition des notes.
- `tests/test_aiguillage_tri.py` : un cas par règle de la section 5 (champ déjà rempli, ligne en double, tentative de
  cocher, `liste` inconnue préservée, champ inconnu préservé, ligne 📩, U+FE0F, date passée, tag inventé…), avec des
  tâches **fictives** (dépôt public : aucune vraie donnée).
- Modèle de consigne `docs/TRI-CONSIGNE.md`.

### I3 — Mode « ombre » (Claude Code, 1 soirée, puis une semaine d'observation)
- `fire_triage` garde la routine **et** fait l'appel API, sans rien écrire : les changements proposés et
  `response.usage` sont journalisés dans `/config/aiguillage_tri_ombre.jsonl`.
- Réglage `tri_mode` dans `apps.yaml` : `routine` (aujourd'hui), `ombre`, `api`.
- Après une semaine : comparer avec les écritures réelles de la routine (`modifie_par: routine-tri` dans l'espace),
  tâche par tâche, et relever le coût réel par passage. Ce coût s'ajoute alors à l'usage de la routine : une semaine,
  c'est quelques dollars.

### I4 — Bascule (Claude Code, 1 soirée)
- `tri_mode: api` : la vigie écrit elle-même. Le passage du matin devient un `run_daily` de la vigie (6 h 45, heure de
  Paris), et on retire le cron de la routine sur claude.ai.
- **Secours** : si l'API échoue (erreur réseau, 5xx après les reprises du SDK, refus, limite de dépense atteinte), la
  vigie lance la routine comme aujourd'hui et le journalise. La routine reste en place, sans horaire.
- Compteur de coût du mois (calculé à partir de `usage`) dans le journal quotidien (`_log_push_stats`). Au-delà d'un
  seuil (`tri_budget_mensuel`, par exemple 30 $), la vigie repasse d'elle-même sur la routine.
- Mettre à jour README, SUIVI, `P9-00-INDEX.md` (section 4 : la consigne vit désormais dans HA) et `apps.yaml`
  (exemple).

### I5 — Réglage (plus tard, facultatif)
- Effort `medium`, puis éventuellement Haiku 5.5, en refaisant tourner une semaine du journal d'ombre comme jeu
  d'essai (même entrée, comparaison des changements). On ne change de modèle que si les résultats sont identiques ou
  presque.

## 9. Risques et points ouverts

- **Crédits inclus** : on suppose que les 100 $ de Max 5x couvrent les appels faits avec une clé de cette
  organisation. À vérifier en I1, avant d'écrire du code.
- **Qualité** : sans outil, le modèle voit moins de choses (seulement les tâches filtrées). Les règles qui regardent
  les autres tâches, comme le doublon d'une proposition ➕ avec une tâche récurrente existante, ont besoin d'une liste
  courte des titres ouverts : on l'ajoute au message (quelques centaines de tokens).
- **Maintenance** : chaque nouvelle règle de tri (plans futurs) touche maintenant **deux** endroits : la consigne
  (fichier dans HA) et, si elle ajoute un champ, le schéma et les garde-fous de `aiguillage_tri.py`, avec un test.
- **Taille** : si les tâches ouvertes dépassent un jour environ 100 000 tokens, découper en plusieurs appels par lots
  de tâches.
