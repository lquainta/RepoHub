import Foundation
import OSLog
import Observation
import RepoHubCore

/// Pull request and CI status from the backend for the repositories that have
/// a GitHub remote. Empty while signed out.
@MainActor
@Observable
final class GitHubStatusModel {
    /// The latest status per repository and branch. Worktrees of one
    /// repository on different branches have different checks.
    private(set) var statuses: [GitHubStatusRequest: GitHubRepositoryStatus] = [:]
    /// When ``statuses`` were last updated.
    private(set) var lastUpdated: Date?
    /// A user-facing description of the most recent failure, if any.
    private(set) var errorMessage: String?
    /// Called after every successful refresh with the previous and new statuses
    /// (for notifications, #79).
    var onUpdate: (@MainActor (_ old: Statuses, _ new: Statuses) -> Void)?

    typealias Statuses = [GitHubStatusRequest: GitHubRepositoryStatus]

    /// The most repositories the backend accepts per request.
    static let batchSize = 100

    private let account: AccountModel
    private let api: any APIClienting
    private let interval: Duration
    private let logger = Logger(subsystem: "com.lquainta.RepoHub", category: "GitHub")
    private var pollTask: Task<Void, Never>?

    /// Creates a model that asks `api` with `account`'s session.
    ///
    /// - Parameters:
    ///   - account: Supplies the access token; signed out, nothing is requested.
    ///   - api: The backend.
    ///   - interval: Time between refreshes while polling. The backend caches
    ///     pull requests for 60 seconds, so polling faster gains nothing.
    init(account: AccountModel, api: any APIClienting, interval: Duration = .seconds(60)) {
        self.account = account
        self.api = api
        self.interval = interval
    }

    /// The status of `repository` with checks for `branch`, if known.
    func status(for repository: GitHubRepository, branch: String?) -> GitHubRepositoryStatus? {
        statuses[GitHubStatusRequest(repository: repository, branch: branch)]
    }

    /// Refreshes now and then every `interval`, asking `requests` each time
    /// which repositories to include.
    func startPolling(_ requests: @escaping @MainActor () -> [GitHubStatusRequest]) {
        pollTask?.cancel()
        pollTask = Task { [weak self, interval] in
            while !Task.isCancelled {
                await self?.refresh(requests())
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Asks the backend about `requests`, in batches of ``batchSize``. Signed
    /// out, it clears everything instead.
    func refresh(_ requests: [GitHubStatusRequest]) async {
        guard account.user != nil else {
            statuses = [:]
            lastUpdated = nil
            return
        }
        let unique = Array(Set(requests))
        guard !unique.isEmpty else {
            statuses = [:]
            return
        }
        do {
            let token = try await account.accessToken()
            var updated: Statuses = [:]
            for start in stride(from: 0, to: unique.count, by: Self.batchSize) {
                let batch = Array(unique[start..<min(start + Self.batchSize, unique.count)])
                // Results come back in request order.
                let results = try await api.repositoryStatuses(batch, accessToken: token)
                for (request, status) in zip(batch, results) {
                    updated[request] = status
                }
            }
            let old = statuses
            statuses = updated
            lastUpdated = .now
            errorMessage = nil
            onUpdate?(old, updated)
        } catch APIError.unauthorized {
            statuses = [:]
        } catch {
            // Keep showing the last known statuses.
            logger.error("GitHub status refresh failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
