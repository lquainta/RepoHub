import PostgresKit
import PostgresNIO
import Testing
import Vapor

@testable import App

@Suite("Configuration")
struct ConfigurationTests {
    private func reader(_ values: [String: String]) -> EnvironmentReader {
        EnvironmentReader { values[$0] }
    }

    @Test("Missing required variable throws an error naming it")
    func missingRequiredNamesKey() {
        #expect(throws: ConfigurationError.missing(key: "DATABASE_URL")) {
            try reader([:]).required("DATABASE_URL")
        }
        #expect(ConfigurationError.missing(key: "DATABASE_URL").description.contains("DATABASE_URL"))
    }

    @Test("Empty and whitespace-only values count as unset", arguments: ["", "   "])
    func emptyIsUnset(value: String) {
        #expect(reader(["KEY": value]).optional("KEY") == nil)
        #expect(throws: ConfigurationError.missing(key: "KEY")) {
            try reader(["KEY": value]).required("KEY")
        }
    }

    @Test("Integer values parse, fall back to the default, and reject garbage")
    func integerParsing() throws {
        #expect(try reader(["PORT": "9090"]).integer("PORT", default: 8080) == 9090)
        #expect(try reader([:]).integer("PORT", default: 8080) == 8080)
        #expect(throws: ConfigurationError.invalid(key: "PORT", expected: "an integer")) {
            try reader(["PORT": "eighty"]).integer("PORT", default: 8080)
        }
    }

    private let databaseURL = "postgres://repohub:secret@db.example.com:5432/repohub"

    @Test("Build commit defaults to unknown")
    func buildCommitDefault() throws {
        #expect(try AppConfig(reader: reader(["DATABASE_URL": databaseURL])).buildCommit == "unknown")
        #expect(
            try AppConfig(reader: reader(["DATABASE_URL": databaseURL, "BUILD_COMMIT": "abc1234"])).buildCommit
                == "abc1234"
        )
    }

    @Test("DATABASE_URL is required and must be a postgres URL with a user and host")
    func databaseURLValidation() {
        #expect(throws: ConfigurationError.missing(key: "DATABASE_URL")) {
            try DatabaseConfig(reader: reader([:]), environment: .development)
        }
        for invalid in ["mysql://u@h/db", "not a url", "postgres:///db"] {
            #expect(throws: ConfigurationError.self) {
                try DatabaseConfig(reader: reader(["DATABASE_URL": invalid]), environment: .development)
            }
        }
    }

    @Test("Parses host, port, user, and database from the URL")
    func databaseURLParts() throws {
        let config = try DatabaseConfig(reader: reader(["DATABASE_URL": databaseURL]), environment: .development)
        let core = config.postgres.coreConfiguration
        #expect(core.host == "db.example.com")
        #expect(core.port == 5432)
        #expect(core.username == "repohub")
        #expect(core.database == "repohub")
        #expect(config.maxConnectionsPerEventLoop == 4)
    }

    @Test("Without sslmode, production requires TLS and other environments disable it")
    func tlsDefaults() throws {
        let production = try DatabaseConfig(reader: reader(["DATABASE_URL": databaseURL]), environment: .production)
        let development = try DatabaseConfig(reader: reader(["DATABASE_URL": databaseURL]), environment: .development)
        let testing = try DatabaseConfig(reader: reader(["DATABASE_URL": databaseURL]), environment: .testing)
        #expect(production.requiresTLS)
        #expect(!development.requiresTLS)
        #expect(!development.postgres.coreConfiguration.tls.isAllowed)
        #expect(!testing.requiresTLS)
    }

    @Test("An explicit sslmode in the URL wins over the environment default")
    func explicitSSLMode() throws {
        let privateNetwork = try DatabaseConfig(
            reader: reader(["DATABASE_URL": databaseURL + "?sslmode=disable"]),
            environment: .production
        )
        let required = try DatabaseConfig(
            reader: reader(["DATABASE_URL": databaseURL + "?sslmode=require"]),
            environment: .development
        )
        #expect(!privateNetwork.postgres.coreConfiguration.tls.isAllowed)
        #expect(required.requiresTLS)
    }

    @Test("Pool size must be a positive integer")
    func poolSize() throws {
        let config = try DatabaseConfig(
            reader: reader(["DATABASE_URL": databaseURL, "DATABASE_MAX_CONNECTIONS": "10"]),
            environment: .development
        )
        #expect(config.maxConnectionsPerEventLoop == 10)
        #expect(throws: ConfigurationError.invalid(key: "DATABASE_MAX_CONNECTIONS", expected: "a positive integer")) {
            try DatabaseConfig(
                reader: reader(["DATABASE_URL": databaseURL, "DATABASE_MAX_CONNECTIONS": "0"]),
                environment: .development
            )
        }
    }
}
