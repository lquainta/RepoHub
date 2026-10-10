import Testing
import VaporTesting

@testable import App

/// Configures the app without needing a running database.
private func configureForTesting(_ app: Application) async throws {
    try await configure(app, reader: TestDatabase.reader())
}

/// The `/health` response, decoded independently of the generated types.
private struct HealthResponse: Decodable {
    let status: String
    let version: String
    let commit: String
}

@Suite("App")
struct AppTests {
    @Test("Health endpoint reports ok")
    func healthReportsOK() async throws {
        try await withApp(configure: configureForTesting) { app in
            try await app.testing().test(.GET, "health") { res async throws in
                #expect(res.status == .ok)
                let body = try res.content.decode(HealthResponse.self)
                #expect(body.status == "ok")
                #expect(!body.commit.isEmpty)
            }
        }
    }

    @Test("Unknown routes return 404")
    func unknownRouteNotFound() async throws {
        try await withApp(configure: configureForTesting) { app in
            try await app.testing().test(.GET, "does-not-exist") { res async in
                #expect(res.status == .notFound)
            }
        }
    }

    @Test("The OpenAPI document and its rendered docs are served")
    func documentation() async throws {
        try await withApp(configure: configureForTesting) { app in
            try await app.testing().test(.GET, "openapi.yaml") { res async in
                #expect(res.status == .ok)
                #expect(res.headers.contentType?.subType == "yaml")
                #expect(res.body.string.hasPrefix("openapi: 3.1.0"))
                #expect(res.body.string.contains("operationId: getHealth"))
            }
            try await app.testing().test(.GET, "docs") { res async in
                #expect(res.status == .ok)
                #expect(res.headers.contentType == .html)
                #expect(res.body.string.contains("spec-url=\"/openapi.yaml\""))
            }
        }
    }
}
