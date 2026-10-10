import Fluent
import FluentSQL
import Foundation
import SQLKit
import Testing
import VaporTesting

@testable import App

/// Migrations and stores against a real PostgreSQL database (`TEST_DATABASE_URL`).
@Suite("Database", .serialized, .tags(.integration), .enabled(if: TestDatabase.isAvailable))
struct DatabaseIntegrationTests {
    private let expectedTables: Set<String> = [
        "users", "devices", "workspaces", "tracked_repos", "repo_groups", "repo_group_members",
        "repo_snapshots", "webhook_events",
    ]

    private func tables(_ app: Application) async throws -> Set<String> {
        let sql = try #require(app.db as? any SQLDatabase)
        let rows = try await sql.raw(
            """
            SELECT table_name FROM information_schema.tables
            WHERE table_schema = 'public' AND table_name <> '_fluent_migrations'
            """
        ).all()
        return Set(try rows.map { try $0.decode(column: "table_name", as: String.self) })
    }

    private func indexes(_ app: Application) async throws -> Set<String> {
        let sql = try #require(app.db as? any SQLDatabase)
        let rows = try await sql.raw("SELECT indexname FROM pg_indexes WHERE schemaname = 'public'").all()
        return Set(try rows.map { try $0.decode(column: "indexname", as: String.self) })
    }

    @Test("Migrations create every table and index, revert to an empty schema, and apply again")
    func migrateRevertMigrate() async throws {
        try await withMigratedApp { app in
            #expect(try await tables(app) == expectedTables)
            #expect(try await indexes(app).isSuperset(of: CreateIndexes.indexes.map(\.name)))

            try await app.autoRevert()
            #expect(try await tables(app).isEmpty)

            try await app.autoMigrate()
            #expect(try await tables(app) == expectedTables)
        }
    }

    @Test("Every entity is written and read back through the stores")
    func readWriteAllEntities() async throws {
        try await withMigratedApp { app in
            let stores = Stores(database: app.db)
            let profile = GitHubProfile(id: 42, login: "octocat", name: "Mona", avatarURL: "https://example.com/a.png")
            let user = try await stores.users.upsert(profile, tokenCiphertext: Data([1, 2, 3]), scopes: "repo")
            let userID = try user.requireID()
            #expect(try await stores.users.find(githubID: 42)?.login == "octocat")

            let device = try await stores.devices.create(
                userID: userID,
                name: "MacBook",
                refreshTokenHash: Data([9]),
                expiresAt: .now.addingTimeInterval(3_600)
            )
            #expect(try await stores.devices.findActive(refreshTokenHash: Data([9]), now: .now)?.id == device.id)

            let workspace = try await stores.sync.defaultWorkspace(userID: userID)
            let workspaceID = try workspace.requireID()
            #expect(try await stores.sync.defaultWorkspace(userID: userID).id == workspaceID)

            let repoID = UUID()
            _ = try await stores.sync.upsert(
                TrackedRepoChange(
                    id: repoID,
                    remoteURL: "https://github.com/octocat/hello",
                    githubOwner: "octocat",
                    githubName: "hello",
                    displayName: "hello",
                    updatedAt: .now
                ),
                workspaceID: workspaceID
            )
            #expect(try await stores.sync.repositories(githubOwner: "octocat", name: "hello").map(\.id) == [repoID])

            let groupID = UUID()
            _ = try await stores.sync.upsert(
                RepoGroupChange(id: groupID, name: "Work", sortOrder: 0, memberIDs: [repoID], updatedAt: .now),
                workspaceID: workspaceID
            )
            #expect(try await stores.sync.members(groupID: groupID) == [repoID])

        }
    }

