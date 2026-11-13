import Foundation
import RepoHubAPIClient
import RepoHubCore

/// Why a backend call failed, in terms the app can act on.
enum APIError: Error, Equatable, LocalizedError {
    /// The session is invalid or expired, or was revoked.
    case unauthorized
    /// The sign-in code expired or the user denied access.
    case signInRejected(String)
    case rateLimited
    /// The backend or GitHub is unavailable or isn't configured.
    case unavailable(String)
    /// The backend returned something the spec doesn't describe.
    case unexpectedResponse(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            String(localized: "Your session has ended. Sign in again.")
        case .signInRejected(let reason):
            String(localized: "Sign-in didn't complete: \(reason)")
        case .rateLimited:
            String(localized: "Too many requests. Try again in a minute.")
        case .unavailable(let reason):
            String(localized: "The RepoHub server is unavailable: \(reason)")
        case .unexpectedResponse(let statusCode):
            String(localized: "The RepoHub server sent an unexpected response (HTTP \(statusCode)).")
        }
    }
}

/// The RepoHub backend. View models depend on this protocol so tests can use a fake.
protocol APIClienting: Sendable {
    func startDeviceSignIn() async throws -> DeviceAuthorization
    func pollDeviceSignIn(deviceCode: String, deviceName: String) async throws -> DeviceSignInPoll
    func refreshSession(refreshToken: String) async throws -> Session
    func signOut(accessToken: String) async throws
    func currentUser(accessToken: String) async throws -> UserProfile
    /// Pull requests and checks for up to 100 repositories, in request order.
    func repositoryStatuses(_ requests: [GitHubStatusRequest], accessToken: String) async throws
        -> [GitHubRepositoryStatus]
    /// The synced settings and the groups changed since `since` (all if `nil`).
    func workspace(since: Date?, accessToken: String) async throws -> SyncedWorkspace
    /// Stores settings (last write wins); returns what's stored.
    func updateSettings(_ settings: SyncedSettings, accessToken: String) async throws -> SyncedSettings
    /// Creates or updates a group (last write wins); returns what's stored,
    /// which may have another group's ID if one with the same name existed.
    func putGroup(_ group: SyncedGroup, accessToken: String) async throws -> SyncedGroup
    /// Deletes a group as of `deletedAt`.
    func deleteGroup(id: UUID, deletedAt: Date, accessToken: String) async throws
    /// Stores daily snapshots for the activity history.
    func uploadSnapshots(_ snapshots: [ActivitySnapshot], accessToken: String) async throws
    /// Activity for the last `days` days.
    func activity(days: Int, accessToken: String) async throws -> [RepositoryActivity]
    /// Repositories whose pull requests or checks just changed on GitHub,
    /// as they happen, until the server ends the stream.
    func repositoryChanges(accessToken: String) async throws -> AsyncThrowingStream<GitHubRepository, any Error>
}

/// ``APIClienting`` backed by the client generated from the OpenAPI spec.
struct RepoHubAPI: APIClienting {
    let baseURL: URL

    private func client(_ accessToken: String? = nil) -> Client {
        .repoHub(baseURL: baseURL, accessToken: accessToken)
    }

    func startDeviceSignIn() async throws -> DeviceAuthorization {
        switch try await client().startDeviceSignIn() {
        case .ok(let ok):
            let body = try ok.body.json
            guard let url = URL(string: body.verificationURI) else {
                throw APIError.unexpectedResponse(statusCode: 200)
            }
            return DeviceAuthorization(
                deviceCode: body.deviceCode,
                userCode: body.userCode,
                verificationURL: url,
                expiresIn: .seconds(body.expiresIn),
                interval: .seconds(body.interval)
            )
        case .tooManyRequests:
            throw APIError.rateLimited
        case .badGateway(let response):
            throw APIError.unavailable(Self.reason(try? response.body.json))
        case .serviceUnavailable(let response):
            throw APIError.unavailable(Self.reason(try? response.body.json))
        case .undocumented(let statusCode, _):
            throw APIError.unexpectedResponse(statusCode: statusCode)
        }
    }

    func pollDeviceSignIn(deviceCode: String, deviceName: String) async throws -> DeviceSignInPoll {
        let request = Components.Schemas.DeviceTokenRequest(deviceCode: deviceCode, deviceName: deviceName)
        switch try await client().pollDeviceSignIn(body: .json(request)) {
        case .ok(let ok):
            return .signedIn(Session(try ok.body.json))
        case .accepted(let accepted):
            return .pending(interval: .seconds(try accepted.body.json.interval))
        case .badRequest(let response):
            throw APIError.signInRejected(Self.reason(try? response.body.json))
        case .tooManyRequests:
            throw APIError.rateLimited
        case .badGateway(let response):
            throw APIError.unavailable(Self.reason(try? response.body.json))
        case .serviceUnavailable(let response):
            throw APIError.unavailable(Self.reason(try? response.body.json))
        case .undocumented(let statusCode, _):
            throw APIError.unexpectedResponse(statusCode: statusCode)
        }
    }

