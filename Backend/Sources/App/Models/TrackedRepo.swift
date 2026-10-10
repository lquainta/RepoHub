import Fluent
import Foundation

/// A repository in a workspace, identified by its normalized remote URL
/// because local paths differ between Macs.
final class TrackedRepo: Model, @unchecked Sendable {
    static let schema = "tracked_repos"

    @ID(key: .id) var id: UUID?
    @Parent(key: "workspace_id") var workspace: Workspace
    @Field(key: "remote_url") var remoteURL: String
    @OptionalField(key: "github_owner") var githubOwner: String?
    @OptionalField(key: "github_name") var githubName: String?
    @Field(key: "display_name") var displayName: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Field(key: "updated_at") var updatedAt: Date
    @OptionalField(key: "deleted_at") var deletedAt: Date?

    @Children(for: \.$trackedRepo) var snapshots: [RepoSnapshot]

    init() {}

    init(
        id: UUID? = nil,
        workspaceID: Workspace.IDValue,
        remoteURL: String,
        githubOwner: String? = nil,
        githubName: String? = nil,
        displayName: String,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.$workspace.id = workspaceID
        self.remoteURL = remoteURL
        self.githubOwner = githubOwner
        self.githubName = githubName
        self.displayName = displayName
        self.updatedAt = updatedAt
    }
}