    @Test("Snapshots upsert by day and webhook payloads round-trip as JSON")
    func snapshotsAndWebhookPayloads() async throws {
        try await withMigratedApp { app in
            let stores = Stores(database: app.db)
            let user = try await stores.users.upsert(
                GitHubProfile(id: 5, login: "u"),
                tokenCiphertext: Data(),
                scopes: ""
            )
            let workspaceID = try await stores.sync.defaultWorkspace(userID: try user.requireID()).requireID()
            let repoID = UUID()
            _ = try await stores.sync.upsert(
                TrackedRepoChange(id: repoID, remoteURL: "u", displayName: "r", updatedAt: .now),
                workspaceID: workspaceID
            )

            let day = try Date("2026-10-01T00:00:00Z", strategy: .iso8601)
            try await stores.snapshots.upsert(
                RepoSnapshot(trackedRepoID: repoID, day: day, commits: 3, dirty: true, ahead: 1, behind: 0)
            )
            try await stores.snapshots.upsert(
                RepoSnapshot(trackedRepoID: repoID, day: day, commits: 5, dirty: false, ahead: 0, behind: 0)
            )
            let snapshots = try await stores.snapshots.snapshots(repositoryIDs: [repoID], from: day, through: day)
            #expect(snapshots.map(\.commits) == [5])

            let event = WebhookEvent(
                deliveryID: "d-1",
                event: "check_run",
                action: "completed",
                repoFullName: "octocat/hello",
                payload: .object(["action": .string("completed")])
            )
            #expect(try await stores.webhookEvents.insertIfNew(event))
            let stored = try #require(try await WebhookEvent.query(on: app.db).first())
            #expect(stored.payload == .object(["action": .string("completed")]))
        }
    }

