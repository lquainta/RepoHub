#!/usr/bin/env bash
# One-time setup for .github/workflows/backup.yml (#34). Creates the Tigris
# bucket and the `backups` environment's secrets. Prints no secret values.
# Needs `fly` and `gh` logged in. Usage: scripts/setup-backups.sh
set -euo pipefail

repo=lquainta/RepoHub
bucket=repohub-backups

gh api -X PUT "repos/$repo/environments/backups" --silent \
    -F 'deployment_branch_policy[protected_branches]=true' \
    -F 'deployment_branch_policy[custom_branch_policies]=false'

# `fly storage create` prints the bucket's credentials once; feed them
# straight into GitHub secrets.
credentials=$(fly storage create --name "$bucket" --org personal --yes)
for key in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_ENDPOINT_URL_S3; do
    value=$(printf '%s\n' "$credentials" | sed -n "s/^ *$key: *//p" | head -1)
    [ -n "$value" ] || { echo "error: $key not found in fly storage output" >&2; exit 1; }
    printf '%s' "$value" | gh secret set "$key" --env backups --repo "$repo"
done
gh variable set BACKUP_BUCKET --env backups --repo "$repo" --body "s3://$bucket/postgres"

fly tokens create deploy --app repohub-db --name github-actions-backup --expiry 8760h \
    | gh secret set FLY_BACKUP_TOKEN --env backups --repo "$repo"

# A random passphrase; also save it in your password manager, or the backups
# can't be decrypted if GitHub's copy is lost.
passphrase=$(openssl rand -base64 32)
printf '%s' "$passphrase" | gh secret set BACKUP_PASSPHRASE --env backups --repo "$repo"
secrets_file="$HOME/.config/repohub/secrets.env"
if [ -f "$secrets_file" ] && ! grep -q '^BACKUP_PASSPHRASE=' "$secrets_file"; then
    printf 'BACKUP_PASSPHRASE=%s\n' "$passphrase" >>"$secrets_file"
    echo "BACKUP_PASSPHRASE saved to $secrets_file"
fi

echo "Done. Run the first backup: gh workflow run backup.yml --repo $repo"
