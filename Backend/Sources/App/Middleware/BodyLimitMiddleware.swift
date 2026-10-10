import Vapor

/// Rejects request bodies over the limit with `413 Payload Too Large`.
///
/// The OpenAPI routes stream their bodies, so Vapor's per-route
/// `maxBodySize` doesn't apply. This middleware collects bodies up to the
/// limit first. Later middleware (such as the webhook signature check) and
/// the handlers read the collected bytes.
struct BodyLimitMiddleware: AsyncMiddleware {
    /// Most requests are small JSON documents.
    static let defaultLimit: ByteCount = "64kb"
    /// GitHub webhook payloads can be larger (check runs with long output).
    static let webhookLimit: ByteCount = "1mb"

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard [.POST, .PUT, .PATCH].contains(request.method) else {
            return try await next.respond(to: request)
        }
        let limit = request.url.path.hasPrefix("/webhooks/") ? Self.webhookLimit : Self.defaultLimit
        let tooLarge = Abort(.payloadTooLarge, reason: "Request bodies are limited to \(limit.value / 1_024) KB.")
        if let length = request.headers.first(name: .contentLength).flatMap(Int.init), length > limit.value {
            throw tooLarge
        }
        if let collected = request.body.data {
            // Already buffered (for example, a small body that arrived in one piece).
            guard collected.readableBytes <= limit.value else {
                throw tooLarge
            }
        } else {
            _ = try await request.body.collect(max: limit.value).get()
        }
        return try await next.respond(to: request)
    }
}