    func refreshSession(refreshToken: String) async throws -> Session {
        switch try await client().refreshSession(body: .json(.init(refreshToken: refreshToken))) {
        case .ok(let ok):
            return Session(try ok.body.json)
        case .unauthorized:
            throw APIError.unauthorized
        case .tooManyRequests:
            throw APIError.rateLimited
        case .undocumented(let statusCode, _):
            throw APIError.unexpectedResponse(statusCode: statusCode)
        }
    }

    func signOut(accessToken: String) async throws {
        switch try await client(accessToken).signOut() {
        case .noContent:
            return
        case .unauthorized:
            throw APIError.unauthorized
        case .tooManyRequests:
            throw APIError.rateLimited
        case .undocumented(let statusCode, _):
            throw APIError.unexpectedResponse(statusCode: statusCode)
        }
    }

    func currentUser(accessToken: String) async throws -> UserProfile {
        switch try await client(accessToken).getCurrentUser() {
        case .ok(let ok):
            return UserProfile(try ok.body.json)
        case .unauthorized:
            throw APIError.unauthorized
        case .tooManyRequests:
            throw APIError.rateLimited
        case .undocumented(let statusCode, _):
            throw APIError.unexpectedResponse(statusCode: statusCode)
        }
    }

    func repositoryStatuses(
        _ requests: [GitHubStatusRequest],
        accessToken: String
    ) async throws -> [GitHubRepositoryStatus] {
        let body = Components.Schemas.RepositoryStatusRequest(
            repositories: requests.map {
                .init(owner: $0.repository.owner, name: $0.repository.name, branch: $0.branch)
            }
        )
        switch try await client(accessToken).getRepositoryStatuses(body: .json(body)) {
        case .ok(let ok):
            return try ok.body.json.repositories.map(GitHubRepositoryStatus.init)
        case .badRequest(let response):
            throw APIError.unavailable(Self.reason(try? response.body.json))
        case .unauthorized:
            throw APIError.unauthorized
        case .tooManyRequests:
            throw APIError.rateLimited
        case .undocumented(let statusCode, _):
            throw APIError.unexpectedResponse(statusCode: statusCode)
        }
    }

    func workspace(since: Date?, accessToken: String) async throws -> SyncedWorkspace {
        switch try await client(accessToken).getWorkspace(query: .init(since: since)) {
        case .ok(let ok):
            let body = try ok.body.json
            return SyncedWorkspace(
                serverTime: body.serverTime,
                settings: SyncedSettings(body.settings),
                groups: body.groups.compactMap(SyncedGroup.init)
            )
        case .unauthorized:
            throw APIError.unauthorized
        case .tooManyRequests:
            throw APIError.rateLimited
        case .undocumented(let statusCode, _):
            throw APIError.unexpectedResponse(statusCode: statusCode)
        }
    }

    func updateSettings(_ settings: SyncedSettings, accessToken: String) async throws -> SyncedSettings {
        let body = Components.Schemas.SyncedSettings(
            staleBranchDays: settings.staleBranchDays,
            updatedAt: settings.updatedAt
        )
        switch try await client(accessToken).updateWorkspaceSettings(body: .json(body)) {
        case .ok(let ok):
            return SyncedSettings(try ok.body.json)
        case .unauthorized:
            throw APIError.unauthorized
        case .tooManyRequests:
            throw APIError.rateLimited
        case .undocumented(let statusCode, _):
            throw APIError.unexpectedResponse(statusCode: statusCode)
        }
    }

    func putGroup(_ group: SyncedGroup, accessToken: String) async throws -> SyncedGroup {
        let body = Components.Schemas.SyncedGroup(
            id: group.id.uuidString,
            name: group.name,
            sortOrder: group.sortOrder,
            members: group.members,
            updatedAt: group.updatedAt,
            deletedAt: group.deletedAt
        )
        switch try await client(accessToken).putGroup(path: .init(groupID: group.id.uuidString), body: .json(body)) {
        case .ok(let ok):
            guard let stored = SyncedGroup(try ok.body.json) else {
                throw APIError.unexpectedResponse(statusCode: 200)
            }
            return stored
        case .badRequest(let response):
            throw APIError.unavailable(Self.reason(try? response.body.json))
        case .unauthorized:
            throw APIError.unauthorized
        case .tooManyRequests:
            throw APIError.rateLimited
        case .undocumented(let statusCode, _):
            throw APIError.unexpectedResponse(statusCode: statusCode)
        }
    }

