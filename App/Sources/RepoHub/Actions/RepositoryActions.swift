import Foundation
import OSLog
import Observation
import RepoHubCore

/// Fetch, pull, and open actions on tracked repositories.
///
/// Network actions report failures per repository so one unreachable remote
/// doesn't hide the others, and refresh the affected statuses when they finish.
@MainActor
@Observable
final class RepositoryActions {
    /// Progress of a running "Fetch All".
    struct Progress: Equatable {
        var completed: Int
        var total: Int
    }

    /// A failed action on one repository.
    struct Failure: Equatable, Identifiable {
        let id = UUID()
        /// The repository's display name.
        let repository: String
        /// What went wrong, for the user.
        let message: String

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.repository == rhs.repository && lhs.message == rhs.message
        }
    }

    /// Paths of repositories with a fetch or pull in progress.
    private(set) var busy: Set<String> = []
    /// Progress of "Fetch All", or `nil` when it isn't running.
    private(set) var fetchAllProgress: Progress?
    /// Failures from the most recent actions, cleared when the user dismisses them.
    var failures: [Failure] = []

    private let git: any GitServicing
    private let workspace: any WorkspaceOpening
    private let defaults: UserDefaults
    private let maxConcurrentFetches: Int
    private let logger = Logger(subsystem: "com.lquainta.RepoHub", category: "Actions")
    /// Called with the paths whose state changed, so statuses and details can refresh.
    var onRepositoriesChanged: @MainActor ([String]) async -> Void = { _ in }

    init(
        git: any GitServicing = GitService(),
        workspace: any WorkspaceOpening = SystemWorkspace(),
        defaults: UserDefaults = .standard,
        maxConcurrentFetches: Int = 4
    ) {
        self.git = git
        self.workspace = workspace
        self.defaults = defaults
        self.maxConcurrentFetches = max(1, maxConcurrentFetches)
    }

    /// Fetches every repository in `paths`, at most `maxConcurrentFetches` at a time.
    func fetchAll(_ paths: [String]) async {
        guard fetchAllProgress == nil, !paths.isEmpty else {
            return
        }
        fetchAllProgress = Progress(completed: 0, total: paths.count)
        defer { fetchAllProgress = nil }
        await run(paths, concurrency: maxConcurrentFetches) { git, url in
            try await git.fetch(url)
        } onEach: { [weak self] in
            self?.fetchAllProgress?.completed += 1
        }
    }

    /// Fetches the repositories in `paths`.
    func fetch(_ paths: [String]) async {
        await run(paths, concurrency: maxConcurrentFetches) { git, url in try await git.fetch(url) }
    }

    /// Fast-forwards the repositories in `paths` to their upstreams. Never merges.
    func pull(_ paths: [String]) async {
        await run(paths, concurrency: maxConcurrentFetches) { git, url in try await git.pull(url) }
    }

    /// Opens the repository in the preferred editor.
    func openInEditor(_ path: String) async {
        await open(path, bundleID: AppPreferences.editorBundleID(defaults))
    }

    /// Opens the repository in the preferred terminal.
    func openInTerminal(_ path: String) async {
        await open(path, bundleID: AppPreferences.terminalBundleID(defaults))
    }

    /// Shows the repository's folder in Finder.
    func revealInFinder(_ path: String) {
        workspace.revealInFinder(URL(fileURLWithPath: path, isDirectory: true))
    }

    /// Copies the URL of the `origin` remote (or the first remote) to the clipboard.
    func copyRemoteURL(_ path: String) async {
        if let remote = await preferredRemote(path) {
            workspace.copyToClipboard(remote.fetchURL)
        }
    }

    /// Opens the repository's page on github.com, if a remote points there.
    func openOnGitHub(_ path: String) async {
        guard let remote = await preferredRemote(path) else {
            return
        }
        guard let repository = GitHubRepository(remoteURL: remote.fetchURL) else {
            record(path, String(localized: "The remote \(remote.name) isn't on GitHub."))
            return
        }
        workspace.openInBrowser(repository.webURL)
    }

    // MARK: - Helpers

    private func run(
        _ paths: [String],
        concurrency: Int,
        operation: @escaping @Sendable (any GitServicing, URL) async throws -> Void,
        onEach: @escaping @MainActor () -> Void = {}
    ) async {
        let pending = paths.filter { !busy.contains($0) }
        guard !pending.isEmpty else {
            return
        }
        busy.formUnion(pending)
        defer { busy.subtract(pending) }

        let git = git
        await withTaskGroup(of: (String, String?).self) { group in
            var queue = pending[...]
            func startNext() {
                guard let path = queue.popFirst() else {
                    return
                }
                group.addTask {
                    do {
                        try await operation(git, URL(fileURLWithPath: path, isDirectory: true))
                        return (path, nil)
                    } catch let error as GitError {
                        return (path, Self.message(for: error))
                    } catch {
                        return (path, error.localizedDescription)
                    }
                }
            }
            for _ in 0..<concurrency {
                startNext()
            }
            for await (path, failure) in group {
                if let failure {
                    record(path, failure)
                }
                onEach()
                startNext()
            }
        }
        // Failed pulls may still have fetched, so refresh every repository that ran.
        await onRepositoriesChanged(pending)
    }

    private func open(_ path: String, bundleID: String) async {
        do {
            try await workspace.open(URL(fileURLWithPath: path, isDirectory: true), withApplication: bundleID)
        } catch {
            record(path, error.localizedDescription)
        }
    }

    private func preferredRemote(_ path: String) async -> Remote? {
        do {
            let remotes = try await git.remotes(of: URL(fileURLWithPath: path, isDirectory: true))
            guard let remote = remotes.first(where: { $0.name == "origin" }) ?? remotes.first else {
                record(path, String(localized: "This repository has no remotes."))
                return nil
            }
            return remote
        } catch let error as GitError {
            record(path, Self.message(for: error))
        } catch {
            record(path, error.localizedDescription)
        }
        return nil
    }

    private func record(_ path: String, _ message: String) {
        let name = URL(fileURLWithPath: path).lastPathComponent
        logger.error("Action on \(path, privacy: .private) failed: \(message, privacy: .public)")
        failures.append(Failure(repository: name, message: message))
    }

    nonisolated private static func message(for error: GitError) -> String {
        if case .commandFailed(let command, _, let stderr) = error, command.hasPrefix("git pull") {
            if stderr.contains("Not possible to fast-forward") || stderr.contains("diverged") {
                return String(localized: "The branch has diverged from its upstream. Merge or rebase it yourself.")
            }
            if stderr.contains("no tracking information") {
                return String(localized: "The current branch has no upstream to pull from.")
            }
        }
        return StatusText.message(for: error)
    }
}
