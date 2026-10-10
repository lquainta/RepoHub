import Foundation
import SwiftData
import Testing

@testable import RepoHub

@MainActor
@Suite("LibraryStore")
struct LibraryStoreTests {
    private let container: ModelContainer
    private let store: LibraryStore

    init() throws {
        container = try Persistence.makeInMemoryContainer()
        store = LibraryStore(container: container)
    }

    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    @Test("Adding a folder twice keeps a single entry")
    func addFolderIsIdempotent() throws {
        #expect(try store.addScanFolder(at: url("/tmp/dev")) != nil)
        #expect(try store.addScanFolder(at: url("/tmp/dev/")) == nil)
        #expect(try store.scanFolders().map(\.path) == ["/tmp/dev"])
    }

    @Test("Replacing repositories adds new ones and removes missing ones")
    func replaceRepositories() throws {
        let folder = try #require(try store.addScanFolder(at: url("/tmp/dev")))
        try store.replaceRepositories(in: folder, with: [url("/tmp/dev/b"), url("/tmp/dev/a")])
        #expect(try store.repositories().map(\.name) == ["a", "b"])

        try store.replaceRepositories(in: folder, with: [url("/tmp/dev/b"), url("/tmp/dev/c")])
        #expect(try store.repositories().map(\.path) == ["/tmp/dev/b", "/tmp/dev/c"])
    }

    @Test("A repository found through overlapping folders is tracked once")
    func overlappingFolders() throws {
        let parent = try #require(try store.addScanFolder(at: url("/tmp/dev")))
        let child = try #require(try store.addScanFolder(at: url("/tmp/dev/work")))
        try store.replaceRepositories(in: parent, with: [url("/tmp/dev/work/api")])
        try store.replaceRepositories(in: child, with: [url("/tmp/dev/work/api")])

        let repositories = try store.repositories()
        #expect(repositories.count == 1)
        #expect(repositories.first?.folder?.path == "/tmp/dev")
    }

    @Test("Removing a folder removes its repositories")
    func removeFolderCascades() throws {
        let folder = try #require(try store.addScanFolder(at: url("/tmp/dev")))
        try store.replaceRepositories(in: folder, with: [url("/tmp/dev/a")])
        try store.removeScanFolder(folder)
        #expect(try store.scanFolders().isEmpty)
        #expect(try store.repositories().isEmpty)
    }
}

@MainActor
@Suite("Persistence")
struct PersistenceTests {
    @Test("Data written to disk is read back by a new container using the migration plan")
    func persistsAcrossLaunches() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "repohub-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "RepoHub.store")

        do {
            let store = LibraryStore(container: try Persistence.makeContainer(at: storeURL))
            let folder = try #require(try store.addScanFolder(at: URL(fileURLWithPath: "/tmp/dev")))
            try store.replaceRepositories(in: folder, with: [URL(fileURLWithPath: "/tmp/dev/api")])
        }

        let reopened = LibraryStore(container: try Persistence.makeContainer(at: storeURL))
        #expect(try reopened.scanFolders().map(\.path) == ["/tmp/dev"])
        #expect(try reopened.repositories().map(\.name) == ["api"])
    }

    @Test("The migration plan ends at the schema the app uses")
    func migrationPlanIsCurrent() {
        #expect(RepoHubMigrationPlan.schemas.last == SchemaV2.self)
        #expect(Persistence.schema.version == SchemaV2.versionIdentifier)
    }
}
