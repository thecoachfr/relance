# Contrat du capteur `sensor.hub_meteo` (24/10/2026) — source unique de la Météo des trois vues du Hub

Calculé par l'app AppDaemon `hub_meteo` (dépôt Rappels, à côté de la vigie ; détail de mise en œuvre en fin de fichier). Les vues (Hub TV, Hub iPad/iPhone,
Nest Hub) ne font QUE l'afficher : aucun calcul météo dans les vues. Rafraîchi toutes les 5 min (et dès que la pluie
dans l'heure change).

État : la température « maintenant » (nombre, 1 décimale, °C), ou `unavailable`.

Attributs :
- `maj` : ISO 8601, heure du calcul.
- `maintenant` : { `temperature` (1 déc.), `source` : "terrasse" | "jardin" | "quartier" (capteur retenu),
  `ressenti` (entier), `condition` (code HA : rainy, cloudy, partlycloudy, sunny, clear-night, pouring, snowy, fog,
  windy, lightning-rainy…), `libelle` (français : « Pluie modérée », « Nuageux »…), `vent_kmh` (entier),
  `vent_dir` (« sud-ouest »), `rafales_kmh` (entier ou null), `humidite` (entier, %) }.
- `dans_l_heure` : { `debut` (ISO, heure de la 1re case), `pas_min` : 5, `niveaux` : 12 entiers 0 sec, 1 faible,
  2 modérée, 3 forte } ou null si Météo-France ne donne rien.
- `pastille` : texte court pour l'en-tête des trois vues, ou null (pas de pluie dans l'heure) :
  « Pluie dans 10 min », « Pluie jusqu'à 9 h 25 », « Pluie forte dans 5 min ».
- `phrase` : liste de segments [{ `texte`, `ton` : "normal" | "pluie" | "alerte" }] ; les vues colorent
  pluie = bleu clair #7CC0FF gras, alerte = jaune #FFB21A gras. Ex. : « Pluie jusqu'à 9 h 25 »(pluie) « , puis sec
  jusqu'à 15 h. La pluie revient l'après-midi, »(normal) « forte en soirée »(pluie) « ; »(normal) « rafales à
  65 km/h vers 22 h »(alerte) « . ».
- `heures` : 24 entrées à partir de l'heure suivante : { `heure` (ISO), `condition`, `temperature` (recalée sur la
  mesure, 1 déc.), `temperature_mf` (brute Météo-France), `pluie_mm` (1 déc.), `vent_kmh`, `rafales_kmh`
  (0 si inconnu) }. Les vues affichent la température recalée arrondie, la pluie en mm si > 0, les rafales en
  jaune à partir de 40 km/h.
- `jours` : 3 entrées (demain et les deux suivants) : { `date`, `nom` (« Dimanche »), `condition`, `min`, `max`
  (entiers), `resume` (« pluie le matin », « sec ») }.
- `vigilance` : { `couleur` : "Vert" | "Jaune" | "Orange" | "Rouge", `risques` : liste des risques non verts
  (« Vent violent »…) }.
- `apprentissage` (ajouté le 24/10/2026, validé par Alexandre ; les vues ne l'affichent pas pour l'instant) :
  { `jours_de_donnees` (entier : jours ayant des relevés sur les 30 derniers), `actif` (bool : au moins une heure
  corrigée), `ecarts` : 24 valeurs (heure locale 0 à 23, °C arrondis à 0,1, ou null si l'heure n'est pas corrigée),
  `maj` (ISO, dernier calcul) }. Avec l'apprentissage actif, `heures[].temperature` et `jours[].min/max` incluent
  la correction ; `temperature_mf` reste la valeur brute de Météo-France.

Règles d'affichage communes (« Mêmes boutons, même ordre ») :
- Section « Météo » entre Maison et À faire (ordre : Accueil, Vidéo, Audio, Maison, Météo, À faire). iPad/iPhone :
  rail / onglet « Météo », icône `umbrella` ; Nest Hub : onglet « Météo » (mdi:weather-partly-rainy) ; Hub TV :
  écran Météo, ouvert par OK sur la météo de l'en-tête (devenue focalisable) — pas de 4e tuile.
- Contenu, dans cet ordre : Maintenant (icône, grand chiffre, libellé, « ressenti 7° · vent 15 km/h, sud-ouest »,
  « mesuré sur la terrasse » / « mesuré au jardin » / « quartier (Netatmo) » en petit, puis la phrase), Dans l'heure
  (12 cases, légende sec / faible / modérée / forte, repères d'heure), Prochaines heures (heure, icône, température,
  barre et mm de pluie, rafales), Les prochains jours (+ vigilance ; si vigilance non verte, bandeau jaune/orange/rouge
  en tête). Nest Hub : pas de « prochains jours » (place), 9 heures ; iPhone : 6 heures visibles, défilement.
