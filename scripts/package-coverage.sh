#!/usr/bin/env bash
# Runs a Swift package's tests with code coverage and exports LCOV for the
# package's own sources (tests, dependencies, and other local packages excluded).
#
# Usage: scripts/package-coverage.sh <package-dir> <output.lcov>
set -euo pipefail

package="${1:?usage: $0 <package-dir> <output.lcov>}"
output="${2:?usage: $0 <package-dir> <output.lcov>}"
package_abs="$(cd "$package" && pwd)"

swift test --package-path "$package" --enable-code-coverage

bin="$(swift build --package-path "$package" --show-bin-path)"
profdata="$bin/codecov/default.profdata"
# Locate the instrumented test binary. macOS: <Target>Tests.xctest bundle.
# Linux (Swift 6.4 build system): <Target>Tests.so, run by <Target>Tests-test-runner.
if [ "$(uname)" = "Darwin" ]; then
    bundle="$(find "$bin" -maxdepth 1 -name '*.xctest' | head -n 1)"
    binary="$bundle/Contents/MacOS/$(basename "$bundle" .xctest)"
    llvm_cov=(xcrun llvm-cov)
else
    binary="$(find "$bin" -maxdepth 1 \( -name '*Tests.so' -o -name '*.xctest' \) -type f | head -n 1)"
    llvm_cov=(llvm-cov)
fi
if [ ! -f "$binary" ]; then
    echo "No test binary found in $bin" >&2
    exit 1
fi

# Exclude dependencies, tests, and manifests. A package outside Packages/
# (the backend) also excludes the local packages it depends on, which are
# measured on their own.
ignore='(\.build/|/Tests/|Package\.swift)'
if [[ "$package_abs" != */Packages/* ]]; then
    ignore='(\.build/|/Tests/|Package\.swift|/Packages/)'
fi

mkdir -p "$(dirname "$output")"
"${llvm_cov[@]}" export -format=lcov "$binary" -instr-profile "$profdata" -ignore-filename-regex="$ignore" > "$output"
"${llvm_cov[@]}" report "$binary" -instr-profile "$profdata" -ignore-filename-regex="$ignore" | tail -n 1
