import Fluent
import Foundation

/// A signed-in copy of the app. Only the refresh token's hash is stored.
final class Device: Model, @unchecked Sendable {
    static let schema = "devices"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @Field(key: "name") var name: String
    /// SHA-256 of the current refresh token; rotated on every refresh.
    @Field(key: "refresh_token_hash") var refreshTokenHash: Data
    @Field(key: "refresh_expires_at") var refreshExpiresAt: Date
    @Field(key: "last_seen_at") var lastSeenAt: Date
    /// Set when the device signs out; a revoked device can't refresh.
    @OptionalField(key: "revoked_at") var revokedAt: Date?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: User.IDValue,
        name: String,
        refreshTokenHash: Data,
        refreshExpiresAt: Date,
        lastSeenAt: Date = .now
    ) {
        self.id = id
        self.$user.id = userID
        self.name = name
        self.refreshTokenHash = refreshTokenHash
        self.refreshExpiresAt = refreshExpiresAt
        self.lastSeenAt = lastSeenAt
    }
}
