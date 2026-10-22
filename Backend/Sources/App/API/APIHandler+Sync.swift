import Fluent
import Foundation
import OpenAPIRuntime
import RepoHubAPI

/// Group and settings sync between a user's Macs (#80).
extension APIHandler {
    private var sync: WorkspaceSync { WorkspaceSync(database: app.db) }

    func getWorkspace(_ input: Operations.getWorkspace.Input) async throws -> Operations.getWorkspace.Output {
        guard let user = RequestContext.user else {
            return .unauthorized(.init(body: .json(Self.error("Not signed in."))))
        }
        // Read the clock first, so a group stored while this runs is returned next time.
        let serverTime = Date.now
        let settings = try await sync.settings(userID: user.userID)
        let groups = try await sync.groups(userID: user.userID, since: input.query.since)
        return .ok(
            .init(
                body: .json(
                    .init(serverTime: serverTime, settings: Self.settings(settings), groups: groups.map(Self.group))
                )
            )
        )
    }

    func updateWorkspaceSettings(
        _ input: Operations.updateWorkspaceSettings.Input
    ) async throws -> Operations.updateWorkspaceSettings.Output {
        guard let user = RequestContext.user else {
            return .unauthorized(.init(body: .json(Self.error("Not signed in."))))
        }
        let body: Components.Schemas.SyncedSettings
        switch input.body {
        case .json(let json): body = json
        }
        let days = body.staleBranchDays.map { min(max($0, 0), 3_650) }
        let stored = try await sync.update(
            SyncedSettingsState(staleBranchDays: days, updatedAt: body.updatedAt),
            userID: user.userID
        )
        return .ok(.init(body: .json(Self.settings(stored))))
    }

    func putGroup(_ input: Operations.putGroup.Input) async throws -> Operations.putGroup.Output {
        guard let user = RequestContext.user else {
            return .unauthorized(.init(body: .json(Self.error("Not signed in."))))
        }
        guard case .json(let body) = input.body else {
            return .badRequest(.init(body: .json(Self.error("Expected a JSON body."))))
        }
        let name = body.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = UUID(uuidString: body.id), UUID(uuidString: input.path.groupID) == id else {
            return .badRequest(.init(body: .json(Self.error("The group ID must be a UUID matching the path."))))
        }
        guard (1...100).contains(name.count), body.members.count <= 1_000,
            body.members.allSatisfy({ (1...500).contains($0.count) })
        else {
            return .badRequest(.init(body: .json(Self.error("The group name or members are invalid."))))
        }
        let stored = try await sync.put(
            SyncedGroupState(
                id: id,
                name: name,
                sortOrder: body.sortOrder,
                members: body.members,
                updatedAt: body.updatedAt,
                deletedAt: body.deletedAt
            ),
            userID: user.userID
        )
        return .ok(.init(body: .json(Self.group(stored))))
    }

    func deleteGroup(_ input: Operations.deleteGroup.Input) async throws -> Operations.deleteGroup.Output {
        guard let user = RequestContext.user else {
            return .unauthorized(.init(body: .json(Self.error("Not signed in."))))
        }
        if let id = UUID(uuidString: input.path.groupID) {
            try await sync.delete(groupID: id, deletedAt: input.query.deletedAt, userID: user.userID)
        }
        return .noContent(.init())
    }

    private static func settings(_ settings: SyncedSettingsState) -> Components.Schemas.SyncedSettings {
        .init(staleBranchDays: settings.staleBranchDays, updatedAt: settings.updatedAt)
    }

    private static func group(_ group: SyncedGroupState) -> Components.Schemas.SyncedGroup {
        .init(
            id: group.id.uuidString,
            name: group.name,
            sortOrder: group.sortOrder,
            members: group.members,
            updatedAt: group.updatedAt,
            deletedAt: group.deletedAt
        )
    }
}
