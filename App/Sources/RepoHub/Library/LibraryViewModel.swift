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
    /// Fetch, pull, and open actions.
    let actions: RepositoryActions
    /// Watches for file changes and refreshes affected repositories, if enabled.
    let autoRefresh: AutoRefreshController?
    /// Path of the selected repository, if any.
    private(set) var selectedPath: String?
    /// User-defined groups, oldest first.
    private(set) var groups: [RepoGroup] = []
    /// What the sidebar is showing.
    var scope: SidebarScope = .all
    /// Search text and quick filters applied to the dashboard.
    var filter = RepositoryFilter()

    let store: LibraryStore
    /// The injected scanner, or `nil` to use one built from the current preferences.
    private let injectedScanner: (any RepositoryScanning)?
    private let logger = Logger(subsystem: "com.lquainta.RepoHub", category: "Library")

    init(
        store: LibraryStore,
        scanner: (any RepositoryScanning)? = nil,
        statuses: StatusMonitor? = nil,
        detail: RepositoryDetailModel? = nil,
        actions: RepositoryActions? = nil,
        autoRefresh: AutoRefreshController? = nil
    ) {
        self.store = store
        self.injectedScanner = scanner
        self.statuses = statuses ?? StatusMonitor()
        self.detail = detail ?? RepositoryDetailModel()
        self.actions = actions ?? RepositoryActions()
        self.autoRefresh = autoRefresh
        self.actions.onRepositoriesChanged = { [weak self] paths in
            await self?.repositoriesChanged(paths)
        }
        autoRefresh?.onRefresh = { [weak self] paths in
            await self?.repositoriesChanged(paths)
        }
        autoRefresh?.onRefreshAll = { [weak self] in
            guard let self else { return }
            await repositoriesChanged(repositories.map(\.path))
        }
        autoRefresh?.onBackgroundFetch = { [weak self] in
            await self?.fetchAll()
        }
    }

    /// Fetches every tracked repository.
    func fetchAll() async {
        await actions.fetchAll(repositories.map(\.path))
    }

    /// Re-reads statuses (and the open details) of the repositories at `paths`.
    func repositoriesChanged(_ paths: [String]) async {
        await statuses.refresh(paths)
        if let selectedPath, paths.contains(selectedPath) {
            await detail.reload()
        }
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
                state: statuses.state(for: repository.path),
                facts: statuses.facts[repository.path]
            )
        }
    }

    /// Rows in the sidebar's scope that match the search and filters.
    var visibleRows: [DashboardRow] {
        let inScope: Set<String>? =
            switch scope {
            case .all: nil
            case .group(let name): Set(groups.first { $0.name == name }?.repositories.map(\.path) ?? [])
            case .folder(let path): Set(repositories.filter { $0.folder?.path == path }.map(\.path))
            }
        let scoped = inScope.map { paths in rows.filter { paths.contains($0.id) } } ?? rows
        return filter.apply(to: scoped)
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
            groups = try store.groups()
        } catch {
            report(error, message: String(localized: "Couldn't load your folders."))
        }
        autoRefresh?.update(folders: folders.map(\.path), repositories: repositories.map(\.path))
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
        if scope == .folder(folder.path) {
            scope = .all
        }
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
        // Read the ignore list at every scan so Settings changes apply on the next refresh.
        let scanner = injectedScanner ?? RepositoryScanner(ignoredNames: AppPreferences.ignoredFolderNames())

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

    func report(_ error: any Error, message: String) {
        logger.error("\(message, privacy: .public) \(error.localizedDescription, privacy: .public)")
        errorMessage = message
    }
}
