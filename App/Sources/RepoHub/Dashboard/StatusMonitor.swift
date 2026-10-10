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

/// Reads and caches the git status of tracked repositories.
@MainActor
@Observable
final class StatusMonitor {
    /// The latest known state per repository path. A path with no entry hasn't been read yet.
    private(set) var states: [String: RepositoryStatusState] = [:]
    /// Paths whose status is being read right now.
    private(set) var refreshing: Set<String> = []

    private let git: any GitServicing
    private let maxConcurrentReads: Int
    private let logger = Logger(subsystem: "com.lquainta.RepoHub", category: "Status")

    /// Creates a monitor.
    ///
    /// - Parameters:
    ///   - git: Reads repository status.
    ///   - maxConcurrentReads: How many `git status` commands may run at once.
    init(git: any GitServicing = GitService(), maxConcurrentReads: Int = 8) {
        self.git = git
        self.maxConcurrentReads = max(1, maxConcurrentReads)
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
        await withTaskGroup(of: (String, RepositoryStatusState).self) { group in
            var queue = pending[...]
            func startNext() {
                guard let path = queue.popFirst() else {
                    return
                }
                group.addTask {
                    await (path, Self.read(path, with: git))
                }
            }
            for _ in 0..<maxConcurrentReads {
                startNext()
            }
            for await (path, state) in group {
                states[path] = state
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
