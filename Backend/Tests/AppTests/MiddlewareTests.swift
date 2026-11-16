import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
import Vapor
import VaporTesting

@testable import App

@Suite("Middleware")
struct MiddlewareTests {
    private func authentication(limit: Int) -> AuthenticationMiddleware {
        let user = AuthenticatedUser(userID: UUID(), deviceID: UUID())
        return AuthenticationMiddleware(
            authenticate: { token in token == "valid" ? user : nil },
            limiter: RateLimiter(store: InMemoryCacheStore(), now: { Date(timeIntervalSince1970: 1_800_000_010) }),
            limitPerMinute: limit
        )
    }

    private func call(
        _ middleware: AuthenticationMiddleware,
        operation: String,
        authorization: String? = "Bearer valid"
    ) async throws -> (response: HTTPResponse, sawUser: Bool) {
        var request = HTTPRequest(method: .get, scheme: "https", authority: "example.com", path: "/me")
        if let authorization {
            request.headerFields[.authorization] = authorization
        }
        let sawUser = Flag()
        let (response, _) = try await middleware.intercept(
            request,
            body: nil,
            metadata: .init(),
            operationID: operation
        ) { _, _, _ in
            sawUser.set(RequestContext.user != nil)
            return (HTTPResponse(status: .ok), nil)
        }
        return (response, sawUser.value)
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = false
        var value: Bool { lock.withLock { stored } }
        func set(_ value: Bool) { lock.withLock { stored = value } }
    }

    @Test("A signed-in user over the per-user limit gets 429 with Retry-After; the handler doesn't run")
    func perUserLimit() async throws {
        let middleware = authentication(limit: 2)
        #expect(try await call(middleware, operation: "getCurrentUser").response.status == .ok)
        #expect(try await call(middleware, operation: "getCurrentUser").sawUser)

        let limited = try await call(middleware, operation: "getCurrentUser")
        #expect(limited.response.status == .tooManyRequests)
        #expect(limited.response.headerFields[.retryAfter] == "50")
        #expect(!limited.sawUser)
    }

    @Test("Public operations skip authentication and the per-user limit")
    func publicOperations() async throws {
        let middleware = authentication(limit: 1)
        for _ in 0..<3 {
            let result = try await call(middleware, operation: "getHealth", authorization: nil)
            #expect(result.response.status == .ok && !result.sawUser)
        }
        let rejected = try await call(middleware, operation: "getCurrentUser", authorization: "Bearer wrong")
        #expect(rejected.response.status == .unauthorized)
        #expect(rejected.response.headerFields[.wwwAuthenticate] == "Bearer")
    }

    private func withLimitedApp(
        trustsProxyHeader: Bool,
        _ body: (Application) async throws -> Void
    ) async throws {
        try await withApp { app in
            app.middleware.use(
                RateLimitMiddleware(
                    limiter: RateLimiter(
                        store: InMemoryCacheStore(),
                        now: { Date(timeIntervalSince1970: 1_800_000_010) }
                    ),
                    limitPerMinute: 1,
                    authLimitPerMinute: 1,
                    trustsProxyHeader: trustsProxyHeader
                )
            )
            app.get("ping") { _ in "pong" }
            try await body(app)
        }
    }

    @Test("Behind Fly's proxy, clients are limited by Fly-Client-IP; elsewhere the header is ignored")
    func proxyHeader() async throws {
        func statuses(_ app: Application, addresses: [String]) async throws -> [HTTPStatus] {
            var statuses: [HTTPStatus] = []
            for address in addresses {
                statuses.append(try await app.send(.GET, "ping", headers: ["Fly-Client-IP": address]).status)
            }
            return statuses
        }
        try await withLimitedApp(trustsProxyHeader: true) { app in
            let trusted = try await statuses(app, addresses: ["203.0.113.1", "203.0.113.2", "203.0.113.1"])
            #expect(trusted == [.ok, .ok, .tooManyRequests])
        }
        try await withLimitedApp(trustsProxyHeader: false) { app in
            // A different header value doesn't get a fresh allowance.
            let untrusted = try await statuses(app, addresses: ["203.0.113.1", "203.0.113.2"])
            #expect(untrusted == [.ok, .tooManyRequests])
        }
    }

    @Test("A body over the limit is rejected even when no Content-Length announces it")
    func bodyLimitWithoutLength() async throws {
        try await withApp { app in
            app.middleware.use(BodyLimitMiddleware())
            app.post("echo") { _ in "ok" }
            let oversized = ByteBuffer(repeating: 0x61, count: BodyLimitMiddleware.defaultLimit.value + 1)
            try await app.testing().test(.POST, "echo", body: oversized) { response async in
                #expect(response.status == .payloadTooLarge)
            }
            try await app.testing().test(.POST, "echo", body: ByteBuffer(string: "small")) { response async in
                #expect(response.status == .ok)
            }
        }
    }
}
