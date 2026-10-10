import Foundation
import Vapor

/// Secrets and limits for authentication, webhooks, and rate limiting.
///
/// Production requires every secret. In development and testing, missing
/// keys are replaced with random ones for the life of the process (sessions
/// and stored tokens then don't survive a restart), and missing GitHub
/// settings disable the features that need them.
struct SecurityConfig: Sendable {
    /// HMAC-SHA256 key for access tokens (`JWT_SIGNING_KEY`, base64, at least 32 bytes).
    let jwtSigningKey: Data
    /// AES-256-GCM key for GitHub tokens at rest (`TOKEN_ENCRYPTION_KEY`, base64, exactly 32 bytes).
    let tokenEncryptionKey: Data
    /// The GitHub OAuth app's client ID (`GITHUB_CLIENT_ID`); sign-in is disabled without it.
    let githubClientID: String?
    /// Shared secret for webhook signatures (`GITHUB_WEBHOOK_SECRET`); webhooks are rejected without it.
    let githubWebhookSecret: String?
    /// Requests per minute per client IP (`RATE_LIMIT_PER_MINUTE`, default 120).
    let rateLimitPerMinute: Int
    /// Requests per minute per client IP to `/auth` (`AUTH_RATE_LIMIT_PER_MINUTE`, default 30).
    let authRateLimitPerMinute: Int

    init(reader: EnvironmentReader, environment: Environment, logger: Logger = Logger(label: "SecurityConfig")) throws {
        let isProduction = environment == .production
        jwtSigningKey = try Self.key(
            "JWT_SIGNING_KEY",
            reader: reader,
            required: isProduction,
            minimumBytes: 32,
            logger: logger
        )
        tokenEncryptionKey = try Self.key(
            "TOKEN_ENCRYPTION_KEY",
            reader: reader,
            required: isProduction,
            exactBytes: 32,
            logger: logger
        )
        githubClientID = isProduction ? try reader.required("GITHUB_CLIENT_ID") : reader.optional("GITHUB_CLIENT_ID")
        githubWebhookSecret =
            isProduction ? try reader.required("GITHUB_WEBHOOK_SECRET") : reader.optional("GITHUB_WEBHOOK_SECRET")
        rateLimitPerMinute = try reader.integer("RATE_LIMIT_PER_MINUTE", default: 120)
        authRateLimitPerMinute = try reader.integer("AUTH_RATE_LIMIT_PER_MINUTE", default: 30)
        guard rateLimitPerMinute > 0 else {
            throw ConfigurationError.invalid(key: "RATE_LIMIT_PER_MINUTE", expected: "a positive integer")
        }
        guard authRateLimitPerMinute > 0 else {
            throw ConfigurationError.invalid(key: "AUTH_RATE_LIMIT_PER_MINUTE", expected: "a positive integer")
        }
    }

    private static func key(
        _ name: String,
        reader: EnvironmentReader,
        required: Bool,
        minimumBytes: Int = 0,
        exactBytes: Int? = nil,
        logger: Logger
    ) throws -> Data {
        guard let raw = required ? try reader.required(name) : reader.optional(name) else {
            logger.warning("\(name) is not set; using a random key until restart")
            return Data((0..<(exactBytes ?? max(32, minimumBytes))).map { _ in UInt8.random(in: .min ... .max) })
        }
        let expectation =
            exactBytes.map { "base64 for exactly \($0) bytes" } ?? "base64 for at least \(minimumBytes) bytes"
        guard let data = Data(base64Encoded: raw), data.count >= minimumBytes,
            exactBytes.map({ data.count == $0 }) ?? true
        else {
            throw ConfigurationError.invalid(key: name, expected: expectation)
        }
        return data
    }
}
