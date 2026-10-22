import Foundation
import OSLog
import Observation

/// Signing in to GitHub through the backend's device flow, and the session
/// that other features use to call the backend.
@MainActor
@Observable
final class AccountModel {
    enum State: Equatable {
        case signedOut
        /// Waiting for the user to enter `userCode` at `verificationURL`.
        case awaitingApproval(userCode: String, verificationURL: URL)
        case signedIn(UserProfile)
    }

    private(set) var state: State = .signedOut
    /// A user-facing description of the most recent failure, if any.
    var errorMessage: String?

    /// The signed-in user, if any.
    var user: UserProfile? {
        if case .signedIn(let user) = state {
            return user
        }
        return nil
    }

    private let api: any APIClienting
    private let credentials: any CredentialStoring
    private let workspace: any WorkspaceOpening
    private let deviceName: String
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: "com.lquainta.RepoHub", category: "Account")

    /// The current access token and when it expires; `nil` until a session is
    /// created or refreshed in this launch.
    private var session: (accessToken: String, expires: Date)?
    /// The refresh token from the Keychain or the latest session.
    private var refreshToken: String?
    private var signInTask: Task<Void, Never>?
    /// Whether ``restore()`` has run.
    private var hasRestored = false
    /// A refresh in progress, shared by concurrent callers so the single-use
    /// refresh token is only spent once.
    private var refreshTask: Task<String, any Error>?

    init(
        api: any APIClienting,
        credentials: any CredentialStoring = KeychainCredentialStore(),
        workspace: any WorkspaceOpening = SystemWorkspace(),
        deviceName: String = Host.current().localizedName ?? "Mac",
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.api = api
        self.credentials = credentials
        self.workspace = workspace
        self.deviceName = deviceName
        self.sleep = sleep
        self.now = now
    }

    /// Restores the session saved by an earlier launch, once, from whichever
    /// scene appears first. If the server can't be reached, the user stays
    /// signed in and the session is refreshed on the next request; if the
    /// server rejects it, the user is signed out.
    func restore() async {
        guard !hasRestored else {
            return
        }
        hasRestored = true
        let stored: StoredCredentials?
        do {
            stored = try credentials.load()
        } catch {
            logger.error("Could not read credentials: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return
        }
        guard let stored else {
            state = .signedOut
            return
        }
        refreshToken = stored.refreshToken
        state = .signedIn(stored.user)
        do {
            _ = try await accessToken()
        } catch APIError.unauthorized {
            // `accessToken()` already signed out locally.
        } catch {
            logger.info("Session not refreshed at launch: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Starts the device flow: shows a code, opens GitHub, and polls until
    /// the user approves, denies, or the code expires.
    func signIn() {
        guard signInTask == nil else {
            return
        }
        errorMessage = nil
        signInTask = Task { [weak self] in
            await self?.runSignIn()
            self?.signInTask = nil
        }
    }

    /// Stops waiting for approval.
    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        if case .awaitingApproval = state {
            state = .signedOut
        }
    }

    /// Waits for a sign-in started with ``signIn()`` to finish.
    func waitForSignIn() async {
        await signInTask?.value
    }

    /// Revokes this device's session on the server and forgets it locally.
    /// The local credentials are removed even if the server can't be reached.
    func signOut() async {
        cancelSignIn()
        var revocationError: (any Error)?
        if let token = try? await accessToken() {
            do {
                try await api.signOut(accessToken: token)
            } catch APIError.unauthorized {
                // Already revoked.
            } catch {
                revocationError = error
            }
        }
        forgetSession()
        if let revocationError {
            let reason = revocationError.localizedDescription
            logger.error("Sign-out not confirmed by server: \(reason, privacy: .public)")
            errorMessage = String(
                localized: "Signed out on this Mac, but the server couldn't be reached to revoke the session: \(reason)"
            )
        }
    }

    /// A valid access token, refreshed if it has expired or is about to.
    /// Throws ``APIError/unauthorized`` (and signs out) if the session was revoked.
    func accessToken() async throws -> String {
        if let session, session.expires.timeIntervalSince(now()) > 30 {
            return session.accessToken
        }
        if let refreshTask {
            return try await refreshTask.value
        }
        guard let refreshToken else {
            throw APIError.unauthorized
        }
        let task = Task { [api] in
            try await api.refreshSession(refreshToken: refreshToken)
        }
        let refresh = Task<String, any Error> { [weak self] in
            do {
                let session = try await task.value
                try self?.adopt(session)
                return session.accessToken
            } catch APIError.unauthorized {
                self?.forgetSession()
                self?.errorMessage = APIError.unauthorized.localizedDescription
                throw APIError.unauthorized
            }
        }
        refreshTask = refresh
        defer { refreshTask = nil }
        return try await refresh.value
    }

    private func runSignIn() async {
        do {
            let authorization = try await api.startDeviceSignIn()
            state = .awaitingApproval(userCode: authorization.userCode, verificationURL: authorization.verificationURL)
            workspace.copyToClipboard(authorization.userCode)
            workspace.openInBrowser(authorization.verificationURL)
            var interval = authorization.interval
            while true {
                try await sleep(interval)
                try Task.checkCancellation()
                switch try await api.pollDeviceSignIn(deviceCode: authorization.deviceCode, deviceName: deviceName) {
                case .pending(let next):
                    interval = next
                case .signedIn(let session):
                    try adopt(session)
                    return
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            logger.error("Sign-in failed: \(error.localizedDescription, privacy: .public)")
            state = .signedOut
            errorMessage = error.localizedDescription
        }
    }

    /// Uses `session` from now on and saves its refresh token.
    private func adopt(_ session: Session) throws {
        let lifetime = TimeInterval(session.expiresIn.components.seconds)
        self.session = (session.accessToken, now().addingTimeInterval(lifetime))
        refreshToken = session.refreshToken
        state = .signedIn(session.user)
        try credentials.save(StoredCredentials(refreshToken: session.refreshToken, user: session.user))
    }

    private func forgetSession() {
        session = nil
        refreshToken = nil
        state = .signedOut
        do {
            try credentials.delete()
        } catch {
            logger.error("Could not delete credentials: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
