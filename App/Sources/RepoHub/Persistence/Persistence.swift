import Foundation
import SwiftData

/// Creates the app's SwiftData container.
enum Persistence {
    /// The schema for the current model version.
    static let schema = Schema(versionedSchema: SchemaV1.self)

    /// Default on-disk location: `~/Library/Application Support/RepoHub/RepoHub.store`.
    static var defaultStoreURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "RepoHub", directoryHint: .isDirectory)
            .appending(path: "RepoHub.store", directoryHint: .notDirectory)
    }

    /// Opens (creating or migrating as needed) the store at `url`.
    static func makeContainer(at url: URL = defaultStoreURL) throws -> ModelContainer {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(
            for: schema,
            migrationPlan: RepoHubMigrationPlan.self,
            configurations: configuration
        )
    }

    /// Creates an empty store that lives only in memory, for tests and previews.
    static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: schema,
            migrationPlan: RepoHubMigrationPlan.self,
            configurations: configuration
        )
    }
}
