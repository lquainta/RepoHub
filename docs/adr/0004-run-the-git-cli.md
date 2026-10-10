# 0004. Read repositories by running the git CLI, not libgit2

- **Status:** Accepted
- **Date:** 2026-10-08
- **Issue:** #60, #67

## Context and problem statement

RepoHub reads status, branches, commits, and stashes from many repositories, and runs fetch and pull. It can either link a git library or run the `git` executable and parse its output.

## Decision drivers

- Results must match what the user sees in their own terminal, including their config (credential helpers, SSH config, `includeIf`, `core.fsmonitor`).
- Fetch and pull must authenticate exactly as the user's git does, without RepoHub handling credentials.
- Parsing must be stable across git versions.
- Testable without real repositories where possible.

## Considered options

1. Run `git` with machine-readable output (`status --porcelain=v2 -z`, `for-each-ref --format`, `log --format` with 0x1F separators)
2. libgit2 via SwiftGit2 or a custom wrapper
3. Read `.git` files directly

## Decision outcome

Chosen option: **run the git CLI**, through `ProcessGitRunner` behind the `GitCommandRunning` protocol.

- Only stable, documented machine formats are parsed. Fields use the ASCII unit separator (0x1F) and entries use NUL (`-z`), so paths with spaces or newlines are safe.
- Read-only commands pass `--no-optional-locks`, so RepoHub never takes `index.lock` or conflicts with the user's own git commands.
- Arguments go straight to the process, never through a shell. `GIT_TERMINAL_PROMPT=0` and `LC_ALL=C` keep runs non-interactive and stderr in English.
- Every command has a timeout, and cancelling the task terminates the process.

### Consequences

- Good: identical behavior to the user's git, with free authentication for fetch and pull.
- Good: parsers are pure functions tested against output recorded from real git (`Fixtures/generate-fixtures.sh`); a fake runner tests the service.
- Bad: a process per command. Bounded concurrency (8 status reads, 4 network operations) and FSEvents-driven, per-repository refreshes keep this cheap.
- Bad: needs `git` installed; the app reports `gitNotFound` clearly.
- Neutral: process handling has platform subtleties. See #105: blocking waits must run on dedicated threads, not the libdispatch pool.

## Pros and cons of the options

### libgit2

- Good: no process overhead.
- Bad: ignores parts of the user's config; separate credential handling for fetch; C dependency and build complexity; results can differ from `git status`.

### Reading `.git` directly

- Good: fastest.
- Bad: re-implements git (index format, packed refs, worktrees); fragile.
