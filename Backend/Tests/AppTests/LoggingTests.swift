import Foundation
import Logging
import Testing
import Vapor
import VaporTesting

@testable import App

/// Collects log lines written by a handler.
private final class LineSink: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var lines: [String] { lock.withLock { stored } }

    func append(_ line: String) {
        lock.withLock { stored.append(line) }
    }

    /// The last line, decoded.
    func last() throws -> [String: Any] {
        let line = try #require(lines.last)
        return try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }
}

@Suite("Structured logging")
struct LoggingTests {
    private func logger(_ sink: LineSink, level: Logger.Level = .info, provider: Logger.MetadataProvider? = nil)
        -> Logger
    {
        Logger(label: "test") { label in
            JSONLogHandler(label: label, level: level, metadataProvider: provider) { sink.append($0) }
        }
    }

    @Test("Each line is one JSON object with timestamp, level, message, and a top-level request_id")
    func jsonLine() throws {
        let sink = LineSink()
        var log = logger(sink)
        log[metadataKey: "request-id"] = "req-123"
        log.info("Signed in", metadata: ["user": "octocat", "devices": .array(["a", "b"])])

        #expect(sink.lines.count == 1 && !sink.lines[0].contains("\n"))
        let object = try sink.last()
        #expect(object["level"] as? String == "info")
        #expect(object["message"] as? String == "Signed in")
        #expect(object["request_id"] as? String == "req-123")
        #expect(object["label"] as? String == "test")
        let timestamp = try #require(object["timestamp"] as? String)
        #expect(
            (try? Date(timestamp, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)))
                != nil
        )
        let metadata = try #require(object["metadata"] as? [String: Any])
        #expect(metadata["user"] as? String == "octocat")
        #expect(metadata["devices"] as? [String] == ["a", "b"])
        #expect(metadata["request-id"] == nil)
        #expect(object["file"] == nil, "Source locations are only added for warnings and above")
    }

    @Test("Messages below the level are dropped; warnings include the source location")
    func levels() throws {
        let sink = LineSink()
        let log = logger(sink, level: .notice)
        log.info("hidden")
        log.debug("hidden")
        log.warning("Slow request")

        #expect(sink.lines.count == 1)
        let object = try sink.last()
        #expect(object["level"] as? String == "warning")
        #expect((object["file"] as? String)?.contains("LoggingTests.swift:") == true)
    }

    @Test("Call-site metadata overrides the logger's, which overrides the provider's")
    func metadataPrecedence() throws {
        let sink = LineSink()
        let provider = Logger.MetadataProvider { ["key": "provider", "trace": "t-1"] }
        var log = logger(sink, provider: provider)
        log[metadataKey: "key"] = "logger"
        log.info("x", metadata: ["key": "call"])

        let metadata = try #require(try sink.last()["metadata"] as? [String: Any])
        #expect(metadata["key"] as? String == "call")
        #expect(metadata["trace"] as? String == "t-1")
    }

    @Test("Quotes, newlines, and Unicode in messages stay valid JSON on one line")
    func escaping() throws {
        let sink = LineSink()
        logger(sink).error("Bad \"input\"\nnext line — ünïcode")
        #expect(sink.lines.count == 1)
        #expect(try sink.last()["message"] as? String == "Bad \"input\"\nnext line — ünïcode")
    }

    @Test("LOG_FORMAT defaults to JSON in production and text elsewhere, and rejects other values")
    func format() throws {
        #expect(try LogFormat.detect(environment: .production, value: nil) == .json)
        #expect(try LogFormat.detect(environment: .development, value: nil) == .text)
        #expect(try LogFormat.detect(environment: .development, value: " JSON ") == .json)
        #expect(try LogFormat.detect(environment: .production, value: "text") == .text)
        #expect(throws: ConfigurationError.invalid(key: "LOG_FORMAT", expected: "json or text")) {
            try LogFormat.detect(environment: .production, value: "xml")
        }
    }

    @Test("Responses carry the request ID, including errors, and it's reused from X-Request-Id")
    func requestIDs() async throws {
        try await withApp { app in
            try await configure(app, reader: TestDatabase.reader())
            let given = try await app.send(.GET, "health", headers: ["X-Request-Id": "from-client-1"])
            #expect(given.headers.first(name: .xRequestId) == "from-client-1")

            let generated = try await app.send(.GET, "health")
            let id = try #require(generated.headers.first(name: .xRequestId))
            #expect(UUID(uuidString: id) != nil)

            let failed = try await app.send(.GET, "me")
            #expect(failed.status == .unauthorized)
            #expect(failed.headers.contains(name: .xRequestId))
        }
    }

    @Test("Code without a Request logs with the current request's ID")
    func contextLogger() async throws {
        try await withApp { app in
            try await configure(app, reader: TestDatabase.reader())
            // Async, like the generated OpenAPI handlers (task-locals don't cross into synchronous routes).
            app.get("test-context") { _ async in
                app.contextLogger[metadataKey: "request-id"]?.description ?? "none"
            }
            let response = try await app.send(.GET, "test-context", headers: ["X-Request-Id": "trace-42"])
            #expect(response.body.string == "trace-42")
            #expect(app.contextLogger[metadataKey: "request-id"] == nil, "Outside a request, the app logger is used")
        }
    }
}
