import Fluent
import Foundation
import OpenAPIRuntime
import RepoHubAPI
import RepoHubCore
import Vapor

/// Implements the operations in openapi/openapi.yaml.
///
/// The protocol is generated from the spec, so an operation added to the spec
/// fails to compile until it's implemented here, and a handler can't return
/// a response the spec doesn't allow. Authentication happens before these
/// run (``AuthenticationMiddleware``); protected operations read the user
/// from ``RequestContext/user``.
struct APIHandler: APIProtocol {
    let app: Application

    private var auth: AuthService { app.authService(on: app.db) }
    private var logger: Logger { app.contextLogger }

    // MARK: - Health

    func getHealth(_ input: Operations.getHealth.Input) async throws -> Operations.getHealth.Output {
        .ok(.init(body: .json(.init(status: .ok, version: RepoHubCore.version, commit: app.config.buildCommit))))
    }

    func getReadiness(_ input: Operations.getReadiness.Input) async throws -> Operations.getReadiness.Output {
        let results = await app.readinessChecker.check()
        func component(_ result: ReadinessChecker.Result) -> Components.Schemas.DependencyCheck {
            .init(
                status: result.isUp ? .up : .down,
                latencyMs: result.latencyMilliseconds,
                error: result.error
            )
        }
        let body = Components.Schemas.Readiness(
            status: results.database.isUp && results.cache.isUp ? .ready : .unavailable,
            checks: .init(database: component(results.database), cache: component(results.cache))
        )
        guard body.status == .ready else {
            logger.warning(
                "Not ready",
                metadata: ["database": "\(results.database.error ?? "up")", "cache": "\(results.cache.error ?? "up")"]
            )
            return .serviceUnavailable(.init(body: .json(body)))
        }
        return .ok(.init(body: .json(body)))
    }

    // MARK: - Auth

    func startDeviceSignIn(
        _ input: Operations.startDeviceSignIn.Input
    ) async throws -> Operations.startDeviceSignIn.Output {
        do {
            let code = try await auth.startDeviceSignIn()
            return .ok(
                .init(
                    body: .json(
                        .init(
                            deviceCode: code.deviceCode,
                            userCode: code.userCode,
                            verificationURI: code.verificationURI,
                            expiresIn: code.expiresIn,
                            interval: code.interval
                        )
                    )
                )
            )
        } catch AuthError.notConfigured {
            return .serviceUnavailable(.init(body: .json(Self.error("Sign-in isn't configured on this server."))))
        } catch let error as GitHubOAuthError {
            logger.error("GitHub device code request failed: \(error.reason)")
            return .badGateway(.init(body: .json(Self.error("GitHub couldn't start sign-in. Try again."))))
        }
    }

    func pollDeviceSignIn(_ input: Operations.pollDeviceSignIn.Input) async throws -> Operations.pollDeviceSignIn.Output
    {
        guard case .json(let request) = input.body else {
            return .badRequest(.init(body: .json(Self.error("Expected a JSON body."))))
        }
        let name = request.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100, !request.deviceCode.isEmpty, request.deviceCode.count <= 200 else {
            return .badRequest(.init(body: .json(Self.error("deviceCode and deviceName are required."))))
        }
        do {
            switch try await auth.pollDeviceSignIn(deviceCode: request.deviceCode, deviceName: name) {
            case .signedIn(let session):
                return .ok(.init(body: .json(try Self.session(session))))
            case .pending(let interval):
                return .accepted(.init(body: .json(.init(status: .pending, interval: interval))))
            case .slowDown(let interval):
                return .accepted(.init(body: .json(.init(status: .slowDown, interval: interval))))
            }
        } catch AuthError.notConfigured {
            return .serviceUnavailable(.init(body: .json(Self.error("Sign-in isn't configured on this server."))))
        } catch AuthError.expired {
            return .badRequest(.init(body: .json(Self.error("The code expired. Start signing in again."))))
        } catch AuthError.denied {
            return .badRequest(.init(body: .json(Self.error("Access was denied on GitHub."))))
        } catch let error as GitHubOAuthError {
            logger.error("GitHub device flow failed: \(error.reason)")
            return .badGateway(.init(body: .json(Self.error("GitHub couldn't complete sign-in. Try again."))))
        }
    }

    func refreshSession(_ input: Operations.refreshSession.Input) async throws -> Operations.refreshSession.Output {
        guard case .json(let request) = input.body else {
            return .unauthorized(.init(body: .json(Self.error("Expected a refresh token."))))
        }
        do {
            return .ok(.init(body: .json(try Self.session(try await auth.refresh(refreshToken: request.refreshToken)))))
        } catch AuthError.unauthorized {
            return .unauthorized(
                .init(body: .json(Self.error("The refresh token is invalid, expired, or already used.")))
            )
        }
    }

    func signOut(_ input: Operations.signOut.Input) async throws -> Operations.signOut.Output {
        guard let user = RequestContext.user else {
            return .unauthorized(.init(body: .json(Self.error("Not signed in."))))
        }
        try await auth.signOut(user)
        return .noContent(.init())
    }

    // MARK: - Account

    func getCurrentUser(_ input: Operations.getCurrentUser.Input) async throws -> Operations.getCurrentUser.Output {
        guard let current = RequestContext.user, let user = try await User.find(current.userID, on: app.db) else {
            return .unauthorized(.init(body: .json(Self.error("Not signed in."))))
        }
        return .ok(.init(body: .json(try Self.profile(user))))
    }

    // MARK: - Webhooks

    func receiveGitHubWebhook(
        _ input: Operations.receiveGitHubWebhook.Input
    ) async throws -> Operations.receiveGitHubWebhook.Output {
        // The signature was verified against the raw body by WebhookSignatureMiddleware.
        guard case .json(let container) = input.body else {
            return .badRequest(.init(body: .json(Self.error("Expected a JSON payload."))))
        }
        let payload = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(container))
        guard case .string(let fullName)? = payload["repository"]?["full_name"] else {
            return .badRequest(.init(body: .json(Self.error("The delivery has no repository."))))
        }
        var action: String?
        if case .string(let value)? = payload["action"] {
            action = value
        }
        let event = WebhookEvent(
            deliveryID: input.headers.X_hyphen_GitHub_hyphen_Delivery,
            event: input.headers.X_hyphen_GitHub_hyphen_Event,
            action: action,
            repoFullName: fullName,
            payload: payload
        )
        if try await FluentWebhookEventStore(database: app.db).insertIfNew(event) {
            let parts = fullName.split(separator: "/", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                await app.githubCache.invalidate(owner: parts[0], name: parts[1])
            }
        }
        return .accepted(.init())
    }

    // MARK: - Mapping

    private static func error(_ reason: String) -> Components.Schemas._Error {
        .init(error: true, reason: reason)
    }

    private static func profile(_ user: User) throws -> Components.Schemas.UserProfile {
        .init(id: try user.requireID().uuidString, login: user.login, name: user.name, avatarURL: user.avatarURL)
    }

    private static func session(_ session: SessionResult) throws -> Components.Schemas.Session {
        .init(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            tokenType: .Bearer,
            expiresIn: session.expiresIn,
            user: try profile(session.user)
        )
    }
}
