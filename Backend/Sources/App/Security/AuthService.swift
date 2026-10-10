import Fluent
import Foundation
import Logging

/// The user a request is authenticated as.
struct AuthenticatedUser: Equatable, Sendable {
    var userID: UUID
    var deviceID: UUID
}

/// A signed-in session for one device.
struct SessionResult: Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresIn: Int
    var user: User
}

/// Why an authentication request failed.
enum AuthError: Error, Equatable {
    /// Sign-in isn't configured on this server (no `GITHUB_CLIENT_ID`).
    case notConfigured
    /// The device code expired before the user approved it.
    case expired
    /// The user denied access on GitHub.
    case denied
    /// Missing, invalid, expired, revoked, or reused credentials.
    case unauthorized
}

/// Sign-in with GitHub's device flow, sessions, and sign-out (#49, #75).
struct AuthService: Sendable {
    /// Scopes requested from GitHub: `repo` to read pull requests and checks
    /// of private repositories (OAuth apps have no read-only private scope),
    /// and `read:user` for the profile.
    static let scopes = ["repo", "read:user"]

    let users: any UserStore
    let devices: any DeviceStore
    /// `nil` when `GITHUB_CLIENT_ID` isn't configured.
    let oauth: (any GitHubOAuth)?
    let tokens: SessionTokens
    let cipher: TokenCipher
    var logger = Logger(label: "com.lquainta.RepoHub.Auth")
    var now: @Sendable () -> Date = { .now }

    /// The outcome of polling for a session.
    enum PollResult: Sendable {
        case signedIn(SessionResult)
        case pending(interval: Int)
        case slowDown(interval: Int)
    }

    func startDeviceSignIn() async throws -> DeviceCode {
        guard let oauth else {
            throw AuthError.notConfigured
        }
        return try await oauth.requestDeviceCode(scopes: Self.scopes)
    }

    /// Polls GitHub once; on approval, stores the user and their encrypted
    /// GitHub token and starts a session for a new device named `deviceName`.
    func pollDeviceSignIn(deviceCode: String, deviceName: String) async throws -> PollResult {
        guard let oauth else {
            throw AuthError.notConfigured
        }
        switch try await oauth.pollToken(deviceCode: deviceCode) {
        case .pending:
            return .pending(interval: 5)
        case .slowDown(let interval):
            return .slowDown(interval: interval)
        case .expired:
            throw AuthError.expired
        case .denied:
            throw AuthError.denied
        case .approved(let githubToken, let scopes):
            let profile = try await oauth.user(token: githubToken)
            let user = try await users.upsert(profile, tokenCiphertext: try cipher.seal(githubToken), scopes: scopes)
            let refresh = SessionTokens.makeRefreshToken()
            let device = try await devices.create(
                userID: try user.requireID(),
                name: deviceName,
                refreshTokenHash: refresh.hash,
                expiresAt: now().addingTimeInterval(SessionTokens.refreshTokenLifetime)
            )
            logger.info(
                "Signed in",
                metadata: ["user": "\(profile.login)", "device": "\(device.id?.uuidString ?? "")"]
            )
            return .signedIn(
                try await session(for: user, deviceID: try device.requireID(), refreshToken: refresh.token)
            )
        }
    }

    /// Exchanges a refresh token for a new session. The old refresh token stops working.
    func refresh(refreshToken: String) async throws -> SessionResult {
        guard let device = try await devices.findActive(refreshTokenHash: SessionTokens.hash(refreshToken), now: now()),
            let user = try await users.find(id: device.$user.id)
        else {
            throw AuthError.unauthorized
        }
        let refresh = SessionTokens.makeRefreshToken()
        try await devices.rotate(
            device,
            refreshTokenHash: refresh.hash,
            expiresAt: now().addingTimeInterval(SessionTokens.refreshTokenLifetime),
            now: now()
        )
        return try await session(for: user, deviceID: try device.requireID(), refreshToken: refresh.token)
    }

    /// Revokes the device. When no signed-in devices remain, the stored GitHub token is erased.
    func signOut(_ user: AuthenticatedUser) async throws {
        try await devices.revoke(id: user.deviceID, now: now())
        let active = try await devices.devices(userID: user.userID).filter { $0.revokedAt == nil }
        if active.isEmpty {
            try await users.clearGitHubToken(userID: user.userID)
        }
        logger.info("Signed out", metadata: ["device": "\(user.deviceID)", "remaining_devices": "\(active.count)"])
    }

    /// Verifies an access token and that its device is still signed in.
    func authenticate(accessToken: String) async throws -> AuthenticatedUser? {
        guard let claims = await tokens.verify(accessToken),
            let device = try await devices.find(id: claims.deviceID),
            device.$user.id == claims.userID,
            device.revokedAt == nil
        else {
            return nil
        }
        return AuthenticatedUser(userID: claims.userID, deviceID: claims.deviceID)
    }

    /// The user's decrypted GitHub token, or `nil` if it was erased.
    func githubToken(for user: User) throws -> String? {
        user.githubTokenCiphertext.isEmpty ? nil : try cipher.open(user.githubTokenCiphertext)
    }

    private func session(for user: User, deviceID: UUID, refreshToken: String) async throws -> SessionResult {
        SessionResult(
            accessToken: try await tokens.accessToken(userID: try user.requireID(), deviceID: deviceID, now: now()),
            refreshToken: refreshToken,
            expiresIn: Int(SessionTokens.accessTokenLifetime),
            user: user
        )
    }
}
