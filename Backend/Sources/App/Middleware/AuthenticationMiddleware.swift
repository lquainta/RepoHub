import Foundation
import HTTPTypes
import OpenAPIRuntime

/// The authenticated user for the current request, set by ``AuthenticationMiddleware``.
enum RequestContext {
    @TaskLocal static var user: AuthenticatedUser?
}

/// Requires a valid access token for every operation except those the spec
/// marks `security: []`, and applies the per-user rate limit.
///
/// It runs inside the generated server, so it sees each request's
/// `operationID`, and handlers read the user from ``RequestContext/user``.
struct AuthenticationMiddleware: ServerMiddleware {
    /// Operations with `security: []` in openapi/openapi.yaml. A test keeps this in sync with the spec.
    static let publicOperations: Set<String> = [
        "getHealth", "startDeviceSignIn", "pollDeviceSignIn", "refreshSession", "receiveGitHubWebhook",
    ]

    let authenticate: @Sendable (String) async throws -> AuthenticatedUser?
    let limiter: RateLimiter
    let limitPerMinute: Int

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        metadata: ServerRequestMetadata,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, ServerRequestMetadata) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        if Self.publicOperations.contains(operationID) {
            return try await next(request, body, metadata)
        }
        guard let header = request.headerFields[.authorization], header.lowercased().hasPrefix("bearer "),
            let user = try await authenticate(String(header.dropFirst("bearer ".count)))
        else {
            return Self.error(
                .unauthorized,
                "Sign in again: the access token is missing, invalid, or expired.",
                extraHeaders: [
                    .wwwAuthenticate: "Bearer"
                ]
            )
        }
        if case .limited(let retryAfter) = await limiter.check("user:\(user.userID)", limit: limitPerMinute) {
            return Self.error(
                .tooManyRequests,
                "Too many requests. Try again in \(retryAfter) seconds.",
                extraHeaders: [
                    .retryAfter: "\(retryAfter)"
                ]
            )
        }
        return try await RequestContext.$user.withValue(user) {
            try await next(request, body, metadata)
        }
    }

    private static func error(_ status: HTTPResponse.Status, _ reason: String, extraHeaders: HTTPFields) -> (
        HTTPResponse, HTTPBody?
    ) {
        var response = HTTPResponse(status: status)
        response.headerFields = extraHeaders
        response.headerFields[.contentType] = "application/json; charset=utf-8"
        let json = (try? JSONEncoder().encode(ErrorResponse(error: true, reason: reason))) ?? Data()
        return (response, HTTPBody(json))
    }
}
