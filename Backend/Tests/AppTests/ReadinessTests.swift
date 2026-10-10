import Foundation
import Testing
import Vapor
import VaporTesting

@testable import App

private struct Unreachable: Error {}

@Suite("Readiness")
struct ReadinessTests {
    @Test("Both dependencies up means ready")
    func allUp() async {
        let results = await ReadinessChecker(database: {}, cache: {}).check()
        #expect(results.database.isUp && results.cache.isUp)
        #expect(results.database.error == nil)
    }

    @Test("A failing dependency is down, and its error never includes details that could leak credentials")
    func failing() async {
        let results = await ReadinessChecker(database: { throw Unreachable() }, cache: {}).check()
        #expect(!results.database.isUp && results.cache.isUp)
        #expect(results.database.error == "Unreachable (Unreachable)")
    }

    @Test("A hung dependency times out instead of hanging the probe")
    func hung() async {
        let checker = ReadinessChecker(
            database: {},
            cache: { try await Task.sleep(for: .seconds(30)) },
            timeout: .milliseconds(100)
        )
        let clock = ContinuousClock()
        let start = clock.now
        let results = await checker.check()
        #expect(!results.cache.isUp)
        #expect(results.cache.error?.hasPrefix("Timed out") == true)
        #expect(clock.now - start < .seconds(2))
    }

    @Test("GET /ready answers 200 when ready and 503 with the failing component otherwise")
    func endpoint() async throws {
        try await withApp { app in
            try await configure(app, reader: TestDatabase.reader())
            app.readinessChecker = ReadinessChecker(database: {}, cache: {})
            let ready = try await app.send(.GET, "ready")
            #expect(ready.status == .ok)
            #expect(
                ready.body.string.contains(#""status":"ready""#) || ready.body.string.contains(#""status" : "ready""#)
            )

            app.readinessChecker = ReadinessChecker(database: { throw Unreachable() }, cache: {})
            let down = try await app.send(.GET, "ready")
            #expect(down.status == .serviceUnavailable)
            let body = try JSONSerialization.jsonObject(with: Data(down.body.string.utf8)) as? [String: Any]
            let checks = body?["checks"] as? [String: [String: Any]]
            #expect(body?["status"] as? String == "unavailable")
            #expect(checks?["database"]?["status"] as? String == "down")
            #expect(checks?["cache"]?["status"] as? String == "up")
        }
    }

    @Test("/ready isn't rate limited, because monitors poll it")
    func notRateLimited() async throws {
        try await withApp { app in
            try await configure(app, reader: TestDatabase.reader(["RATE_LIMIT_PER_MINUTE": "2"]))
            app.readinessChecker = ReadinessChecker(database: {}, cache: {})
            for _ in 0..<5 {
                let response = try await app.send(.GET, "ready")
                #expect(response.status == .ok)
            }
        }
    }
}

extension DatabaseIntegrationTests {
    @Suite("Readiness against real services")
    struct ReadinessIntegrationTests {
        @Test("Ready with the real database and Redis; unavailable when the database can't be reached")
        func realServices() async throws {
            try await withApp { app in
                var overrides: [String: String] = [:]
                if let redis = TestRedis.url {
                    overrides["REDIS_URL"] = redis
                }
                try await configure(app, reader: TestDatabase.reader(overrides))
                try await app.asyncBoot()
                let ready = try await app.send(.GET, "ready")
                #expect(ready.status == .ok)
            }
            // A "stopped" database: nothing listens on port 1.
            try await withApp { app in
                try await configure(
                    app,
                    reader: TestDatabase.reader(["DATABASE_URL": "postgres://repohub:x@127.0.0.1:1/repohub_test"])
                )
                let down = try await app.send(.GET, "ready")
                #expect(down.status == .serviceUnavailable)
                #expect(down.body.string.contains("down"))
            }
        }
    }
}
