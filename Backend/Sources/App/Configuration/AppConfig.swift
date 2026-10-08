import Vapor

/// Application configuration, loaded from the environment once at startup.
///
/// Loading fails fast with a ``ConfigurationError`` naming the offending
/// variable, so a misconfigured deployment never starts serving traffic.
struct AppConfig: Sendable {
    /// Git commit the running build was produced from, reported by `/health`.
    let buildCommit: String

    /// Loads configuration using `reader`.
    init(reader: EnvironmentReader = EnvironmentReader()) throws {
        buildCommit = reader.optional("BUILD_COMMIT") ?? "unknown"
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
