import Logging
import Vapor

/// The current request's logger, which carries its `request-id`.
enum RequestLog {
    @TaskLocal static var logger: Logger?
}

/// Makes each request's logger (with its `request-id`) available to code that
/// has no `Request`, such as the generated OpenAPI handlers and the services
/// they call, and returns the ID in `X-Request-Id` so a user's report can be
/// matched to the logs.
struct RequestIDMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let response = try await RequestLog.$logger.withValue(request.logger) {
            try await next.respond(to: request)
        }
        response.headers.replaceOrAdd(name: .xRequestId, value: request.id)
        return response
    }
}

extension Application {
    /// The current request's logger when there is one, otherwise the app's.
    var contextLogger: Logger {
        RequestLog.logger ?? logger
    }
}
