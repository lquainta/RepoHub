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

    /// Loads configuration using `reader`.
    init(reader: EnvironmentReader = EnvironmentReader(), environment: Environment = .development) throws {
        buildCommit = reader.optional("BUILD_COMMIT") ?? "unknown"
        database = try DatabaseConfig(reader: reader, environment: environment)
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
