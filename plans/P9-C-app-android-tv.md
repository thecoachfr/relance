# P9-C — App Android TV « Aiguillage TV » pour le Freebox Player Pop

*Plan du 16/10/2026. Lire d'abord `P9-00-INDEX.md`. Nouveau dépôt **privé** `thecoachfr/aiguillage-tv`, créé par Alexandre le 16/10 (la création de dépôt échoue depuis les outils de Claude). Au premier commit, copier ce plan dans `docs/SPEC.md` du nouveau dépôt et créer `docs/STATUT.md`. Prérequis : lot 0 et plan B (champs `envie`, liens validés dans `relance/docs/LIENS-TV.md`).*

**État au 16/10 au soir** : C0 à C4 faits et essayés par Alexandre, plus l'onglet Audio (lecture sur la TV ou les LS50, contenu de la playlist « À écouter »). Suivi détaillé : `aiguillage-tv/docs/STATUT.md`. Reste : ouvrir Apple TV, Prime Video, France TV et Arte.

## 1. But

Parcourir depuis le canapé, à la télécommande, les envies **« À regarder »** et **« À écouter »** d'Aiguillage, et les ouvrir dans l'app de la plateforme sur la TV. Choix d'Alexandre (16/10) : une **vraie app Android TV**, en plus du bouton « Sur la TV » de l'iPhone (plan B).

## 2. Contraintes vérifiées

- Le Freebox Player Pop tourne sous **Android TV** et Alexandre l'a mis en **mode développeur** : une app maison s'installe par **ADB** depuis le Mac, sans le Play Store. Autre voie : APK sur clé USB ouvert avec un gestionnaire de fichiers après avoir autorisé les sources inconnues (méthode décrite par Univers Freebox en 2020).
- **Vérification des développeurs Android** (FAQ Android Developers, lue le 16/10) : « Apps installed using ADB won't require verification ». L'obligation s'applique d'abord aux téléphones et tablettes de quelques pays (septembre 2026), puis à tous les pays en 2027. Repli si un jour l'installation par ADB était bloquée : compte gratuit « distribution limitée » (20 appareils, sans pièce d'identité).
- Le code Swift d'Aiguillage ne se réutilise pas : app en **Kotlin + Jetpack Compose for TV** (`androidx.tv`). Skip (traduction SwiftUI → Compose) ne documente ni la TV ni la navigation à la télécommande : écarté.
- Le Player date de 2020 : **lot C0** mesure sa version d'Android TV et sa mémoire avant de fixer `minSdk`.
- Une mise à jour de Free pourrait couper le mode développeur : le noter si cela arrive.

## 3. Architecture

- Données : les mêmes que l'app iPhone, dans HA (`donnees_apps`, espace `aiguillage`) par l'API REST : `POST /api/services/donnees_apps/lire?return_response` puis `changements` depuis le dernier `seq`, avec le jeton de l'utilisateur non administrateur `apps-perso`. Adresse : HA en local (le Player est sur le même réseau), adresse Nabu Casa en secours.
- Configuration (adresse, jeton) : **poussée une fois par ADB depuis le Mac** (par exemple un `am start` avec extras ou un fichier lu au premier lancement puis effacé), rangée dans un stockage chiffré de l'app. Pas de saisie du jeton à la télécommande. Jamais dans le dépôt.
- Cache local (Room ou fichier JSON) : l'app affiche le dernier état si HA ne répond pas. Écritures (« Vu », « Écouté ») : file d'attente locale rejouée au retour de HA, `version_attendue`, `modifie_par: "tv"`, `op_id` neuf. Le repli imposé par C2 est assuré par les appareils Apple ; la TV ne fait que lire et cocher, sa file locale suffit.
- Ouverture : `Intent.ACTION_VIEW` avec le lien de la tâche, transformé selon `relance/docs/LIENS-TV.md` (ex. Netflix `?source=30`) ; si aucune app ne répond, ouvrir l'app de la plateforme par son identifiant de paquet.

## 4. Lots

### C0 — Mesures et squelette
- Sur le Player : version d'Android TV, niveau d'API, mémoire, résolution, `adb connect` depuis le Mac. Noter dans `docs/STATUT.md`.
- Projet Gradle (Android Studio sur le Mac), Compose for TV, signature de débogage ; clé de signature de version **hors dépôt**.
- **Accepté quand** : une app « Bonjour » s'installe par `./gradlew installDebug` et se lance depuis l'écran d'accueil du Player (bannière TV).

### C1 — Lecture des envies
- Client REST `donnees_apps` (lire, changements), décodage de `TacheHA` v2 (champs inconnus ignorés), cache, rafraîchissement au retour au premier plan et toutes les 5 minutes.
- **Accepté quand** : les envies créées sur l'iPhone apparaissent sur la TV en moins de 5 minutes ; HA coupé → dernier état affiché avec un bandeau « hors ligne ».

### C2 — Écrans
- Accueil en rangées : « À regarder » par plateforme, « À écouter », « Récemment ajoutés ». Cartes avec l'affiche TMDB (`envie.tmdb.affiche`) ou un visuel par défaut, titre, plateforme, badge « inclus dans ton abonnement ».
- Fiche : résumé court, période (ligne `🗓`), boutons « Ouvrir », « Vu » / « Écouté », « Pas maintenant ».
- Navigation entièrement à la télécommande (focus visible, retour), textes lisibles à 3 m. Mention « Disponibilités : JustWatch » (exigence TMDB).
- **Accepté quand** : parcours complet à la télécommande sans souris ; liste de contrôle du focus cochée.

### C3 — Ouvrir et cocher
- « Ouvrir » lance le titre dans l'app de la plateforme (formes de liens de LIENS-TV.md) ; « Vu » écrit dans HA et la tâche passe en historique sur l'iPhone.
- **« À écouter » : lire sur la TV** (demande d'Alexandre du 16/10). « Ouvrir » passe le lien Spotify à l'app Spotify du Player (`Intent.ACTION_VIEW`, paquet `com.spotify.music`, qui affiche le contenu sans forcément le lire) ; « Lire » demande à HA de lancer la lecture par Spotify Connect (script `script.aiguillage_spotify_sur_tv` du plan B). L'app TV ne garde **aucun** jeton Spotify : tout passe par HA.
- **Accepté quand** : pour chaque plateforme du tableau B5, l'ouverture donne le même résultat que le script HA ; « Vu » rejoué sans doublon après une coupure de HA.

### C4 — Mises à jour
- Script `scripts/installer.sh` (adb connect + installation de la version signée) ; numéro de version visible dans l'app.

## 5. Tests

Tests unitaires (décodage, transformation des liens, file d'attente), un test d'interface Compose minimal, et la liste de contrôle manuelle sur le Player dans `docs/STATUT.md`.

## 6. Hors périmètre

Ajout d'envies depuis la TV, lecture intégrée, autres téléviseurs (The Frame n'est pas sous Android TV), publication sur le Play Store.
