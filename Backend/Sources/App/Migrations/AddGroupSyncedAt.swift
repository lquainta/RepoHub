import Fluent
import FluentSQL
import SQLKit

/// Adds `repo_groups.synced_at`: when the server last stored the group.
///
/// `updated_at` is the client's clock, which decides conflicts but can't be
/// compared with another Mac's clock. `GET /workspace?since=` filters on
/// `synced_at` instead, so no change is missed when clocks disagree (#80).
struct AddGroupSyncedAt: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(RepoGroup.schema)
            .field("synced_at", .datetime, .required, .sql(.default(SQLFunction("now"))))
            .update()
        if let sql = database as? any SQLDatabase {
            try await sql.create(index: "repo_groups_workspace_synced_at_idx")
                .on(RepoGroup.schema)
                .column("workspace_id")
                .column("synced_at")
                .run()
        }
    }

    func revert(on database: any Database) async throws {
        if let sql = database as? any SQLDatabase {
            try await sql.drop(index: "repo_groups_workspace_synced_at_idx").run()
        }
        try await database.schema(RepoGroup.schema).deleteField("synced_at").update()
    }
}
