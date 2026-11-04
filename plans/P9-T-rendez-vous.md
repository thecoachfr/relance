# P9-T — Rendez-vous : une quatrième nature, et une vigie qui classe les natures

*Plan du 04/11/2026, demandé par Alexandre après l'analyse des 170 tâches de HA. Lire d'abord `P9-00-INDEX.md` et
`P9-P-pour-info.md`. Dépôts : relance + HA + hub-ipad et hub-tv (« un Hub, trois vues »).*

*Dépôt public : aucun nom, adresse ni donnée personnelle dans ce plan.*

## 1. Le besoin

Aiguillage a trois natures : Tâche, Info, Envie. Il en manque une : ce qui a lieu à une date et une heure fixes, où il
suffit d'y aller (dentiste, soirée, expertise, intervenante à domicile).

**Mesure du 04/11** (68 éléments ouverts) : 13 sont des rendez-vous, rangés dans les trois natures.

| Rangés en | Ouverts | Conséquence aujourd'hui |
|---|---:|---|
| Tâche | 6 | « En retard » une fois l'heure passée, à cocher, suggestions 💡 inutiles |
| Envie (🎟 Sortie) | 5 | Bonnes relances, mais la nature Envie est détournée (seule envie datée) |
| Info | 2 | Aucun rappel possible : Info sert de « ne me relance pas » |

Autres constats, traités ici :
- **Le tri ne connaît pas `📣`** : ni `aiguillage_tri.py`, ni la consigne réelle, ni `relance_vigie.py`. Il ne pose
  jamais d'info et continue d'ajouter des 💡 aux infos.
- **Le tri ne pose `🎟` que s'il voit un billet** (règle T de la consigne réelle) : un rendez-vous sans billet reste
  une tâche.
- **`docs/TRI-CONSIGNE.md` a du retard** : la règle T et `🎟` n'y sont pas.
- **Mails transformés en tâche** (`tache_du_mail`, action de l'app Courrier ou de l'agent) : sans `demande`, le titre
  devient « Répondre à … », même pour une expédition, une promo ou une lettre d'information (4 cas sur 5 relevés).

## 2. Les règles

**Marqueur** : ligne cachée `📌 Rendez-vous` dans les notes, copiée en mode HA (champ `notes`, pas de nouveau champ
TacheHA, comme `📣`). Date obligatoire, heure attendue mais facultative.

| | Tâche | Rendez-vous | Info | Envie |
|---|---|---|---|---|
| Date | facultative | **obligatoire** | obligatoire | aucune (sauf 🎟) |
| Rappels | insiste | **avant, jamais après** | résumé du matin | autour de la période |
| Retard | oui | **jamais** | jamais | jamais |
| À cocher | oui | **non** | non | oui |
| Une fois passé | reste | **se range ou avance** | se range ou avance | reste (🎟 attend « Vu ») |

- **Une fois passé** : même mécanique que `PourInfo.suite` (à mettre en commun), après la fin de la journée. Écrit par
  l'appareil qui relance, jamais par la vigie.
- **Reste à cocher ?** Non, mais supprimer depuis la fiche reste possible (rendez-vous annulé).
- **`📣 Pour info`** garde son sens : un signal sans rien à faire. Les sorties gardent `🎟` : aucune migration, ni des
  billets ni des listes d'Envies.
- **Dans le code** : `TaskItem.aHoraireFixe` (vrai pour `📌` et `🎟`) remplace les tests `kind.isDated` qui concernent
  le retard et À faire.

## 3. Décisions d'Alexandre (04/11)

1. **Rendez-vous ponctuel** : veille au soir, puis 2 h avant ; le rappel de départ (lieu) et « Prévenir » s'ajoutent.
   Pas de rappel à J-7.
2. **Rendez-vous récurrent** : résumé du matin seulement, plus « Prévenir » si demandé.
3. **Sport et intervenante restent en Info**, comme les poubelles : aucune reprise pour eux.
4. **La vigie classe seule** après une semaine d'essai à blanc relue ensemble, sur les nouvelles tâches seulement,
   jamais après une correction.

## 4. Lots

| Lot | Contenu | Dépôt |
|---|---|---|
| **R1** | Modèle `RendezVous` (marqueur, notes, `hiddenPrefixes`), `aHoraireFixe`, `isOverdue`, planificateur (décisions 1 et 2), résumés du matin et du soir, passage partagé avec `PourInfo`, tests | relance |
| **R2** | Sélecteur Tâche · RDV · Info · Envie (`NatureTache`, saisie rapide, fiche, date obligatoire) ; À faire, Agenda, Mac, widgets, montre : sans bouton Fait ni retard ; pas d'activité en direct | relance |
| **R3** | Trois vues du Hub : pas de retard ni de coche, repère visuel ; contrat dans `homeassistant/` | relance (Nest Hub) + hub-tv + hub-ipad |
| **R4** | Tri : champ `nature` (`""`, `rendez_vous`, `info`) dans `SCHEMA`, `appliquer` qui ajoute la ligne, gardes Python, plus de 💡 sur `📌` et `📣` ; consigne réelle, puis modèle remis à jour (règle T et `🎟` compris) ; essai à blanc | relance + NUC |
| **R5** | Courrier : titre de repli neutre sans « Répondre à » ; `tache_du_mail` propose la nature d'après la `demande` et l'`echeance` | relance + NUC |
| **R6** | Reprise des 6 tâches ouvertes qui sont des rendez-vous : liste validée par Alexandre, puis écriture en un lot, après sauvegarde | HA |

