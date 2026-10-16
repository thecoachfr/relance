# P9-F — Piste : présence à la maison (Hue MotionAware, puis Bermuda)

*Piste ajoutée le 16/10/2026 à la demande d'Alexandre. Lire d'abord `P9-00-INDEX.md`. Devenue un plan exécuté le 16/10 au soir (F1 à F4, voir « 3 bis »). Dépôts : configuration HA, `relance` (vigie, app).*

## 1. Constat (vérifié le 16/10/2026)

- La Hue Bridge Pro est dans HA. La zone MotionAware « Salon » y apparaît sous deux entités de l'intégration Hue : `switch.salon_salon_motionaware` (active la zone) et `binary_sensor.salon` (classe `motion`).
- La zone était désactivée ; activée le 16/10 à 7 h 52 depuis le chat Claude. Essai à 7 h 55 : `binary_sensor.salon` passe à `on`, puis revient à `off` environ 10 s plus tard. Aucun abonnement Hue n'a été nécessaire pour ce détecteur ; HA 2026.10.1.
- Ce que fait MotionAware (documentation Philips Hue) : mesure des perturbations du signal Zigbee entre au moins 3 ampoules compatibles par zone, 4 zones au plus par Bridge Pro. Il détecte du **mouvement**, pas une présence immobile, et ne dit pas **qui** bouge (un animal ou une personne dans la pièce voisine peut le déclencher). La détection de présence est annoncée comme une étape future, sans date (Hueblog, 1er décembre 2025).

## 2. Idées

1. **Capteur « quelqu'un au salon »** dans HA : `binary_sensor.salon` avec un délai de retour au repos (par exemple 10 minutes sans mouvement), pour passer du mouvement à une présence approximative.
2. **Rappels « à la maison »** dans Aiguillage : un nouveau déclencheur d'action `presence`, à ajouter au plan D le moment venu, exécuté par la vigie à partir de ce capteur, au lieu de la position GPS de l'iPhone. Moins de batterie (lien avec le plan E) et fonctionne même téléphone posé.
3. **Nest Hub de l'entrée** : n'afficher le bandeau de notification (P1) ou les rappels du jour que si quelqu'un est présent dans l'espace ouvert entrée-cuisine-salon.
4. **Savoir qui** : MotionAware ne le dira jamais. C'est le rôle du projet Bermuda d'Alexandre (relais Bluetooth par pièce, iPhone et iPad reconnus par leur clé IRK). Bermuda dit quel appareil est dans quelle pièce ; MotionAware confirme qu'il y a vraiment quelqu'un. Ensemble : actions « quand je suis au bureau », « en arrivant dans la chambre ».

## 3. Limites à garder en tête

- Mouvement seulement : assis immobile = « personne » tant que la présence Hue n'existe pas.
- Faux positifs possibles (animaux, voisins à travers un mur ou un plancher, selon la documentation Hue).
- 4 zones au plus, 3 ampoules au moins par zone : toutes les pièces ne pourront pas être couvertes.
- L'activation de la zone peut avoir lancé un comportement réglé dans l'app Hue (allumage au passage) : à vérifier dans l'app.

## 3 bis. Fait (16/10/2026)

**État au 16/10 au soir** : F1 à F4 faits ; « à la maison » et « dans une pièce » (Bureau, 22 h 08) essayés, notifications reçues. À essayer : le Nest Hub sans personne. Bermuda : la pièce brute saute toutes les quelques secondes, lissage à régler par Alexandre.

- **Idée 1** : `binary_sensor.presence_salon` (helper Template, `delay_off` 10 min).
- **Idée 2** : action `rappel_maison` (vigie, notification visible sur les iPhone, une fois par jour et par tâche).
- **Idée 4 (Bermuda, relais installés par Alexandre)** : `sensor.piece_d_alexandre` (helper Template : pièce de la
  montre, sinon de l'iPhone, sinon « Absent », d'après `sensor.private_ble_watch_area` et `sensor.private_ble_iphone_area`).
  Action « Me le rappeler dans… » (`rappel_piece`, `params.piece`) : la vigie notifie quand la pièce domine les
  2 dernières minutes (70 % du temps ; la pièce brute de Bermuda saute toutes les quelques secondes), une fois par
  jour et par tâche (`piece_entity` dans `apps.yaml`). Pièces proposées par l'app : liste des
  zones HA publiée par la vigie sous la clé non-UUID `config:pieces`. `domicile_entity` : retour à la maison d'après
  `device_tracker.private_ble_iphone`.
- **Idée 3 (Nest Hub)** : `binary_sensor.quelqu_un_dans_l_espace_de_vie` (présence salon, ou Alexandre dans l'entrée,
  la cuisine ou le salon). Option `presence_entity` des cartes `nest-hub-entree-card` et `nest-hub-leger-card` : le bloc
  Aiguillage est masqué quand personne n'est là. Les deux cartes sont des fichiers `/local/nest-hub/` (la légère
  n'est plus une ressource inline).

## 4. Ordre

Le capteur de présence (idée 1) est une simple configuration HA, faisable à tout moment. Les idées 2 et 3 viennent après D3 (exécutant HA des actions). L'idée 4 attend l'installation des relais Bermuda.
