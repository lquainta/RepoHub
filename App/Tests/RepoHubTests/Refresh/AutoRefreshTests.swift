import Foundation
import RepoHubCore
import Testing

@testable import RepoHub

@Suite("ChangeRouter")
struct ChangeRouterTests {
    private let router = ChangeRouter(repositories: ["/dev/app", "/dev/app/vendor/lib", "/dev/web/"]) { _ in nil }

    @Test("Changes map to the innermost repository")
    func innermost() {
        #expect(router.repositories(affectedBy: ["/dev/app/Sources/a.swift"]) == ["/dev/app"])
        #expect(router.repositories(affectedBy: ["/dev/app/vendor/lib/x.c"]) == ["/dev/app/vendor/lib"])
        #expect(router.repositories(affectedBy: ["/dev/web/index.html", "/dev/app"]) == ["/dev/web", "/dev/app"])
    }

    @Test("Changes reported under a repository's canonical path map back to its tracked path")
    func canonicalPaths() {
        let router = ChangeRouter(repositories: ["/var/folders/x/project"]) { path in
            path.hasPrefix("/var/") ? "/private" + path : nil
        }
        #expect(router.repositories(affectedBy: ["/private/var/folders/x/project/a.txt"]) == ["/var/folders/x/project"])
        #expect(router.repositories(affectedBy: ["/var/folders/x/project/a.txt"]) == ["/var/folders/x/project"])
    }

    @Test("Paths outside repositories, or in a sibling with a shared prefix, are ignored")
    func outside() {
        #expect(router.repositories(affectedBy: ["/dev/notes.txt", "/dev/application/x", "/other"]).isEmpty)
    }

    @Test("Git internals that affect status count; object storage, logs, and lock files don't")
    func gitInternals() {
        #expect(router.repositories(affectedBy: ["/dev/app/.git/HEAD"]) == ["/dev/app"])
        #expect(router.repositories(affectedBy: ["/dev/app/.git/index"]) == ["/dev/app"])
        #expect(router.repositories(affectedBy: ["/dev/app/.git/refs/heads/main"]) == ["/dev/app"])
        #expect(
            router.repositories(affectedBy: [
                "/dev/app/.git/objects/ab/cdef", "/dev/app/.git/logs/HEAD", "/dev/app/.git/index.lock",
                "/dev/app/.git/FETCH_HEAD",
            ]).isEmpty
        )
    }
}

/// Records watch calls and lets tests deliver change events.
@MainActor
private final class FakeWatcher: FileWatching {
    private(set) var watched: [[String]] = []
    private(set) var stopped = 0
    private var onChange: (@MainActor ([String]) -> Void)?

    func watch(_ folders: [String], onChange: @escaping @MainActor ([String]) -> Void) {
        watched.append(folders)
        self.onChange = onChange
    }

    func stop() {
        stopped += 1
    }

    func send(_ paths: [String]) {
        onChange?(paths)
    }
}

@MainActor
@Suite("AutoRefreshController")
struct AutoRefreshControllerTests {
    @Test("The watcher restarts only when the folders change")
    func watchesFolders() {
        let watcher = FakeWatcher()
        let controller = AutoRefreshController(watcher: watcher)
        controller.update(folders: ["/b", "/a"], repositories: [])
        controller.update(folders: ["/a", "/b"], repositories: ["/a/x"])
        controller.update(folders: ["/a"], repositories: [])
        #expect(watcher.watched == [["/a", "/b"], ["/a"]])
    }

    @Test("Bursts of changes are debounced into one refresh of the affected repositories")
    func debounces() async throws {
        let watcher = FakeWatcher()
        let controller = AutoRefreshController(watcher: watcher, debounce: .milliseconds(100))
        var refreshes: [[String]] = []
        controller.onRefresh = { refreshes.append($0) }
        controller.update(folders: ["/dev"], repositories: ["/dev/a", "/dev/b", "/dev/c"])

        watcher.send(["/dev/a/1.txt"])
        try await Task.sleep(for: .milliseconds(20))
        watcher.send(["/dev/b/2.txt", "/dev/notes.txt"])
        watcher.send(["/dev/a/.git/objects/x"])
        try await Task.sleep(for: .milliseconds(400))

        #expect(refreshes == [["/dev/a", "/dev/b"]])
    }

