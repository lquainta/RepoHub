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
        group.modifiedAt = .now
        try context.save()
        return group
    }

    /// Renames `group`.
    ///
    /// - Throws: ``GroupError`` if the name is empty or used by another group.
    func rename(_ group: RepoGroup, to name: String) throws {
        group.name = try validatedGroupName(name, excluding: group)
        group.modifiedAt = .now
        try context.save()
    }

    /// Deletes `group`. Its repositories stay tracked.
    ///
    /// - Returns: The group's sync ID, if it was synced, so other Macs can be told.
    @discardableResult
    func deleteGroup(_ group: RepoGroup) throws -> UUID? {
        let syncID = group.syncID
        context.delete(group)
        try context.save()
        return syncID
    }

    /// Adds the repositories at `paths` to `group`; ones already in it are ignored.
    func add(_ paths: [String], to group: RepoGroup) throws {
        let members = Set(group.repositories.map(\.path))
        for repository in try repositories() where paths.contains(repository.path) && !members.contains(repository.path)
        {
            group.repositories.append(repository)
        }
        group.modifiedAt = .now
        try context.save()
    }

    /// Removes the repositories at `paths` from `group`.
    func remove(_ paths: [String], from group: RepoGroup) throws {
        group.repositories.removeAll { paths.contains($0.path) }
        group.modifiedAt = .now
        try context.save()
    }

    // MARK: - Sync

    /// Applies a group from another Mac if it's newer than the local one
    /// (last write wins), matching by sync ID, then by name.
    ///
    /// - Parameters:
    ///   - remote: The group as the server stores it.
    ///   - identity: A tracked repository's remote identity, if known.
    /// - Throws: An error if the store can't be read or saved.
    func applySynced(_ remote: SyncedGroup, identity: (TrackedRepository) -> String?) throws {
        let local =
            try groups().first { $0.syncID == remote.id }
            ?? groups().first { $0.name.localizedCaseInsensitiveCompare(remote.name) == .orderedSame }
        if let deletedAt = remote.deletedAt {
            if let local, local.lastChange <= deletedAt {
                context.delete(local)
                try context.save()
            }
            return
        }
        let group: RepoGroup
        if let local {
            local.syncID = remote.id
            guard remote.updatedAt > local.lastChange else {
                try context.save()
                return
            }
            if (try? validatedGroupName(remote.name, excluding: local)) != nil {
                local.name = remote.name
            }
            group = local
        } else {
            guard let name = try? validatedGroupName(remote.name, excluding: nil) else {
                return
            }
            group = RepoGroup(name: name, createdAt: remote.updatedAt)
            context.insert(group)
            group.syncID = remote.id
        }
        let wanted = Set(remote.members)
        var found: Set<String> = []
        group.repositories = try repositories().filter { repository in
            guard let id = identity(repository), wanted.contains(id) else {
                return false
            }
            found.insert(id)
            return true
        }
        group.remoteOnlyMembers = wanted.subtracting(found).sorted()
        group.modifiedAt = remote.updatedAt
        try context.save()
    }

    /// Records the server's ID for `group`, after it was pushed.
    func adoptSyncID(_ id: UUID, for group: RepoGroup) throws {
        group.syncID = id
        try context.save()
    }

    /// Remembers the remote identities of the repositories at `paths` in
    /// their groups before they stop being tracked on this Mac (a scan folder
    /// was removed), so a later sync doesn't remove them on other Macs.
    func preserveMemberships(of paths: Set<String>, identity: (TrackedRepository) -> String?) throws {
        for group in try groups() {
            let leaving = group.repositories.filter { paths.contains($0.path) }.compactMap(identity)
            if !leaving.isEmpty {
                group.remoteOnlyMembers = Array(Set(group.remoteOnlyMembers).union(leaving)).sorted()
            }
        }
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
