import Testing
import VaporTesting

@testable import App

/// Configures the app without needing a running database.
private func configureForTesting(_ app: Application) async throws {
    try await configure(app, reader: TestDatabase.reader())
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
}
