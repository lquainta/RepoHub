import Vapor

extension Application {
    /// Reports unhandled errors to Sentry when `SENTRY_DSN` is set, and adds
    /// `GET /debug/error` when `DEBUG_TOKEN` is set.
    func configureErrorReporting(_ config: AppConfig) {
        var reporters: [any ErrorReporting] = []
        if let dsn = config.sentryDSN {
            reporters.append(
                SentryReporter(dsn: dsn, environment: environment.name, release: config.buildCommit, client: client)
            )
        } else {
            logger.notice("SENTRY_DSN is not set; unhandled errors are only logged")
        }
        if !reporters.isEmpty {
            // After Vapor's ErrorMiddleware, so errors pass through here first.
            middleware.use(ErrorReportingMiddleware(reporter: ErrorReporters(reporters: reporters)))
        }
        if let token = config.debugToken {
            // Not in the OpenAPI spec: it exists only to check error reporting
            // end to end, and 404s without the token.
            get("debug", "error") { request -> Response in
                guard request.headers.first(name: "X-Debug-Token") == token else {
                    throw Abort(.notFound)
                }
                throw DebugError.forced
            }
        }
    }
}

/// The error `GET /debug/error` throws.
enum DebugError: Error, CustomStringConvertible {
    case forced

    var description: String {
        "Forced error from GET /debug/error, to check error reporting"
    }
}
