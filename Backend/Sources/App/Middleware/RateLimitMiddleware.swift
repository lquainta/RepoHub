import Vapor

/// Limits requests per client IP; `/auth` has a stricter limit. `/health` and `/ready` are exempt (monitors poll them).
struct RateLimitMiddleware: AsyncMiddleware {
    let limiter: RateLimiter
    let limitPerMinute: Int
    let authLimitPerMinute: Int
    /// Read the client IP from Fly.io's `Fly-Client-IP` header. Only safe
    /// behind Fly's proxy; anywhere else a client could set it to dodge limits.
    let trustsProxyHeader: Bool

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let path = request.url.path
        guard path != "/health", path != "/ready" else {
            return try await next.respond(to: request)
        }
        let isAuth = path.hasPrefix("/auth/")
        let key = "\(isAuth ? "auth" : "ip"):\(clientIP(request))"
        let decision = await limiter.check(key, limit: isAuth ? authLimitPerMinute : limitPerMinute)
        if case .limited(let retryAfter) = decision {
            return try Self.tooManyRequests(retryAfter: retryAfter)
        }
        return try await next.respond(to: request)
    }

    private func clientIP(_ request: Request) -> String {
        if trustsProxyHeader, let address = request.headers.first(name: "Fly-Client-IP") {
            return address
        }
        return request.remoteAddress?.ipAddress ?? "unknown"
    }

    /// A `429` with `Retry-After`, in the API's error format.
    static func tooManyRequests(retryAfter: Int) throws -> Response {
        let response = Response(status: .tooManyRequests)
        response.headers.replaceOrAdd(name: .retryAfter, value: "\(retryAfter)")
        try response.content.encode(
            ErrorResponse(error: true, reason: "Too many requests. Try again in \(retryAfter) seconds.")
        )
        return response
    }
}

/// Vapor's error format, `{"error": true, "reason": "..."}`.
struct ErrorResponse: Content {
    let error: Bool
    let reason: String
}
