import Foundation
import RepoHubCore
import Testing

@testable import RepoHub

/// Returns canned scan results per root path.
private struct FakeScanner: RepositoryScanning {
    var results: [String: Result<[URL], ScanError>]

    func scan(_ root: URL, maxDepth: Int) async throws -> [URL] {
        guard let result = results[root.path] else {
            return []
        }
        return try result.get()
    }
}

@MainActor
@Suite("LibraryViewModel")
struct LibraryViewModelTests {
    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    private func makeModel(_ results: [String: Result<[URL], ScanError>]) throws -> LibraryViewModel {
        let store = LibraryStore(container: try Persistence.makeInMemoryContainer())
        return LibraryViewModel(store: store, scanner: FakeScanner(results: results))
    }

    @Test("Adding folders scans them and lists their repositories")
    func addFoldersScans() async throws {
        let model = try makeModel([
            "/dev": .success([url("/dev/web"), url("/dev/api")]),
            "/school": .success([url("/school/cs471")]),
        ])
        await model.addFolders([url("/dev"), url("/school")])

        #expect(model.folders.map(\.path) == ["/dev", "/school"])
        #expect(model.repositories.map(\.name) == ["api", "cs471", "web"])
        #expect(!model.isScanning)
        #expect(model.errorMessage == nil)
    }

    @Test("Adding a folder that's already tracked does nothing")
    func addDuplicateFolder() async throws {
        let model = try makeModel(["/dev": .success([url("/dev/api")])])
        await model.addFolders([url("/dev")])
        await model.addFolders([url("/dev")])
        #expect(model.folders.count == 1)
        #expect(model.repositories.count == 1)
    }

    @Test("A folder that fails to scan reports an error without stopping the others")
    func scanFailureIsIsolated() async throws {
        let model = try makeModel([
            "/gone": .failure(.folderNotFound(path: "/gone")),
            "/dev": .success([url("/dev/api")]),
        ])
        await model.addFolders([url("/gone"), url("/dev")])

        #expect(model.repositories.map(\.name) == ["api"])
        #expect(model.errorMessage?.contains("/gone") == true)
    }

    @Test("Removing a folder removes its repositories")
    func removeFolder() async throws {
        let model = try makeModel(["/dev": .success([url("/dev/api")])])
        await model.addFolders([url("/dev")])
        let folder = try #require(model.folders.first)

        model.remove(folder)
        #expect(model.folders.isEmpty)
        #expect(model.repositories.isEmpty)
    }

    @Test("Load restores folders and repositories saved earlier")
    func loadRestoresState() async throws {
        let store = LibraryStore(container: try Persistence.makeInMemoryContainer())
        let scanner = FakeScanner(results: ["/dev": .success([url("/dev/api")])])
        await LibraryViewModel(store: store, scanner: scanner).addFolders([url("/dev")])

        let restored = LibraryViewModel(store: store, scanner: scanner)
        restored.load()
        #expect(restored.folders.map(\.path) == ["/dev"])
        #expect(restored.repositories.map(\.name) == ["api"])
    }
}

/// Rescanning needs results that change between calls.
private final class SequenceScanner: RepositoryScanning, @unchecked Sendable {
    private let lock = NSLock()
    private var batches: [[URL]]

    init(_ batches: [[URL]]) {
        self.batches = batches
    }

    func scan(_ root: URL, maxDepth: Int) async throws -> [URL] {
        lock.withLock { batches.isEmpty ? [] : batches.removeFirst() }
    }
}

@MainActor
@Suite("LibraryViewModel rescan")
struct LibraryViewModelRescanTests {
    @Test("Rescan adds new repositories and drops deleted ones")
    func rescan() async throws {
        let store = LibraryStore(container: try Persistence.makeInMemoryContainer())
        let scanner = SequenceScanner([
            [URL(fileURLWithPath: "/dev/api"), URL(fileURLWithPath: "/dev/old")],
            [URL(fileURLWithPath: "/dev/api"), URL(fileURLWithPath: "/dev/new")],
        ])
        let model = LibraryViewModel(store: store, scanner: scanner)
        await model.addFolders([URL(fileURLWithPath: "/dev")])
        #expect(model.repositories.map(\.name) == ["api", "old"])

        await model.rescanAll()
        #expect(model.repositories.map(\.name) == ["api", "new"])
    }
}
