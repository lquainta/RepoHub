# Restore the production database

Backups are made two ways (#34):

| Layer | What | Retention | Where |
| --- | --- | --- | --- |
| **Nightly logical backup** | `pg_dump --format=custom` of `repohub`, AES-256 encrypted (`openssl enc -pbkdf2`) | 14 days | Tigris bucket `repohub-backups`, prefix `postgres/` |
| **Volume snapshots** (provider) | Fly's automatic daily snapshot of the database volume | 5 days | Fly (`fly volumes snapshots list`) |

The nightly backup is [`.github/workflows/backup.yml`](../../.github/workflows/backup.yml). Every **Sunday**, the same workflow **restores the latest backup into a throwaway PostgreSQL 18 database** and checks its tables and migrations, so restores are tested continuously, not only when they're needed.

## Restore into a scratch database (a check, or to recover a few rows)

```sh
# Credentials from the `backups` environment / your password manager.
export BACKUP_PASSPHRASE=... BACKUP_DEST=s3://repohub-backups/postgres
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_ENDPOINT_URL_S3=https://fly.storage.tigris.dev AWS_REGION=auto

createdb repohub_restore
scripts/restore-db.sh latest postgres://localhost/repohub_restore     # or a name from `aws s3 ls`
psql repohub_restore -c 'SELECT count(*) FROM users'
```

`restore-db.sh` refuses any target whose name doesn't end in `_restore` or `_test`, because it drops and recreates every object.

## Restore production

1. **Stop writes:** `fly scale count 0 --app repohub-backend` (the API is down from here).
2. Open a proxy to the database: `fly proxy 15432:5432 --app repohub-db`.
3. Restore into a new database, then swap it in, so a failed restore leaves production as it was:
   ```sh
   psql postgres://postgres:$OPERATOR_PASSWORD@localhost:15432/postgres -c 'CREATE DATABASE repohub_restore OWNER repohub'
   scripts/restore-db.sh latest postgres://postgres:$OPERATOR_PASSWORD@localhost:15432/repohub_restore
   psql postgres://postgres:$OPERATOR_PASSWORD@localhost:15432/postgres \
     -c 'ALTER DATABASE repohub RENAME TO repohub_broken' -c 'ALTER DATABASE repohub_restore RENAME TO repohub'
   ```
4. **Start the API:** `fly scale count 1 --app repohub-backend`. It runs pending migrations on deploy only, so a backup from an older schema needs `fly deploy` (or `fly ssh console --app repohub-backend -C './App migrate --yes'`).
5. Check `https://repohub-backend.fly.dev/ready`, then drop `repohub_broken` after a few days.

**From a volume snapshot instead** (whole-machine loss): `fly volumes snapshots list <volume>` and `fly volumes create pg_data --snapshot-id <id> --app repohub-db`, then attach it to a new database machine.

## Restore drill log

| Date | Backup | Where | Result |
| --- | --- | --- | --- |
| 2026-10-22 | Local test database (500 rows) | Local PostgreSQL 16, `repohub_restore` | Restored; row counts matched. Guards refused a live database, a truncated dump, and a wrong passphrase. |

Add a row after each manual drill. The weekly automated restore is in the workflow's run history.
