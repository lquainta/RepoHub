import Foundation
import RepoHubAPIClient

/// A GitHub user, as the backend describes them.
struct UserProfile: Equatable, Sendable, Codable {
    var id: String
    var login: String
    var name: String?
    var avatarURL: URL?
}

/// A code for the user to enter on GitHub.
struct DeviceAuthorization: Equatable, Sendable {
    /// Sent back while polling; never shown.
    var deviceCode: String
    /// Shown to the user, for example `WDJB-MJHT`.
    var userCode: String
    var verificationURL: URL
    /// When the code stops working.
    var expiresIn: Duration
    /// The minimum time between polls.
    var interval: Duration
}

/// Tokens for one signed-in device.
struct Session: Equatable, Sendable {
    var accessToken: String
    /// Single-use; exchanged for a new session when the access token expires.
    var refreshToken: String
    var expiresIn: Duration
    var user: UserProfile
}

/// The result of one poll for a device sign-in.
enum DeviceSignInPoll: Equatable, Sendable {
    /// The user hasn't approved yet; poll again after `interval`.
    case pending(interval: Duration)
    case signedIn(Session)
}

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
