#!/usr/bin/env bash
# Proves the git hooks in .githooks/ block bad commits (#61): commits with a
# swift-format error, a SwiftLint error, a secret, or a non-conventional
# message must fail, and a clean commit must succeed.
# Usage: scripts/test-git-hooks.sh   (needs swift, swiftlint, and gitleaks)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

cd "$work"
git init -q -b main
git config user.email test@example.com
git config user.name "Hook Test"
git config commit.gpgsign false
git config core.hooksPath "$repo_root/.githooks"
cp "$repo_root/.swift-format" "$repo_root/.swiftlint.yml" "$repo_root/.gitleaks.toml" .
mkdir -p App/Sources

passed=0
failed=0

# expect <succeed|fail> <description> <commit message>: commits what's staged.
expect() {
    local outcome=$1 description=$2 message=$3
    if git commit -q -m "$message" >/dev/null 2>&1; then
        result=succeed
    else
        result=fail
    fi
    if [ "$result" = "$outcome" ]; then
        echo "✓ $description"
        passed=$((passed + 1))
    else
        echo "✗ $description: expected the commit to $outcome, but it didn't"
        failed=$((failed + 1))
    fi
    git reset -q --hard 2>/dev/null || true
}

# A clean commit is allowed.
printf 'struct Clean {\n    let value = 1\n}\n' > App/Sources/Clean.swift
git add -A
expect succeed "clean Swift file with a conventional message is committed" "feat(app): add a clean type"

# Formatting errors are blocked.
printf 'struct   Messy{let value=1}\n' > App/Sources/Messy.swift
git add -A
expect fail "a swift-format error is blocked" "feat(app): add a messy type"

# Lint errors are blocked (force unwrapping is an opt-in error in .swiftlint.yml).
printf 'let number = Int("1")!\n' > App/Sources/Unwrap.swift
git add -A
expect fail "a SwiftLint error is blocked" "feat(app): force unwrap"

# Secrets are blocked. The token is random and built at run time, so no
# secret-shaped string is in this file (Gitleaks also ignores low-entropy fakes).
token="ghp_$(od -An -tx1 -N18 /dev/urandom | tr -d " \n")"
printf 'GITHUB_TOKEN=%s\n' "$token" > config.env
git add -A
expect fail "a GitHub token is blocked" "chore: add config"

# Commit messages must be conventional. (A blocked commit's new file is reset away, so recreate it.)
stage_notes() {
    printf 'notes\n' > notes.txt
    git add -A
}
stage_notes
expect fail "a non-conventional message is blocked" "Added some notes"
stage_notes
expect fail "an unknown scope is blocked" "docs(website): add notes"
stage_notes
expect succeed "a conventional message without a scope is allowed" "docs: add notes"

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
