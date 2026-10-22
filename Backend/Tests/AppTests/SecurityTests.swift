import Foundation
import Testing
import Vapor

@testable import App

@Suite("TokenCipher")
struct TokenCipherTests {
    private let key = Data(repeating: 7, count: 32)

    @Test("Round-trips a token and never stores it in plain text")
    func roundTrip() throws {
        let cipher = TokenCipher(key: key)
        let sealed = try cipher.seal("gho_secret")
        #expect(try cipher.open(sealed) == "gho_secret")
        #expect(sealed.range(of: Data("gho_secret".utf8)) == nil)
        #expect(sealed.first == 1)
        #expect(try cipher.seal("gho_secret") != sealed, "Each seal uses a fresh nonce")
    }

    @Test("Tampered data, another key, and unknown versions are rejected")
    func rejectsTampering() throws {
        let cipher = TokenCipher(key: key)
        var sealed = try cipher.seal("gho_secret")
        sealed[sealed.count - 1] ^= 0xFF
        #expect(throws: (any Error).self) { try cipher.open(sealed) }
        #expect(throws: (any Error).self) {
            try TokenCipher(key: Data(repeating: 8, count: 32)).open(try cipher.seal("x"))
        }
        #expect(throws: TokenCipher.CipherError.unsupportedVersion(9)) { try cipher.open(Data([9, 1, 2, 3])) }
        #expect(throws: TokenCipher.CipherError.malformed) { try cipher.open(Data()) }
    }
}

@Suite("SessionTokens")
struct SessionTokensTests {
    @Test("Access tokens verify with the same key and carry the user and device")
    func accessTokens() async throws {
        let tokens = await SessionTokens(signingKey: Data(repeating: 1, count: 32))
        let user = UUID()
        let device = UUID()
        let token = try await tokens.accessToken(userID: user, deviceID: device)

        let claims = try #require(await tokens.verify(token))
        #expect(claims.userID == user && claims.deviceID == device)
    }

    @Test("Expired, forged, and malformed access tokens are rejected")
    func rejectsBadTokens() async throws {
        let tokens = await SessionTokens(signingKey: Data(repeating: 1, count: 32))
        let expired = try await tokens.accessToken(
            userID: UUID(),
            deviceID: UUID(),
            now: .now.addingTimeInterval(-3_600)
        )
        let forged = try await SessionTokens(signingKey: Data(repeating: 2, count: 32))
            .accessToken(userID: UUID(), deviceID: UUID())

        #expect(await tokens.verify(expired) == nil)
        #expect(await tokens.verify(forged) == nil)
        #expect(await tokens.verify("not.a.jwt") == nil)
    }

    @Test("Refresh tokens are random, URL-safe, and stored only as a stable hash")
    func refreshTokens() {
        let first = SessionTokens.makeRefreshToken()
        let second = SessionTokens.makeRefreshToken()
        #expect(first.token != second.token)
        #expect(first.token.count == 43)
        #expect(first.token.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(first.hash == SessionTokens.hash(first.token))
        #expect(first.hash.count == 32)
    }
}

@Suite("WebhookSignature")
struct WebhookSignatureTests {
    private let body = Data(#"{"action":"completed"}"#.utf8)

    @Test("A signature made with the secret is valid")
    func valid() {
        let header = WebhookSignature.sign(body, secret: "s3cret")
        #expect(header.hasPrefix("sha256=") && header.count == 71)
        #expect(WebhookSignature.isValid(header, body: body, secret: "s3cret"))
        #expect(
            WebhookSignature.isValid(
                header.uppercased().replacingOccurrences(of: "SHA256=", with: "sha256="),
                body: body,
                secret: "s3cret"
            )
        )
    }

    @Test(
        "Wrong secrets, altered bodies, and malformed headers are rejected",
        arguments: [nil, "", "sha1=abc", "sha256=", "sha256=zz", "sha256=abc"]
    )
    func invalid(header: String?) {
        #expect(!WebhookSignature.isValid(header, body: body, secret: "s3cret"))
    }

    @Test("Signatures don't transfer between secrets or bodies")
    func doesNotTransfer() {
        let header = WebhookSignature.sign(body, secret: "s3cret")
        #expect(!WebhookSignature.isValid(header, body: body, secret: "other"))
        #expect(!WebhookSignature.isValid(header, body: Data(#"{"action":"created"}"#.utf8), secret: "s3cret"))
    }
}

