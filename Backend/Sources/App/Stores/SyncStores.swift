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

    /// Repositories changed after `since` (all if `nil`), including deletions.
    func repositories(workspaceID: UUID, changedSince since: Date?) async throws -> [TrackedRepo]
    /// Applies a repository change if it's newer; returns the stored row.
    func upsert(_ change: TrackedRepoChange, workspaceID: UUID) async throws -> TrackedRepo
    /// Repositories with this GitHub owner and name, in every workspace (webhook fan-out).
    func repositories(githubOwner: String, name: String) async throws -> [TrackedRepo]

    /// Groups changed after `since` (all if `nil`), including deletions.
    func groups(workspaceID: UUID, changedSince since: Date?) async throws -> [RepoGroup]
    /// Applies a group change (including its members) if it's newer; returns the stored row.
    func upsert(_ change: RepoGroupChange, workspaceID: UUID) async throws -> RepoGroup
    /// The repository ids in a group.
    func members(groupID: UUID) async throws -> [UUID]
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

    func repositories(workspaceID: UUID, changedSince since: Date?) async throws -> [TrackedRepo] {
        var query = TrackedRepo.query(on: database).filter(\.$workspace.$id == workspaceID)
        if let since {
            query = query.filter(\.$updatedAt > since)
        }
        return try await query.sort(\.$updatedAt).all()
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

    func repositories(githubOwner: String, name: String) async throws -> [TrackedRepo] {
        try await TrackedRepo.query(on: database)
            .filter(\.$githubOwner == githubOwner)
            .filter(\.$githubName == name)
            .filter(\.$deletedAt == nil)
            .all()
    }

    func groups(workspaceID: UUID, changedSince since: Date?) async throws -> [RepoGroup] {
        var query = RepoGroup.query(on: database).filter(\.$workspace.$id == workspaceID)
        if let since {
            query = query.filter(\.$updatedAt > since)
        }
        return try await query.sort(\.$sortOrder).sort(\.$name).all()
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
            try await group.save(on: database)

            let groupID = try group.requireID()
            try await RepoGroupMember.query(on: database).filter(\.$id.$group.$id == groupID).delete()
            for memberID in Set(change.memberIDs) {
                try await RepoGroupMember(groupID: groupID, trackedRepoID: memberID).create(on: database)
            }
            return group
        }
    }

    func members(groupID: UUID) async throws -> [UUID] {
        try await RepoGroupMember.query(on: database)
            .filter(\.$id.$group.$id == groupID)
            .all()
            .compactMap { $0.id?.$trackedRepo.id }
            .sorted { $0.uuidString < $1.uuidString }
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
