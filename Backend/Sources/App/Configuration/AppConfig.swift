import Vapor

/// Application configuration, loaded from the environment once at startup.
///
/// Loading fails fast with a ``ConfigurationError`` naming the offending
/// variable, so a misconfigured deployment never starts serving traffic.
struct AppConfig: Sendable {
    /// Git commit the running build was produced from, reported by `/health`.
    let buildCommit: String
    /// PostgreSQL connection settings.
    let database: DatabaseConfig
    /// Redis for the GitHub response cache. Required in production; elsewhere
    /// an in-memory cache is used when it's unset.
    let redisURL: String?
    /// Authentication, webhook, and rate-limit settings.
    let security: SecurityConfig
    /// Where unhandled errors are reported; off when unset (#51).
    let sentryDSN: SentryDSN?
    /// Enables `GET /debug/error` for this token, to check error reporting
    /// end to end; off when unset.
    let debugToken: String?

    /// Loads configuration using `reader`.
    init(reader: EnvironmentReader = EnvironmentReader(), environment: Environment = .development) throws {
        buildCommit = reader.optional("BUILD_COMMIT") ?? "unknown"
        database = try DatabaseConfig(reader: reader, environment: environment)
        redisURL = environment == .production ? try reader.required("REDIS_URL") : reader.optional("REDIS_URL")
        if let redisURL, URL(string: redisURL)?.scheme?.hasPrefix("redis") != true {
            throw ConfigurationError.invalid(key: "REDIS_URL", expected: "a redis:// or rediss:// URL")
        }
        security = try SecurityConfig(reader: reader, environment: environment)
        if let dsn = reader.optional("SENTRY_DSN") {
            guard let parsed = SentryDSN(dsn) else {
                throw ConfigurationError.invalid(key: "SENTRY_DSN", expected: "https://<key>@<host>/<project>")
            }
            sentryDSN = parsed
        } else {
            sentryDSN = nil
        }
        debugToken = reader.optional("DEBUG_TOKEN").flatMap { $0.count >= 32 ? $0 : nil }
    }
}

private struct AppConfigKey: StorageKey {
    typealias Value = AppConfig
}

extension Application {
    /// Configuration loaded in `configure(_:)`.
    var config: AppConfig {
        get {
            guard let config = storage[AppConfigKey.self] else {
                preconditionFailure("AppConfig accessed before configure(_:) loaded it")
            }
            return config
        }
        set { storage[AppConfigKey.self] = newValue }
    }
}
