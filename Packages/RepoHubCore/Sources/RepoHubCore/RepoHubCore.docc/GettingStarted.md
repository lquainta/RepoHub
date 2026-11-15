# Getting Started

Add RepoHubCore to a package, read a repository's status, and find repositories in a folder.

## Add the package

RepoHubCore is a local package in the RepoHub repository:

```swift
// Package.swift
dependencies: [.package(path: "../Packages/RepoHubCore")],
targets: [.target(name: "MyTool", dependencies: ["RepoHubCore"])]
```

It runs `/usr/bin/git` by default (on macOS, from the Xcode Command Line Tools); give ``ProcessGitRunner`` another `executableURL` to use a different git. ``GitService`` reports ``GitError/gitNotFound(path:)`` if git isn't there.

## Read a repository

```swift
let git = GitService()
let repository = URL(filePath: "/Users/me/dev/api", directoryHint: .isDirectory)

let status = try await git.status(of: repository)
if status.isClean {
    print("Clean, \(status.ahead) ahead, \(status.behind) behind")
}

let details = try await git.details(of: repository, commitLimit: 10)
for commit in details.recentCommits {
    print(commit.hash.prefix(7), commit.subject)
}
```

Every call runs git in the background with a timeout. Network actions (``GitService/fetch(_:)`` and ``GitService/pull(_:)``) never merge: pull is fast-forward only.

## Find repositories

```swift
let scanner = RepositoryScanner()
let repositories = try await scanner.scan(URL(filePath: "/Users/me/dev"), maxDepth: 4)
```

The scanner skips hidden folders and names like `node_modules`, finds linked worktrees, and doesn't descend into a repository it already found.

## Test without git

View models and tools should depend on ``GitServicing`` and take a fake in tests. To test ``GitService`` itself without running git, give it a ``GitCommandRunning`` that returns recorded output:

```swift
struct RecordedRunner: GitCommandRunning {
    func run(_ arguments: [String], in directory: URL) async throws -> String {
        try String(contentsOf: fixture(for: arguments), encoding: .utf8)
    }
}
let git = GitService(runner: RecordedRunner())
```
