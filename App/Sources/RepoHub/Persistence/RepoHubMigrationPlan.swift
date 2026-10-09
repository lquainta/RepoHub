import SwiftData

/// Ordered list of every schema version and the migrations between them.
///
/// SwiftData uses this to upgrade an existing store on launch. Append new
/// versions to `schemas` and add a stage for each step; never reorder or
/// remove entries.
enum RepoHubMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
