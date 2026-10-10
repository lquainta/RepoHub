import Foundation
import Vapor

/// GitHub's OAuth device flow, run by the backend so the GitHub token never
/// reaches the app. ``VaporGitHubOAuth`` is the real implementation; tests use fakes.
protocol GitHubOAuth: Sendable {
    /// Starts the flow: a code for the user and a URL to enter it at.
    func requestDeviceCode(scopes: [String]) async throws -> DeviceCode
    /// Asks whether the user approved the device code yet.
    func pollToken(deviceCode: String) async throws -> DeviceTokenResult
    /// The profile of the user who owns `token`.
    func user(token: String) async throws -> GitHubProfile
}

/// GitHub's response to starting the device flow.
struct DeviceCode: Equatable, Sendable {
    var deviceCode: String
    var userCode: String
    var verificationURI: String
    var expiresIn: Int
    var interval: Int
}

/// The outcome of one poll.
enum DeviceTokenResult: Equatable, Sendable {
    case approved(token: String, scopes: String)
    case pending
    /// Polling too fast; wait at least `interval` seconds.
    case slowDown(interval: Int)
    case expired
    case denied
}

/// An unexpected failure talking to GitHub's OAuth endpoints.
struct GitHubOAuthError: Error, Equatable {
    var reason: String
}

/// Calls `github.com/login/device/code`, `github.com/login/oauth/access_token`, and `api.github.com/user`.
struct VaporGitHubOAuth: GitHubOAuth {
    let client: any Client
    let clientID: String
    var webBaseURL = "https://github.com"
    var apiBaseURL = "https://api.github.com"

    // GitHub's snake_case fields, decoded with `snakeCase`.
    private struct DeviceCodeResponse: Decodable {
        let deviceCode: String
        let userCode: String
        let verificationUri: String
        let expiresIn: Int
        let interval: Int
    }

    private struct TokenResponse: Decodable {
        let accessToken: String?
        let scope: String?
        let error: String?
        let interval: Int?
    }

    private struct UserResponse: Decodable {
        let id: Int64
        let login: String
        let name: String?
        let avatarUrl: String?
    }

    private static let snakeCase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func requestDeviceCode(scopes: [String]) async throws -> DeviceCode {
        let response = try await client.post(URI(string: webBaseURL + "/login/device/code"), headers: jsonHeaders) {
            try $0.content.encode(["client_id": clientID, "scope": scopes.joined(separator: " ")], as: .urlEncodedForm)
        }
        guard response.status == .ok else {
            throw GitHubOAuthError(reason: "Device code request failed with \(response.status.code)")
        }
        let body = try response.content.decode(DeviceCodeResponse.self, using: Self.snakeCase)
        return DeviceCode(
            deviceCode: body.deviceCode,
            userCode: body.userCode,
            verificationURI: body.verificationUri,
            expiresIn: body.expiresIn,
            interval: body.interval
        )
    }

    func pollToken(deviceCode: String) async throws -> DeviceTokenResult {
        let response = try await client.post(
            URI(string: webBaseURL + "/login/oauth/access_token"),
            headers: jsonHeaders
        ) {
            try $0.content.encode(
                [
                    "client_id": clientID,
                    "device_code": deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                ],
                as: .urlEncodedForm
            )
        }
        guard response.status == .ok else {
            throw GitHubOAuthError(reason: "Token request failed with \(response.status.code)")
        }
        let body = try response.content.decode(TokenResponse.self, using: Self.snakeCase)
        if let token = body.accessToken {
            return .approved(token: token, scopes: body.scope ?? "")
        }
        switch body.error {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown(interval: body.interval ?? 10)
        case "expired_token": return .expired
        case "access_denied": return .denied
        default: throw GitHubOAuthError(reason: "Unexpected device flow error: \(body.error ?? "none")")
        }
    }

    func user(token: String) async throws -> GitHubProfile {
        var headers = jsonHeaders
        headers.bearerAuthorization = BearerAuthorization(token: token)
        headers.replaceOrAdd(name: "X-GitHub-Api-Version", value: "2022-11-28")
        let response = try await client.get(URI(string: apiBaseURL + "/user"), headers: headers)
        guard response.status == .ok else {
            throw GitHubOAuthError(reason: "User request failed with \(response.status.code)")
        }
        let body = try response.content.decode(UserResponse.self, using: Self.snakeCase)
        return GitHubProfile(id: body.id, login: body.login, name: body.name, avatarURL: body.avatarUrl)
    }

    private var jsonHeaders: HTTPHeaders {
        ["Accept": "application/json", "User-Agent": "RepoHub"]
    }
}