    func deleteGroup(id: UUID, deletedAt: Date, accessToken: String) async throws {
        let output = try await client(accessToken).deleteGroup(
            path: .init(groupID: id.uuidString),
            query: .init(deletedAt: deletedAt)
        )
        switch output {
        case .noContent:
            return
        case .unauthorized:
            throw APIError.unauthorized
        case .tooManyRequests:
            throw APIError.rateLimited
        case .undocumented(let statusCode, _):
            throw APIError.unexpectedResponse(statusCode: statusCode)
        }
    }

    func uploadSnapshots(_ snapshots: [ActivitySnapshot], accessToken: String) async throws {
        let body = Components.Schemas.SnapshotUpload(
            snapshots: snapshots.map {
                .init(
                    repository: $0.repository,
                    day: $0.day,
                    commits: $0.commits,
                    dirty: $0.capture?.dirty,
                    ahead: $0.capture?.ahead,
                    behind: $0.capture?.behind
                )
            }
        )
        switch try await client(accessToken).uploadSnapshots(body: .json(body)) {
        case .noContent:
            return
        case .badRequest(let response):
            throw APIError.unavailable(Self.reason(try? response.body.json))
        case .unauthorized:
            throw APIError.unauthorized
        case .tooManyRequests:
            throw APIError.rateLimited
        case .undocumented(let statusCode, _):
            throw APIError.unexpectedResponse(statusCode: statusCode)
        }
    }

    func activity(days: Int, accessToken: String) async throws -> [RepositoryActivity] {
        switch try await client(accessToken).getActivity(query: .init(days: days)) {
        case .ok(let ok):
            return try ok.body.json.repositories.map { repository in
                RepositoryActivity(
                    repository: repository.repository,
                    name: repository.name,
                    days: repository.days.map { .init(day: $0.day, commits: $0.commits, dirty: $0.dirty) }
                )
            }
        case .unauthorized:
            throw APIError.unauthorized
        case .tooManyRequests:
            throw APIError.rateLimited
        case .undocumented(let statusCode, _):
            throw APIError.unexpectedResponse(statusCode: statusCode)
        }
    }

    func repositoryChanges(accessToken: String) async throws -> AsyncThrowingStream<GitHubRepository, any Error> {
        let changes: AsyncThrowingStream<Components.Schemas.RepositoryChanged, any Error>
        switch try await client(accessToken).streamEvents() {
        case .ok(let ok):
            changes = try ok.repositoryChanges()
        case .unauthorized:
            throw APIError.unauthorized
        case .tooManyRequests:
            throw APIError.rateLimited
        case .undocumented(let statusCode, _):
            throw APIError.unexpectedResponse(statusCode: statusCode)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await change in changes {
                        continuation.yield(GitHubRepository(owner: change.owner, name: change.name))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func reason(_ error: Components.Schemas._Error?) -> String {
        error?.reason ?? String(localized: "no details")
    }
}

extension UserProfile {
    init(_ profile: Components.Schemas.UserProfile) {
        self.init(
            id: profile.id,
            login: profile.login,
            name: profile.name,
            avatarURL: profile.avatarURL.flatMap(URL.init(string:))
        )
    }
}

extension Session {
    init(_ session: Components.Schemas.Session) {
        self.init(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresIn: .seconds(session.expiresIn),
            user: UserProfile(session.user)
        )
    }
}

extension GitHubRepositoryStatus {
    init(_ status: Components.Schemas.RepositoryGitHubStatus) {
        self.init(
            repository: GitHubRepository(owner: status.owner, name: status.name),
            pullRequests: status.pullRequests.compactMap { pull in
                URL(string: pull.url).map { url in
                    PullRequest(
                        number: pull.number,
                        title: pull.title,
                        url: url,
                        author: pull.author,
                        isDraft: pull.isDraft,
                        headBranch: pull.headBranch,
                        reviewRequested: pull.reviewRequested
                    )
                }
            },
            checks: status.checks.flatMap { checks in
                URL(string: checks.url).map { url in
                    Checks(
                        state: CheckState(rawValue: checks.state.rawValue) ?? .pending,
                        total: checks.total,
                        failed: checks.failed,
                        pending: checks.pending,
                        url: url
                    )
                }
            },
            error: status.error?.rawValue
        )
    }
}

extension SyncedGroup {
    init?(_ group: Components.Schemas.SyncedGroup) {
        guard let id = UUID(uuidString: group.id) else {
            return nil
        }
        self.init(
            id: id,
            name: group.name,
            sortOrder: group.sortOrder,
            members: group.members,
            updatedAt: group.updatedAt,
            deletedAt: group.deletedAt
        )
    }
}

extension SyncedSettings {
    init(_ settings: Components.Schemas.SyncedSettings) {
        self.init(staleBranchDays: settings.staleBranchDays, updatedAt: settings.updatedAt)
    }
}
