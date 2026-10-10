import Foundation
import OSLog
import Observation
import RepoHubCore

/// What's known about a repository's git status.
enum RepositoryStatusState: Equatable {
    /// The status has been read successfully.
    case loaded(RepoStatus)
    /// Reading the status failed; the message is user-facing.
    case failed(String)
}

/// Facts used by the quick filters that `git status` doesn't report.
struct RepositoryFacts: Equatable {
    /// Configured remotes.
    var remoteCount: Int
    /// Local branches suggested for cleanup (see ``StaleBranchDetector``).
    var staleBranchCount: Int
}

/// Reads and caches the git status of tracked repositories.
@MainActor
@Observable
final class StatusMonitor {
    /// The latest known state per repository path. A path with no entry hasn't been read yet.
    private(set) var states: [String: RepositoryStatusState] = [:]
    /// Paths whose status is being read right now.
    private(set) var refreshing: Set<String> = []
    /// Remote and stale-branch counts per path, read along with the status.
    private(set) var facts: [String: RepositoryFacts] = [:]

    private let git: any GitServicing
    private let maxConcurrentReads: Int
    private let staleBranchDays: @Sendable () -> Int?
    private let logger = Logger(subsystem: "com.lquainta.RepoHub", category: "Status")

    /// Creates a monitor.
    ///
    /// - Parameters:
    ///   - git: Reads repository status.
    ///   - maxConcurrentReads: How many repositories may be read at once.
    ///   - staleBranchDays: The inactivity threshold for counting stale branches.
    init(
        git: any GitServicing = GitService(),
        maxConcurrentReads: Int = 8,
        staleBranchDays: @escaping @Sendable () -> Int? = { AppPreferences.staleBranchDays() }
    ) {
        self.git = git
        self.maxConcurrentReads = max(1, maxConcurrentReads)
        self.staleBranchDays = staleBranchDays
    }

    /// The state for `path`, or `nil` if it hasn't been read yet.
    func state(for path: String) -> RepositoryStatusState? {
        states[path]
    }

    /// Reads the status of every repository in `paths`, at most
    /// `maxConcurrentReads` at a time. Previous results stay visible until
    /// they're replaced.
    func refresh(_ paths: [String]) async {
        let pending = paths.filter { !refreshing.contains($0) }
        guard !pending.isEmpty else {
            return
        }
        refreshing.formUnion(pending)

        let git = git
        let days = staleBranchDays()
        await withTaskGroup(of: (String, RepositoryStatusState, RepositoryFacts?).self) { group in
            var queue = pending[...]
            func startNext() {
                guard let path = queue.popFirst() else {
                    return
                }
                group.addTask {
                    async let state = Self.read(path, with: git)
                    async let facts = Self.readFacts(path, with: git, staleBranchDays: days)
                    return await (path, state, facts)
                }
            }
            for _ in 0..<maxConcurrentReads {
                startNext()
            }
            for await (path, state, facts) in group {
                states[path] = state
                self.facts[path] = facts
                refreshing.remove(path)
                if case .failed(let message) = state {
                    logger.error("Status of \(path, privacy: .private) failed: \(message, privacy: .public)")
                }
                startNext()
            }
        }
        // Anything not reached (cancellation) is no longer refreshing.
        refreshing.subtract(pending)
    }

    /// Drops cached states for repositories that are no longer tracked.
    func retain(only paths: Set<String>) {
        states = states.filter { paths.contains($0.key) }
        facts = facts.filter { paths.contains($0.key) }
    }

    /// Reads remote and stale-branch counts; `nil` if either can't be read.
    nonisolated private static func readFacts(
        _ path: String,
        with git: any GitServicing,
        staleBranchDays: Int?
    ) async -> RepositoryFacts? {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        async let remotes = git.remotes(of: url)
        async let stale = git.staleBranches(of: url, inactiveAfterDays: staleBranchDays)
        guard let remotes = try? await remotes, let stale = try? await stale else {
            return nil
        }
        return RepositoryFacts(remoteCount: remotes.count, staleBranchCount: stale.candidates.count)
    }

    nonisolated private static func read(_ path: String, with git: any GitServicing) async -> RepositoryStatusState {
        do {
            return .loaded(try await git.status(of: URL(fileURLWithPath: path, isDirectory: true)))
        } catch let error as GitError {
            return .failed(StatusText.message(for: error))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