**Ordre** : R1 → R2 → R3 → R4 → R5 → R6. **R3 doit être déployé avant R4** : sinon la vigie poserait des `📌` que les
Hubs montreraient en retard, et l'app doit lire le marqueur partout avant qu'il apparaisse dans les données.

**Gardes de R4** (Python, pas seulement la consigne) :
- Nature posée seulement sur une tâche **nouvelle** (sans `categorie` avant ce passage). C'est ce qui protège une
  correction à la main : une tâche déjà triée n'est jamais reclassée.
- `rendez_vous` refusé sans `jour`, ou si la tâche a une `liste`, une envie, une ligne `📣` ou `📌` ; `info` refusé
  sans `jour`. Tout refus est noté (`refus`) et le reste de la tâche s'applique.
- Dans le doute, le modèle laisse `""` : une tâche reste la valeur sûre, car elle relance.
- Critère donné au modèle : « y aller suffit-il ? » → rendez-vous ; « faut-il faire quelque chose avant ? » → tâche
  (« prendre rendez-vous », « préparer le dossier » restent des tâches).

**Essai à blanc de R4** : `tri_mode: ombre` ne convient pas (il repasse la routine en tri principal). Ajouter un
réglage `tri_natures` (`essai` / `actif`) : en `essai`, les natures proposées vont dans
`/config/aiguillage_tri_ombre.jsonl` sans être écrites. Passage en `actif` après relecture, avec Alexandre.

## 5. Critères de réussite

- Aucun rendez-vous « En retard » sur aucun écran, ni dans les trois vues du Hub.
- Sur la semaine d'essai : aucune vraie action classée en rendez-vous ou en info, car elle ne serait plus relancée.
  C'est l'erreur à éviter en priorité ; l'erreur inverse (rendez-vous resté tâche) est sans gravité.
- Aucune 💡 ajoutée à un `📌` ou un `📣`.
- Tests Swift et Python verts, `nest-hub-leger-card.js` vérifiée au banc.

## 6. Risques

- **Une action classée à tort en rendez-vous n'est plus relancée** : d'où les gardes, l'essai à blanc et la valeur
  sûre « tâche ».
- **Ancienne build sur un appareil** : `📌` y apparaîtrait dans les notes et le rendez-vous resterait une tâche ;
  sans gravité, déployer R2 partout avant R4.
- **Rendez-vous sans heure** : rappel du matin seulement.

## 7. État

- 04/11 : plan rédigé, décisions prises.
- 04/11 : **R1 codé**, pas encore visible : rien ne pose `📌` avant R2. `Shared/Model/RendezVous.swift`, planificateur,
  résumé du matin (« Rendez-vous : … »), pas dans le résumé du soir (le rappel de la veille suffit),
  `avancerPasses` commun avec les infos, tests dans `RelanceTests/RendezVousNatureTests.swift`.
  Correctif au passage : une sortie entre minuit et 2 h pouvait planter le planificateur, déduit du code, non reproduit (`at(jour, minutes - 120)`).
- 04/11 : **R2 codé**, pas encore essayé sur un vrai appareil. Sélecteur Tâche · RDV · Info · Envie (« Rendez-vous » en
  toutes lettres débordait de l'iPhone, vu au simulateur ; VoiceOver lit le mot entier) dans la saisie et la fiche : date
  obligatoire, ni priorité, ni liste. Épingle à la place du rond dans À faire, l'Agenda, la barre des menus du Mac, le
  widget et la montre ; ni Fait, ni Reporter (fiche, balayages, menus, carte, ⌘↩). Notifications sans Fait : catégorie
  `RENDEZ_VOUS` (Itinéraire) avec une adresse, aucun bouton sinon. Passé, il quitte À faire et le widget.
  Un rendez-vous lu dans un texte (P9-L4 : scan, partage) prend cette nature. Choix en codant : **pas d'activité en
  direct** (elle n'existe que pour relancer et porte un bouton Fait) ; « Marque comme fait » de Siri laissé tel quel,
  car c'est une demande explicite. Vu au simulateur (iPhone 17, démo) : liste, saisie, fiche, passage en RDV.
  Non vus : Mac, montre, widget, notification réelle (compilés et couverts par les tests, pas regardés à l'écran).
  R1 et R2 commités en local (`f80f5b7`), pas poussés.
- 04/11 : **R3 codé et testé, pas commité ni déployé.** Même règle dans `taskFrom` (Nest Hub), `Taches.kt` (Hub TV, H56) et
  `Taches.swift` (Hub iPad) : un rendez-vous n'apparaît que le jour même, jusqu'à son heure (sans heure : toute la
  journée) ; jamais en retard ni urgent ; épingle à la place de la case, rien à cocher. Il compte dans « N à faire »,
  comme dans À faire de l'app. Un récurrent pas encore avancé par l'app reste caché, sans gravité.
  Tests : Hub TV 167 verts, Hub iPad 174 verts, `taskFrom` essayé avec node. Non vu à l'écran sur les trois vues.
- 04/11 : **R3 déployé en partie.** Hub TV installé à 14 h 06 (`b62596e`, versionCode 157, accueil vérifié). Hub iPad
  (`d718a8b`) et Aiguillage (R1, R2, et les 7 commits d'avant) poussés : TestFlight par Xcode Cloud, build non vérifié.
  **Reste, avant R4** : la carte du Nest Hub (partage `config` non monté). Rien vu à l'écran sur les trois vues.
