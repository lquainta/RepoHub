import Foundation
import RepoHubCore

@testable import RepoHub

/// A `GitServicing` fake that returns canned statuses per repository path and
/// records how many reads ran at the same time.
actor FakeGit: GitServicing {
    private var results: [String: Result<RepoStatus, GitError>]
    private let delay: Duration
    private var running = 0
    /// The most reads that were ever running at once.
    private(set) var peakConcurrency = 0
    /// Every path read, in the order reads started.
    private(set) var reads: [String] = []

    init(_ results: [String: Result<RepoStatus, GitError>] = [:], delay: Duration = .zero) {
        self.results = results
        self.delay = delay
    }

    func setResult(_ result: Result<RepoStatus, GitError>, for path: String) {
        results[path] = result
    }

    func status(of repository: URL) async throws -> RepoStatus {
        reads.append(repository.path)
        running += 1
        peakConcurrency = max(peakConcurrency, running)
        defer { running -= 1 }
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        return try (results[repository.path] ?? .success(RepoStatus(head: .branch("main")))).get()
    }
}
