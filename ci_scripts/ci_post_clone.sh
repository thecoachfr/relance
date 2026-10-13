#!/bin/sh
# Xcode Cloud, juste après la récupération du dépôt :
# 1. recrée Secrets.xcconfig, absent du dépôt public, à partir des variables secrètes du workflow ;
# 2. donne à l'app et à toutes ses extensions le numéro de build de Xcode Cloud (TestFlight l'exige croissant).
set -eu
cd "${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$0")/..}"

: "${GOOGLE_CLIENT_ID:?Variable GOOGLE_CLIENT_ID manquante dans le workflow Xcode Cloud}"
: "${GOOGLE_REVERSED_CLIENT_ID:?Variable GOOGLE_REVERSED_CLIENT_ID manquante dans le workflow Xcode Cloud}"
: "${RELANCE_WEBHOOK_URL:?Variable RELANCE_WEBHOOK_URL manquante dans le workflow Xcode Cloud}"
: "${CI_BUILD_NUMBER:?Numéro de build Xcode Cloud absent}"

# Dans un .xcconfig, « // » ouvre un commentaire : on écrit « https:/$()/ » (voir Secrets.example.xcconfig).
webhook="${RELANCE_WEBHOOK_URL#https://}"
cat > Relance/Resources/Secrets.xcconfig <<XCCONFIG
GOOGLE_CLIENT_ID = ${GOOGLE_CLIENT_ID}
GOOGLE_REVERSED_CLIENT_ID = ${GOOGLE_REVERSED_CLIENT_ID}
RELANCE_WEBHOOK_URL = https:/\$()/${webhook}
XCCONFIG

for plist in Relance/Resources/Info.plist RelanceMac/Info.plist RelanceShare/Info.plist \
             RelanceWidgets/Info.plist RelanceWatch/Info.plist RelanceWatchWidgets/Info.plist; do
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${CI_BUILD_NUMBER}" "$plist"
done
echo "Secrets écrits, build ${CI_BUILD_NUMBER}."
