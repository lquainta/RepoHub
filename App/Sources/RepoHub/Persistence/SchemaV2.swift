import Foundation
import SwiftData

/// Version 2 of RepoHub's persisted data model: adds user-defined repository groups.
///
/// Migrated from ``SchemaV1`` with a lightweight stage: the new `RepoGroup`
/// table and the group relationship start empty. Never edit a shipped
/// schema version; add `SchemaV3` instead.
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [ScanFolder.self, TrackedRepository.self, RepoGroup.self]
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
        /// Groups the user put this repository in.
        var groups: [RepoGroup] = []

        init(path: String, name: String, discoveredAt: Date = .now, folder: ScanFolder? = nil) {
            self.path = path
            self.name = name
            self.discoveredAt = discoveredAt
            self.folder = folder
        }
    }

    /// A user-defined collection of repositories, such as "School" or "Work".
    @Model
    final class RepoGroup {
        /// Display name, unique among groups.
        @Attribute(.unique) var name: String
        /// When the group was created; groups are listed in this order.
        var createdAt: Date
        /// Repositories in the group. Deleting a group leaves its repositories alone.
        @Relationship(deleteRule: .nullify, inverse: \TrackedRepository.groups)
        var repositories: [TrackedRepository] = []

        init(name: String, createdAt: Date = .now) {
            self.name = name
            self.createdAt = createdAt
        }
    }
}

/// The current version of the scan folder model.
typealias ScanFolder = SchemaV2.ScanFolder
/// The current version of the tracked repository model.
typealias TrackedRepository = SchemaV2.TrackedRepository
/// The current version of the repository group model.
typealias RepoGroup = SchemaV2.RepoGroup
