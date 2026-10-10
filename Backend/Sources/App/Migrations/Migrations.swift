import Fluent

/// Every schema migration, in the order they run. Never reorder or remove
/// entries; add new migrations at the end. Each one implements `revert`.
enum Migrations {
    static let all: [any AsyncMigration] = [
        CreateUsers(),
        CreateDevices(),
        CreateWorkspaces(),
        CreateTrackedRepos(),
        CreateRepoGroups(),
        CreateRepoGroupMembers(),
        CreateRepoSnapshots(),
        CreateWebhookEvents(),
        CreateIndexes(),
    ]
}
