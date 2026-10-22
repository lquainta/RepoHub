import Foundation
import RepoHubCore

/// A canned backend for UI tests (`REPOHUB_UI_TEST_STUB_BACKEND=1`): sign-in
/// shows the code `TEST-CODE` and is approved on the first poll, as `octocat`.
/// Everything else is empty. Never used outside UI tests.
struct UITestBackend: APIClienting {
    static let user = UserProfile(id: "00000000-0000-0000-0000-000000000001", login: "octocat", name: "The Octocat")

    private var session: Session {
        Session(
            accessToken: "ui-test-access",
            refreshToken: "ui-test-refresh",
            expiresIn: .seconds(900),
            user: Self.user
        )
    }

    func startDeviceSignIn() async throws -> DeviceAuthorization {
        DeviceAuthorization(
            deviceCode: "ui-test-device",
            userCode: "TEST-CODE",
            verificationURL: URL(fileURLWithPath: "/dev/null"),
            expiresIn: .seconds(900),
            interval: .seconds(1)
        )
    }

    func pollDeviceSignIn(deviceCode: String, deviceName: String) async throws -> DeviceSignInPoll {
        .signedIn(session)
    }

    func refreshSession(refreshToken: String) async throws -> Session { session }
    func signOut(accessToken: String) async throws {}
    func currentUser(accessToken: String) async throws -> UserProfile { Self.user }

    func repositoryStatuses(_ requests: [GitHubStatusRequest], accessToken: String) async throws
        -> [GitHubRepositoryStatus]
    {
        requests.map { GitHubRepositoryStatus(repository: $0.repository) }
    }

    func workspace(since: Date?, accessToken: String) async throws -> SyncedWorkspace {
        SyncedWorkspace(
            serverTime: .now,
            settings: SyncedSettings(staleBranchDays: nil, updatedAt: .distantPast),
            groups: []
        )
    }

    func updateSettings(_ settings: SyncedSettings, accessToken: String) async throws -> SyncedSettings { settings }
    func putGroup(_ group: SyncedGroup, accessToken: String) async throws -> SyncedGroup { group }
    func deleteGroup(id: UUID, deletedAt: Date, accessToken: String) async throws {}
    func uploadSnapshots(_ snapshots: [ActivitySnapshot], accessToken: String) async throws {}
    func activity(days: Int, accessToken: String) async throws -> [RepositoryActivity] { [] }

    func repositoryChanges(accessToken: String) async throws -> AsyncThrowingStream<GitHubRepository, any Error> {
        AsyncThrowingStream { _ in }
    }
}

/// Opens nothing: UI tests must not launch a browser or other apps.
@MainActor
struct UITestWorkspace: WorkspaceOpening {
    func open(_ folder: URL, withApplication bundleID: String) async throws {}
    func revealInFinder(_ url: URL) {}
    func openInBrowser(_ url: URL) {}
    func copyToClipboard(_ string: String) {}
}
