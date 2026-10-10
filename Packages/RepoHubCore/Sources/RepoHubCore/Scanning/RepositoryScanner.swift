import Foundation

/// Finds git repositories below a folder.
public protocol RepositoryScanning: Sendable {
    /// Finds every repository under `root`.
    ///
    /// - Parameters:
    ///   - root: Folder to search. If it is itself a repository, only `root` is returned.
    ///   - maxDepth: How many directory levels below `root` to search.
    /// - Returns: The working-tree URL of each repository, sorted by path.
    /// - Throws: ``ScanError/folderNotFound(path:)`` if `root` is not a directory;
    ///   `CancellationError` if the task is cancelled.
    func scan(_ root: URL, maxDepth: Int) async throws -> [URL]
}

/// An error raised while scanning for repositories.
public enum ScanError: Error, Equatable, Sendable {
    /// The folder to scan does not exist or is not a directory.
    case folderNotFound(path: String)
}

/// Walks the file system concurrently looking for directories that contain `.git`.
///
/// - A `.git` directory (normal repository) or `.git` file (linked worktree or
///   submodule) marks a repository. The scanner does not descend into a
///   repository, so submodules are not counted separately.
/// - Hidden directories, symbolic links (avoids cycles), and
///   ``defaultIgnoredNames`` such as `node_modules` are skipped.
public struct RepositoryScanner: RepositoryScanning {
    /// Directory names that never contain repositories worth tracking and can be very large.
    public static let defaultIgnoredNames: Set<String> = [
        "node_modules", ".build", "Pods", "Carthage", "DerivedData", "Library",
    ]

    /// Directory names to skip, in addition to hidden directories.
    public let ignoredNames: Set<String>
    /// Whether sibling directories are scanned in parallel. Sequential
    /// scanning exists as a baseline for the performance tests.
    public let concurrent: Bool

    /// Creates a scanner that skips `ignoredNames`.
    public init(ignoredNames: Set<String> = RepositoryScanner.defaultIgnoredNames, concurrent: Bool = true) {
        self.ignoredNames = ignoredNames
        self.concurrent = concurrent
    }

    /// Returns the working-tree URL of every repository under `root`, sorted by path.
    ///
    /// Returned URLs are built from `root` as given, so they always share its prefix.
    public func scan(_ root: URL, maxDepth: Int) async throws -> [URL] {
        let root = root.standardizedFileURL
        guard Self.isDirectory(root) else {
            throw ScanError.folderNotFound(path: root.path)
        }
        let found = try await scan(directory: root, depth: 0, maxDepth: maxDepth)
        return found.sorted { $0.path < $1.path }
    }

    private func scan(directory: URL, depth: Int, maxDepth: Int) async throws -> [URL] {
        try Task.checkCancellation()
        if Self.isRepository(directory) {
            return [directory]
        }
        guard depth < maxDepth else {
            return []
        }
        let children = subdirectories(of: directory)
        guard concurrent else {
            var found: [URL] = []
            for child in children {
                found += try await scan(directory: child, depth: depth + 1, maxDepth: maxDepth)
            }
            return found
        }
        return try await withThrowingTaskGroup(of: [URL].self) { group in
            for child in children {
                group.addTask {
                    try await scan(directory: child, depth: depth + 1, maxDepth: maxDepth)
                }
            }
            var found: [URL] = []
            for try await repositories in group {
                found.append(contentsOf: repositories)
            }
            return found
        }
    }

    /// Non-hidden, non-ignored, non-symlink subdirectories. Unreadable
    /// directories (for example, permission denied) are treated as empty.
    ///
    /// Child URLs are built from `directory` rather than taken from the
    /// listing, because Foundation may return resolved paths (on macOS,
    /// `/private/var` for `/var`).
    private func subdirectories(of directory: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return names.compactMap { name in
            guard !name.hasPrefix("."), !ignoredNames.contains(name) else {
                return nil
            }
            let child = directory.appendingPathComponent(name, isDirectory: true)
            // attributesOfItem does not follow a final symbolic link, so links report their own type.
            let type = (try? fileManager.attributesOfItem(atPath: child.path))?[.type] as? FileAttributeType
            return type == .typeDirectory ? child : nil
        }
    }

    private static func isRepository(_ directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(".git").path)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
