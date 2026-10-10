import Fluent
import Foundation

/// A user-defined group of repositories, such as "School" or "Work".
final class RepoGroup: Model, @unchecked Sendable {
    static let schema = "repo_groups"

    @ID(key: .id) var id: UUID?
    @Parent(key: "workspace_id") var workspace: Workspace
    @Field(key: "name") var name: String
    @Field(key: "sort_order") var sortOrder: Int
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Field(key: "updated_at") var updatedAt: Date
    @OptionalField(key: "deleted_at") var deletedAt: Date?

    init() {}

    init(id: UUID? = nil, workspaceID: Workspace.IDValue, name: String, sortOrder: Int = 0, updatedAt: Date = .now) {
        self.id = id
        self.$workspace.id = workspaceID
        self.name = name
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
    }
}

/// Membership of a repository in a group. The primary key is the pair.
final class RepoGroupMember: Model, @unchecked Sendable {
    static let schema = "repo_group_members"

    /// The `(group_id, tracked_repo_id)` primary key.
    final class IDValue: Fields, Hashable, @unchecked Sendable {
        @Parent(key: "group_id") var group: RepoGroup
        @Parent(key: "tracked_repo_id") var trackedRepo: TrackedRepo

        init() {}

        init(groupID: RepoGroup.IDValue, trackedRepoID: TrackedRepo.IDValue) {
            self.$group.id = groupID
            self.$trackedRepo.id = trackedRepoID
        }

        static func == (lhs: IDValue, rhs: IDValue) -> Bool {
            lhs.$group.id == rhs.$group.id && lhs.$trackedRepo.id == rhs.$trackedRepo.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine($group.id)
            hasher.combine($trackedRepo.id)
        }
    }

    @CompositeID var id: IDValue?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(groupID: RepoGroup.IDValue, trackedRepoID: TrackedRepo.IDValue) {
        self.id = IDValue(groupID: groupID, trackedRepoID: trackedRepoID)
    }
}
