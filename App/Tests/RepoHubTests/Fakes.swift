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

    /// Per-path delays for `details(of:)`, to simulate slow repositories.
    private var detailDelays: [String: Duration] = [:]

    func setDetailDelay(_ delay: Duration, for path: String) {
        detailDelays[path] = delay
    }

    /// Returns details built from the canned status for `repository`.
    func details(of repository: URL, commitLimit: Int) async throws -> RepositoryDetails {
        if let delay = detailDelays[repository.path] {
            try await Task.sleep(for: delay)
        }
        let status = try (results[repository.path] ?? .success(RepoStatus(head: .branch("main")))).get()
        return RepositoryDetails(status: status, remotes: [Remote(name: "origin", fetchURL: repository.path)])
    }

    /// Errors to throw from network actions, per path.
    private var actionFailures: [String: GitError] = [:]
    /// Remotes per path; defaults to an `origin` on GitHub.
    private var remoteLists: [String: [Remote]] = [:]
    /// Every fetch and pull, as `"fetch /path"` or `"pull /path"`, in start order.
    private(set) var actionLog: [String] = []

    func setActionFailure(_ error: GitError, for path: String) {
        actionFailures[path] = error
    }

    func setRemotes(_ remotes: [Remote], for path: String) {
        remoteLists[path] = remotes
    }

    func fetch(_ repository: URL) async throws {
        try await performAction("fetch", repository)
    }

    func pull(_ repository: URL) async throws {
        try await performAction("pull", repository)
    }

    func remotes(of repository: URL) async throws -> [Remote] {
        remoteLists[repository.path] ?? [
            Remote(name: "origin", fetchURL: "git@github.com:owner/\(repository.lastPathComponent).git")
        ]
    }

    private func performAction(_ name: String, _ repository: URL) async throws {
        actionLog.append("\(name) \(repository.path)")
        running += 1
        peakConcurrency = max(peakConcurrency, running)
        defer { running -= 1 }
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        if let error = actionFailures[repository.path] {
            throw error
        }
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

/// Records what would have been opened or copied.
@MainActor
final class FakeWorkspace: WorkspaceOpening {
    private(set) var opened: [(folder: URL, bundleID: String)] = []
    private(set) var revealed: [URL] = []
    private(set) var browsed: [URL] = []
    private(set) var clipboard: String?
    /// Bundle identifiers that act as if the app isn't installed.
    var missingApps: Set<String> = []

    func open(_ folder: URL, withApplication bundleID: String) async throws {
        if missingApps.contains(bundleID) {
            throw WorkspaceError.applicationNotFound(bundleID: bundleID)
        }
        opened.append((folder, bundleID))
    }

    func revealInFinder(_ url: URL) {
        revealed.append(url)
    }

    func openInBrowser(_ url: URL) {
        browsed.append(url)
    }

    func copyToClipboard(_ string: String) {
        clipboard = string
    }
}
