import Foundation
import Logging
import Vapor

/// An unhandled error or 5xx response, with what's needed to find its cause.
struct ErrorReport: Sendable {
    var eventID = UUID()
    var timestamp = Date()
    /// The error's type, such as `PSQLError`.
    var type: String
    /// A description; never contains secrets (errors don't carry credentials).
    var message: String
    var status: UInt
    var method: String
    /// The path without the query string, which may contain tokens.
    var path: String
    var requestID: String
    /// Where the error was caught, innermost first.
    var stack: [String]
}

/// Receives reports of unhandled errors: Sentry (#51) and email alerts (#52).
protocol ErrorReporting: Sendable {
    func report(_ report: ErrorReport) async
}

/// Sends every report to each reporter.
struct ErrorReporters: ErrorReporting {
    var reporters: [any ErrorReporting]

    func report(_ report: ErrorReport) async {
        for reporter in reporters {
            await reporter.report(report)
        }
    }
}

/// Reports errors that escape route handlers, and 5xx responses, before
/// Vapor's `ErrorMiddleware` turns them into a response. Client errors (4xx)
/// aren't reported.
struct ErrorReportingMiddleware: AsyncMiddleware {
    let reporter: any ErrorReporting

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        do {
            let response = try await next.respond(to: request)
            if response.status.code >= 500 {
                await report(nil, status: response.status, request: request)
            }
            return response
        } catch {
            let status = (error as? any AbortError)?.status ?? .internalServerError
            if status.code >= 500 {
                await report(error, status: status, request: request)
            }
            throw error
        }
    }

    private func report(_ error: (any Error)?, status: HTTPResponseStatus, request: Request) async {
        await reporter.report(
            ErrorReport(
                type: error.map { String(reflecting: type(of: $0)) } ?? "HTTP \(status.code)",
                message: error.map { String(describing: $0) } ?? status.reasonPhrase,
                status: status.code,
                method: request.method.rawValue,
                path: request.url.path,
                requestID: request.id,
                stack: Thread.callStackSymbols
            )
        )
    }
}

/// A parsed Sentry DSN: `https://<public key>@<host>/<project id>`.
struct SentryDSN: Equatable, Sendable {
    var publicKey: String
    var host: String
    var projectID: String

    init?(_ string: String) {
        guard let url = URLComponents(string: string), let key = url.user, !key.isEmpty, let host = url.host,
            url.scheme == "https"
        else {
            return nil
        }
        let project = url.path.split(separator: "/").last.map(String.init) ?? ""
        guard !project.isEmpty else {
            return nil
        }
        publicKey = key
        self.host = host + (url.port.map { ":\($0)" } ?? "")
        projectID = project
    }

    /// Where events are sent.
    var envelopeURL: String {
        "https://\(host)/api/\(projectID)/envelope/"
    }
}

/// Sends reports to Sentry with its envelope API. There's no Sentry SDK for
/// server-side Swift on Linux, and the envelope format is small and stable.
struct SentryReporter: ErrorReporting {
    let dsn: SentryDSN
    let environment: String
    let release: String
    let client: any Client
    var logger = Logger(label: "com.lquainta.RepoHub.Sentry")

    func report(_ report: ErrorReport) async {
        do {
            var headers = HTTPHeaders()
            headers.replaceOrAdd(name: .contentType, value: "application/x-sentry-envelope")
            headers.replaceOrAdd(
                name: "X-Sentry-Auth",
                value: "Sentry sentry_version=7, sentry_client=repohub-backend/\(release), sentry_key=\(dsn.publicKey)"
            )
            let response = try await client.post(URI(string: dsn.envelopeURL), headers: headers) { request in
                request.body = ByteBuffer(bytes: try envelope(for: report))
            }
            if response.status.code >= 300 {
                logger.warning("Sentry rejected an event", metadata: ["status": "\(response.status.code)"])
            }
        } catch {
            // Reporting must never cause another failure.
            logger.warning("Could not send an event to Sentry: \(error)")
        }
    }

    /// The envelope: a header line, an item header line, and the event.
    func envelope(for report: ErrorReport) throws -> Data {
        let id = report.eventID.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        let event = SentryEvent(
            eventID: id,
            timestamp: report.timestamp,
            level: "error",
            platform: "other",
            logger: "vapor",
            release: release,
            environment: environment,
            transaction: "\(report.method) \(report.path)",
            tags: ["request_id": report.requestID, "status": "\(report.status)"],
            request: .init(method: report.method, url: report.path),
            exception: .init(values: [
                .init(
                    type: report.type,
                    value: report.message,
                    // Sentry wants the outermost frame first.
                    stacktrace: .init(frames: report.stack.reversed().map { .init(function: $0) })
                )
            ])
        )
        var data = Data()
        data.append(try encoder.encode(["event_id": id]))
        data.append(0x0A)
        data.append(try encoder.encode(["type": "event"]))
        data.append(0x0A)
        data.append(try encoder.encode(event))
        data.append(0x0A)
        return data
    }
}

/// The parts of a Sentry event RepoHub sends.
struct SentryEvent: Encodable {
    struct Request: Encodable {
        var method: String
        var url: String
    }

    struct Frame: Encodable {
        var function: String
    }

    struct Stacktrace: Encodable {
        var frames: [Frame]
    }

    struct Exception: Encodable {
        var type: String
        var value: String
        var stacktrace: Stacktrace
    }

    struct Exceptions: Encodable {
        var values: [Exception]
    }

    var eventID: String
    var timestamp: Date
    var level: String
    var platform: String
    var logger: String
    var release: String
    var environment: String
    var transaction: String
    var tags: [String: String]
    var request: Request
    var exception: Exceptions

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case timestamp, level, platform, logger, release, environment, transaction, tags, request, exception
    }
}
