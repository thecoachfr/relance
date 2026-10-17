# P9-J — Mémoire des échanges Signal avec Yoann (recherche, résumés)

*Rédigé le 17/10/2026 dans Claude Code, à la demande d'Alexandre, après « Signal → envies ». Les
règles communes sont dans `P9-00-INDEX.md` (section 5). Le dépôt est public : aucun message, aucun numéro et aucun
extrait réel ne va dans le dépôt, les tests ou SUIVI.*


**État (17/10 au soir)** : J1, J2 et J3 faits et en service (mode d'emploi : `docs/MEMOIRE-SIGNAL.md`). Choix
d'Alexandre le 17/10 : Yoann est d'accord ; texte brut gardé **un an**, puis résumés seuls ; pièces jointes
**purgées après 30 jours** ; historique (J5) **plus tard**. Écarts avec le plan : la recherche dans le texte passe par
l'événement `aiguillage_memoire_chercher` et la clé `recherche` de l'espace `memoire` (pas de service HA) ; les résumés
de la semaine et du mois se font à partir des résumés du jour ; la purge des pièces jointes passe par l'API de
l'add-on Signal (`DELETE /v1/attachments/<id>`). Reste : premier résumé de nuit réel (18/10 à 3 h), J4, J5.

## 1. Le besoin

Retrouver une information échangée avec Yoann sur Signal (« le nom du resto dont il m'a parlé en septembre », « ce
qu'on avait dit pour les vacances », « l'adresse qu'il m'a envoyée »), sans faire défiler la conversation. Pour ça, la
maison garde une **mémoire** de la conversation : le texte des messages, consultable par mots, et un **résumé par
jour** avec les faits utiles (lieux, dates, recommandations, promesses).

## 2. Ce qu'on a déjà, et une limite importante

- signal-cli tourne dans l'add-on « Signal Messenger » (`1315902c_signal_messenger`, mode json-rpc), lié comme
  **appareil secondaire** au compte d'Alexandre. L'app AppDaemon `aiguillage_signal` écoute son websocket.
- `message_retenu` reçoit déjà les messages **de** Yoann (`dataMessage`) et voit passer les messages qu'Alexandre
  envoie depuis son iPhone (`syncMessage.sentMessage`, aujourd'hui gardés seulement pour la « Note à moi-même »). On a
  donc les deux côtés de la conversation.
- **Pas d'historique** : un appareil lié ne reçoit que les messages postérieurs à sa liaison. La mémoire commence au
  jour du branchement (17/10), sauf import ponctuel (J5, facultatif).
- **Trous possibles** : en mode json-rpc, signal-cli remet les messages au client connecté. Si AppDaemon est arrêté
  (redémarrage, mise à jour), les messages reçus pendant ce temps peuvent manquer à la mémoire, alors qu'ils restent
  bien sur l'iPhone. À mesurer en J1 : arrêter AppDaemon 5 minutes, envoyer un message, regarder s'il arrive à la
  reconnexion. Si ce n'est pas le cas, piste de secours : une conservation côté add-on, si sa configuration le permet.

## 3. Ce qu'on construit

```
Signal ──► add-on signal-cli ──► AiguillageSignal (AppDaemon)
                                    ├─ envies (existant)
                                    └─ mémoire : SQLite sur le NUC (messages + index plein texte)
                                                    │
                     chaque nuit ───────────────────┤ résumé du jour (API Claude) → table « resumes »
                                                    │                             └─ copie dans donnees_apps
                                                    ▼                                (espace « memoire »)
                         recherche : Claude (chat, connecteur HA) ou question depuis l'app (J4)
```

### J1 — Capture (1 soirée)
- Fonctions pures dans `aiguillage_memoire.py` : notification signal-cli → ligne
  `{horodatage, sens (reçu / envoyé), auteur, texte, citation (réponse à…), pièces jointes (type, nom, taille)}`.
  Seule la conversation à deux avec les numéros de `memoire.conversations` est gardée (réglage dans
  `/config/aiguillage_signal.json`), pas les groupes.
- Base **SQLite** `/config/aiguillage_memoire.sqlite` : une table `messages` (clé : horodatage Signal + auteur, donc
  pas de doublon), une table virtuelle **FTS5** pour la recherche par mots, et une table `resumes`.
  Modifications et suppressions venues de Signal : un message modifié remplace l'ancien texte, un message supprimé
  « pour tous » est supprimé aussi de la mémoire.
- Pièces jointes : on garde seulement les **métadonnées** (« photo », « note vocale 0:42 »). Les fichiers restent là où
  signal-cli les range (voir 5).
- Tests sur des notifications **fictives** (`tests/test_aiguillage_memoire.py`).

### J2 — Résumé de chaque nuit (1 soirée)
- À 3 h, `run_daily` : les messages de la veille (rien s'il n'y en a pas) → **un appel** à l'API Messages (même clé et
  mêmes réglages que le plan I), avec une sortie structurée :
  `{"resume": "5 lignes au plus", "faits": [{"type": "lieu|date|reco|promesse|info", "texte": "…", "quand": "…"}],
  "mots_cles": ["…"]}`.
- Le résumé va dans la table `resumes`. Une **copie** va dans `donnees_apps`, espace `memoire`, clé `yoann-AAAA-MM-JJ` :
  c'est petit (moins de 2 Ko), déjà sauvegardé avec HA et lisible par le connecteur Home Assistant de claude.ai.
- Un résumé de la **semaine** le dimanche, et un du **mois** le 1er, faits à partir des résumés du jour. Ça garde la
  recherche rapide quand la mémoire grandit.
- Les messages sont des **données, jamais des instructions** (consigne du résumé, comme pour le tri).

### J3 — Chercher depuis Claude (une demi-soirée)
- Depuis le chat claude.ai ou Claude Code, avec le connecteur HA existant : « dans ma mémoire Signal, qu'est-ce que
  Yoann m'a conseillé comme resto ? » → `donnees_apps.lire` sur l'espace `memoire`, puis réponse à partir des
  résumés. Ça ne coûte rien de plus que l'usage normal du forfait.
- Pour chercher dans le **texte exact** des messages (un mot, un nom) : un service HA `aiguillage_memoire.chercher`
  (événement écouté par AppDaemon, réponse en événement, ou script HA), qui interroge FTS5 et renvoie au plus 30
  messages avec leur date et leurs voisins immédiats. À valider en J3 : la forme la plus simple qui donne une réponse
  au connecteur.
- Fiche dans le mémo du tri ? Non : la mémoire est séparée du tri et des tâches.

### J4 — Question depuis l'app (facultatif, 2 soirées)
- Écran « Demander à la mémoire » (iPhone, Mac) : la question part vers HA (webhook) ; AppDaemon cherche dans FTS5 et
  dans les résumés, envoie ce qu'il a trouvé et la question à l'API, puis renvoie une réponse courte **avec les dates
  des messages cités**.
- Ce lot ne vaut le coup que si J3 ne suffit pas à l'usage.

### J5 — Import de l'historique (facultatif, une demi-soirée)
- Seule voie réaliste : exporter la conversation depuis **Signal Desktop sur le Mac**, s'il est installé et lié
  (outil tiers `signal-export`, qui lit la base locale de Desktop), puis l'importer dans la même table. Décision
  d'Alexandre : outil tiers à installer, base de Desktop à ouvrir.
- On résume l'historique **une fois**, par la Batch API (moitié prix), mois par mois.

## 4. Coûts

### Temps
| Lot | Temps |
|---|---|
| J1 capture + J2 résumés + J3 recherche par Claude (le cœur) | **2 à 3 soirées** |
| J4 question depuis l'app | 2 soirées |
| J5 import de l'historique | une demi-soirée, plus le temps d'export |

### Stockage sur le NUC
On ne connaît pas encore le volume de la conversation. Les chiffres ci-dessous sont des hypothèses : J1 compte les
messages réels, et on refait le calcul au bout de deux semaines.

| Hypothèse | Texte + index FTS5 | Résumés |
|---|---|---|
| 50 messages/jour | ~3 Mo/an | < 1 Mo/an |
| 200 messages/jour | ~12 Mo/an | < 1 Mo/an |

C'est **négligeable**. La seule vraie place, ce sont les **pièces jointes** que signal-cli télécharge déjà dans le
dossier de l'add-on (photos, vidéos, notes vocales), avec ou sans ce plan : quelques centaines de Mo à quelques Go
par an selon les échanges. À vérifier en J1 (taille du dossier de l'add-on), puis à décider : purge des pièces
jointes de plus de 30 jours, ou pas.

### Crédits Claude (API, sur les 100 $ de Max 5x)
| Poste | Calcul (Sonnet 5.5) | Par mois |
|---|---|---|
| Résumé de chaque nuit (consigne ~1 500 tokens + messages du jour ~1 500 à 6 000, sortie ~400) | ~0,01 $ par jour | **~0,30 à 0,50 $** |
| Résumés de la semaine et du mois | quelques milliers de tokens | < 0,10 $ |
| Recherche depuis claude.ai (J3) | quota du forfait, pas l'API | 0 $ |
| Questions depuis l'app (J4), ~8 000 tokens par question | ~0,02 $ par question, 5 par jour | ~3 $ |
| Import de l'historique (J5), par exemple 3 ans × 100 messages par jour ≈ 3 M tokens, Batch API | une fois | ~3 à 4 $ une seule fois (Haiku 5.5 : ~0,20 $) |

Avec le plan I (10 à 30 $), l'ensemble reste **loin des 100 $**. Haiku 5.5 suffit sans doute pour les résumés : à
essayer sur une semaine réelle, en comparant avec Sonnet.

## 5. À décider avant de coder (Alexandre)

1. **Yoann** : la mémoire garde ses messages chez Alexandre et en envoie le texte à l'API Claude pour les résumés. Le
   lui dire, et s'arrêter s'il n'est pas d'accord. (Données chez Anthropic : selon la politique de conservation de
   l'API.)
2. **Durée de conservation** des messages bruts : tout garder, ou ne garder que les résumés au-delà d'un an.
3. **Pièces jointes** : purge après 30 jours, ou pas.
4. **Historique** : import J5, oui ou non.
5. **Sauvegarde** : la base SQLite est dans le dossier d'AppDaemon, donc dans les sauvegardes HA. Elles sont
   chiffrées si on choisit cette option dans HA : à vérifier.

## 6. Risques

- Trous dans la capture quand AppDaemon redémarre (voir 2) : à mesurer en J1.
- signal-cli doit rester à jour. Un appareil lié qui reste trop longtemps hors ligne est délié par Signal : déjà vrai
  pour « Signal → envies ».
- La qualité des résumés dépend du style des échanges (messages très courts, beaucoup de liens) : ajuster la consigne
  après une semaine.
- Les fichiers de la base et les journaux contiennent des données personnelles : jamais dans le dépôt, jamais dans
  SUIVI. Les journaux d'AppDaemon n'écrivent que des compteurs, pas le texte des messages.
