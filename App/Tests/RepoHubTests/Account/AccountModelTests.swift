import Foundation
import Testing

@testable import RepoHub

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
    private(set) var calls: [String] = []

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

@MainActor
@Suite("Account")
struct AccountModelTests {
    let api = FakeAPI()
    let store = InMemoryCredentialStore()
    let workspace = FakeWorkspace()
    let clock = TestClock()
    /// Every sleep requested while polling.
    let sleeps = SleepRecorder()

    final class SleepRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var durations: [Duration] = []
        var all: [Duration] { lock.withLock { durations } }
        func record(_ duration: Duration) { lock.withLock { durations.append(duration) } }
    }

    func makeModel() -> AccountModel {
        AccountModel(
            api: api,
            credentials: store,
            workspace: workspace,
            deviceName: "Test Mac",
            sleep: { [sleeps] in sleeps.record($0) },
            now: { [clock] in clock.now() }
        )
    }

    @Test("Sign-in shows the code, opens GitHub, polls at the server's interval, and stores the session")
    func signIn() async throws {
        await api.setPolls([
            .success(.pending(interval: .seconds(5))),
            .success(.pending(interval: .seconds(10))),
            .success(.signedIn(.fixture())),
        ])
        let model = makeModel()

        model.signIn()
        await model.waitForSignIn()

        #expect(model.state == .signedIn(.octocat))
        #expect(workspace.browsed == [URL(fileURLWithPath: "/login/device")])
        #expect(workspace.clipboard == "WDJB-MJHT")
        #expect(sleeps.all == [.seconds(5), .seconds(5), .seconds(10)])
        #expect(await api.calls.filter { $0.hasPrefix("poll") }.count == 3)
        #expect(await api.calls.contains("poll device Test Mac"))
        #expect(try store.load() == StoredCredentials(refreshToken: "refresh", user: .octocat))
        #expect(try await model.accessToken() == "access")
    }

    @Test("A denied or expired code signs out with the server's reason")
    func signInRejected() async throws {
        await api.setPolls([.failure(.signInRejected("The code expired."))])
        let model = makeModel()

        model.signIn()
        await model.waitForSignIn()

        #expect(model.state == .signedOut)
        #expect(model.errorMessage?.contains("The code expired.") == true)
        #expect(try store.load() == nil)
    }

    @Test("Cancelling stops polling and returns to signed out")
    func cancelSignIn() async throws {
        await api.setPolls([.success(.pending(interval: .seconds(5)))])
        let model = AccountModel(
            api: api,
            credentials: store,
            workspace: workspace,
            sleep: { _ in try await Task.sleep(for: .milliseconds(5)) }
        )

        model.signIn()
        while case .signedOut = model.state {
            await Task.yield()
        }
        model.cancelSignIn()

        #expect(model.state == .signedOut)
        #expect(model.errorMessage == nil)
    }

    @Test("Relaunching restores the session from the Keychain and refreshes it")
    func restore() async throws {
        try store.save(StoredCredentials(refreshToken: "saved", user: .octocat))
        let model = makeModel()

        await model.restore()

        #expect(model.state == .signedIn(.octocat))
        #expect(await api.calls == ["refresh saved"])
        // The single-use refresh token was replaced by the new one.
        #expect(try store.load()?.refreshToken == "r2")
        #expect(try await model.accessToken() == "refreshed")
    }

    @Test("Restoring with nothing stored stays signed out without calling the server")
    func restoreNothing() async {
        let model = makeModel()

        await model.restore()

        #expect(model.state == .signedOut)
        #expect(await api.calls.isEmpty)
    }

    @Test("A revoked session is forgotten at launch")
    func restoreRevoked() async throws {
        try store.save(StoredCredentials(refreshToken: "revoked", user: .octocat))
        await api.setRefreshResult(.failure(.unauthorized))
        let model = makeModel()

        await model.restore()

        #expect(model.state == .signedOut)
        #expect(try store.load() == nil)
    }

    @Test("Offline at launch keeps the user signed in and retries on the next request")
    func restoreOffline() async throws {
        try store.save(StoredCredentials(refreshToken: "saved", user: .octocat))
        await api.setRefreshResult(.failure(.unavailable("offline")))
        let model = makeModel()

        await model.restore()
        #expect(model.state == .signedIn(.octocat))

        await api.setRefreshResult(.success(.fixture(access: "later", refresh: "r3")))
        #expect(try await model.accessToken() == "later")
        #expect(try store.load()?.refreshToken == "r3")
    }

    @Test("An expiring access token is refreshed once, even for concurrent requests")
    func refreshOnce() async throws {
        await api.setPolls([.success(.signedIn(.fixture()))])
        let model = makeModel()
        model.signIn()
        await model.waitForSignIn()

        clock.advance(by: 890)
        async let first = model.accessToken()
        async let second = model.accessToken()
        let tokens = try await [first, second]

        #expect(tokens == ["refreshed", "refreshed"])
        #expect(await api.calls.filter { $0.hasPrefix("refresh") } == ["refresh refresh"])
    }

    @Test("Sign-out revokes the session on the server and deletes it from the Keychain")
    func signOut() async throws {
        await api.setPolls([.success(.signedIn(.fixture()))])
        let model = makeModel()
        model.signIn()
        await model.waitForSignIn()

        await model.signOut()

        #expect(model.state == .signedOut)
        #expect(await api.calls.last == "signOut access")
        #expect(try store.load() == nil)
        #expect(model.errorMessage == nil)
        await #expect(throws: APIError.unauthorized) { try await model.accessToken() }
    }

    @Test("Sign-out still forgets the session locally when the server can't be reached")
    func signOutOffline() async throws {
        await api.setPolls([.success(.signedIn(.fixture()))])
        await api.setSignOutError(.unavailable("offline"))
        let model = makeModel()
        model.signIn()
        await model.waitForSignIn()

        await model.signOut()

        #expect(model.state == .signedOut)
        #expect(try store.load() == nil)
        #expect(model.errorMessage?.contains("Signed out on this Mac") == true)
    }
}