- Pastille d'en-tête : si `pastille` non nul, une pastille bleue (bord #4E95D1, texte #7CC0FF, « 🌧️ » ou icône pluie)
  AVANT « N à faire » et « N à surveiller », dans les trois vues ; toucher / OK ouvre la Météo.
- La météo de l'en-tête (« ☁️ 13° ») prend `état` de `sensor.hub_meteo` (la mesure) au lieu de weather.alfortville.
- Couleurs de pluie : sec #2E3A46, faible #3E6A8E, modérée #4E95D1, forte #7CC0FF.
- Maquettes de référence : /tmp/maquettes-meteo/meteo-{tv,ipad,nest,iphone}.png et meteo.html.

---

## Mise en œuvre : app AppDaemon `hub_meteo` (déployée le 24/10/2026 vers 8 h 55)

Code : `homeassistant/appdaemon/apps/hub_meteo.py` (fonctions pures, puis la classe `HubMeteo`), tests :
`homeassistant/appdaemon/tests/test_hub_meteo.py` (`uv run --with pytest python -m pytest -q homeassistant/appdaemon/tests`).
Exemple du contrat : `homeassistant/HUB-METEO-exemple.json` (les tests vérifient que les clés publiées sont les mêmes).
Déploiement : copier `hub_meteo.py` dans `/Volumes/addon_configs/a0d7b954_appdaemon/apps/` (AppDaemon recharge seul) ;
bloc `hub_meteo` dans `apps.yaml` (sauvegarde d'avant : `apps.yaml.avant-meteo-20261024`, à la racine du dossier).

- **Publication par l'API REST de HA** (`POST /api/states/sensor.hub_meteo`, jeton du superviseur), pas par
  `self.set_state` : AppDaemon 4.5.13 retire des attributs, récursivement, les valeurs vides (0, null) ; au premier
  déploiement `niveaux` n'avait plus que 2 cases sur 12, et `rafales_kmh: 0`, `pluie_mm: 0`, `rafales_kmh: null`
  manquaient. Taille des attributs : environ 5 Ko (limite de l'enregistreur : 16 Ko).
- **Rafraîchi** toutes les 5 min et 3 s après chaque changement de `sensor.alfortville_next_rain`.
- **Mesure** : terrasse, jardin, quartier (dans cet ordre) ; capteur ignoré seulement s'il n'est pas un nombre
  (`unavailable` quand Zigbee2MQTT ne voit plus l'appareil, `unknown`). Pas de règle d'ancienneté (corrigé le 24/10 à
  9 h 07) : le Sonoff de la terrasse n'envoie rien tant que la valeur ne change pas, `last_reported` reste à l'heure
  du dernier changement (7 h 13 encore à 9 h 06 ce matin) et l'historique du 21 au 24/10 montre des trous de 2 à 3 h
  sans message ; « figé depuis 2 h » (règle du premier déploiement) l'aurait fait basculer à tort. Le premier gardé est écarté s'il dépasse de plus de 2,5 °C l'un des autres (soleil) :
  le plus bas des autres. Aucun capteur : état `unavailable`, `temperature` et `source` null.
- **Prévision MF à maintenant** : interpolée entre les points horaires ; avant le premier (MF commence à l'heure
  suivante), entre `temperature` de `weather.alfortville` (à son `last_updated`) et le premier point ; l'app garde
  aussi les points des 3 dernières heures. **Recalage** : `temperature` = MF + écart × (e^(−h/4) − e^(−2)) / (1 − e^(−2)),
  h = heures depuis maintenant (1 à 0 h, 0,27 à 4 h, 0 dès 8 h, sans saut). Le ressenti reçoit le même écart.
- **Libellé** : la case en cours de « dans l'heure » l'emporte (« Pluie faible / modérée / forte », condition
  `rainy` ou `pouring`), sinon le libellé de la condition MF.
- **Dans l'heure** : chaque case prend la dernière clé connue ≤ sa minute ; les cases déjà passées sont ignorées.
  Une averse s'arrête à la première accalmie d'au moins 10 min (ou qui va au bout de l'heure).
- **Pastille** : « Pluie jusqu'à 9 h 25 » (il pleut), « Pluie toute l'heure », « Pluie dans 10 min » ; « Pluie
  forte » si une case est forte ; null sinon.
- **Phrase** (retouchée à 9 h 03 à la demande du coordinateur) : l'heure à venir d'abord, puis la bascule suivante
  sur 24 h. Une heure MF ne compte que si plus de la moitié tombe après la fenêtre minute par minute, et il faut
  au moins 0,2 mm/h pour « la pluie revient » (une trace de 0,1 mm ne coupe pas une période sèche). Reprise le jour
  même : l'heure (« La pluie revient vers 17 h ») ; un autre jour : le moment (« demain matin »). « forte » (≥ 2 mm/h)
  avec une période (« forte en soirée »), « vers 21 h » si c'est la même période que le début. Rafales ≥ 50 km/h
  sur les 24 h : la plus forte, en alerte. Exemples réels : « Pluie dans 20 min, jusqu'à 9 h 20, puis sec. La pluie
  revient vers 17 h, forte en soirée ; rafales à 65 km/h vers 22 h. » ; « Sec pour l'instant. La pluie arrive vers
  17 h, … » ; « Pas de pluie prévue dans les 24 h. »
- **Jours** : min, max et condition de la prévision du jour de MF (sinon les heures) ; `resume` court (22 caractères
  au plus, coupé sinon sur la TV) : une seule période (« pluie le matin », « pluie à midi », « pluie l'après-midi »,
  « pluie le soir » ; « pluie la nuit » seulement si c'est la seule pluie), deux périodes ou plus : « pluie toute la
  journée », ou « averses » si le cumul du jour est sous 2 mm ; « sec ». Périodes : nuit 0-6 h, matin 6-12 h,
  midi 12-14 h, après-midi 14-18 h, soir 18-24 h ; une prévision de 3 ou 6 h couvre toutes ses heures.
- **Vigilance** : état de `sensor.94_weather_alert` (Vert s'il est inconnu), risques = attributs non verts.

### Apprentissage automatique (24/10/2026, validé par Alexandre)

**Relevés** : chaque heure (minute 2), une ligne dans `/config/hub_meteo_releves.jsonl` (côté Mac :
`/Volumes/addon_configs/a0d7b954_appdaemon/hub_meteo_releves.jsonl`, à côté de `hub_ipad_activite.json`), 60 jours
gardés, et une ligne « Météo : relevé … » dans `logs/appdaemon.log`. Premier relevé : 24/10 à 9 h 02.

```json
{"t": "2026-10-24T09:00:00+02:00", "mesure": 8.4, "source": "terrasse", "mf": 9.3, "condition": "rainy",
 "prev": {"1": 9.9, "3": 11.2, "6": 13.1, "12": 11.6, "24": 13.0}}
```

`mesure` = température retenue à l'heure `t`, `mf` = MF interpolée à `t`, `condition` = condition MF (relevée depuis
le 24/10 vers 9 h 20, pour séparer plus tard ciel clair et couvert), `prev[k]` = ce que MF prévoit, à `t`, pour
`t + k` heures.

**Calcul, chaque nuit à 3 h 30** (et au démarrage s'il n'y a pas encore de fichier) : `apprendre` lit les relevés des
30 derniers jours et calcule, pour chaque heure locale de la journée (24 cases), l'écart moyen `mesure − mf`. Une
case n'est retenue que si elle a des relevés sur **au moins 14 jours** et un **écart-type < 1,5 °C** (sinon pas de
correction) ; moyenne **plafonnée à ±3 °C**, puis **lissée** avec les cases voisines retenues (poids 1-2-1, en
boucle sur 24 h). Résultat dans `/config/hub_meteo_apprentissage.json` (relu au démarrage ; champ `detail` en plus :
jours, moyenne et écart-type de chaque heure, même non retenue), publié dans l'attribut `apprentissage`. Pas encore
par horizon ni par ciel clair / couvert (trop peu de données) : à ajouter quand il y aura plusieurs semaines de
relevés, d'abord en comparant `detail` des deux découpages.

**Application** : `heures[].temperature` = MF + correction de son heure + recalage, où le recalage porte sur l'écart
entre la mesure et la prévision **déjà corrigée** à maintenant (pas de double comptage). Le ressenti suit l'écart
total mesure − MF. `jours[].min/max` : les heures du jour sont corrigées et le min / max de MF décalés d'autant que le
min / max de ces heures. Le 24/10 : 1 jour de données, `actif` false, aucune correction ; première correction
possible vers le 7/11 (14 jours).

Diagnostic à la main, par horizon (même fonction que dans les tests) :

```sh
cd "Rappels/homeassistant/appdaemon/apps" && python3 -c "
import json, hub_meteo as m
r = [json.loads(l) for l in open('/Volumes/addon_configs/a0d7b954_appdaemon/hub_meteo_releves.jsonl')]
for k in (1, 3, 6, 12, 24):
    print(k, m.ecart_moyen_par_heure(r, k))"
```
