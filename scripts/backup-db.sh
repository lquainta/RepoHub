#!/usr/bin/env bash
# Encrypts a pg_dump and stores it with 14-day retention (#34).
# Usage: scripts/backup-db.sh <dump-file>
#   BACKUP_PASSPHRASE  encryption passphrase (AES-256, PBKDF2)
#   BACKUP_DEST        s3://bucket/prefix (Tigris, via the AWS CLI and
#                      AWS_* credentials) or a local directory (tests)
#   BACKUP_RETENTION_DAYS  default 14
set -euo pipefail

dump=${1:?Usage: backup-db.sh <dump-file>}
: "${BACKUP_PASSPHRASE:?Set BACKUP_PASSPHRASE}"
: "${BACKUP_DEST:?Set BACKUP_DEST to s3://bucket/prefix or a directory}"
retention=${BACKUP_RETENTION_DAYS:-14}

# A dump smaller than this is an error message, not a database.
size=$(wc -c <"$dump" | tr -d ' ')
if [ "$size" -lt 1024 ]; then
    echo "error: $dump is only $size bytes; refusing to store it as a backup" >&2
    exit 1
fi
# Custom-format dumps start with this signature.
if [ "$(head -c 5 "$dump")" != "PGDMP" ]; then
    echo "error: $dump is not a pg_dump custom-format archive" >&2
    exit 1
fi

name="repohub-$(date -u +%Y%m%dT%H%M%SZ).dump.enc"
encrypted=$(mktemp)
trap 'rm -f "$encrypted"' EXIT
openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass env:BACKUP_PASSPHRASE -in "$dump" -out "$encrypted"

cutoff=$(date -u -d "-$retention days" +%Y%m%dT%H%M%SZ 2>/dev/null || date -u -v "-${retention}d" +%Y%m%dT%H%M%SZ)
case "$BACKUP_DEST" in
s3://*)
    aws s3 cp --only-show-errors "$encrypted" "${BACKUP_DEST%/}/$name"
    existing=$(aws s3 ls "${BACKUP_DEST%/}/" | awk '{print $4}' | grep '^repohub-.*\.dump\.enc$' || true)
    remove() { aws s3 rm --only-show-errors "${BACKUP_DEST%/}/$1"; }
    ;;
*)
    mkdir -p "$BACKUP_DEST"
    cp "$encrypted" "$BACKUP_DEST/$name"
    existing=$(find "$BACKUP_DEST" -maxdepth 1 -name 'repohub-*.dump.enc' -exec basename {} \;)
    remove() { rm -f "${BACKUP_DEST:?}/$1"; }
    ;;
esac
echo "stored $name ($size bytes before encryption)"

# Names sort by time, so anything named before the cutoff is older than the retention.
for old in $existing; do
    stamp=${old#repohub-}
    stamp=${stamp%.dump.enc}
    if [[ "$stamp" < "$cutoff" ]]; then
        remove "$old"
        echo "pruned $old"
    fi
done