    @Test("Background fetch is off at 0 and due once the interval passes")
    func fetchSchedule() {
        let last = Date(timeIntervalSince1970: 0)
        #expect(
            !AutoRefreshController.isFetchDue(lastFetch: last, now: last.addingTimeInterval(9_999), intervalMinutes: 0)
        )
        #expect(
            !AutoRefreshController.isFetchDue(lastFetch: last, now: last.addingTimeInterval(599), intervalMinutes: 10)
        )
        #expect(
            AutoRefreshController.isFetchDue(lastFetch: last, now: last.addingTimeInterval(600), intervalMinutes: 10)
        )
    }

    @Test("Background fetch runs when due, using the preference")
    func backgroundFetch() async throws {
        let name = "AutoRefreshTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let controller = AutoRefreshController(watcher: FakeWatcher(), defaults: defaults)
        var fetches = 0
        controller.onBackgroundFetch = { fetches += 1 }

        await controller.backgroundFetchIfDue(now: .now.addingTimeInterval(3_600))
        #expect(fetches == 0)

        defaults.set(15, forKey: AppPreferences.backgroundFetchMinutesKey)
        await controller.backgroundFetchIfDue(now: .now.addingTimeInterval(3_600))
        await controller.backgroundFetchIfDue(now: .now.addingTimeInterval(3_660))
        #expect(fetches == 1)
    }
}

@MainActor
@Suite("Auto-refresh end to end", .serialized)
struct AutoRefreshIntegrationTests {
    private func makeRepository() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "repohub-watch-\(UUID().uuidString)", directoryHint: .isDirectory)
        let repo = root.appending(path: "project", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init", "-q", "-b", "main", repo.path]
        try process.run()
        process.waitUntilExit()
        return root
    }

    @Test("FSEvents reports a file written in a watched folder")
    func watcherSeesWrites() async throws {
        let root = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let watcher = FSEventsWatcher(latency: 0.1)
        var seen: [String] = []
        watcher.watch([root.path]) { seen.append(contentsOf: $0) }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))

        try "hello".write(to: root.appending(path: "project/new.txt"), atomically: true, encoding: .utf8)

        let deadline = ContinuousClock.now + .seconds(3)
        while !seen.contains(where: { $0.hasSuffix("/project/new.txt") }) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(seen.contains { $0.hasSuffix("/project/new.txt") })
    }

    @Test("Editing a file updates the repository's status within 2 seconds")
    func statusUpdatesAfterEdit() async throws {
        let root = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryViewModel(
            store: LibraryStore(container: try Persistence.makeInMemoryContainer()),
            autoRefresh: AutoRefreshController(watcher: FSEventsWatcher(latency: 0.2))
        )
        defer { model.autoRefresh?.stop() }
        await model.addFolders([root])
        let path = try #require(model.repositories.first?.path)
        #expect(model.statuses.state(for: path) == .loaded(RepoStatus(head: .unborn(branch: "main"))))
        try await Task.sleep(for: .milliseconds(300))

        let edited = ContinuousClock.now
        try "hello".write(to: root.appending(path: "project/new.txt"), atomically: true, encoding: .utf8)
        while model.rows.first?.status?.changes.untracked != 1 && ContinuousClock.now - edited < .seconds(5) {
            try await Task.sleep(for: .milliseconds(50))
        }
        let elapsed = ContinuousClock.now - edited
        #expect(model.rows.first?.status?.changes.untracked == 1)
        #expect(elapsed < .seconds(2))
    }
}
