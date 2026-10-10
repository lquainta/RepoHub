import Vapor

/// Rejects GitHub webhook deliveries whose `X-Hub-Signature-256` doesn't
/// match the raw body, before the payload is parsed.
struct WebhookSignatureMiddleware: AsyncMiddleware {
    static let path = "/webhooks/github"
    /// `nil` when `GITHUB_WEBHOOK_SECRET` isn't configured: every delivery is rejected.
    let secret: String?

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard request.method == .POST, request.url.path == Self.path else {
            return try await next.respond(to: request)
        }
        guard let secret else {
            throw Abort(.serviceUnavailable, reason: "Webhooks aren't configured on this server.")
        }
        let body = try await request.body.collect(max: BodyLimitMiddleware.webhookLimit.value).get()
        let bytes = body.map { Data($0.readableBytesView) } ?? Data()
        guard WebhookSignature.isValid(request.headers.first(name: "X-Hub-Signature-256"), body: bytes, secret: secret)
        else {
            request.logger.warning("Rejected webhook with an invalid signature")
            throw Abort(.unauthorized, reason: "Invalid webhook signature.")
        }
        return try await next.respond(to: request)
    }
}
