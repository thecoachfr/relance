# Contrat du capteur `sensor.hub_temperatures` (03/11/2026) — thermomètres des pièces et tendance, pour les trois vues

Calculé par l'app AppDaemon `hub_temperatures` (dépôt Rappels, `homeassistant/appdaemon/apps/hub_temperatures.py`,
tests `tests/test_hub_temperatures.py`, exemple `HUB-TEMPERATURES-exemple.json`). Les vues (Hub TV, Hub iPad/iPhone,
Nest Hub) ne font QUE l'afficher : aucun calcul de tendance dans les vues. Rafraîchi toutes les 5 min.

Décisions d'Alexandre (03/11/2026) : fiche = les thermomètres seuls (pas les sondes de la clim, du ventilateur ni des
têtes de chauffage) ; tendance = flèche colorée ; fenêtre 1 h ; l'Entrée prend la sonde du couloir.

État : le nombre de thermomètres lus (entier).

Attributs :
- `maj` : ISO 8601, heure du calcul ; `fenetre_min` : 60 ; `seuil` : 0.3 (°C).
- `pieces` : identifiant de pièce des vues (`salon`, `chambre`, `bureau`, `sdb`, `entree`, `terrasse`, `jardin` ; la
  cuisine n'a pas de thermomètre) → { `tendance` : "monte" | "baisse" | "stable" | null, `ecart_1h` (°C, 1 déc., ou
  null), `sondes` : liste, le principal d'abord, de { `nom` (« Netatmo », « Thermomètre », « Couloir »), `entite`,
  `temperature` (1 déc. ou null), `ecart_1h`, `tendance` } }.

Calcul : valeur d'il y a 1 h = dernier état connu à ce moment dans l'historique de HA (le Sonoff n'envoie que sur
changement) ; écart ≥ +0,3 → « monte », ≤ −0,3 → « baisse », sinon « stable » ; une des deux valeurs illisible → null.
Tendance de la pièce = celle du principal (le thermomètre que le plan affiche), sinon du premier qui en a une.

Thermomètres (principal d'abord) :
- Salon : Netatmo `sensor.salon_temperature`, Thermomètre (Sonoff) `sensor.thermometree_salon_temperature`.
- Chambre : Netatmo `sensor.chambre_temperature`, Thermomètre (Sonoff) `sensor.thermometre_chambre_temperature`.
- Bureau `sensor.bureau_temperature`, Salle de bain `sensor.salon_canape_temperature` (nom trompeur, c'est la SDB),
  Entrée `sensor.temperature_couloir_temperature`, Terrasse, Jardin : un Sonoff chacun.
- Écartés : `sensor.temperature_clim_sejour`, `sensor.ventilateur_temperature`, `sensor.vt_chauffage_*_ema_temperature`,
  le capteur de particules (ESP, 31 °C), la Freebox.

Règles d'affichage communes :
- **Plan** : à droite de la température d'une pièce, une flèche ↑ orange `#FF9F43` si `tendance` = "monte", ↓ bleue
  `#7CC0FF` si "baisse", rien si "stable" ou null. La température affichée reste celle du principal (entité de la
  pièce dans la vue) ; l'Entrée affiche désormais `sensor.temperature_couloir_temperature`.
- **Fiche de la pièce** : en tête, une ligne par thermomètre, « Netatmo 19,0° ↑ » (même flèche, mêmes couleurs) ; une
  seule ligne si la pièce n'en a qu'un. VoiceOver / lecteur d'écran : « en hausse », « en baisse », « stable ».
- Capteur absent ou illisible : pas de flèche, la fiche lit la valeur des entités elles-mêmes.

Déploiement : `hub_temperatures.py` dans `/addon_configs/a0d7b954_appdaemon/apps/` et bloc `hub_temperatures` dans
`apps.yaml` (AppDaemon recharge seul).
