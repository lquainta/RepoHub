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
        return LibraryViewModel(
            store: store,
            scanner: FakeScanner(results: results),
            statuses: StatusMonitor(git: FakeGit())
        )
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
        await LibraryViewModel(store: store, scanner: scanner, statuses: StatusMonitor(git: FakeGit()))
            .addFolders([url("/dev")])

        let restored = LibraryViewModel(store: store, scanner: scanner, statuses: StatusMonitor(git: FakeGit()))
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
        let model = LibraryViewModel(store: store, scanner: scanner, statuses: StatusMonitor(git: FakeGit()))
        await model.addFolders([URL(fileURLWithPath: "/dev")])
        #expect(model.repositories.map(\.name) == ["api", "old"])

        await model.rescanAll()
        #expect(model.repositories.map(\.name) == ["api", "new"])
        #expect(Set(model.statuses.states.keys) == ["/dev/api", "/dev/new"])
    }
}

@MainActor
@Suite("LibraryViewModel statuses")
struct LibraryViewModelStatusTests {
    private func makeModel(git: FakeGit) throws -> LibraryViewModel {
        let store = LibraryStore(container: try Persistence.makeInMemoryContainer())
        let scanner = FakeScanner(results: [
            "/dev": .success([URL(fileURLWithPath: "/dev/api"), URL(fileURLWithPath: "/dev/web")])
        ])
        return LibraryViewModel(
            store: store,
            scanner: scanner,
            statuses: StatusMonitor(git: git),
            detail: RepositoryDetailModel(git: git)
        )
    }

    @Test("Selecting a repository loads its details")
    func selectLoadsDetails() async throws {
        let model = try makeModel(git: FakeGit())
        await model.addFolders([URL(fileURLWithPath: "/dev")])

        await model.select("/dev/web")

        #expect(model.selectedRepository?.name == "web")
        #expect(model.detail.path == "/dev/web")
        guard case .loaded = model.detail.state else {
            Issue.record("Expected loaded details, got \(model.detail.state)")
            return
        }
    }

    @Test("Fetch All refreshes the status of every repository")
    func fetchAllRefreshesStatus() async throws {
        let git = FakeGit()
        let store = LibraryStore(container: try Persistence.makeInMemoryContainer())
        let scanner = FakeScanner(results: ["/dev": .success([URL(fileURLWithPath: "/dev/api")])])
        let model = LibraryViewModel(
            store: store,
            scanner: scanner,
            statuses: StatusMonitor(git: git),
            detail: RepositoryDetailModel(git: git),
            actions: RepositoryActions(git: git, workspace: FakeWorkspace())
        )
        await model.addFolders([URL(fileURLWithPath: "/dev")])

        let behind = RepoStatus(head: .branch("main"), upstream: "origin/main", behind: 2)
        await git.setResult(.success(behind), for: "/dev/api")
        await model.fetchAll()

        #expect(await git.actionLog == ["fetch /dev/api"])
        #expect(model.rows.first?.status == behind)
    }

    @Test("Removing the selected repository's folder clears the selection")
    func removeClearsSelection() async throws {
        let model = try makeModel(git: FakeGit())
        await model.addFolders([URL(fileURLWithPath: "/dev")])
        await model.select("/dev/api")
        let folder = try #require(model.folders.first)

        model.remove(folder)

        #expect(model.selectedPath == nil)
        #expect(model.selectedRepository == nil)
    }

    @Test("Scanning reads the status of every new repository and rows combine both")
    func scanReadsStatus() async throws {
        let dirty = RepoStatus(head: .branch("main"), changes: FileChangeCounts(untracked: 1))
        let model = try makeModel(git: FakeGit(["/dev/web": .success(dirty)]))

        await model.addFolders([URL(fileURLWithPath: "/dev")])

        #expect(model.rows.map(\.name) == ["api", "web"])
        #expect(model.rows.last?.status == dirty)
        #expect(model.rows.allSatisfy { $0.state != nil })
    }

