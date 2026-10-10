import Foundation

/// Reads and changes repository state. ``GitService`` is the real
/// implementation; the app's view models depend on this protocol so tests can
/// inject fakes.
public protocol GitServicing: Sendable {
    /// Returns the current status of the repository at `repository`.
    func status(of repository: URL) async throws -> RepoStatus
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
        let output = try await runner.run(
            [
                // Don't take index.lock for a read; avoids conflicts with the user's own git commands.
                "--no-optional-locks",
                "status", "--porcelain=v2", "--branch", "--show-stash", "-z", "--untracked-files=normal",
            ],
            in: repository
        )
        var status = try PorcelainStatusParser.parse(output)

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
}
