import Foundation
import OSLog
import Observation
import RepoHubCore

/// Loads the details of the selected repository.
@MainActor
@Observable
final class RepositoryDetailModel {
    /// What the detail pane shows.
    enum State: Equatable {
        /// No repository is selected.
        case empty
        /// Details are being read for the first time.
        case loading
        /// Details were read.
        case loaded(RepositoryDetails)
        /// Reading failed; the message is user-facing.
        case failed(String)
    }

    /// The repository being shown, if any.
    private(set) var path: String?
    /// What the pane shows. While reloading, the previous details stay visible.
    private(set) var state: State = .empty

    private let git: any GitServicing
    private let logger = Logger(subsystem: "com.lquainta.RepoHub", category: "Detail")
    /// Identifies the latest load so a slow earlier load can't overwrite it.
    private var generation = 0

    init(git: any GitServicing = GitService()) {
        self.git = git
    }

    /// Shows the repository at `path`, or nothing if `path` is `nil`.
    func show(_ path: String?) async {
        guard path != self.path else {
            return
        }
        self.path = path
        state = path == nil ? .empty : .loading
        await reload()
    }

    /// Reads the shown repository's details again.
    func reload() async {
        guard let path else {
            return
        }
        generation += 1
        let current = generation
        let result: State
        do {
            result = .loaded(try await git.details(of: URL(fileURLWithPath: path, isDirectory: true)))
        } catch let error as GitError {
            logger.error("Details of \(path, privacy: .private) failed: \(String(describing: error), privacy: .public)")
            result = .failed(StatusText.message(for: error))
        } catch is CancellationError {
            return
        } catch {
            result = .failed(error.localizedDescription)
        }
        // Ignore results for a repository that's no longer shown, or superseded by a newer load.
        if current == generation && path == self.path {
            state = result
        }
    }
}
