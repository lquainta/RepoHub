import Fluent
import FluentPostgresDriver
import Foundation
import Vapor

/// PostgreSQL connection settings, from `DATABASE_URL` and related variables.
struct DatabaseConfig: Sendable {
    /// Connection settings parsed from the URL, including TLS.
    let postgres: SQLPostgresConfiguration
    /// Connections per event loop (`DATABASE_MAX_CONNECTIONS`, default 4).
    let maxConnectionsPerEventLoop: Int

    /// Loads the configuration.
    ///
    /// TLS comes from the URL's `sslmode` query item when present. Otherwise
    /// production requires TLS and other environments disable it (local
    /// containers don't offer it). Use `?sslmode=disable` explicitly for a
    /// private network that encrypts traffic itself.
    init(reader: EnvironmentReader, environment: Environment) throws {
        let raw = try reader.required("DATABASE_URL")
        guard var components = URLComponents(string: raw), components.scheme?.hasPrefix("postgres") == true else {
            throw ConfigurationError.invalid(key: "DATABASE_URL", expected: "a postgres:// URL")
        }
        let tlsKeys: Set<String> = ["sslmode", "tlsmode", "ssl", "tls"]
        if !(components.queryItems ?? []).contains(where: { tlsKeys.contains($0.name.lowercased()) }) {
            let mode = environment == .production ? "require" : "disable"
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "sslmode", value: mode)]
        }
        guard let url = components.url, let postgres = try? SQLPostgresConfiguration(url: url) else {
            throw ConfigurationError.invalid(key: "DATABASE_URL", expected: "a postgres:// URL with a user and host")
        }
        self.postgres = postgres
        maxConnectionsPerEventLoop = try reader.integer("DATABASE_MAX_CONNECTIONS", default: 4)
        guard maxConnectionsPerEventLoop > 0 else {
            throw ConfigurationError.invalid(key: "DATABASE_MAX_CONNECTIONS", expected: "a positive integer")
        }
    }

    /// Whether connections require TLS.
    var requiresTLS: Bool {
        postgres.coreConfiguration.tls.isEnforced
    }
}

extension Application {
    /// Registers PostgreSQL as the default database.
    func configureDatabase(_ config: DatabaseConfig) {
        databases.use(
            .postgres(
                configuration: config.postgres,
                maxConnectionsPerEventLoop: config.maxConnectionsPerEventLoop
            ),
            as: .psql
        )
    }
}
