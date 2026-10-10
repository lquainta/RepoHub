import SwiftData

/// Ordered list of every schema version and the migrations between them.
///
/// SwiftData uses this to upgrade an existing store on launch. Append new
/// versions to `schemas` and add a stage for each step; never reorder or
/// remove entries.
enum RepoHubMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    /// V2 only adds the `RepoGroup` model and an empty relationship, which
    /// SwiftData can infer.
    static let migrateV1toV2 = MigrationStage.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
}
