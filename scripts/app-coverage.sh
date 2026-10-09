#!/usr/bin/env bash
# Exports LCOV for the macOS app's own sources from an Xcode test run.
# Run `make test-app DERIVED_DATA=<dir>` first.
#
# Usage: scripts/app-coverage.sh <derived-data-dir> <output.lcov>
set -euo pipefail

derived="${1:?usage: $0 <derived-data-dir> <output.lcov>}"
output="${2:?usage: $0 <derived-data-dir> <output.lcov>}"

profdata="$(find "$derived/Build/ProfileData" -name 'Coverage.profdata' | head -n 1)"
# Debug builds put the app's code in RepoHub.debug.dylib next to a small stub executable.
macos="$derived/Build/Products/Debug/RepoHub.app/Contents/MacOS"
binary="$macos/RepoHub.debug.dylib"
[ -f "$binary" ] || binary="$macos/RepoHub"
if [ -z "$profdata" ] || [ ! -f "$binary" ]; then
    echo "Coverage data not found in $derived; run 'make test-app DERIVED_DATA=$derived' first" >&2
    exit 1
fi

# RepoHubCore is measured with its own package tests.
ignore='(/Tests/|DerivedData|/Packages/|\.build/)'
mkdir -p "$(dirname "$output")"
xcrun llvm-cov export -format=lcov "$binary" -instr-profile "$profdata" -ignore-filename-regex="$ignore" > "$output"
xcrun llvm-cov report "$binary" -instr-profile "$profdata" -ignore-filename-regex="$ignore" | tail -n 1
