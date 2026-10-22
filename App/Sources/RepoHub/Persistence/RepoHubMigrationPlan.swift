import SwiftData

/// Ordered list of every schema version and the migrations between them.
///
/// SwiftData uses this to upgrade an existing store on launch. Append new
/// versions to `schemas` and add a stage for each step; never reorder or
/// remove entries.
enum RepoHubMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3]
    }

    /// V2 only adds the `RepoGroup` model and an empty relationship, which
    /// SwiftData can infer.
    static let migrateV1toV2 = MigrationStage.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)

    /// V3 adds optional sync attributes to `RepoGroup`, which SwiftData can infer.
    static let migrateV2toV3 = MigrationStage.lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self)
}
