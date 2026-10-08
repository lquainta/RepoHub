import Testing
import VaporTesting

@testable import App

@Suite("App")
struct AppTests {
    @Test("Health endpoint reports ok")
    func healthReportsOK() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "health") { res async throws in
                #expect(res.status == .ok)
                let body = try res.content.decode(HealthResponse.self)
                #expect(body.status == "ok")
            }
        }
    }

    @Test("Unknown routes return 404")
    func unknownRouteNotFound() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "does-not-exist") { res async in
                #expect(res.status == .notFound)
            }
        }
    }
}
