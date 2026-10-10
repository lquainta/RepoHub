import Foundation

/// Reads and changes repository state. ``GitService`` is the real
/// implementation; the app's view models depend on this protocol so tests can
/// inject fakes.
public protocol GitServicing: Sendable {
    /// Returns the current status of the repository at `repository`.
    func status(of repository: URL) async throws -> RepoStatus
    /// Returns the status plus changed files, branches, recent commits, remotes, and stashes.
    func details(of repository: URL, commitLimit: Int) async throws -> RepositoryDetails
    /// Downloads objects and refs from every remote and prunes deleted remote branches.
    func fetch(_ repository: URL) async throws
    /// Fast-forwards the current branch to its upstream. Never creates a merge commit.
    func pull(_ repository: URL) async throws
    /// Returns the configured remotes, sorted by name.
    func remotes(of repository: URL) async throws -> [Remote]
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
        async let remotes = remotes(of: repository)
        async let stashOutput = runner.run(
            ["--no-optional-locks", "stash", "list", "--format=\(StashListParser.format)"],
            in: repository
        )

        let (status, files) = try PorcelainStatusParser.parseWithFiles(try await statusOutput)
        var details = RepositoryDetails(
            status: status,
            files: files,
            branches: try BranchListParser.parse(try await branchOutput),
            remotes: try await remotes,
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

    /// Runs `git fetch --all --prune`.
    ///
    /// - Throws: ``GitError`` if a remote can't be reached or authentication fails.
    public func fetch(_ repository: URL) async throws {
        _ = try await runner.run(["fetch", "--all", "--prune", "--quiet"], in: repository)
    }

    /// Runs `git pull --ff-only`, so local commits are never merged or rebased.
    ///
    /// - Throws: ``GitError/commandFailed(command:exitCode:stderr:)`` if the
    ///   branch has diverged from its upstream, has no upstream, or local
    ///   changes would be overwritten.
    public func pull(_ repository: URL) async throws {
        _ = try await runner.run(["pull", "--ff-only", "--quiet"], in: repository)
    }

    /// Runs `git remote -v`.
    public func remotes(of repository: URL) async throws -> [Remote] {
        try RemoteListParser.parse(try await runner.run(["remote", "-v"], in: repository))
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
