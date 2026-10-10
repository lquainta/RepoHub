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
    /// The git status of each repository.
    let statuses: StatusMonitor
    /// Details of the selected repository.
    let detail: RepositoryDetailModel
    /// Path of the selected repository, if any.
    private(set) var selectedPath: String?

    private let store: LibraryStore
    private let scanner: any RepositoryScanning
    private let logger = Logger(subsystem: "com.lquainta.RepoHub", category: "Library")

    init(
        store: LibraryStore,
        scanner: any RepositoryScanning = RepositoryScanner(),
        statuses: StatusMonitor? = nil,
        detail: RepositoryDetailModel? = nil
    ) {
        self.store = store
        self.scanner = scanner
        self.statuses = statuses ?? StatusMonitor()
        self.detail = detail ?? RepositoryDetailModel()
    }

    /// The selected repository, if it's still tracked.
    var selectedRepository: TrackedRepository? {
        repositories.first { $0.path == selectedPath }
    }

    /// Selects the repository at `path` (or nothing) and loads its details.
    func select(_ path: String?) async {
        selectedPath = path
        await detail.show(path)
    }

    /// Dashboard rows: every repository with its latest known status.
    var rows: [DashboardRow] {
        repositories.map { repository in
            DashboardRow(
                id: repository.path,
                name: repository.name,
                path: repository.path,
                state: statuses.state(for: repository.path)
            )
        }
    }

    /// Reads the git status of every repository again.
    func refreshStatuses() async {
        await statuses.refresh(repositories.map(\.path))
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
        statuses.retain(only: Set(repositories.map(\.path)))
        if selectedRepository == nil {
            selectedPath = nil
            Task { await detail.show(nil) }
        }
    }

    /// Scans every folder again, picking up new repositories and dropping
    /// deleted ones, then refreshes every repository's status.
    func rescanAll() async {
        await scan(folders)
        await refreshStatuses()
        await detail.reload()
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
        let paths = Set(repositories.map(\.path))
        statuses.retain(only: paths)
        if selectedPath.map({ !paths.contains($0) }) == true {
            await select(nil)
        }
        // Read newly found repositories right away; known ones keep their status.
        await statuses.refresh(repositories.map(\.path).filter { statuses.state(for: $0) == nil })
    }

    private func report(_ error: any Error, message: String) {
        logger.error("\(message, privacy: .public) \(error.localizedDescription, privacy: .public)")
        errorMessage = message
    }
}
