import AppKit
import Foundation
import OSLog
import Observation

/// Keeps statuses current without manual refreshes:
///
/// - Watches scan folders and refreshes only the repositories whose files
///   changed, after a short debounce.
/// - Refreshes everything when the app becomes active.
/// - Optionally fetches every repository on an interval (off by default).
@MainActor
final class AutoRefreshController {
    /// Refreshes the given repository paths.
    var onRefresh: @MainActor ([String]) async -> Void = { _ in }
    /// Refreshes every repository (on app activation).
    var onRefreshAll: @MainActor () async -> Void = {}
    /// Fetches every repository (background fetch).
    var onBackgroundFetch: @MainActor () async -> Void = {}

    private let watcher: any FileWatching
    private let debounce: Duration
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.lquainta.RepoHub", category: "AutoRefresh")

    private var watchedFolders: [String] = []
    private var router = ChangeRouter(repositories: [String]())
    private var pending: Set<String> = []
    private var debounceTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var activationObserver: (any NSObjectProtocol)?
    private var lastBackgroundFetch = Date.now

    init(
        watcher: any FileWatching = FSEventsWatcher(),
        debounce: Duration = .milliseconds(300),
        defaults: UserDefaults = .standard
    ) {
        self.watcher = watcher
        self.debounce = debounce
        self.defaults = defaults
    }

    /// Updates what's watched. Restarts the file watcher only if the folders changed.
    func update(folders: [String], repositories: [String]) {
        router = ChangeRouter(repositories: repositories)
        let folders = folders.sorted()
        guard folders != watchedFolders else {
            return
        }
        watchedFolders = folders
        watcher.watch(folders) { [weak self] paths in
            self?.filesChanged(paths)
        }
        logger.info("Watching \(folders.count) folders")
    }

    /// Starts activation refreshes and the background fetch loop.
    func start() {
        guard activationObserver == nil else {
            return
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.onRefreshAll() }
        }
        fetchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self?.backgroundFetchIfDue()
            }
        }
    }

    /// Stops watching and all timers.
    func stop() {
        watcher.stop()
        watchedFolders = []
        debounceTask?.cancel()
        fetchTask?.cancel()
        fetchTask = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    /// Routes changed paths to repositories and refreshes them after the debounce.
    func filesChanged(_ paths: [String]) {
        let affected = router.repositories(affectedBy: paths)
        guard !affected.isEmpty else {
            return
        }
        pending.formUnion(affected)
        debounceTask?.cancel()
        debounceTask = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else {
                return
            }
            let paths = pending.sorted()
            pending = []
            await onRefresh(paths)
        }
    }

    /// Fetches every repository if the configured interval has passed.
    func backgroundFetchIfDue(now: Date = .now) async {
        guard
            Self.isFetchDue(
                lastFetch: lastBackgroundFetch,
                now: now,
                intervalMinutes: AppPreferences.backgroundFetchMinutes(defaults)
            )
        else {
            return
        }
        lastBackgroundFetch = now
        logger.info("Background fetch")
        await onBackgroundFetch()
    }

    /// Whether a background fetch is due; an interval of 0 turns it off.
    nonisolated static func isFetchDue(lastFetch: Date, now: Date, intervalMinutes: Int) -> Bool {
        intervalMinutes > 0 && now.timeIntervalSince(lastFetch) >= Double(intervalMinutes) * 60
    }
}
