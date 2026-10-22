# ``RepoHubCore``

Read and change git repositories: status, details, remotes, stale branches, and repository discovery.

## Overview

RepoHubCore is the part of RepoHub that talks to git. The macOS app uses it for every repository on the dashboard, and the backend shares its models. It builds on macOS and Linux and depends only on Foundation.

It runs the `git` command-line tool (ADR 0004) rather than linking libgit2, and parses git's stable, machine-readable output formats, such as `git status --porcelain=v2`.

```swift
import RepoHubCore

let git = GitService()
let status = try await git.status(of: URL(filePath: "/Users/me/dev/api"))
print(status.head.branchName ?? "detached", status.ahead, status.behind, status.changes)
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Architecture>

### Reading and changing repositories

- ``GitServicing``
- ``GitService``
- ``GitCommandRunning``
- ``ProcessGitRunner``
- ``GitError``

### Status and details

- ``RepoStatus``
- ``HeadState``
- ``FileChangeCounts``
- ``FileChange``
- ``RepositoryDetails``
- ``CommitSummary``
- ``Branch``
- ``Remote``
- ``StashEntry``

### Finding repositories

- ``RepositoryScanning``
- ``RepositoryScanner``
- ``ScanError``

### Cleaning up branches

- ``StaleBranchDetector``
- ``StaleBranchReport``
- ``StaleBranch``
- ``StaleReason``
- ``BranchDeletionResult``

### Identifying repositories

- ``GitHubRepository``
- ``RemoteIdentity``

### Parsing git output

- ``PorcelainStatusParser``
- ``BranchListParser``
- ``CommitSummaryParser``
- ``RemoteListParser``
- ``StashListParser``
