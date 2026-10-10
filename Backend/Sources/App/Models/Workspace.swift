import Fluent
import Foundation

/// Preferences synced between a user's Macs.
struct WorkspaceSettings: Codable, Equatable, Sendable {
    /// Days without commits before a branch counts as stale; `nil` uses the app's default.
    var staleBranchDays: Int?

    init(staleBranchDays: Int? = nil) {
        self.staleBranchDays = staleBranchDays
    }
}

/// A user's synced configuration: repositories, groups, and settings.
///
/// `updatedAt` is the client's last-write-wins clock, not a server timestamp,
/// and `deletedAt` marks a deletion so other Macs learn about it (#80).
final class Workspace: Model, @unchecked Sendable {
    static let schema = "workspaces"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @Field(key: "name") var name: String
    @Field(key: "settings") var settings: WorkspaceSettings
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Field(key: "updated_at") var updatedAt: Date
    @OptionalField(key: "deleted_at") var deletedAt: Date?

    @Children(for: \.$workspace) var repositories: [TrackedRepo]
    @Children(for: \.$workspace) var groups: [RepoGroup]

    init() {}

    init(
        id: UUID? = nil,
        userID: User.IDValue,
        name: String,
        settings: WorkspaceSettings = WorkspaceSettings(),
        updatedAt: Date = .now
    ) {
        self.id = id
        self.$user.id = userID
        self.name = name
        self.settings = settings
        self.updatedAt = updatedAt
    }
}
