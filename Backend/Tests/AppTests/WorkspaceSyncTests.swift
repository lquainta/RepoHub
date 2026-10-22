import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting

@testable import App

/// The parts of sync responses the route test reads.
private struct WorkspaceBody: Decodable {
    struct Group: Decodable {
        let id: String
        let name: String
        let members: [String]
        let deletedAt: Date?
    }

    let serverTime: Date
    let groups: [Group]
}

extension DatabaseIntegrationTests {
    @Suite("Workspace sync")
    struct WorkspaceSyncTests {
        private let epoch = Date(timeIntervalSince1970: 1_800_000_000)

        private func user(_ app: Application) async throws -> UUID {
            let user = User(
                githubID: Int64.random(in: 1...1_000_000),
                login: "octocat",
                githubTokenCiphertext: Data(),
                githubTokenScopes: ""
            )
            try await user.create(on: app.db)
            return try user.requireID()
        }

        private func groupChange(
            _ name: String,
            id: UUID = UUID(),
            members: [String] = [],
            at seconds: TimeInterval,
            deleted: TimeInterval? = nil
        ) -> SyncedGroupState {
            SyncedGroupState(
                id: id,
                name: name,
                sortOrder: 0,
                members: members,
                updatedAt: epoch + seconds,
                deletedAt: deleted.map { epoch + $0 }
            )
        }

        @Test("Settings are last-write-wins by the client's time")
        func settings() async throws {
            try await withMigratedApp { app in
                let sync = WorkspaceSync(database: app.db)
                let userID = try await user(app)

                let first = try await sync.update(.init(staleBranchDays: 30, updatedAt: epoch + 10), userID: userID)
                let older = try await sync.update(.init(staleBranchDays: 60, updatedAt: epoch + 5), userID: userID)

                #expect(first.staleBranchDays == 30)
                #expect(older == first)
                #expect(try await sync.settings(userID: userID).staleBranchDays == 30)
            }
        }

        @Test("A group's members are remote identities; repositories are created once per workspace")
        func members() async throws {
            try await withMigratedApp { app in
                let sync = WorkspaceSync(database: app.db)
                let userID = try await user(app)
                let identities = ["github.com/o/a", "gitlab.com/g/b"]

                let change = groupChange("School", members: identities + ["GitHub.com/o/a"], at: 1)
                let stored = try await sync.put(change, userID: userID)
                _ = try await sync.put(groupChange("Work", members: ["github.com/o/a"], at: 1), userID: userID)

                #expect(stored.members == identities)
                let repositories = try await TrackedRepo.query(on: app.db).all()
                #expect(repositories.count == 2)
                let gitHub = try #require(repositories.first { $0.remoteURL == "github.com/o/a" })
                #expect(gitHub.githubOwner == "o" && gitHub.githubName == "a" && gitHub.displayName == "a")
            }
        }

        @Test("Older changes are ignored and newer ones win")
        func lastWriteWins() async throws {
            try await withMigratedApp { app in
                let sync = WorkspaceSync(database: app.db)
                let userID = try await user(app)
                let id = UUID()
                _ = try await sync.put(
                    groupChange("School", id: id, members: ["github.com/o/a"], at: 10),
                    userID: userID
                )

                let older = try await sync.put(groupChange("Old", id: id, at: 5), userID: userID)
                let newer = try await sync.put(
                    groupChange("Classes", id: id, members: ["github.com/o/b"], at: 20),
                    userID: userID
                )

                #expect(older.name == "School" && older.members == ["github.com/o/a"])
                #expect(newer.name == "Classes" && newer.members == ["github.com/o/b"])
            }
        }

        @Test("A group with the same name from another Mac is merged into the existing one")
        func sameNameMerges() async throws {
            try await withMigratedApp { app in
                let sync = WorkspaceSync(database: app.db)
                let userID = try await user(app)
                let first = try await sync.put(groupChange("School", at: 1), userID: userID)

                let second = try await sync.put(
                    groupChange("school", members: ["github.com/o/a"], at: 2),
                    userID: userID
                )

                #expect(second.id == first.id)
                #expect(try await sync.groups(userID: userID, since: nil).count == 1)
            }
        }