    @Test("Removing a folder forgets its repositories' statuses")
    func removeForgetsStatus() async throws {
        let model = try makeModel(git: FakeGit())
        await model.addFolders([URL(fileURLWithPath: "/dev")])
        let folder = try #require(model.folders.first)

        model.remove(folder)

        #expect(model.statuses.states.isEmpty)
        #expect(model.rows.isEmpty)
    }

    @Test("Refreshing statuses reads every repository again")
    func refreshReadsAll() async throws {
        let git = FakeGit()
        let model = try makeModel(git: git)
        await model.addFolders([URL(fileURLWithPath: "/dev")])

        await model.refreshStatuses()

        #expect(await git.reads.sorted() == ["/dev/api", "/dev/api", "/dev/web", "/dev/web"])
    }
}

@MainActor
@Suite("LibraryViewModel scope and groups")
struct LibraryViewModelScopeTests {
    private func makeModel() async throws -> LibraryViewModel {
        let store = LibraryStore(container: try Persistence.makeInMemoryContainer())
        let scanner = FakeScanner(results: [
            "/dev": .success([URL(fileURLWithPath: "/dev/api"), URL(fileURLWithPath: "/dev/web")]),
            "/school": .success([URL(fileURLWithPath: "/school/cs471")]),
        ])
        let git = FakeGit()
        let model = LibraryViewModel(
            store: store,
            scanner: scanner,
            statuses: StatusMonitor(git: git, staleBranchDays: { nil }),
            detail: RepositoryDetailModel(git: git),
            actions: RepositoryActions(git: git, workspace: FakeWorkspace())
        )
        await model.addFolders([URL(fileURLWithPath: "/dev"), URL(fileURLWithPath: "/school")])
        return model
    }

    @Test("Scope limits rows to a group or folder, and search applies within it")
    func scope() async throws {
        let model = try await makeModel()
        #expect(model.createGroup(named: "Work", adding: ["/dev/api", "/school/cs471"]))

        model.scope = .group("Work")
        #expect(model.visibleRows.map(\.name) == ["api", "cs471"])
        model.filter.searchText = "cs"
        #expect(model.visibleRows.map(\.name) == ["cs471"])

        model.filter = RepositoryFilter()
        model.scope = .folder("/dev")
        #expect(model.visibleRows.map(\.name) == ["api", "web"])
        #expect(model.groupNames(containing: "/dev/api") == ["Work"])
    }

    @Test("Renaming the selected group keeps it selected; deleting it shows all repositories")
    func renameAndDelete() async throws {
        let model = try await makeModel()
        model.createGroup(named: "Work", adding: ["/dev/api"])
        model.scope = .group("Work")

        model.renameGroup("Work", to: "Job")
        #expect(model.scope == .group("Job"))
        #expect(model.visibleRows.map(\.name) == ["api"])

        model.deleteGroup("Job")
        #expect(model.scope == .all)
        #expect(model.visibleRows.count == 3)
    }

    @Test("A duplicate group name is reported instead of created")
    func duplicateReported() async throws {
        let model = try await makeModel()
        model.createGroup(named: "Work")
        #expect(!model.createGroup(named: "work"))
        #expect(model.errorMessage != nil)
        #expect(model.groups.count == 1)
    }

    @Test("Removing the folder being viewed returns to all repositories")
    func removeScopedFolder() async throws {
        let model = try await makeModel()
        model.scope = .folder("/school")
        model.remove(try #require(model.folders.first { $0.path == "/school" }))
        #expect(model.scope == .all)
    }

    @Test("Filters use facts read with the status")
    func factsReachRows() async throws {
        let model = try await makeModel()
        model.filter.quickFilters = [.noRemote]
        #expect(model.visibleRows.isEmpty)
        model.filter.quickFilters = []
        #expect(model.rows.allSatisfy { $0.facts == RepositoryFacts(remoteCount: 1, staleBranchCount: 0) })
    }
}
