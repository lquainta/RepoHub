#!/usr/bin/env bash
# One-time monitoring setup. Prints no secret values.
# - Sentry (#51): creates the backend and macOS app projects in the
#   `landon-quaintance` org, stages the backend's SENTRY_DSN on Fly, and saves
#   the app's DSN as the SENTRY_DSN_APP repository variable for release builds.
# - Alerts (#52): Sentry rules that email about app crashes, and the backend's
#   EMAIL_API_KEY / ALERT_EMAIL_TO on Fly.
# - Uptime (#53): an UptimeRobot monitor on /ready that emails when it fails.
# Needs SENTRY_USER_TOKEN, EMAIL_API_KEY, and UPTIMEROBOT_API_KEY in
# ~/.config/repohub/secrets.env, and `fly` and `gh` logged in.
# Usage: scripts/setup-monitoring.sh <alert-email>
set -euo pipefail

alert_email=${1:?Usage: setup-monitoring.sh <alert-email>}
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
    if ! api "projects/$org/$1/" >/dev/null 2>&1; then  # 404: not created yet
        api "teams/$org/$team/projects/" -X POST -d "{\"name\":\"$1\",\"slug\":\"$1\",\"platform\":\"$2\"}" >/dev/null
        echo "created $1"
    fi
    api "projects/$org/$1/keys/" | jq -r '.[0].dsn.public'
}

backend_dsn=$(project repohub-backend other)
app_dsn=$(project repohub-macos apple-macos)

# Email on new or regressed app crashes (#52). Sentry's new alert engine
# ("workflows") attaches them to the project's issue-stream detector. Crash
# spikes are already covered: Sentry marks a spiking issue as escalating and
# high priority, and every new project gets a default workflow that emails on
# high-priority issues. The backend emails directly (EmailAlerter).
# Workflows need a token with the alerts:write scope.
project_id=$(api "projects/$org/repohub-macos/" | jq -r .id)
detector=$(api "organizations/$org/detectors/?project=$project_id" | jq -r '.[] | select(.type == "issue_stream") | .id')
name="Email on new or regressed crashes"
if api "organizations/$org/workflows/" | jq -e --arg name "$name" '.[] | select(.name == $name)' >/dev/null; then
    echo "alert workflow exists: $name"
elif api "organizations/$org/workflows/" -X POST -d "{
    \"name\": \"$name\", \"enabled\": true, \"config\": {\"frequency\": 30}, \"environment\": null,
    \"detectorIds\": [\"$detector\"],
    \"triggers\": {\"logicType\": \"any-short\", \"actions\": [], \"conditions\": [
        {\"type\": \"first_seen_event\", \"comparison\": true, \"conditionResult\": true},
        {\"type\": \"regression_event\", \"comparison\": true, \"conditionResult\": true}]},
    \"actionFilters\": [{\"logicType\": \"any-short\", \"conditions\": [], \"actions\": [
        {\"type\": \"email\", \"data\": {\"fallthroughType\": \"ActiveMembers\"},
         \"config\": {\"targetType\": \"issue_owners\", \"targetIdentifier\": null}}]}]
}" >/dev/null 2>&1; then
    echo "added alert workflow: $name"
else
    echo "warning: couldn't add the alert workflow \"$name\": the token needs the alerts:write scope." >&2
    echo "  Add it at https://sentry.io/settings/account/api/auth-tokens/ and run this script again." >&2
fi

gh variable set SENTRY_DSN_APP --repo "$repo" --body "$app_dsn"

: "${EMAIL_API_KEY:?Add EMAIL_API_KEY (Resend) to ~/.config/repohub/secrets.env}"
printf 'SENTRY_DSN=%s\nEMAIL_API_KEY=%s\nALERT_EMAIL_TO=%s\n' "$backend_dsn" "$EMAIL_API_KEY" "$alert_email" \
    | fly secrets import --app repohub-backend --stage

# Uptime (#53): check /ready every 5 minutes; the account's email contact is alerted.
: "${UPTIMEROBOT_API_KEY:?Add UPTIMEROBOT_API_KEY to ~/.config/repohub/secrets.env}"
monitors=$(curl -fsS -X POST https://api.uptimerobot.com/v2/getMonitors \
    -d "api_key=$UPTIMEROBOT_API_KEY" -d format=json -d search=repohub-backend)
if [ "$(printf '%s' "$monitors" | jq '.monitors | length')" = 0 ]; then
    contacts=$(curl -fsS -X POST https://api.uptimerobot.com/v2/getAlertContacts \
        -d "api_key=$UPTIMEROBOT_API_KEY" -d format=json | jq -r '[.alert_contacts[].id + "_0_0"] | join("-")')
    curl -fsS -X POST https://api.uptimerobot.com/v2/newMonitor -d "api_key=$UPTIMEROBOT_API_KEY" -d format=json \
        -d type=2 -d friendly_name="repohub-backend /ready" -d url=https://repohub-backend.fly.dev/ready \
        -d keyword_type=2 -d keyword_value='"ready"' -d interval=300 \
        -d alert_contacts="$contacts" | jq -e '.stat == "ok"' >/dev/null
    echo "created the UptimeRobot monitor"
fi
echo "Done. The backend picks up the staged secrets on its next deploy."
