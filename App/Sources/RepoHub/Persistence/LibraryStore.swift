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

    // MARK: - Groups

    /// All groups, oldest first.
    func groups() throws -> [RepoGroup] {
        try context.fetch(FetchDescriptor<RepoGroup>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    /// Creates a group named `name` (trimmed).
    ///
    /// - Throws: ``GroupError`` if the name is empty or already used.
    @discardableResult
    func createGroup(named name: String) throws -> RepoGroup {
        let name = try validatedGroupName(name, excluding: nil)
        let group = RepoGroup(name: name)
        context.insert(group)
        try context.save()
        return group
    }

    /// Renames `group`.
    ///
    /// - Throws: ``GroupError`` if the name is empty or used by another group.
    func rename(_ group: RepoGroup, to name: String) throws {
        group.name = try validatedGroupName(name, excluding: group)
        try context.save()
    }

    /// Deletes `group`. Its repositories stay tracked.
    func deleteGroup(_ group: RepoGroup) throws {
        context.delete(group)
        try context.save()
    }

    /// Adds the repositories at `paths` to `group`; ones already in it are ignored.
    func add(_ paths: [String], to group: RepoGroup) throws {
        let members = Set(group.repositories.map(\.path))
        for repository in try repositories() where paths.contains(repository.path) && !members.contains(repository.path)
        {
            group.repositories.append(repository)
        }
        try context.save()
    }

    /// Removes the repositories at `paths` from `group`.
    func remove(_ paths: [String], from group: RepoGroup) throws {
        group.repositories.removeAll { paths.contains($0.path) }
        try context.save()
    }

    private func validatedGroupName(_ name: String, excluding group: RepoGroup?) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GroupError.emptyName
        }
        let taken = try groups().contains {
            $0 !== group && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !taken else {
            throw GroupError.duplicateName(trimmed)
        }
        return trimmed
    }

    private func folder(atPath path: String) throws -> ScanFolder? {
        var descriptor = FetchDescriptor<ScanFolder>(predicate: #Predicate { $0.path == path })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

/// Why a group couldn't be created or renamed.
enum GroupError: LocalizedError, Equatable {
    case emptyName
    case duplicateName(String)

    var errorDescription: String? {
        switch self {
        case .emptyName: String(localized: "A group needs a name.")
        case .duplicateName(let name): String(localized: "There's already a group named \(name).")
        }
    }
}
