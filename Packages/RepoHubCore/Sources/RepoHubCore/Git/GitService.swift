import Foundation

/// Reads and changes repository state. ``GitService`` is the real
/// implementation; the app's view models depend on this protocol so tests can
/// inject fakes.
public protocol GitServicing: Sendable {
    /// Returns the current status of the repository at `repository`.
    func status(of repository: URL) async throws -> RepoStatus
    /// Returns the status plus changed files, branches, recent commits, remotes, and stashes.
    func details(of repository: URL, commitLimit: Int) async throws -> RepositoryDetails
}

extension GitServicing {
    /// Returns details with the 20 most recent commits.
    public func details(of repository: URL) async throws -> RepositoryDetails {
        try await details(of: repository, commitLimit: 20)
    }
}

/// Reads repository state by running git.
public struct GitService: GitServicing {
    private let runner: any GitCommandRunning

    /// Creates a service that runs commands with `runner`.
    public init(runner: any GitCommandRunning = ProcessGitRunner()) {
        self.runner = runner
    }

    /// Returns the current status of the repository at `repository`.
    ///
    /// - Throws: ``GitError`` if git fails or its output can't be parsed.
    public func status(of repository: URL) async throws -> RepoStatus {
        var status = try PorcelainStatusParser.parse(try await runStatus(in: repository))

        // A repository with no commits has nothing to log.
        if case .unborn = status.head {
            return status
        }
        let log = try await runner.run(
            ["--no-optional-locks", "log", "-1", "--format=\(CommitSummaryParser.format)"],
            in: repository
        )
        status.lastCommit = try CommitSummaryParser.parse(log)
        return status
    }

    /// Returns the status plus changed files, branches, the `commitLimit` most
    /// recent commits, remotes, and stashes of the repository at `repository`.
    ///
    /// The underlying git commands run concurrently.
    ///
    /// - Throws: ``GitError`` if any git command fails or its output can't be parsed.
    public func details(of repository: URL, commitLimit: Int = 20) async throws -> RepositoryDetails {
        async let statusOutput = runStatus(in: repository)
        async let branchOutput = runner.run(
            ["--no-optional-locks", "for-each-ref", "--format=\(BranchListParser.format)"]
                + BranchListParser.refPatterns,
            in: repository
        )
        async let remoteOutput = runner.run(["remote", "-v"], in: repository)
        async let stashOutput = runner.run(
            ["--no-optional-locks", "stash", "list", "--format=\(StashListParser.format)"],
            in: repository
        )

        let (status, files) = try PorcelainStatusParser.parseWithFiles(try await statusOutput)
        var details = RepositoryDetails(
            status: status,
            files: files,
            branches: try BranchListParser.parse(try await branchOutput),
            remotes: try RemoteListParser.parse(try await remoteOutput),
            stashes: try StashListParser.parse(try await stashOutput)
        )
        // A repository with no commits has nothing to log.
        if case .unborn = status.head {
            return details
        }
        let log = try await runner.run(
            ["--no-optional-locks", "log", "-\(max(1, commitLimit))", "--format=\(CommitSummaryParser.format)"],
            in: repository
        )
        details.recentCommits = try CommitSummaryParser.parseList(log)
        details.status.lastCommit = details.recentCommits.first
        return details
    }

    private func runStatus(in repository: URL) async throws -> String {
        try await runner.run(
            [
                // Don't take index.lock for a read; avoids conflicts with the user's own git commands.
                "--no-optional-locks",
                "status", "--porcelain=v2", "--branch", "--show-stash", "-z", "--untracked-files=normal",
            ],
            in: repository
        )
    }
}
