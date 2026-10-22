import Foundation
import Testing
import Vapor
import VaporTesting

@testable import App

/// Records reports instead of sending them.
actor RecordingReporter: ErrorReporting {
    private(set) var reports: [ErrorReport] = []

    func report(_ report: ErrorReport) async {
        reports.append(report)
    }
}

/// The error a test route throws.
private struct Boom: Error, CustomStringConvertible {
    var description: String { "boom" }
}

@Suite("Error reporting")
struct ErrorReportingTests {
    private func withReportingApp(_ body: (Application, RecordingReporter) async throws -> Void) async throws {
        let reporter = RecordingReporter()
        try await withApp { app in
            app.middleware.use(ErrorReportingMiddleware(reporter: reporter))
            app.get("boom") { _ -> String in throw Boom() }
            app.get("unavailable") { _ -> Response in Response(status: .serviceUnavailable) }
            app.get("missing") { _ -> String in throw Abort(.notFound) }
            app.get("ok") { _ in "ok" }
            try await body(app, reporter)
        }
    }

    @Test("Unhandled errors and 5xx responses are reported with the request; 4xx and successes aren't")
    func reportsServerErrorsOnly() async throws {
        try await withReportingApp { app, reporter in
            let boom = try await app.send(.GET, "boom?token=secret")
            #expect(boom.status == .internalServerError)
            #expect(try await app.send(.GET, "unavailable").status == .serviceUnavailable)
            #expect(try await app.send(.GET, "missing").status == .notFound)
            #expect(try await app.send(.GET, "ok").status == .ok)

            let reports = await reporter.reports
            #expect(reports.map(\.status) == [500, 503])
            let first = try #require(reports.first)
            #expect(first.type.hasSuffix("Boom") && first.message == "boom")
            // The query string, which can hold tokens, is never reported.
            #expect(first.method == "GET" && first.path == "/boom")
            #expect(!first.requestID.isEmpty && !first.stack.isEmpty)
        }
    }

    @Test(
        "DSNs parse into key, host, and project; malformed ones don't",
        arguments: [
            ("https://abc123@o1.ingest.us.sentry.io/4507", "abc123", "o1.ingest.us.sentry.io", "4507"),
            ("https://k@sentry.example.edu:9000/42", "k", "sentry.example.edu:9000", "42"),
        ]
    )
    func dsn(string: String, key: String, host: String, project: String) throws {
        let dsn = try #require(SentryDSN(string))
        #expect(dsn.publicKey == key && dsn.host == host && dsn.projectID == project)
        #expect(dsn.envelopeURL == "https://\(host)/api/\(project)/envelope/")
    }

    @Test("Malformed DSNs are rejected", arguments: ["", "http://k@host/1", "https://host/1", "https://k@host/"])
    func badDSN(string: String) {
        #expect(SentryDSN(string) == nil)
    }

    @Test("The envelope has a header, an item header, and the event with its stack trace")
    func envelope() async throws {
        let dsn = try #require(SentryDSN("https://k@o1.ingest.sentry.io/1"))
        try await withApp { app in
            let reporter = SentryReporter(dsn: dsn, environment: "production", release: "abc1234", client: app.client)
            let report = ErrorReport(
                type: "PSQLError",
                message: "connection refused",
                status: 500,
                method: "POST",
                path: "/github/status",
                requestID: "req-1",
                stack: ["inner", "outer"]
            )

            let lines = try #require(String(bytes: try reporter.envelope(for: report), encoding: .utf8))
                .split(separator: "\n")
                .map(String.init)

            #expect(lines.count == 3)
            let id = report.eventID.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            #expect(lines[0] == #"{"event_id":"\#(id)"}"#)
            #expect(lines[1] == #"{"type":"event"}"#)
            let event = try JSONSerialization.jsonObject(with: Data(lines[2].utf8)) as? [String: Any]
            #expect(event?["release"] as? String == "abc1234")
            #expect(event?["environment"] as? String == "production")
            #expect(event?["transaction"] as? String == "POST /github/status")
            #expect((event?["tags"] as? [String: String])?["request_id"] == "req-1")
            let exception = (event?["exception"] as? [String: Any])?["values"] as? [[String: Any]]
            #expect(exception?.first?["type"] as? String == "PSQLError")
            let frames = (exception?.first?["stacktrace"] as? [String: Any])?["frames"] as? [[String: String]]
            #expect(frames?.map { $0["function"] } == ["outer", "inner"])
        }
    }

    @Test("GET /debug/error needs DEBUG_TOKEN set and sent; then it fails with a 500")
    func debugRoute() async throws {
        let token = String(repeating: "t", count: 32)
        try await withApp { app in
            try await configure(app, reader: TestDatabase.reader())
            #expect(try await app.send(.GET, "debug/error", headers: ["X-Debug-Token": token]).status == .notFound)
        }
        try await withApp { app in
            try await configure(app, reader: TestDatabase.reader(["DEBUG_TOKEN": token]))
            #expect(try await app.send(.GET, "debug/error").status == .notFound)
            let forced = try await app.send(.GET, "debug/error", headers: ["X-Debug-Token": token])
            #expect(forced.status == .internalServerError)
        }
    }

    @Test("A malformed SENTRY_DSN stops the app from starting")
    func invalidDSNFailsFast() {
        #expect(throws: ConfigurationError.self) {
            try AppConfig(reader: TestDatabase.reader(["SENTRY_DSN": "not a dsn"]))
        }
    }
}
