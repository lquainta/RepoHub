#!/usr/bin/env bash
# Restores a backup from scripts/backup-db.sh into a scratch database (#34).
# Usage: scripts/restore-db.sh <backup-name|latest> <target-database-url>
#   BACKUP_PASSPHRASE, BACKUP_DEST  as for backup-db.sh
# The target's name must end in _restore or _test: restoring drops and
# recreates every object in it, so it must never be a live database.
set -euo pipefail

which=${1:?Usage: restore-db.sh <backup-name|latest> <target-database-url>}
target=${2:?Usage: restore-db.sh <backup-name|latest> <target-database-url>}
: "${BACKUP_PASSPHRASE:?Set BACKUP_PASSPHRASE}"
: "${BACKUP_DEST:?Set BACKUP_DEST}"

database=${target%%\?*}
database=${database##*/}
case "$database" in
*_restore | *_test) ;;
*)
    echo "error: refusing to restore into '$database'; use a scratch database ending in _restore or _test" >&2
    exit 1
    ;;
esac

case "$BACKUP_DEST" in
s3://*) list() { aws s3 ls "${BACKUP_DEST%/}/" | awk '{print $4}'; } ;;
*) list() { find "$BACKUP_DEST" -maxdepth 1 -name 'repohub-*.dump.enc' -exec basename {} \;; } ;;
esac
if [ "$which" = latest ]; then
    which=$(list | grep '^repohub-.*\.dump\.enc$' | sort | tail -1)
    [ -n "$which" ] || { echo "error: no backups in $BACKUP_DEST" >&2; exit 1; }
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
case "$BACKUP_DEST" in
s3://*) aws s3 cp --only-show-errors "${BACKUP_DEST%/}/$which" "$work/backup.enc" ;;
*) cp "$BACKUP_DEST/$which" "$work/backup.enc" ;;
esac
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:BACKUP_PASSPHRASE -in "$work/backup.enc" -out "$work/backup.dump"
pg_restore --clean --if-exists --no-owner --no-privileges --exit-on-error -d "$target" "$work/backup.dump"
echo "restored $which into $database"
