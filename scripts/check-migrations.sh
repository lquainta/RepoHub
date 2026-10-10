#!/usr/bin/env bash
# Proves the schema can be created and torn down entirely from migrations:
# migrate -> revert -> migrate against a clean database (#31).
# Usage: DATABASE_URL=postgres://... scripts/check-migrations.sh
set -euo pipefail

: "${DATABASE_URL:?Set DATABASE_URL to a clean, disposable database}"
cd "$(dirname "$0")/.."

app() { swift run --package-path Backend -q App migrate "$@" --yes; }

tables() {
    # Every table except Fluent's own bookkeeping table.
    psql "$DATABASE_URL" -tAc "SELECT count(*) FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name <> '_fluent_migrations'"
}

echo "== migrate"
app
created=$(tables)
echo "$created tables"

echo "== revert"
app --revert
remaining=$(tables)
if [ "$remaining" -ne 0 ]; then
    echo "::error::Reverting all migrations left $remaining tables behind"
    exit 1
fi

echo "== migrate again"
app
again=$(tables)
if [ "$again" -ne "$created" ]; then
    echo "::error::Re-applying migrations created $again tables, expected $created"
    exit 1
fi
echo "Migrations apply, revert, and re-apply cleanly ($created tables)."
