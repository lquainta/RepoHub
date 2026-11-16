import Foundation
import Logging
import Testing
import Vapor
import VaporTesting

@testable import App

/// Answers every request with one status and records what was sent.
private final class RecordingClient: Client, @unchecked Sendable {
    let eventLoop: any EventLoop
    private let status: HTTPStatus
    private let lock = NSLock()
    private var sent: [ClientRequest] = []
    var requests: [ClientRequest] { lock.withLock { sent } }

    init(eventLoop: any EventLoop, status: HTTPStatus) {
        self.eventLoop = eventLoop
        self.status = status
    }

    func send(_ request: ClientRequest) -> EventLoopFuture<ClientResponse> {
        lock.withLock { sent.append(request) }
        return eventLoop.makeSucceededFuture(ClientResponse(status: status))
    }

    func delegating(to eventLoop: any EventLoop) -> any Client { self }
}

/// A client whose requests never reach the server.
private struct OfflineClient: Client {
    let eventLoop: any EventLoop

    func send(_ request: ClientRequest) -> EventLoopFuture<ClientResponse> {
        eventLoop.makeFailedFuture(Abort(.serviceUnavailable))
    }

    func delegating(to eventLoop: any EventLoop) -> any Client { self }
}

private actor CountingReporter: ErrorReporting {
    private(set) var count = 0
    func report(_ report: ErrorReport) async { count += 1 }
}

private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var all: [String] { lock.withLock { stored } }
    func append(_ line: String) { lock.withLock { stored.append(line) } }
}

/// How error reports leave the server: Sentry's envelope API and Resend's email API.
@Suite("Error report transports")
struct ErrorTransportTests {
    private let report = ErrorReport(
        type: "PSQLError",
        message: "connection refused",
        status: 500,
        method: "POST",
        path: "/github/status",
        requestID: "req-42",
        stack: []
    )

    private func sentry(_ client: any Client, logTo lines: Lines) throws -> SentryReporter {
        var reporter = SentryReporter(
            dsn: try #require(SentryDSN("https://key123@o1.ingest.us.sentry.io/42")),
            environment: "testing",
            release: "abc1234",
            client: client
        )
        reporter.logger = Logger(label: "test") { label in
            JSONLogHandler(label: label, level: .info, metadataProvider: nil) { lines.append($0) }
        }
        return reporter
    }

    @Test("Sentry gets the envelope at the project's URL, authenticated with the DSN's key")
    func sentrySends() async throws {
        try await withApp { app in
            let client = RecordingClient(eventLoop: app.eventLoopGroup.any(), status: .ok)
            let lines = Lines()
            try await sentry(client, logTo: lines).report(report)

            let request = try #require(client.requests.first)
            #expect(request.url.string == "https://o1.ingest.us.sentry.io/api/42/envelope/")
            #expect(request.headers.first(name: .contentType) == "application/x-sentry-envelope")
            let auth = try #require(request.headers.first(name: "X-Sentry-Auth"))
            #expect(auth.contains("sentry_key=key123") && auth.contains("repohub-backend/abc1234"))
            let body = try #require(request.body.map { String(buffer: $0) })
            #expect(body.contains("PSQLError") && body.contains("req-42"))
            #expect(lines.all.isEmpty)
        }
    }

    @Test("A rejected or unsendable Sentry event is logged and never throws")
    func sentryFailures() async throws {
        try await withApp { app in
            let lines = Lines()
            let rejecting = RecordingClient(eventLoop: app.eventLoopGroup.any(), status: .tooManyRequests)
            try await sentry(rejecting, logTo: lines).report(report)
            #expect(lines.all.last?.contains("Sentry rejected an event") == true)

            try await sentry(OfflineClient(eventLoop: app.eventLoopGroup.any()), logTo: lines).report(report)
            #expect(lines.all.last?.contains("Could not send an event to Sentry") == true)
            #expect(lines.all.count == 2)
        }
    }

    @Test("Resend gets the message with the API key; an error status throws")
    func resend() async throws {
        try await withApp { app in
            let client = RecordingClient(eventLoop: app.eventLoopGroup.any(), status: .ok)
            try await ResendMailer(apiKey: "re_key", client: client)
                .send(to: "me@example.com", subject: "RepoHub error", text: "details")

            let request = try #require(client.requests.first)
            #expect(request.url.string == "https://api.resend.com/emails")
            #expect(request.headers.bearerAuthorization?.token == "re_key")
            let message = try request.content.decode(ResendMessage.self)
            #expect(message.recipients == ["me@example.com"])
            #expect(message.subject == "RepoHub error" && message.text == "details")
            #expect(message.from.contains("onboarding@resend.dev"))

            let failing = RecordingClient(eventLoop: app.eventLoopGroup.any(), status: .forbidden)
            await #expect(throws: Abort.self) {
                try await ResendMailer(apiKey: "re_key", client: failing)
                    .send(to: "me@example.com", subject: "s", text: "t")
            }
        }
    }

    @Test("Every configured reporter receives each report")
    func fanOut() async {
        let first = CountingReporter()
        let second = CountingReporter()
        await ErrorReporters(reporters: [first, second]).report(report)
        #expect(await first.count == 1)
        #expect(await second.count == 1)
    }

    @Test("With SENTRY_DSN and email alerts configured, unhandled errors go to both")
    func configuredReporters() async throws {
        try await withApp { app in
            let client = RecordingClient(eventLoop: app.eventLoopGroup.any(), status: .ok)
            app.clients.use { _ in client }
            try await configure(
                app,
                reader: TestDatabase.reader([
                    "SENTRY_DSN": "https://key123@o1.ingest.us.sentry.io/42",
                    "EMAIL_API_KEY": "re_key",
                    "ALERT_EMAIL_TO": "me@example.com",
                    "DEBUG_TOKEN": String(repeating: "t", count: 32),
                ])
            )
            let response = try await app.send(
                .GET,
                "debug/error",
                headers: ["X-Debug-Token": String(repeating: "t", count: 32)]
            )
            #expect(response.status == .internalServerError)
            let hosts = Set(client.requests.compactMap(\.url.host))
            #expect(hosts == ["o1.ingest.us.sentry.io", "api.resend.com"])
        }
    }
}
