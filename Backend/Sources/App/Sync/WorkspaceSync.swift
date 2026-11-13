import Fluent
import Foundation

/// A group as Macs sync it: members are remote identities, not IDs.
struct SyncedGroupState: Equatable, Sendable {
    var id: UUID
    var name: String
    var sortOrder: Int
    /// Remote identities (`github.com/owner/repo`), sorted.
    var members: [String]
    var updatedAt: Date
    var deletedAt: Date?
}

/// Synced settings and the client time they were changed at.
struct SyncedSettingsState: Equatable, Sendable {
    var staleBranchDays: Int?
    var updatedAt: Date
}

/// Syncs a user's groups and settings between Macs (#80), last write wins
/// by each change's `updatedAt` (docs/architecture/database.md).
struct WorkspaceSync: Sendable {
    let database: any Database

    private var store: FluentSyncStore { FluentSyncStore(database: database) }

    /// The workspace's settings.
    func settings(userID: UUID) async throws -> SyncedSettingsState {
        let workspace = try await store.defaultWorkspace(userID: userID)
        return SyncedSettingsState(staleBranchDays: workspace.settings.staleBranchDays, updatedAt: workspace.updatedAt)
    }

    /// Stores `settings` if they're newer than the stored ones; returns what's stored.
    func update(_ settings: SyncedSettingsState, userID: UUID) async throws -> SyncedSettingsState {
        let workspace = try await store.defaultWorkspace(userID: userID)
        if settings.updatedAt > workspace.updatedAt {
            workspace.settings = WorkspaceSettings(staleBranchDays: settings.staleBranchDays)
            workspace.updatedAt = settings.updatedAt
            try await workspace.update(on: database)
        }
        return SyncedSettingsState(staleBranchDays: workspace.settings.staleBranchDays, updatedAt: workspace.updatedAt)
    }

    /// Groups the server stored after `since` (all if `nil`), including deleted ones.
    func groups(userID: UUID, since: Date?) async throws -> [SyncedGroupState] {
        let workspaceID = try await store.defaultWorkspace(userID: userID).requireID()
        var query = RepoGroup.query(on: database).filter(\.$workspace.$id == workspaceID)
        if let since {
            query = query.filter(\.$syncedAt > since)
        }
        var states: [SyncedGroupState] = []
        for group in try await query.sort(\.$sortOrder).sort(\.$name).all() {
            states.append(try await state(of: group, on: database))
        }
        return states
    }

    /// Creates or updates a group if `change` is newer than what's stored.
    ///
    /// A group with the same name (ignoring case) but another ID is the same
    /// group created on another Mac, or a deleted one: the change is applied
    /// to it, and the returned state has its ID.
    func put(_ change: SyncedGroupState, userID: UUID) async throws -> SyncedGroupState {
        let workspaceID = try await store.defaultWorkspace(userID: userID).requireID()
        return try await database.transaction { database in
            let group: RepoGroup
            var existing = try await RepoGroup.query(on: database)
                .filter(\.$workspace.$id == workspaceID)
                .filter(\.$id == change.id)
                .first()
            if existing == nil {
                existing = try await self.group(named: change.name, workspaceID: workspaceID, on: database)
            }
            if let existing {
                guard change.updatedAt > existing.updatedAt else {
                    return try await state(of: existing, on: database)
                }
                // Renaming onto another group's name would break the unique
                // constraint; keep the stored name instead.
                if existing.name != change.name,
                    let other = try await self.group(named: change.name, workspaceID: workspaceID, on: database),
                    other.id != existing.id
                {
                    group = existing
                } else {
                    existing.name = change.name
                    group = existing
                }
            } else {
                group = RepoGroup(id: change.id, workspaceID: workspaceID, name: change.name)
            }
            group.sortOrder = change.sortOrder
            group.updatedAt = change.updatedAt
            group.deletedAt = change.deletedAt
            group.syncedAt = .now
            try await group.save(on: database)
            try await replaceMembers(of: group, with: change.members, workspaceID: workspaceID, on: database)
            return try await state(of: group, on: database)
        }
    }

    /// Marks a group deleted at `deletedAt` unless it changed later.
    func delete(groupID: UUID, deletedAt: Date, userID: UUID) async throws {
        let workspaceID = try await store.defaultWorkspace(userID: userID).requireID()
        guard
            let group = try await RepoGroup.query(on: database)
                .filter(\.$workspace.$id == workspaceID)
                .filter(\.$id == groupID)
                .first(),
            group.deletedAt == nil, deletedAt > group.updatedAt
        else {
            return
        }
        group.deletedAt = deletedAt
        group.updatedAt = deletedAt
        group.syncedAt = .now
        try await group.update(on: database)
    }

    private func group(named name: String, workspaceID: UUID, on database: any Database) async throws -> RepoGroup? {
        try await RepoGroup.query(on: database)
            .filter(\.$workspace.$id == workspaceID)
            .all()
            .first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func replaceMembers(
        of group: RepoGroup,
        with identities: [String],
        workspaceID: UUID,
        on database: any Database
    ) async throws {
        let groupID = try group.requireID()
        try await RepoGroupMember.query(on: database).filter(\.$id.$group.$id == groupID).delete()
        for identity in Set(identities.map { $0.lowercased() }) {
            let repository = try await trackedRepository(identity, workspaceID: workspaceID, on: database)
            try await RepoGroupMember(groupID: groupID, trackedRepoID: try repository.requireID()).create(on: database)
        }
    }

    /// The workspace's repository with this remote identity, created (or restored) if needed.
    func trackedRepository(
        _ identity: String,
        workspaceID: UUID,
        on database: any Database
    ) async throws -> TrackedRepo {
        if let existing = try await TrackedRepo.query(on: database)
            .filter(\.$workspace.$id == workspaceID)
            .filter(\.$remoteURL == identity)
            .first()
        {
            if existing.deletedAt != nil {
                existing.deletedAt = nil
                existing.updatedAt = .now
                try await existing.update(on: database)
            }
            return existing
        }
        let parts = identity.split(separator: "/").map(String.init)
        let isGitHub = parts.count == 3 && parts[0] == "github.com"
        let repository = TrackedRepo(
            workspaceID: workspaceID,
            remoteURL: identity,
            githubOwner: isGitHub ? parts[1] : nil,
            githubName: isGitHub ? parts[2] : nil,
            displayName: parts.last ?? identity
        )
        try await repository.create(on: database)
        return repository
    }

    private func state(of group: RepoGroup, on database: any Database) async throws -> SyncedGroupState {
        let groupID = try group.requireID()
        let members = try await RepoGroupMember.query(on: database)
            .filter(\.$id.$group.$id == groupID)
            .all()
            .compactMap { $0.id?.$trackedRepo.id }
        let identities =
            members.isEmpty
            ? []
            : try await TrackedRepo.query(on: database).filter(\.$id ~~ members).all().map(\.remoteURL)
        return SyncedGroupState(
            id: groupID,
            name: group.name,
            sortOrder: group.sortOrder,
            members: identities.sorted(),
            updatedAt: group.updatedAt,
            deletedAt: group.deletedAt
        )
    }
}
