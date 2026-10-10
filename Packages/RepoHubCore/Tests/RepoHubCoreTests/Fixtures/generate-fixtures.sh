#!/usr/bin/env bash
# Regenerates the recorded `git status` / `git log` fixtures from real
# repositories so parser tests run against genuine git output.
# Usage: Tests/RepoHubCoreTests/Fixtures/generate-fixtures.sh
set -euo pipefail

out="$(cd "$(dirname "$0")" && pwd)/git-output"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME="Ada Lovelace" GIT_AUTHOR_EMAIL="ada@example.com"
export GIT_COMMITTER_NAME="Ada Lovelace" GIT_COMMITTER_EMAIL="ada@example.com"
export GIT_AUTHOR_DATE="2026-10-01T09:30:00-06:00" GIT_COMMITTER_DATE="2026-10-01T09:30:00-06:00"

status() { git -C "$1" --no-optional-locks status --porcelain=v2 --branch --show-stash -z > "$out/$2.txt"; }

new_repo() { git init -q -b main "$1"; }
commit_file() { echo "$3" > "$1/$2"; git -C "$1" add "$2"; git -C "$1" commit -q -m "$4"; }

# A bare "origin" plus a clone tracking it
git init -q --bare -b main "$work/origin.git"
new_repo "$work/base"
commit_file "$work/base" README.md "hello" "Initial commit"
git -C "$work/base" remote add origin "$work/origin.git"
git -C "$work/base" push -q -u origin main

# clean: tracking upstream, in sync
status "$work/base" clean

# ahead-behind: 2 local commits, 1 remote commit
git clone -q "$work/origin.git" "$work/other"
commit_file "$work/other" remote.txt "r" "Remote change"
git -C "$work/other" push -q origin main
cp -R "$work/base" "$work/ab"
commit_file "$work/ab" a.txt "a" "Local one"
commit_file "$work/ab" b.txt "b" "Local two"
git -C "$work/ab" fetch -q origin
status "$work/ab" ahead-behind

# dirty: staged add, staged modify, unstaged modify, both, staged rename, untracked (with spaces/unicode)
cp -R "$work/base" "$work/dirty"
commit_file "$work/dirty" keep.txt "k" "Add keep"
commit_file "$work/dirty" both.txt "1" "Add both"
commit_file "$work/dirty" old-name.txt "o" "Add old"
echo new > "$work/dirty/added.txt" && git -C "$work/dirty" add added.txt
echo changed > "$work/dirty/README.md" && git -C "$work/dirty" add README.md
echo changed > "$work/dirty/keep.txt"
echo 2 > "$work/dirty/both.txt" && git -C "$work/dirty" add both.txt && echo 3 > "$work/dirty/both.txt"
git -C "$work/dirty" mv old-name.txt "new name é.txt"
echo u > "$work/dirty/untracked file.txt"
echo u > "$work/dirty/ünïcode.txt"
status "$work/dirty" dirty

# stash: two stashes, clean tree
cp -R "$work/base" "$work/stash"
echo s1 > "$work/stash/README.md" && git -C "$work/stash" stash -q
echo s2 > "$work/stash/README.md" && git -C "$work/stash" stash -q
status "$work/stash" stash

# detached HEAD
cp -R "$work/base" "$work/detached"
git -C "$work/detached" checkout -q --detach HEAD
status "$work/detached" detached

# no upstream: local-only branch
cp -R "$work/base" "$work/noup"
git -C "$work/noup" checkout -q -b feature/local
status "$work/noup" no-upstream

# unborn: fresh repo, no commits, one untracked file
new_repo "$work/unborn"
echo x > "$work/unborn/file.txt"
status "$work/unborn" unborn

# conflicted: merge conflict on one file
new_repo "$work/conflict"
commit_file "$work/conflict" c.txt "base" "Base"
git -C "$work/conflict" checkout -q -b topic
commit_file "$work/conflict" c.txt "topic" "Topic change"
git -C "$work/conflict" checkout -q main
commit_file "$work/conflict" c.txt "main" "Main change"
git -C "$work/conflict" merge -q topic >/dev/null 2>&1 || true
status "$work/conflict" conflicted

# last commit, using the same format GitService requests
git -C "$work/base" log -1 --format='%H%x1f%an%x1f%aI%x1f%s' > "$out/log-last-commit.txt"

# details: branches (current, ahead of upstream, upstream gone, local-only),
# remote-tracking branches, a remote with a separate push URL, and stashes.
# Temporary paths are replaced with /work so fixtures are stable.
sanitize() { sed "s|$work|/work|g"; }
cp -R "$work/base" "$work/details"
git -C "$work/details" checkout -q -b feature/ahead
git -C "$work/details" push -q -u origin feature/ahead
commit_file "$work/details" ahead.txt "a" "Ahead of upstream"
git -C "$work/details" checkout -q -b feature/gone main
git -C "$work/details" push -q -u origin feature/gone
git -C "$work/details" push -q origin --delete feature/gone
git -C "$work/details" fetch -q --prune origin
git -C "$work/details" checkout -q -b local-only main
commit_file "$work/details" local.txt "l" "Local only"
git -C "$work/details" checkout -q main
git -C "$work/details" remote set-url --push origin "git@example.com:ada/repo.git"
git -C "$work/details" remote add upstream "https://example.com/upstream/repo.git"
echo s1 > "$work/details/README.md" && git -C "$work/details" stash push -q -m "First stash"
echo s2 > "$work/details/README.md" && git -C "$work/details" stash push -q -m "Second stash"
git -C "$work/details" for-each-ref --format='%(refname)%1f%(upstream:short)%1f%(upstream:track,nobracket)%1f%(objectname)%1f%(committerdate:iso-strict)%1f%(HEAD)' refs/heads refs/remotes > "$out/for-each-ref.txt"
git -C "$work/details" remote -v | sanitize > "$out/remote-v.txt"
git -C "$work/details" stash list --format='%gd%x1f%cI%x1f%gs' > "$out/stash-list.txt"
git -C "$work/details" log -20 --format='%H%x1f%an%x1f%aI%x1f%s' feature/ahead > "$out/log-recent.txt"

echo "Fixtures written to $out"