        @Test("Deletions are tombstones returned by later syncs; an older deletion is ignored; a newer create revives")
        func deletions() async throws {
            try await withMigratedApp { app in
                let sync = WorkspaceSync(database: app.db)
                let userID = try await user(app)
                let id = UUID()
                _ = try await sync.put(groupChange("School", id: id, at: 10), userID: userID)

                try await sync.delete(groupID: id, deletedAt: epoch + 5, userID: userID)
                #expect(try await sync.groups(userID: userID, since: nil).first?.deletedAt == nil)

                let beforeDelete = Date.now
                try await sync.delete(groupID: id, deletedAt: epoch + 20, userID: userID)
                let changed = try await sync.groups(userID: userID, since: beforeDelete)
                #expect(changed.map(\.id) == [id] && changed.first?.deletedAt == epoch + 20)

                let revived = try await sync.put(groupChange("School", at: 30), userID: userID)
                #expect(revived.id == id && revived.deletedAt == nil)
            }
        }

        @Test("Since returns only groups the server stored after it, whatever the clients' clocks")
        func since() async throws {
            try await withMigratedApp { app in
                let sync = WorkspaceSync(database: app.db)
                let userID = try await user(app)
                _ = try await sync.put(groupChange("Before", at: 100), userID: userID)
                let mark = Date.now
                try await Task.sleep(for: .milliseconds(5))
                // A Mac whose clock is far behind still syncs this change.
                _ = try await sync.put(groupChange("After", at: -1_000_000), userID: userID)

                #expect(try await sync.groups(userID: userID, since: mark).map(\.name) == ["After"])
            }
        }

        @Test("A group created on one Mac appears on another Mac after sync")
        func twoMacs() async throws {
            try await withMigratedApp { app in
                let macA = try await app.signInWithFakeGitHub()
                let macB = try await app.signInWithFakeGitHub()
                var headersA = HTTPHeaders()
                headersA.bearerAuthorization = BearerAuthorization(token: macA)
                var headersB = HTTPHeaders()
                headersB.bearerAuthorization = BearerAuthorization(token: macB)

                let initial = try await app.send(.GET, "workspace", headers: headersB)
                #expect(initial.status == .ok)
                let since = try initial.content.decode(WorkspaceBody.self, using: Self.decoder).serverTime

                let id = UUID().uuidString
                let body = #"""
                    {"id":"\#(id)","name":"School","sortOrder":0,"members":["github.com/o/a"],\#
                    "updatedAt":"2027-01-01T00:00:00Z"}
                    """#
                let put = try await app.send(.PUT, "workspace/groups/\(id)", json: body, headers: headersA)
                #expect(put.status == .ok)

                let iso = ISO8601DateFormatter().string(from: since)
                let synced = try await app.send(.GET, "workspace?since=\(iso)", headers: headersB)
                let workspace = try synced.content.decode(WorkspaceBody.self, using: Self.decoder)
                #expect(workspace.groups.map(\.name) == ["School"])
                #expect(workspace.groups.first?.members == ["github.com/o/a"])

                let mismatched = try await app.send(.PUT, "workspace/groups/\(UUID())", json: body, headers: headersA)
                #expect(mismatched.status == .badRequest)
                #expect(try await app.send(.GET, "workspace").status == .unauthorized)

                let delete = try await app.send(
                    .DELETE,
                    "workspace/groups/\(id)?deletedAt=2027-01-02T00:00:00Z",
                    headers: headersB
                )
                #expect(delete.status == .noContent)
                let afterDelete = try await app.send(.GET, "workspace?since=\(iso)", headers: headersA)
                let deleted = try afterDelete.content.decode(WorkspaceBody.self, using: Self.decoder)
                #expect(deleted.groups.first?.deletedAt != nil)
            }
        }

        private static var decoder: JSONDecoder {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let string = try decoder.singleValueContainer().decode(String.self)
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string) {
                    return date
                }
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: string))
            }
            return decoder
        }
    }
}
