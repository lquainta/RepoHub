import Foundation
import SwiftData
import Testing

@testable import RepoHub

@MainActor
@Suite("LibraryStore groups")
struct GroupStoreTests {
    private let store: LibraryStore

    init() throws {
        store = LibraryStore(container: try Persistence.makeInMemoryContainer())
        let folder = try #require(try store.addScanFolder(at: URL(fileURLWithPath: "/dev")))
        try store.replaceRepositories(
            in: folder,
            with: ["/dev/api", "/dev/web", "/dev/cli"].map { URL(fileURLWithPath: $0) }
        )
    }

    @Test("Groups are created with trimmed, unique (case-insensitive) names")
    func createValidates() throws {
        try store.createGroup(named: "  School ")
        #expect(try store.groups().map(\.name) == ["School"])
        #expect(throws: GroupError.duplicateName("school")) { try store.createGroup(named: "school") }
        #expect(throws: GroupError.emptyName) { try store.createGroup(named: "   ") }
    }

    @Test("Adding and removing repositories; adding twice keeps one membership")
    func membership() throws {
        let group = try store.createGroup(named: "Work")
        try store.add(["/dev/api", "/dev/web"], to: group)
        try store.add(["/dev/api"], to: group)
        #expect(group.repositories.map(\.path).sorted() == ["/dev/api", "/dev/web"])

        try store.remove(["/dev/api"], from: group)
        #expect(group.repositories.map(\.path) == ["/dev/web"])
    }

    @Test("Renaming checks for duplicates but allows changing only the case")
    func rename() throws {
        let work = try store.createGroup(named: "Work")
        try store.createGroup(named: "School")
        #expect(throws: GroupError.duplicateName("School")) { try store.rename(work, to: "School") }
        try store.rename(work, to: "WORK")
        #expect(try store.groups().map(\.name) == ["WORK", "School"])
    }

    @Test("Deleting a group keeps its repositories tracked")
    func deleteKeepsRepositories() throws {
        let group = try store.createGroup(named: "Work")
        try store.add(["/dev/api"], to: group)
        try store.deleteGroup(group)
        #expect(try store.groups().isEmpty)
        #expect(try store.repositories().count == 3)
    }

    @Test("Removing a folder removes its repositories from groups")
    func removingFolderUpdatesGroups() throws {
        let group = try store.createGroup(named: "Work")
        try store.add(["/dev/api"], to: group)
        try store.removeScanFolder(try #require(try store.scanFolders().first))
        #expect(try store.groups().first?.repositories.isEmpty == true)
    }
}

@MainActor
@Suite("Schema migration")
struct SchemaMigrationTests {
    @Test("A version 1 store opens with version 2: folders and repositories kept, no groups")
    func migratesV1() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "repohub-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "RepoHub.store")

        do {
            let legacySchema = Schema(versionedSchema: SchemaV1.self)
            let legacy = try ModelContainer(
                for: legacySchema,
                configurations: ModelConfiguration(schema: legacySchema, url: url)
            )
            let folder = SchemaV1.ScanFolder(path: "/dev")
            legacy.mainContext.insert(folder)
            legacy.mainContext.insert(SchemaV1.TrackedRepository(path: "/dev/api", name: "api", folder: folder))
            try legacy.mainContext.save()
        }

        let store = LibraryStore(container: try Persistence.makeContainer(at: url))
        #expect(try store.scanFolders().map(\.path) == ["/dev"])
        #expect(try store.repositories().map(\.name) == ["api"])
        #expect(try store.groups().isEmpty)
        let group = try store.createGroup(named: "Work")
        try store.add(["/dev/api"], to: group)
        #expect(group.repositories.count == 1)
    }
}
