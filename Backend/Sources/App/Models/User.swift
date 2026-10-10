import Fluent
import Foundation

/// A person signed in with GitHub. See `docs/architecture/database.md`.
final class User: Model, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id) var id: UUID?
    /// GitHub's numeric user id; stable even if the login changes.
    @Field(key: "github_id") var githubID: Int64
    @Field(key: "login") var login: String
    @OptionalField(key: "name") var name: String?
    @OptionalField(key: "avatar_url") var avatarURL: String?
    /// The GitHub OAuth token, encrypted at rest (#49). Never log this.
    @Field(key: "github_token_ciphertext") var githubTokenCiphertext: Data
    /// Space-separated scopes granted to the token.
    @Field(key: "github_token_scopes") var githubTokenScopes: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    @Children(for: \.$user) var devices: [Device]
    @Children(for: \.$user) var workspaces: [Workspace]

    init() {}

    init(
        id: UUID? = nil,
        githubID: Int64,
        login: String,
        name: String? = nil,
        avatarURL: String? = nil,
        githubTokenCiphertext: Data,
        githubTokenScopes: String
    ) {
        self.id = id
        self.githubID = githubID
        self.login = login
        self.name = name
        self.avatarURL = avatarURL
        self.githubTokenCiphertext = githubTokenCiphertext
        self.githubTokenScopes = githubTokenScopes
    }
}
