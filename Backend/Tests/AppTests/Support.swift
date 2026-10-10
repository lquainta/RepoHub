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

    /// Integration tests drop every table, so they only run against a database
    /// whose name ends in `_test`: a mistyped `TEST_DATABASE_URL` pointing at
    /// `repohub_dev` or production fails instead of wiping it.
    static func isDisposable(_ url: String) -> Bool {
        guard let name = URLComponents(string: url)?.path.split(separator: "/").last else {
            return false
        }
        return name.hasSuffix("_test")
    }

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
    let url = try #require(TestDatabase.url)
    try #require(
        TestDatabase.isDisposable(url),
        "TEST_DATABASE_URL must name a database ending in _test; integration tests drop every table."
    )
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
