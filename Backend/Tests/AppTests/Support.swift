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

/// Test Redis settings.
enum TestRedis {
    /// The Redis integration tests use, from `TEST_REDIS_URL`. Tests use unique keys
    /// and never flush, so a shared development Redis is safe.
    static let url = ProcessInfo.processInfo.environment["TEST_REDIS_URL"]

    static var isAvailable: Bool { url != nil }
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

extension Application {
    /// Sends a request through the whole app (middleware included) and returns the response.
    func send(
        _ method: HTTPMethod,
        _ path: String,
        json: String? = nil,
        headers: HTTPHeaders = [:]
    ) async throws -> TestingHTTPResponse {
        var headers = headers
        if json != nil {
            headers.contentType = .json
        }
        return try await testing().sendRequest(
            method,
            path,
            headers: headers,
            body: json.map { ByteBuffer(string: $0) }
        )
    }

    /// Sends a GitHub webhook delivery, signed with `secret` unless `signature` overrides it.
    func sendWebhook(
        _ json: String,
        event: String = "check_run",
        delivery: String = UUID().uuidString,
        secret: String? = nil,
        signature: String? = nil
    ) async throws -> TestingHTTPResponse {
        var headers: HTTPHeaders = ["X-GitHub-Event": event, "X-GitHub-Delivery": delivery]
        if let header = signature ?? secret.map({ WebhookSignature.sign(Data(json.utf8), secret: $0) }) {
            headers.replaceOrAdd(name: "X-Hub-Signature-256", value: header)
        }
        return try await send(.POST, "webhooks/github", json: json, headers: headers)
    }
}

private struct AccessTokenBody: Decodable {
    let accessToken: String
}

extension Application {
    /// Signs in through the device flow with a fake GitHub and returns an access token.
    func signInWithFakeGitHub() async throws -> String {
        githubOAuth = FakeGitHubOAuth(results: [.approved(token: "gho_token", scopes: "repo,read:user")])
        _ = try await send(.POST, "auth/device", json: "")
        let poll = #"{"deviceCode":"dc-1","deviceName":"Test Mac"}"#
        let response = try await send(.POST, "auth/device/token", json: poll)
        return try response.content.decode(AccessTokenBody.self).accessToken
    }

    /// The signed-in user's ID, from an access token.
    func userID(forAccessToken token: String) async throws -> UUID {
        try #require(try await authService(on: db).authenticate(accessToken: token)).userID
    }
}

/// Integration tests skip themselves without a database or Redis, which is
/// right on a laptop but would hide a broken CI setup (#25).
@Suite("Integration environment", .enabled(if: ProcessInfo.processInfo.environment["CI"] == "true"))
struct IntegrationEnvironmentTests {
    @Test("CI provides PostgreSQL and Redis, so integration tests run instead of skipping")
    func servicesConfigured() {
        #expect(TestDatabase.isAvailable, "TEST_DATABASE_URL isn't set in CI")
        #expect(TestRedis.isAvailable, "TEST_REDIS_URL isn't set in CI")
    }
}
