#!/bin/sh
# Xcode Cloud, après chaque action (archive iOS, archive macOS) : signale le résultat à Home Assistant.
set -u
cd "${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$0")/..}"
plateforme=$(printf '%s' "${CI_PRODUCT_PLATFORM:-inconnue}" | tr '[:upper:]' '[:lower:]')
if [ "${CI_XCODEBUILD_EXIT_CODE:-1}" = 0 ]; then etat=ok; else etat=echec; fi
sh ci_scripts/signaler_build.sh "${plateforme}-${etat}"
