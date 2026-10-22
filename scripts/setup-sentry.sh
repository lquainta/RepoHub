#!/usr/bin/env bash
# One-time Sentry setup (#51): creates the backend and macOS app projects in
# the `landon-quaintance` org, sets the backend's SENTRY_DSN on Fly, and saves
# the app's DSN as the SENTRY_DSN_APP repository variable for release builds.
# Needs SENTRY_USER_TOKEN (project:write) in ~/.config/repohub/secrets.env, and
# `fly` and `gh` logged in. Prints no secret values.
set -euo pipefail

org=landon-quaintance
repo=lquainta/RepoHub
# shellcheck disable=SC1090,SC1091
source "$HOME/.config/repohub/secrets.env"
: "${SENTRY_USER_TOKEN:?Add SENTRY_USER_TOKEN to ~/.config/repohub/secrets.env}"

api() {
    curl -fsS -H "Authorization: Bearer $SENTRY_USER_TOKEN" -H 'Content-Type: application/json' \
        "https://sentry.io/api/0/$1" "${@:2}"
}

team=$(api "organizations/$org/teams/" | jq -r '.[0].slug')
[ -n "$team" ] && [ "$team" != null ] || { echo "error: no team in $org" >&2; exit 1; }

project() { # slug platform
    if ! api "projects/$org/$1/" >/dev/null 2>&1; then
        api "teams/$org/$team/projects/" -X POST -d "{\"name\":\"$1\",\"slug\":\"$1\",\"platform\":\"$2\"}" >/dev/null
        echo "created $1"
    fi
    api "projects/$org/$1/keys/" | jq -r '.[0].dsn.public'
}

backend_dsn=$(project repohub-backend other)
app_dsn=$(project repohub-macos apple-macos)

printf 'SENTRY_DSN=%s\n' "$backend_dsn" | fly secrets import --app repohub-backend --stage
gh variable set SENTRY_DSN_APP --repo "$repo" --body "$app_dsn"
echo "Done. The backend picks up SENTRY_DSN on its next deploy."
