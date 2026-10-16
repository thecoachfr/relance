# Consommation de batterie d'Aiguillage

*Audit du plan P9-E ([plans/P9-E-audit-batterie.md](../plans/P9-E-audit-batterie.md)). E1 = mesure de référence avant P9 ; E2 = mesure après A4 et D3.*

## Outils en place (16/10/2026)

- **App iPhone et iPad, Réglages › Diagnostic batterie** :
  - rapports quotidiens de MetricKit, résumés : temps à l'écran et en arrière-plan, position en arrière-plan, position demandée (toutes précisions), processeur, réseau Wi-Fi et cellulaire ;
  - réveils en arrière-plan comptés par l'app, par jour : pushs de la vigie reçus, entrées dans une zone de rappel à l'approche ;
  - « Exporter les mesures » : un fichier JSON (résumés, réveils, rapports bruts de MetricKit).
  - Tout reste dans l'App Group (dossier `Metrics/`), sans réseau. iOS livre au plus un rapport par jour, le premier environ 24 h après l'installation du build.
- **Vigie** : `/config/relance_push_stats.json` dans l'add-on AppDaemon (partage `addon_configs/a0d7b954_appdaemon/`), avec par jour les **salves** par cause (`modification_ha`, `liste_google`, `apres_tri`, `test`) et les **envois** (une salve = un push à chaque appareil enregistré). Gardé 31 jours ; le total de la veille est écrit dans le journal d'AppDaemon à 0 h 00 min 30 s.
- **Réglages › Batterie de l'iPhone** : part d'Aiguillage sur 24 h et sur 10 jours, à l'écran et en arrière-plan. Relevé à la main par Alexandre, avec une capture datée.

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

À faire : même protocole et comparaison avec E1. Le seuil d'acceptation sera fixé avec Alexandre après E1.
