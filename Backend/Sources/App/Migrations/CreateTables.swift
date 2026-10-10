import Fluent
import FluentSQL
import SQLKit

// One migration per table. Constraints and cascade rules follow
// docs/architecture/database.md.

struct CreateUsers: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(User.schema)
            .id()
            .field("github_id", .int64, .required)
            .field("login", .string, .required)
            .field("name", .string)
            .field("avatar_url", .string)
            .field("github_token_ciphertext", .data, .required)
            .field("github_token_scopes", .string, .required)
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime, .required)
            .unique(on: "github_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(User.schema).delete()
    }
}

struct CreateDevices: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Device.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("name", .string, .required)
            .field("refresh_token_hash", .data, .required)
            .field("refresh_expires_at", .datetime, .required)
            .field("last_seen_at", .datetime, .required)
            .field("revoked_at", .datetime)
            .field("created_at", .datetime, .required)
            .unique(on: "refresh_token_hash")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Device.schema).delete()
    }
}

struct CreateWorkspaces: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Workspace.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("name", .string, .required)
            .field("settings", .json, .required)
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime, .required)
            .field("deleted_at", .datetime)
            .unique(on: "user_id", "name")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Workspace.schema).delete()
    }
}

struct CreateTrackedRepos: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(TrackedRepo.schema)
            .id()
            .field("workspace_id", .uuid, .required, .references(Workspace.schema, "id", onDelete: .cascade))
            .field("remote_url", .string, .required)
            .field("github_owner", .string)
            .field("github_name", .string)
            .field("display_name", .string, .required)
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime, .required)
            .field("deleted_at", .datetime)
            .unique(on: "workspace_id", "remote_url")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(TrackedRepo.schema).delete()
    }
}

struct CreateRepoGroups: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(RepoGroup.schema)
            .id()
            .field("workspace_id", .uuid, .required, .references(Workspace.schema, "id", onDelete: .cascade))
            .field("name", .string, .required)
            .field("sort_order", .int, .required, .sql(.default(0)))
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime, .required)
            .field("deleted_at", .datetime)
            .unique(on: "workspace_id", "name")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(RepoGroup.schema).delete()
    }
}

struct CreateRepoGroupMembers: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(RepoGroupMember.schema)
            .field("group_id", .uuid, .required, .references(RepoGroup.schema, "id", onDelete: .cascade))
            .field("tracked_repo_id", .uuid, .required, .references(TrackedRepo.schema, "id", onDelete: .cascade))
            .field("created_at", .datetime, .required)
            .compositeIdentifier(over: "group_id", "tracked_repo_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(RepoGroupMember.schema).delete()
    }
}

struct CreateRepoSnapshots: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(RepoSnapshot.schema)
            .id()
            .field("tracked_repo_id", .uuid, .required, .references(TrackedRepo.schema, "id", onDelete: .cascade))
            .field("day", .date, .required)
            .field("commits", .int, .required)
            .field("dirty", .bool, .required)
            .field("ahead", .int, .required)
            .field("behind", .int, .required)
            .field("captured_at", .datetime, .required)
            .unique(on: "tracked_repo_id", "day")
            .constraint(
                .custom(
                    SQLRaw(
                        "CONSTRAINT repo_snapshots_counts_nonnegative "
                            + "CHECK (commits >= 0 AND ahead >= 0 AND behind >= 0)"
                    )
                )
            )
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(RepoSnapshot.schema).delete()
    }
}

struct CreateWebhookEvents: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(WebhookEvent.schema)
            .id()
            .field("delivery_id", .string, .required)
            .field("event", .string, .required)
            .field("action", .string)
            .field("repo_full_name", .string, .required)
            .field("payload", .json, .required)
            .field("received_at", .datetime, .required)
            .field("processed_at", .datetime)
            .unique(on: "delivery_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(WebhookEvent.schema).delete()
    }
}
