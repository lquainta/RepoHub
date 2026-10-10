import Fluent
import Foundation

/// A GitHub webhook delivery (#77), kept for idempotency and debugging.
final class WebhookEvent: Model, @unchecked Sendable {
    static let schema = "webhook_events"

    @ID(key: .id) var id: UUID?
    /// `X-GitHub-Delivery`; unique, so a redelivery is ignored.
    @Field(key: "delivery_id") var deliveryID: String
    /// `X-GitHub-Event`, such as `check_run`.
    @Field(key: "event") var event: String
    @OptionalField(key: "action") var action: String?
    /// `owner/name`.
    @Field(key: "repo_full_name") var repoFullName: String
    /// The verified payload, stored as `jsonb`.
    @Field(key: "payload") var payload: JSONValue
    @Field(key: "received_at") var receivedAt: Date
    @OptionalField(key: "processed_at") var processedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        deliveryID: String,
        event: String,
        action: String? = nil,
        repoFullName: String,
        payload: JSONValue,
        receivedAt: Date = .now
    ) {
        self.id = id
        self.deliveryID = deliveryID
        self.event = event
        self.action = action
        self.repoFullName = repoFullName
        self.payload = payload
        self.receivedAt = receivedAt
    }
}
