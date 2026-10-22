import Foundation
import RepoHubCore
import Testing

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

    /// The stale branch report returned for every repository.
    var staleReport = StaleBranchReport(defaultBranch: "main", currentBranch: "main", candidates: [])
    /// Branch names whose deletion fails.
    private var undeletable: Set<String> = []
    /// A recorded `deleteBranches` call.
    struct Deletion {
        var names: [String]
        var force: Bool
        var deleteRemote: Bool
    }

    /// Every deletion request.
    private(set) var deletions: [Deletion] = []

    func setStaleReport(_ report: StaleBranchReport) {
        staleReport = report
    }

    func setUndeletable(_ names: Set<String>) {
        undeletable = names
    }

    func staleBranches(of repository: URL, inactiveAfterDays: Int?) async throws -> StaleBranchReport {
        staleReport
    }

    func deleteBranches(
        _ branches: [Branch],
        in repository: URL,
        force: Bool,
        deleteRemote: Bool
    ) async throws -> [BranchDeletionResult] {
        deletions.append(Deletion(names: branches.map(\.name), force: force, deleteRemote: deleteRemote))
        return branches.map { branch in
            undeletable.contains(branch.name)
                ? BranchDeletionResult(
                    name: branch.name,
                    error: .commandFailed(command: "git branch", exitCode: 1, stderr: "error: not fully merged")
                )
                : BranchDeletionResult(name: branch.name, deletedRemote: deleteRemote)
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

/// An `APIClienting` fake with scripted poll results that records every call.
actor FakeAPI: APIClienting {
    var authorization = DeviceAuthorization(
        deviceCode: "device",
        userCode: "WDJB-MJHT",
        verificationURL: URL(fileURLWithPath: "/login/device"),
        expiresIn: .seconds(900),
        interval: .seconds(5)
    )
    /// Returned (or thrown) by successive polls; the last one repeats.
    var polls: [Result<DeviceSignInPoll, APIError>] = []
    var refreshResult: Result<Session, APIError> = .success(.fixture(access: "refreshed", refresh: "r2"))
    var signOutError: APIError?
    /// Answers for ``repositoryStatuses(_:accessToken:)``, by repository; unknown ones are `notFound`.
    var gitHubStatuses: [GitHubRepository: GitHubRepositoryStatus] = [:]
    var gitHubError: APIError?
    /// Every batch requested.
    private(set) var statusBatches: [[GitHubStatusRequest]] = []
    private(set) var calls: [String] = []

    func setGitHubStatus(_ status: GitHubRepositoryStatus) {
        gitHubStatuses[status.repository] = status
    }

    func setGitHubError(_ error: APIError?) {
        gitHubError = error
    }

    func setPolls(_ polls: [Result<DeviceSignInPoll, APIError>]) {
        self.polls = polls
    }

    func setRefreshResult(_ result: Result<Session, APIError>) {
        refreshResult = result
    }

    func setSignOutError(_ error: APIError?) {
        signOutError = error
    }

    func startDeviceSignIn() async throws -> DeviceAuthorization {
        calls.append("start")
        return authorization
    }

    func pollDeviceSignIn(deviceCode: String, deviceName: String) async throws -> DeviceSignInPoll {
        calls.append("poll \(deviceCode) \(deviceName)")
        let next = polls.count > 1 ? polls.removeFirst() : polls[0]
        return try next.get()
    }

    func refreshSession(refreshToken: String) async throws -> Session {
        calls.append("refresh \(refreshToken)")
        try await Task.sleep(for: .milliseconds(10))
        return try refreshResult.get()
    }

    func signOut(accessToken: String) async throws {
        calls.append("signOut \(accessToken)")
        if let signOutError {
            throw signOutError
        }
    }

    func currentUser(accessToken: String) async throws -> UserProfile {
        calls.append("me \(accessToken)")
        return .octocat
    }

    /// The synced workspace, as an in-memory server with the backend's
    /// last-write-wins rules (`serverTime` advances one second per write).
    var serverGroups: [UUID: (group: SyncedGroup, syncedAt: Date)] = [:]
    var serverSettings = SyncedSettings(staleBranchDays: nil, updatedAt: .distantPast)
    var serverClock = Date(timeIntervalSince1970: 2_000_000_000)
    private(set) var syncLog: [String] = []

    func setServerSettings(_ settings: SyncedSettings) {
        serverSettings = settings
    }

    func workspace(since: Date?, accessToken: String) async throws -> SyncedWorkspace {
        syncLog.append("get")
        let groups = serverGroups.values
            .filter { since == nil || $0.syncedAt > since ?? .distantPast }
            .map(\.group)
            .sorted { $0.name < $1.name }
        return SyncedWorkspace(serverTime: serverClock, settings: serverSettings, groups: groups)
    }

    func updateSettings(_ settings: SyncedSettings, accessToken: String) async throws -> SyncedSettings {
        syncLog.append("settings \(settings.staleBranchDays ?? -1)")
        if settings.updatedAt > serverSettings.updatedAt {
            serverSettings = settings
        }
        return serverSettings
    }

    func putGroup(_ group: SyncedGroup, accessToken: String) async throws -> SyncedGroup {
        syncLog.append("put \(group.name)")
        let existing =
            serverGroups[group.id]?.group
            ?? serverGroups.values.map(\.group).first { $0.name.lowercased() == group.name.lowercased() }
        if let existing, group.updatedAt <= existing.updatedAt {
            return existing
        }
        var stored = group
        stored.id = existing?.id ?? group.id
        serverClock += 1
        serverGroups[stored.id] = (stored, serverClock)
        return stored
    }

    func deleteGroup(id: UUID, deletedAt: Date, accessToken: String) async throws {
        syncLog.append("delete \(id)")
        guard var group = serverGroups[id]?.group, group.deletedAt == nil, deletedAt > group.updatedAt else {
            return
        }
        group.deletedAt = deletedAt
        group.updatedAt = deletedAt
        serverClock += 1
        serverGroups[id] = (group, serverClock)
    }

    /// Live changes to send; the stream ends after the last one.
    var changes: [GitHubRepository] = []
    /// Errors to throw from successive `repositoryChanges` calls before streaming.
    var changeErrors: [APIError] = []
    private(set) var changeStreams = 0

    func setChanges(_ changes: [GitHubRepository], failingFirst errors: [APIError] = []) {
        self.changes = changes
        changeErrors = errors
    }

    func repositoryChanges(accessToken: String) async throws -> AsyncThrowingStream<GitHubRepository, any Error> {
        changeStreams += 1
        if !changeErrors.isEmpty {
            throw changeErrors.removeFirst()
        }
        let changes = changes
        self.changes = []
        return AsyncThrowingStream { continuation in
            for change in changes {
                continuation.yield(change)
            }
            continuation.finish()
        }
    }

    func repositoryStatuses(
        _ requests: [GitHubStatusRequest],
        accessToken: String
    ) async throws -> [GitHubRepositoryStatus] {
        calls.append("status \(accessToken)")
        statusBatches.append(requests)
        if let gitHubError {
            throw gitHubError
        }
        return requests.map {
            gitHubStatuses[$0.repository] ?? GitHubRepositoryStatus(repository: $0.repository, error: "notFound")
        }
    }
}

extension UserProfile {
    static let octocat = UserProfile(id: "1", login: "octocat", name: "The Octocat")
}

extension Session {
    static func fixture(access: String = "access", refresh: String = "refresh") -> Session {
        Session(accessToken: access, refreshToken: refresh, expiresIn: .seconds(900), user: .octocat)
    }
}

/// A clock the tests move forward by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000_000)

    func now() -> Date {
        lock.withLock { current }
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current += seconds }
    }
}