/// A cache whose counters always fail, as if Redis were down.
private struct UnavailableCacheStore: CacheStore {
    struct Failure: Error {}
    func get<V: Decodable & Sendable>(_ key: String, as type: V.Type) async throws -> V? { throw Failure() }
    func set<V: Encodable & Sendable>(_ key: String, to value: V, expiresIn seconds: Int) async throws {}
    func delete(_ keys: [String]) async throws {}
    func addToSet(_ key: String, member: String, expiresIn seconds: Int) async throws {}
    func members(ofSet key: String) async throws -> [String] { [] }
    func increment(_ key: String, expiresIn seconds: Int) async throws -> Int { throw Failure() }
    func ping() async throws { throw Failure() }
}

@Suite("RateLimiter")
struct RateLimiterTests {
    private final class Clock: @unchecked Sendable {
        // 20 seconds into a 60-second window (1_000_020 is a multiple of 60).
        var now = Date(timeIntervalSince1970: 1_000_040)
    }

    @Test("Allows up to the limit per window, then limits with the seconds left")
    func limits() async {
        let clock = Clock()
        let limiter = RateLimiter(store: InMemoryCacheStore { clock.now }, now: { clock.now })
        for expected in (0..<3).reversed() {
            #expect(await limiter.check("ip:1", limit: 3) == .allowed(remaining: expected))
        }
        #expect(await limiter.check("ip:1", limit: 3) == .limited(retryAfter: 40))
        #expect(await limiter.check("ip:2", limit: 3) == .allowed(remaining: 2), "Keys are independent")

        clock.now += 40
        #expect(await limiter.check("ip:1", limit: 3) == .allowed(remaining: 2), "A new window starts fresh")
    }

    @Test("If the cache is down, requests are allowed")
    func failsOpen() async {
        #expect(await RateLimiter(store: UnavailableCacheStore()).check("ip:1", limit: 1) == .allowed(remaining: 1))
    }
}

@Suite("SecurityConfig")
struct SecurityConfigTests {
    private let key32 = Data(repeating: 3, count: 32).base64EncodedString()

    private func reader(_ values: [String: String]) -> EnvironmentReader {
        EnvironmentReader { values[$0] }
    }

    @Test("Production requires every secret")
    func productionRequiresSecrets() throws {
        let complete = [
            "JWT_SIGNING_KEY": key32, "TOKEN_ENCRYPTION_KEY": key32,
            "GITHUB_CLIENT_ID": "Ov23li", "GITHUB_WEBHOOK_SECRET": "hook",
        ]
        _ = try SecurityConfig(reader: reader(complete), environment: .production)
        for missing in complete.keys {
            var values = complete
            values[missing] = nil
            #expect(throws: ConfigurationError.missing(key: missing)) {
                try SecurityConfig(reader: reader(values), environment: .production)
            }
        }
    }

    @Test("Development generates throwaway keys and disables unconfigured GitHub features")
    func developmentDefaults() throws {
        let config = try SecurityConfig(reader: reader([:]), environment: .development)
        #expect(config.jwtSigningKey.count == 32 && config.tokenEncryptionKey.count == 32)
        #expect(config.githubClientID == nil && config.githubWebhookSecret == nil)
        #expect(config.rateLimitPerMinute == 120 && config.authRateLimitPerMinute == 30)
    }

    @Test("Keys must be base64 of the right length")
    func keyValidation() {
        let short = Data(repeating: 1, count: 16).base64EncodedString()
        #expect(throws: ConfigurationError.self) {
            try SecurityConfig(reader: reader(["JWT_SIGNING_KEY": short]), environment: .development)
        }
        #expect(throws: ConfigurationError.self) {
            try SecurityConfig(
                reader: reader(["TOKEN_ENCRYPTION_KEY": Data(repeating: 1, count: 48).base64EncodedString()]),
                environment: .development
            )
        }
        #expect(throws: ConfigurationError.self) {
            try SecurityConfig(reader: reader(["JWT_SIGNING_KEY": "not base64!"]), environment: .development)
        }
    }
}

@Suite("Public operations")
struct PublicOperationsTests {
    @Test("The middleware's public operations are exactly those with `security: []` in the spec")
    func matchesSpec() throws {
        let specURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "openapi/openapi.yaml")
        let spec = try String(contentsOf: specURL, encoding: .utf8)
        var publicOperations: Set<String> = []
        // Each operation block runs from its operationId to the next operationId.
        let blocks = spec.components(separatedBy: "operationId: ").dropFirst()
        for block in blocks {
            let name = String(block.prefix { !$0.isNewline })
            if block.contains("security: []") {
                publicOperations.insert(name)
            }
        }
        #expect(publicOperations == AuthenticationMiddleware.publicOperations)
    }
}
