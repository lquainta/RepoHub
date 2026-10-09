import Foundation
import OSLog
import Observation
import RepoHubCore

/// State and actions for the user's scan folders and the repositories found in them.
@MainActor
@Observable
final class LibraryViewModel {
    /// Folders the user added, oldest first.
    private(set) var folders: [ScanFolder] = []
    /// Repositories found in all folders, sorted by name.
    private(set) var repositories: [TrackedRepository] = []
    /// Whether a scan is in progress.
    private(set) var isScanning = false
    /// A user-facing description of the most recent failure, if any.
    var errorMessage: String?

    private let store: LibraryStore
    private let scanner: any RepositoryScanning
    private let logger = Logger(subsystem: "com.lquainta.RepoHub", category: "Library")

    init(store: LibraryStore, scanner: any RepositoryScanning = RepositoryScanner()) {
        self.store = store
        self.scanner = scanner
    }

    /// Loads folders and repositories from the store.
    func load() {
        do {
            folders = try store.scanFolders()
            repositories = try store.repositories()
        } catch {
            report(error, message: String(localized: "Couldn't load your folders."))
        }
    }

    /// Adds folders that aren't already tracked and scans them.
    func addFolders(_ urls: [URL]) async {
        var added: [ScanFolder] = []
        for url in urls {
            do {
                if let folder = try store.addScanFolder(at: url) {
                    added.append(folder)
                }
            } catch {
                report(error, message: String(localized: "Couldn't add \(url.lastPathComponent)."))
            }
        }
        load()
        await scan(added)
    }

    /// Stops tracking `folder` and the repositories found in it.
    func remove(_ folder: ScanFolder) {
        do {
            try store.removeScanFolder(folder)
        } catch {
            report(error, message: String(localized: "Couldn't remove \(folder.path)."))
        }
        load()
    }

    /// Scans every folder again, picking up new repositories and dropping deleted ones.
    func rescanAll() async {
        await scan(folders)
    }

    /// Scans each folder in turn. A failure in one folder doesn't stop the others.
    private func scan(_ folders: [ScanFolder]) async {
        guard !folders.isEmpty else {
            return
        }
        isScanning = true
        defer { isScanning = false }

        for folder in folders {
            let root = URL(fileURLWithPath: folder.path, isDirectory: true)
            do {
                let found = try await scanner.scan(root, maxDepth: folder.maxDepth)
                try store.replaceRepositories(in: folder, with: found)
                logger.info("Scanned \(folder.path, privacy: .private): \(found.count) repositories")
            } catch is CancellationError {
                return
            } catch {
                report(error, message: String(localized: "Couldn't scan \(folder.path)."))
            }
        }
        load()
    }

    private func report(_ error: any Error, message: String) {
        logger.error("\(message, privacy: .public) \(error.localizedDescription, privacy: .public)")
        errorMessage = message
    }
}
