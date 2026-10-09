import Foundation
import SwiftData

/// Version 1 of RepoHub's persisted data model.
///
/// Never edit a shipped schema version. To change the model, add `SchemaV2`
/// with the new definitions, point the type aliases below at it, and add a
/// `MigrationStage` from V1 to V2 in ``RepoHubMigrationPlan``.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [ScanFolder.self, TrackedRepository.self]
    }

    /// A folder the user asked RepoHub to search for repositories.
    @Model
    final class ScanFolder {
        /// Absolute path of the folder.
        @Attribute(.unique) var path: String
        /// Bookmark used to find the folder again if it is moved or renamed.
        var bookmark: Data?
        /// How many directory levels below the folder to search.
        var maxDepth: Int
        /// When the folder was added.
        var addedAt: Date
        /// Repositories discovered in this folder.
        @Relationship(deleteRule: .cascade, inverse: \TrackedRepository.folder)
        var repositories: [TrackedRepository] = []

        init(path: String, bookmark: Data? = nil, maxDepth: Int = 4, addedAt: Date = .now) {
            self.path = path
            self.bookmark = bookmark
            self.maxDepth = maxDepth
            self.addedAt = addedAt
        }
    }

    /// A git repository discovered inside a ``ScanFolder``.
    @Model
    final class TrackedRepository {
        /// Absolute path of the repository's working tree.
        @Attribute(.unique) var path: String
        /// Display name (the directory name).
        var name: String
        /// When the repository was first discovered.
        var discoveredAt: Date
        /// The scan folder it was discovered in.
        var folder: ScanFolder?

        init(path: String, name: String, discoveredAt: Date = .now, folder: ScanFolder? = nil) {
            self.path = path
            self.name = name
            self.discoveredAt = discoveredAt
            self.folder = folder
        }
    }
}

/// The current version of the scan folder model.
typealias ScanFolder = SchemaV1.ScanFolder
/// The current version of the tracked repository model.
typealias TrackedRepository = SchemaV1.TrackedRepository
