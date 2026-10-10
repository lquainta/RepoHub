import Foundation
import Testing
import Vapor
import VaporTesting

@testable import App

/// Route-level security tests through the real middleware stack. None of these reach the database.
@Suite("API security")
struct AuthAPITests {
    private func withConfiguredApp(
        _ overrides: [String: String] = [:],
        _ body: (Application) async throws -> Void
    ) async throws {
        try await withApp { app in
            try await configure(app, reader: TestDatabase.reader(overrides))
            try await body(app)
        }
    }

    @Test("Protected operations reject missing, malformed, and forged tokens with 401")
    func unauthenticated() async throws {
        let forged = try await SessionTokens(signingKey: Data(repeating: 9, count: 32))
            .accessToken(userID: UUID(), deviceID: UUID())
        try await withConfiguredApp { app in
            for authorization in [nil, "Bearer garbage", "Basic dXNlcjpwYXNz", "Bearer \(forged)"] {
                var headers = HTTPHeaders()
                if let authorization {
                    headers.replaceOrAdd(name: .authorization, value: authorization)
                }
                try await app.testing().test(.GET, "me", headers: headers) { res async throws in
                    #expect(res.status == .unauthorized, "\(authorization ?? "no header")")
                    #expect(res.headers.first(name: .wwwAuthenticate) == "Bearer")
                    #expect(try res.content.decode(ErrorResponse.self).error)
                }
            }
            try await app.testing().test(.POST, "auth/signout") { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test("Sign-in answers 503 when GITHUB_CLIENT_ID isn't configured")
    func signInNotConfigured() async throws {
        try await withConfiguredApp { app in
            try await app.testing().test(.POST, "auth/device") { res async throws in
                #expect(res.status == .serviceUnavailable)
                #expect(try res.content.decode(ErrorResponse.self).reason.contains("isn't configured"))
            }
        }
    }

    @Test("Webhooks are rejected without a configured secret, or with a missing or wrong signature")
    func webhookSignatures() async throws {
        let body = #"{"action":"completed","repository":{"full_name":"o/r"}}"#
        try await withConfiguredApp { app in
            let response = try await app.sendWebhook(body, secret: "s3cret")
            #expect(response.status == .serviceUnavailable)
        }
        try await withConfiguredApp(["GITHUB_WEBHOOK_SECRET": "s3cret"]) { app in
            let missing = try await app.sendWebhook(body)
            let garbage = try await app.sendWebhook(body, signature: "sha256=deadbeef")
            let wrongSecret = try await app.sendWebhook(body, secret: "wrong")
            #expect(missing.status == .unauthorized)
            #expect(garbage.status == .unauthorized)
            #expect(wrongSecret.status == .unauthorized)
        }
    }

    @Test("A correctly signed delivery without a repository is a 400")
    func webhookWithoutRepository() async throws {
        try await withConfiguredApp(["GITHUB_WEBHOOK_SECRET": "s3cret"]) { app in
            let response = try await app.sendWebhook(#"{"zen":"Keep it simple."}"#, event: "ping", secret: "s3cret")
            #expect(response.status == .badRequest)
        }
    }

    @Test("Bodies over 64 KB are rejected with 413")
    func bodyLimit() async throws {
        try await withConfiguredApp { app in
            let big = #"{"refreshToken":""# + String(repeating: "a", count: 70_000) + #""}"#
            let response = try await app.send(.POST, "auth/refresh", json: big)
            #expect(response.status == .payloadTooLarge)
        }
    }

    @Test("Auth endpoints are rate limited per IP with Retry-After; /health is exempt")
    func rateLimits() async throws {
        try await withConfiguredApp(["AUTH_RATE_LIMIT_PER_MINUTE": "3", "RATE_LIMIT_PER_MINUTE": "1000"]) { app in
            for _ in 0..<3 {
                try await app.testing().test(.POST, "auth/device") { res async in
                    #expect(res.status == .serviceUnavailable)
                }
            }
            try await app.testing().test(.POST, "auth/device") { res async throws in
                #expect(res.status == .tooManyRequests)
                let retryAfter = try #require(res.headers.first(name: .retryAfter).flatMap(Int.init))
                #expect((1...60).contains(retryAfter))
            }
            for _ in 0..<10 {
                try await app.testing().test(.GET, "health") { res async in
                    #expect(res.status == .ok)
                }
            }
        }
    }
}
