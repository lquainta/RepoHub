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
    if ! api "projects/$org/$1/" >/dev/null 2>&1; then
        api "teams/$org/$team/projects/" -X POST -d "{\"name\":\"$1\",\"slug\":\"$1\",\"platform\":\"$2\"}" >/dev/null
        echo "created $1"
    fi
    api "projects/$org/$1/keys/" | jq -r '.[0].dsn.public'
}

backend_dsn=$(project repohub-backend other)
app_dsn=$(project repohub-macos apple-macos)

# Email on new or regressed app issues, and on crash spikes (#52). The
# backend emails directly (EmailAlerter), so it doesn't need these.
rule() { # name, conditions JSON
    if ! api "projects/$org/repohub-macos/rules/" | jq -e --arg name "$1" '.[] | select(.name == $name)' >/dev/null; then
        api "projects/$org/repohub-macos/rules/" -X POST -d "{
            \"name\": \"$1\", \"actionMatch\": \"any\", \"frequency\": 30,
            \"conditions\": $2,
            \"actions\": [{\"id\": \"sentry.mail.actions.NotifyEmailAction\",
                \"targetType\": \"IssueOwners\", \"fallthroughType\": \"ActiveMembers\"}]
        }" >/dev/null
        echo "added alert rule: $1"
    fi
}
rule "Email on new or regressed crashes" '[
    {"id": "sentry.rules.conditions.first_seen_event.FirstSeenEventCondition"},
    {"id": "sentry.rules.conditions.regression_event.RegressionEventCondition"}]'
rule "Email on crash spikes" '[
    {"id": "sentry.rules.conditions.event_frequency.EventFrequencyCondition", "value": 10, "interval": "1h"}]'

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
