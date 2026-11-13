#!/usr/bin/env bash
# Fails if an architecture diagram names a type that isn't in the code (#54),
# so diagrams are updated when types are renamed or removed.
# Checked: `class X` in class diagrams and `participant X` in sequence diagrams
# (a participant shown `as` something else, like `GitHub as GitHub (main)`, isn't
# a type and is skipped), plus single-word nodes in flowcharts that look like types.
set -euo pipefail
cd "$(dirname "$0")/.."

declared=$(find App/Sources Packages/*/Sources Backend/Sources -name '*.swift' -exec \
    grep -hoE '\b(class|struct|enum|actor|protocol|typealias) [A-Z][A-Za-z0-9]*' {} + | awk '{print $2}' | sort -u)
# External systems and people that appear in diagrams but aren't types.
external="Git GitHub Redis Postgres Keychain Views User Developer CI Deploy Fly Release"

names=$(
    {
        grep -hoE '^\s*class [A-Z][A-Za-z0-9]*' docs/architecture/*.md | awk '{print $2}'
        grep -hE '^\s*participant [A-Z][A-Za-z0-9]*\s*$' docs/architecture/*.md | awk '{print $2}'
        grep -hoE '^\s+[A-Z][A-Za-z0-9]+\s*$' docs/architecture/*.md | tr -d ' '
    } | sort -u
)

missing=0
for name in $names; do
    if ! grep -qx "$name" <<<"$declared" && ! grep -qw "$name" <<<"$external"; then
        echo "::error file=docs/architecture::'$name' is in a diagram but not declared in the code"
        missing=1
    fi
done
[ "$missing" -eq 0 ] && echo "All $(wc -w <<<"$names" | tr -d ' ') names in the architecture diagrams exist in the code."
exit "$missing"
