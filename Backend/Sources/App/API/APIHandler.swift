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

    // MARK: - GitHub

    func getRepositoryStatuses(
        _ input: Operations.getRepositoryStatuses.Input
    ) async throws -> Operations.getRepositoryStatuses.Output {
        guard let current = RequestContext.user, let user = try await User.find(current.userID, on: app.db),
            let token = try auth.githubToken(for: user)
        else {
            return .unauthorized(.init(body: .json(Self.error("Not signed in."))))
        }
        guard case .json(let request) = input.body else {
            return .badRequest(.init(body: .json(Self.error("Expected a JSON body."))))
        }
        guard (1...100).contains(request.repositories.count) else {
            return .badRequest(.init(body: .json(Self.error("Send between 1 and 100 repositories."))))
        }
        let references = request.repositories.map {
            RepositoryStatusService.Reference(owner: $0.owner, name: $0.name, branch: $0.branch)
        }
        let statuses = await RepositoryStatusService(cache: app.githubCache, logger: logger).statuses(
            for: references,
            userID: try user.requireID(),
            login: user.login,
            token: token
        )
        return .ok(.init(body: .json(.init(repositories: statuses.map(Self.status)))))
    }

    // MARK: - Events

    /// Webhook events that change what the app shows, and are sent to `GET /events`.
    static let liveEvents: Set<String> = ["check_run", "check_suite", "pull_request", "pull_request_review", "push"]
    /// How often the stream sends a comment so proxies don't close it.
    static let keepAliveInterval: Duration = .seconds(25)
    /// How long a stream stays open; the app reconnects with a fresh access token.
    static let streamLifetime: Duration = .seconds(600)

    func streamEvents(_ input: Operations.streamEvents.Input) async throws -> Operations.streamEvents.Output {
        guard let user = RequestContext.user else {
            return .unauthorized(.init(body: .json(Self.error("Not signed in."))))
        }
        let changes = await app.eventHub.subscribe(user: user.userID)
        let events = Self.eventStream(changes)
        let body = HTTPBody(events.asEncodedServerSentEvents(), length: .unknown, iterationBehavior: .single)
        return .ok(.init(body: .text_event_hyphen_stream(body)))
    }

    /// `repository` events for `changes`, and `keep-alive` events every
    /// ``keepAliveInterval``, ending after ``streamLifetime``.
    static func eventStream(
        _ changes: AsyncStream<RepositoryChange>,
        keepAlive: Duration = keepAliveInterval,
        lifetime: Duration = streamLifetime
    ) -> AsyncStream<ServerSentEvent> {
        AsyncStream { continuation in
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let forward = Task {
                for await change in changes {
                    let data = (try? encoder.encode(change)).flatMap { String(bytes: $0, encoding: .utf8) }
                    continuation.yield(ServerSentEvent(event: "repository", data: data))
                }
                continuation.finish()
            }
            let timers = Task {
                let clock = ContinuousClock()
                let end = clock.now.advanced(by: lifetime)
                while clock.now < end {
                    try? await Task.sleep(for: min(keepAlive, clock.now.duration(to: end)))
                    guard !Task.isCancelled else {
                        return
                    }
                    if clock.now < end {
                        continuation.yield(ServerSentEvent(event: "keep-alive"))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                forward.cancel()
                timers.cancel()
            }
        }
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
            // Other events (stars, issues, ...) don't change what the app shows.
            if parts.count == 2, Self.liveEvents.contains(event.event) {
                let users = await app.githubCache.invalidate(owner: parts[0], name: parts[1])
                if !users.isEmpty {
                    await app.eventHub.publish(
                        RepositoryChange(owner: parts[0], name: parts[1], event: event.event),
                        to: users
                    )
                }
            }
        }
        return .accepted(.init())
    }

    // MARK: - Mapping

    static func error(_ reason: String) -> Components.Schemas._Error {
        .init(error: true, reason: reason)
    }

    private static func profile(_ user: User) throws -> Components.Schemas.UserProfile {
        .init(id: try user.requireID().uuidString, login: user.login, name: user.name, avatarURL: user.avatarURL)
    }

    private static func status(_ status: RepositoryGitHubStatus) -> Components.Schemas.RepositoryGitHubStatus {
        .init(
            owner: status.owner,
            name: status.name,
            pullRequests: status.pullRequests.map {
                .init(
                    number: $0.number,
                    title: $0.title,
                    url: $0.url,
                    author: $0.author,
                    isDraft: $0.isDraft,
                    headBranch: $0.headBranch,
                    reviewRequested: $0.reviewRequested
                )
            },
            checks: status.checks.map {
                .init(
                    state: .init(rawValue: $0.state.rawValue) ?? .pending,
                    total: $0.total,
                    failed: $0.failed,
                    pending: $0.pending,
                    url: $0.url
                )
            },
            error: status.error.flatMap { .init(rawValue: $0.rawValue) }
        )
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
