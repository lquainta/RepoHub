import Fluent
import SQLKit

/// Secondary indexes for the queries in docs/architecture/database.md.
///
/// Unique constraints and primary keys already have indexes; these cover
/// foreign-key lookups and the webhook and badge queries.
struct CreateIndexes: AsyncMigration {
    /// An index to create.
    struct Index {
        let name: String
        let table: String
        let columns: [String]
    }

    static let indexes: [Index] = [
        Index(name: "devices_user_id_idx", table: Device.schema, columns: ["user_id"]),
        Index(
            name: "tracked_repos_github_repo_idx",
            table: TrackedRepo.schema,
            columns: ["github_owner", "github_name"]
        ),
        Index(
            name: "repo_group_members_tracked_repo_id_idx",
            table: RepoGroupMember.schema,
            columns: ["tracked_repo_id"]
        ),
        Index(
            name: "webhook_events_repo_received_idx",
            table: WebhookEvent.schema,
            columns: ["repo_full_name", "received_at"]
        ),
    ]

    func prepare(on database: any Database) async throws {
        let sql = try Self.sql(database)
        for index in Self.indexes {
            var builder = sql.create(index: index.name).on(index.table)
            for column in index.columns {
                builder = builder.column(column)
            }
            try await builder.run()
        }
    }

    func revert(on database: any Database) async throws {
        let sql = try Self.sql(database)
        for index in Self.indexes.reversed() {
            try await sql.drop(index: index.name).run()
        }
    }

    private static func sql(_ database: any Database) throws -> any SQLDatabase {
        guard let sql = database as? any SQLDatabase else {
            throw MigrationError.sqlDatabaseRequired
        }
        return sql
    }
}

/// A migration ran against a database it can't handle.
enum MigrationError: Error {
    /// Index creation needs a SQL database.
    case sqlDatabaseRequired
}
