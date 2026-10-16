#!/bin/sh
# Signale à Home Assistant qu'un build Xcode Cloud démarre ou se termine, avec son numéro et son commit,
# par le webhook de l'app (variable secrète RELANCE_WEBHOOK_URL, déjà là pour l'app) : la vigie garde la
# correspondance build ↔ commit dans relance_builds.json. Jamais bloquant pour le build.
# Usage : sh ci_scripts/signaler_build.sh <étape>   (demarre, ios-ok, macos-echec…)
etape="${1:-?}"
url=$(printf '%s' "${RELANCE_WEBHOOK_URL:-}" | tr -d '[:space:]')
url="${url#https://}"
url="${url#'https:/$()/'}"
[ -n "$url" ] || exit 0
commit="${CI_COMMIT:-$(git rev-parse HEAD 2>/dev/null || true)}"
payload=$(printf '{"action":"build","device":"%s","token":"%s","environment":"%s"}' \
    "${CI_BUILD_NUMBER:-?}" "$commit" "$etape")
curl -fsS -m 10 -X POST -H 'Content-Type: application/json' -d "$payload" "https://${url}" >/dev/null 2>&1 \
    && echo "Build ${CI_BUILD_NUMBER:-?} (${etape}) signalé à Home Assistant." \
    || echo "Build non signalé à Home Assistant (sans gravité)."
exit 0
