import Foundation
import SwiftData

/// Reads and writes the user's scan folders and discovered repositories.
@MainActor
final class LibraryStore {
    // A ModelContext does not keep its container alive; holding the container
    // here prevents the context from outliving it.
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    /// All scan folders, oldest first.
    func scanFolders() throws -> [ScanFolder] {
        try context.fetch(FetchDescriptor<ScanFolder>(sortBy: [SortDescriptor(\.addedAt)]))
    }

    /// All tracked repositories, sorted by name.
    func repositories() throws -> [TrackedRepository] {
        try context.fetch(FetchDescriptor<TrackedRepository>(sortBy: [SortDescriptor(\.name)]))
    }

    /// Adds a scan folder, or returns `nil` if the folder is already tracked.
    @discardableResult
    func addScanFolder(at url: URL, maxDepth: Int = 4) throws -> ScanFolder? {
        let path = url.standardizedFileURL.path
        guard try folder(atPath: path) == nil else {
            return nil
        }
        let bookmark = try? url.bookmarkData()
        let folder = ScanFolder(path: path, bookmark: bookmark, maxDepth: maxDepth)
        context.insert(folder)
        try context.save()
        return folder
    }

    /// Removes a scan folder and every repository discovered in it.
    func removeScanFolder(_ folder: ScanFolder) throws {
        context.delete(folder)
        try context.save()
    }

    /// Makes `folder`'s repositories match `urls`: adds new ones and removes
    /// ones that are no longer found. A repository already tracked through a
    /// different (overlapping) scan folder is left where it is.
    func replaceRepositories(in folder: ScanFolder, with urls: [URL]) throws {
        let found = Set(urls.map { $0.standardizedFileURL.path })
        for repository in folder.repositories where !found.contains(repository.path) {
            context.delete(repository)
        }

        let known = Set(try repositories().map(\.path))
        for path in found.subtracting(known).sorted() {
            let name = URL(fileURLWithPath: path).lastPathComponent
            context.insert(TrackedRepository(path: path, name: name, folder: folder))
        }
        try context.save()
    }

    private func folder(atPath path: String) throws -> ScanFolder? {
        var descriptor = FetchDescriptor<ScanFolder>(predicate: #Predicate { $0.path == path })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
