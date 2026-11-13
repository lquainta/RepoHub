import Foundation
import Testing
import Vapor

@testable import App

/// Records emails instead of sending them.
actor RecordingMailer: Mailer {
    struct Email: Equatable {
        var recipient: String
        var subject: String
        var text: String
    }

    private(set) var sent: [Email] = []
    var failure: (any Error)?

    func fail(with error: any Error) {
        failure = error
    }

    func send(to recipient: String, subject: String, text: String) async throws {
        if let failure {
            throw failure
        }
        sent.append(Email(recipient: recipient, subject: subject, text: text))
    }
}

/// A cache that's down.
private struct DownCacheStore: CacheStore {
    struct Down: Error {}
    func get<Value: Decodable & Sendable>(_ key: String, as type: Value.Type) async throws -> Value? { throw Down() }
    func set<Value: Encodable & Sendable>(_ key: String, to value: Value, expiresIn seconds: Int) async throws {
        throw Down()
    }
    func delete(_ keys: [String]) async throws { throw Down() }
    func addToSet(_ key: String, member: String, expiresIn seconds: Int) async throws { throw Down() }
    func members(ofSet key: String) async throws -> [String] { throw Down() }
    func increment(_ key: String, expiresIn seconds: Int) async throws -> Int { throw Down() }
    func ping() async throws { throw Down() }
}

@Suite("Email alerts")
struct EmailAlerterTests {
    private func report(_ path: String = "/github/status", type: String = "PSQLError") -> ErrorReport {
        ErrorReport(
            type: type,
            message: "connection refused",
            status: 500,
            method: "POST",
            path: path,
            requestID: "req-42",
            stack: []
        )
    }

    private func alerter(_ mailer: RecordingMailer, store: any CacheStore = InMemoryCacheStore()) -> EmailAlerter {
        EmailAlerter(mailer: mailer, recipient: "me@example.com", store: store, environment: "production")
    }

    @Test("An unhandled error emails the maintainer with what's needed to find it")
    func emails() async throws {
        let mailer = RecordingMailer()

        await alerter(mailer).report(report())

        let email = try #require(await mailer.sent.first)
        #expect(email.recipient == "me@example.com")
        #expect(email.subject == "[RepoHub production] 500 on POST /github/status")
        #expect(email.text.contains("PSQLError") && email.text.contains("req-42"))
    }

    @Test("The same error is emailed once per window; a different error still is")
    func throttlesPerError() async throws {
        let mailer = RecordingMailer()
        let alerter = alerter(mailer)

        for _ in 0..<5 {
            await alerter.report(report())
        }
        await alerter.report(report("/workspace"))

        #expect(await mailer.sent.map(\.subject).count == 2)
    }

    @Test("No more than 10 alerts an hour, whatever fails")
    func hourlyLimit() async throws {
        let mailer = RecordingMailer()
        let alerter = alerter(mailer)

        for index in 0..<25 {
            await alerter.report(report("/path/\(index)"))
        }

        #expect(await mailer.sent.count == EmailAlerter.hourlyLimit)
    }

    @Test("When the cache is down, alerts are still sent")
    func cacheDown() async throws {
        let mailer = RecordingMailer()

        await alerter(mailer, store: DownCacheStore()).report(report())

        #expect(await mailer.sent.count == 1)
    }

    @Test("A failing mailer doesn't throw")
    func mailerFails() async {
        let mailer = RecordingMailer()
        await mailer.fail(with: Abort(.badGateway))

        await alerter(mailer).report(report())

        #expect(await mailer.sent.isEmpty)
    }

    @Test("Alerts are on only with both EMAIL_API_KEY and ALERT_EMAIL_TO; a bad address fails startup")
    func configuration() throws {
        #expect(try AppConfig(reader: TestDatabase.reader(["EMAIL_API_KEY": "re_x"])).emailAlerts == nil)
        let config = try AppConfig(reader: TestDatabase.reader(["EMAIL_API_KEY": "re_x", "ALERT_EMAIL_TO": "a@b.c"]))
        #expect(config.emailAlerts?.recipient == "a@b.c")
        #expect(throws: ConfigurationError.self) {
            try AppConfig(reader: TestDatabase.reader(["EMAIL_API_KEY": "re_x", "ALERT_EMAIL_TO": "nobody"]))
        }
    }
}
