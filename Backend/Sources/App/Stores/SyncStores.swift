import Fluent
import Foundation

/// Workspaces, tracked repositories, and groups: the data synced between Macs (#80).
///
/// Writes are last-write-wins: an incoming change is applied only if its
/// `updatedAt` is later than the stored row's. Deletions are writes that set
/// `deletedAt`, so other Macs see them.
protocol SyncStore: Sendable {
    /// The user's default workspace, created on first use.
    func defaultWorkspace(userID: UUID) async throws -> Workspace

    /// Applies a repository change if it's newer; returns the stored row.
    func upsert(_ change: TrackedRepoChange, workspaceID: UUID) async throws -> TrackedRepo

    /// Applies a group change (including its members) if it's newer; returns the stored row.
    func upsert(_ change: RepoGroupChange, workspaceID: UUID) async throws -> RepoGroup
}

/// A repository change from a client.
struct TrackedRepoChange: Equatable, Sendable {
    var id: UUID
    var remoteURL: String
    var githubOwner: String?
    var githubName: String?
    var displayName: String
    var updatedAt: Date
    var deletedAt: Date?
}

/// A group change from a client, with its full member list.
struct RepoGroupChange: Equatable, Sendable {
    var id: UUID
    var name: String
    var sortOrder: Int
    var memberIDs: [UUID]
    var updatedAt: Date
    var deletedAt: Date?
}

struct FluentSyncStore: SyncStore {
    let database: any Database

    func defaultWorkspace(userID: UUID) async throws -> Workspace {
        if let existing = try await Workspace.query(on: database)
            .filter(\.$user.$id == userID)
            .filter(\.$deletedAt == nil)
            .sort(\.$createdAt)
            .first()
        {
            return existing
        }
        let workspace = Workspace(userID: userID, name: "Default")
        try await workspace.create(on: database)
        return workspace
    }

    func upsert(_ change: TrackedRepoChange, workspaceID: UUID) async throws -> TrackedRepo {
        if let existing = try await TrackedRepo.query(on: database)
            .filter(\.$id == change.id)
            .filter(\.$workspace.$id == workspaceID)
            .first()
        {
            guard change.updatedAt > existing.updatedAt else {
                return existing
            }
            apply(change, to: existing)
            try await existing.update(on: database)
            return existing
        }
        let repository = TrackedRepo(
            id: change.id,
            workspaceID: workspaceID,
            remoteURL: change.remoteURL,
            displayName: change.displayName
        )
        apply(change, to: repository)
        try await repository.create(on: database)
        return repository
    }

    func upsert(_ change: RepoGroupChange, workspaceID: UUID) async throws -> RepoGroup {
        try await database.transaction { database in
            let group: RepoGroup
            if let existing = try await RepoGroup.query(on: database)
                .filter(\.$id == change.id)
                .filter(\.$workspace.$id == workspaceID)
                .first()
            {
                guard change.updatedAt > existing.updatedAt else {
                    return existing
                }
                group = existing
            } else {
                group = RepoGroup(id: change.id, workspaceID: workspaceID, name: change.name)
            }
            group.name = change.name
            group.sortOrder = change.sortOrder
            group.updatedAt = change.updatedAt
            group.deletedAt = change.deletedAt
            group.syncedAt = .now
            try await group.save(on: database)

            let groupID = try group.requireID()
            try await RepoGroupMember.query(on: database).filter(\.$id.$group.$id == groupID).delete()
            for memberID in Set(change.memberIDs) {
                try await RepoGroupMember(groupID: groupID, trackedRepoID: memberID).create(on: database)
            }
            return group
        }
    }

    private func apply(_ change: TrackedRepoChange, to repository: TrackedRepo) {
        repository.remoteURL = change.remoteURL
        repository.githubOwner = change.githubOwner
        repository.githubName = change.githubName
        repository.displayName = change.displayName
        repository.updatedAt = change.updatedAt
        repository.deletedAt = change.deletedAt
    }
}
