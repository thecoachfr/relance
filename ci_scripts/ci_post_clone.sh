#!/bin/sh
# Xcode Cloud, juste après la récupération du dépôt :
# 1. recrée Secrets.xcconfig, absent du dépôt public, à partir des variables secrètes du workflow ;
# 2. donne à l'app et à toutes ses extensions le numéro de build de Xcode Cloud (TestFlight l'exige croissant) ;
# 3. écrit le commit compilé dans AppVersion.swift ; 4. signale le début du build à Home Assistant.
set -eu
cd "${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$0")/..}"

: "${GOOGLE_CLIENT_ID:?Variable GOOGLE_CLIENT_ID manquante dans le workflow Xcode Cloud}"
: "${RELANCE_WEBHOOK_URL:?Variable RELANCE_WEBHOOK_URL manquante dans le workflow Xcode Cloud}"
: "${CI_BUILD_NUMBER:?Numéro de build Xcode Cloud absent}"
case "$CI_BUILD_NUMBER" in *[!0-9]*) echo "CI_BUILD_NUMBER doit être un nombre" >&2; exit 1 ;; esac

# Dans un .xcconfig, « // » ouvre un commentaire : on écrit « https:/$()/ » (voir Secrets.example.xcconfig).
# La variable du workflow peut avoir été collée sous l'une ou l'autre forme : on garde l'hôte et le chemin.
webhook=$(printf '%s' "$RELANCE_WEBHOOK_URL" | tr -d '[:space:]')
webhook="${webhook#https://}"
webhook="${webhook#'https:/$()/'}"
case "$webhook" in
    *'$'*|*://*|*' '*|'')
        echo "RELANCE_WEBHOOK_URL mal formée : attendu https://hote/chemin" >&2
        exit 1 ;;
esac
# Schéma d'URL de retour de la connexion Google : déduit de l'ID client plutôt que repris d'une variable
# (le 15/10, la variable collée avait perdu son « c » initial : la connexion Google plantait l'app).
client_id=$(printf '%s' "$GOOGLE_CLIENT_ID" | tr -d '[:space:]')
case "$client_id" in
    *.apps.googleusercontent.com) ;;
    *) echo "GOOGLE_CLIENT_ID mal formée : attendu …apps.googleusercontent.com" >&2; exit 1 ;;
esac
reversed_client_id="com.googleusercontent.apps.${client_id%.apps.googleusercontent.com}"

cat > Relance/Resources/Secrets.xcconfig <<XCCONFIG
GOOGLE_CLIENT_ID = ${client_id}
GOOGLE_REVERSED_CLIENT_ID = ${reversed_client_id}
RELANCE_WEBHOOK_URL = https:/\$()/${webhook}
XCCONFIG

# Numéro de build : toutes les cibles (app, Mac, widgets, partage, montre, complication) ont
# CFBundleVersion = $(CURRENT_PROJECT_VERSION), défini une seule fois (project.yml, réglages du projet) : on le remplace
# dans le projet généré et on vérifie qu'il a bien été écrit. Pas de PlistBuddy sur les Info.plist (checklist G1).
pbxproj=Relance.xcodeproj/project.pbxproj
sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER};/" "$pbxproj"
grep -q "CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER};" "$pbxproj" || { echo "Numéro de build non écrit dans $pbxproj" >&2; exit 1; }
if grep "CURRENT_PROJECT_VERSION = " "$pbxproj" | grep -vq "CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER};"; then
    echo "Un autre numéro de build reste dans $pbxproj" >&2; exit 1
fi

# Commit compilé, affiché avec la version (Réglages › À propos) : savoir si un build contient une modification.
commit=$(printf '%s' "${CI_COMMIT:-$(git rev-parse HEAD 2>/dev/null || true)}" | cut -c1-7)
if [ -n "$commit" ]; then
    sed -i '' "s/static let commit = \"local\"/static let commit = \"${commit}\"/" Shared/Divers/AppVersion.swift
    grep -q "static let commit = \"${commit}\"" Shared/Divers/AppVersion.swift \
        || { echo "Commit non écrit dans AppVersion.swift" >&2; exit 1; }
fi
echo "Secrets écrits, build ${CI_BUILD_NUMBER}, commit ${commit:-inconnu}."

# Numéro de build ↔ commit, gardé par la vigie : savoir quel build TestFlight contient quoi.
sh ci_scripts/signaler_build.sh demarre
