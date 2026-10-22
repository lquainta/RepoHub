# Architecture

How RepoHubCore is organized, and why it runs git instead of linking a library.

## Overview

```
GitServicing (protocol)          RepositoryScanning (protocol)
      │                                   │
  GitService ──► GitCommandRunning    RepositoryScanner
      │               │
      │         ProcessGitRunner ──► git
      ▼
 parsers (porcelain status, branches, commits, remotes, stashes)
      ▼
 models (RepoStatus, RepositoryDetails, Branch, …)
```

- ``GitService`` builds git command lines and turns their output into models with the parsers. It never parses human-readable output, only git's machine formats: `status --porcelain=v2 -z` (NUL-separated, so any path is safe) and `for-each-ref`, `log`, and `stash list` with explicit `--format` strings.
- ``ProcessGitRunner`` runs git on a dedicated thread per process, with a 30-second timeout, and never lets it prompt (`GIT_TERMINAL_PROMPT=0`). Blocking process I/O stays off Swift's cooperative thread pool.
- Models are `Sendable` value types, safe to pass between the app's actors and the backend's event loops.

## Why the git CLI

ADR 0004 compares the CLI with libgit2. The CLI matches exactly what users see in their terminal (config, hooks, credential helpers, worktrees, sparse checkouts), needs no C dependency on Linux, and its porcelain formats are stable by design. The cost, a process per command, is bounded by running at most eight at a time in the app.

## Diagrams

The class diagram and the sequences that use RepoHubCore are in `docs/architecture/` in the repository: `core.md`, and *Scanning and refreshing* in `sequences.md`.
