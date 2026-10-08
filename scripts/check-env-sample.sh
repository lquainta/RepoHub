#!/usr/bin/env bash
# Fails if the backend reads an environment variable that is not documented in
# .env.sample. Keys are found from EnvironmentReader calls and Environment.get.
set -euo pipefail

cd "$(dirname "$0")/.."

used=$(grep -rhoE '(required|optional|integer|Environment\.get)\("[A-Z][A-Z0-9_]*"' Backend/Sources \
    | grep -oE '"[A-Z][A-Z0-9_]*"' | tr -d '"' | sort -u)

missing=0
for key in $used; do
    if ! grep -qE "^#? ?${key}=" .env.sample; then
        echo "::error file=.env.sample::${key} is read by the backend but not documented in .env.sample"
        missing=1
    fi
done

if [ "$missing" -eq 0 ]; then
    echo "All $(echo "$used" | grep -c .) environment variables are documented in .env.sample."
fi
exit "$missing"