    @Test("Unique and check constraints are enforced by the database")
    func constraints() async throws {
        try await withMigratedApp { app in
            try await User(githubID: 1, login: "a", githubTokenCiphertext: Data(), githubTokenScopes: "").create(
                on: app.db
            )
            await #expect(throws: (any Error).self) {
                try await User(githubID: 1, login: "b", githubTokenCiphertext: Data(), githubTokenScopes: "")
                    .create(on: app.db)
            }

            let user = try #require(try await User.query(on: app.db).first())
            let workspace = Workspace(userID: try user.requireID(), name: "Default")
            try await workspace.create(on: app.db)
            let repo = TrackedRepo(workspaceID: try workspace.requireID(), remoteURL: "u", displayName: "r")
            try await repo.create(on: app.db)
            await #expect(throws: (any Error).self) {
                try await RepoSnapshot(
                    trackedRepoID: try repo.requireID(),
                    day: .now,
                    commits: -1,
                    dirty: false,
                    ahead: 0,
                    behind: 0
                )
                .create(on: app.db)
            }
            await #expect(throws: (any Error).self) {
                try await TrackedRepo(workspaceID: try workspace.requireID(), remoteURL: "u", displayName: "dup")
                    .create(on: app.db)
            }
        }
    }

    @Test("Deleting a user cascades to everything they own; deleting a group keeps its repositories")
    func cascades() async throws {
        try await withMigratedApp { app in
            let stores = Stores(database: app.db)
            let user = try await stores.users.upsert(
                GitHubProfile(id: 7, login: "u"),
                tokenCiphertext: Data(),
                scopes: ""
            )
            let userID = try user.requireID()
            _ = try await stores.devices.create(
                userID: userID,
                name: "Mac",
                refreshTokenHash: Data([1]),
                expiresAt: .now
            )
            let workspaceID = try await stores.sync.defaultWorkspace(userID: userID).requireID()
            let repoID = UUID()
            _ = try await stores.sync.upsert(
                TrackedRepoChange(id: repoID, remoteURL: "u", displayName: "r", updatedAt: .now),
                workspaceID: workspaceID
            )
            let group = RepoGroup(workspaceID: workspaceID, name: "G")
            try await group.create(on: app.db)
            try await RepoGroupMember(groupID: try group.requireID(), trackedRepoID: repoID).create(on: app.db)

            try await group.delete(on: app.db)
            #expect(try await RepoGroupMember.query(on: app.db).count() == 0)
            #expect(try await TrackedRepo.query(on: app.db).count() == 1)

            try await stores.users.delete(id: userID)
            #expect(try await Device.query(on: app.db).count() == 0)
            #expect(try await Workspace.query(on: app.db).count() == 0)
            #expect(try await TrackedRepo.query(on: app.db).count() == 0)
        }
    }

    @Test("Sync upserts are last-write-wins and deletions are kept as tombstones")
    func lastWriteWins() async throws {
        try await withMigratedApp { app in
            let stores = Stores(database: app.db)
            let user = try await stores.users.upsert(
                GitHubProfile(id: 9, login: "u"),
                tokenCiphertext: Data(),
                scopes: ""
            )
            let workspaceID = try await stores.sync.defaultWorkspace(userID: try user.requireID()).requireID()
            let id = UUID()
            let older = Date(timeIntervalSince1970: 1_000)
            let newer = older.addingTimeInterval(60)

            func change(_ name: String, at date: Date, deleted: Date? = nil) -> TrackedRepoChange {
                TrackedRepoChange(id: id, remoteURL: "u", displayName: name, updatedAt: date, deletedAt: deleted)
            }
            _ = try await stores.sync.upsert(change("new", at: newer), workspaceID: workspaceID)
            let stale = try await stores.sync.upsert(change("old", at: older), workspaceID: workspaceID)
            #expect(stale.displayName == "new")

            let latest = newer.addingTimeInterval(60)
            _ = try await stores.sync.upsert(change("new", at: latest, deleted: latest), workspaceID: workspaceID)
            let changed = try await stores.sync.repositories(workspaceID: workspaceID, changedSince: newer)
            #expect(changed.map(\.deletedAt) == [latest])
            #expect(try await stores.sync.repositories(githubOwner: "x", name: "y").isEmpty)
        }
    }

    @Test("Refresh tokens: revoked or expired devices aren't active, and rotation replaces the hash")
    func deviceTokens() async throws {
        try await withMigratedApp { app in
            let stores = Stores(database: app.db)
            let user = try await stores.users.upsert(
                GitHubProfile(id: 3, login: "u"),
                tokenCiphertext: Data(),
                scopes: ""
            )
            let userID = try user.requireID()
            let now = Date.now
            let device = try await stores.devices.create(
                userID: userID,
                name: "Mac",
                refreshTokenHash: Data([1]),
                expiresAt: now.addingTimeInterval(60)
            )
            _ = try await stores.devices.create(
                userID: userID,
                name: "Old",
                refreshTokenHash: Data([2]),
                expiresAt: now.addingTimeInterval(-60)
            )
            #expect(try await stores.devices.findActive(refreshTokenHash: Data([2]), now: now) == nil)

            try await stores.devices.rotate(
                device,
                refreshTokenHash: Data([3]),
                expiresAt: now.addingTimeInterval(60),
                now: now
            )
            #expect(try await stores.devices.findActive(refreshTokenHash: Data([1]), now: now) == nil)
            #expect(try await stores.devices.findActive(refreshTokenHash: Data([3]), now: now) != nil)

            try await stores.devices.revoke(id: try device.requireID(), now: now)
            #expect(try await stores.devices.findActive(refreshTokenHash: Data([3]), now: now) == nil)
            #expect(try await stores.devices.devices(userID: userID).count == 2)
        }
    }

    @Test("Duplicate webhook deliveries are ignored and old events are pruned")
    func webhookIdempotency() async throws {
        try await withMigratedApp { app in
            let store = FluentWebhookEventStore(database: app.db)
            let first = try await store.insertIfNew(Self.event("a", at: .now))
            let duplicate = try await store.insertIfNew(Self.event("a", at: .now))
            let old = try await store.insertIfNew(Self.event("old", at: .now.addingTimeInterval(-40 * 86_400)))
            #expect(first && !duplicate && old)

            let pruned = try await store.prune(receivedBefore: .now.addingTimeInterval(-30 * 86_400))
            let remaining = try await WebhookEvent.query(on: app.db).all().map(\.deliveryID)
            #expect(pruned == 1)
            #expect(remaining == ["a"])

            // Failures other than a duplicate delivery id are errors, not "duplicates".
            let invalid = WebhookEvent(deliveryID: "b", event: "push", repoFullName: "o/r", payload: .null)
            await #expect(throws: (any Error).self) { try await store.insertIfNew(invalid) }
        }
    }

    private static func event(_ id: String, at date: Date) -> WebhookEvent {
        WebhookEvent(deliveryID: id, event: "push", repoFullName: "o/r", payload: .object([:]), receivedAt: date)
    }
}
