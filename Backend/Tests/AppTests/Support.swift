import Fluent
import Foundation
import Testing
import VaporTesting

@testable import App

extension Tag {
    /// Tests that need a real PostgreSQL database (see docs/testing.md).
    @Tag static var integration: Self
}

/// Test database settings.
enum TestDatabase {
    /// The database integration tests use, from `TEST_DATABASE_URL`. Never the
    /// development or production database (#32).
    static let url = ProcessInfo.processInfo.environment["TEST_DATABASE_URL"]

    /// Whether integration tests can run.
    static var isAvailable: Bool { url != nil }

    /// Configuration for tests that don't touch the database: Fluent connects
    /// lazily, so a placeholder URL is enough.
    static func reader(_ overrides: [String: String] = [:]) -> EnvironmentReader {
        let values = ["DATABASE_URL": url ?? "postgres://repohub@localhost:5432/unused"]
            .merging(overrides) { _, new in new }
        return EnvironmentReader { values[$0] }
    }
}

/// Runs `body` with an app connected to the test database, with every
/// migration applied. Leftovers from a crashed run are reverted first, and
/// everything is reverted afterwards, so each test starts from an empty schema.
func withMigratedApp(_ body: (Application) async throws -> Void) async throws {
    try await withApp { app in
        try await configure(app, reader: TestDatabase.reader())
        try await app.autoRevert()
        try await app.autoMigrate()
        do {
            try await body(app)
        } catch {
            try? await app.autoRevert()
            throw error
        }
        try await app.autoRevert()
    }
}
