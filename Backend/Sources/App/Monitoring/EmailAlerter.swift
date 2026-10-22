import Foundation
import Logging
import Vapor

/// Sends an email. ``ResendMailer`` is the real one; tests record messages.
protocol Mailer: Sendable {
    func send(to recipient: String, subject: String, text: String) async throws
}

/// A Resend `POST /emails` body.
struct ResendMessage: Content {
    var from: String
    var recipients: [String]
    var subject: String
    var text: String

    enum CodingKeys: String, CodingKey {
        case from, subject, text
        case recipients = "to"
    }
}

/// Sends email with the [Resend](https://resend.com) API.
struct ResendMailer: Mailer {
    let apiKey: String
    let client: any Client
    /// Resend's shared sender, which works without a verified domain (it can
    /// only email the account's owner, who is the maintainer).
    var from = "RepoHub Alerts <onboarding@resend.dev>"

    func send(to recipient: String, subject: String, text: String) async throws {
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: apiKey)
        let response = try await client.post(URI(string: "https://api.resend.com/emails"), headers: headers) {
            try $0.content.encode(ResendMessage(from: from, recipients: [recipient], subject: subject, text: text))
        }
        guard (200..<300).contains(response.status.code) else {
            throw Abort(.badGateway, reason: "Resend answered \(response.status.code)")
        }
    }
}

/// Emails the maintainer about unhandled errors (#52), throttled so a burst
/// of failures sends a few emails, not hundreds:
/// - one email per kind of error (type, method, and path) per ``window``;
/// - at most ``hourlyLimit`` emails per hour in total.
///
/// Throttling uses the shared cache, so it holds across restarts. If the cache
/// is down, alerts are sent anyway: an outage is when they matter most.
struct EmailAlerter: ErrorReporting {
    static let window = 900
    static let hourlyLimit = 10

    let mailer: any Mailer
    let recipient: String
    let store: any CacheStore
    let environment: String
    var logger = Logger(label: "com.lquainta.RepoHub.EmailAlerter")

    func report(_ report: ErrorReport) async {
        let fingerprint = "\(report.type) \(report.method) \(report.path)"
        guard await allowed(fingerprint) else {
            logger.info("Error alert throttled", metadata: ["fingerprint": "\(fingerprint)"])
            return
        }
        let subject = "[RepoHub \(environment)] \(report.status) on \(report.method) \(report.path)"
        let text = """
            An unhandled error reached a user.

            Error:      \(report.type)
            Message:    \(report.message)
            Request:    \(report.method) \(report.path) → \(report.status)
            Request ID: \(report.requestID)
            Time:       \(ISO8601DateFormatter().string(from: report.timestamp))

            Find it in the logs with `fly logs --app repohub-backend | grep \(report.requestID)`, \
            or in Sentry (repohub-backend). Further alerts for the same error are \
            muted for \(Self.window / 60) minutes.
            """
        do {
            try await mailer.send(to: recipient, subject: subject, text: text)
        } catch {
            logger.warning("Could not send an error alert: \(error)")
        }
    }

    private func allowed(_ fingerprint: String) async -> Bool {
        do {
            let key = "alert:v1:" + fingerprint.lowercased().filter { !$0.isWhitespace }
            guard try await store.increment(key, expiresIn: Self.window) == 1 else {
                return false
            }
            return try await store.increment("alert:v1:hourly", expiresIn: 3_600) <= Self.hourlyLimit
        } catch {
            return true
        }
    }
}
