import Foundation
import RepoHubCore
import Testing

@testable import RepoHub

@MainActor
@Suite("RepositoryActions")
struct RepositoryActionsTests {
    private func makeDefaults() throws -> UserDefaults {
        let name = "RepositoryActionsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Fetch All fetches every repository with bounded concurrency and reports progress")
    func fetchAll() async throws {
        let git = FakeGit(delay: .milliseconds(10))
        let actions = RepositoryActions(
            git: git,
            workspace: FakeWorkspace(),
            defaults: try makeDefaults(),
            maxConcurrentFetches: 2
        )
        var changed: [String] = []
        actions.onRepositoriesChanged = { changed = $0 }
        let paths = (0..<6).map { "/repos/\($0)" }

        await actions.fetchAll(paths)

        #expect(await git.actionLog.sorted() == paths.map { "fetch \($0)" }.sorted())
        #expect(await git.peakConcurrency == 2)
        #expect(actions.fetchAllProgress == nil)
        #expect(actions.busy.isEmpty)
        #expect(Set(changed) == Set(paths))
        #expect(actions.failures.isEmpty)
    }

    @Test("A failing fetch is reported for that repository without stopping the others")
    func fetchFailureIsolated() async throws {
        let git = FakeGit()
        await git.setActionFailure(
            .commandFailed(command: "git fetch", exitCode: 128, stderr: "fatal: Could not resolve host: example.com"),
            for: "/repos/offline"
        )
        let actions = RepositoryActions(git: git, workspace: FakeWorkspace(), defaults: try makeDefaults())

        await actions.fetchAll(["/repos/offline", "/repos/ok"])

        #expect(await git.actionLog.count == 2)
        #expect(
            actions.failures == [.init(repository: "offline", message: "fatal: Could not resolve host: example.com")]
        )
    }

    @Test("A diverged pull explains that it won't merge")
    func pullDiverged() async throws {
        let git = FakeGit()
        await git.setActionFailure(
            .commandFailed(
                command: "git pull --ff-only --quiet",
                exitCode: 128,
                stderr: "fatal: Not possible to fast-forward, aborting."
            ),
            for: "/repos/api"
        )
        let actions = RepositoryActions(git: git, workspace: FakeWorkspace(), defaults: try makeDefaults())

        await actions.pull(["/repos/api"])

        #expect(actions.failures.first?.message.contains("diverged") == true)
    }

    @Test("Open actions use the preferred editor and terminal")
    func openUsesPreferences() async throws {
        let workspace = FakeWorkspace()
        let defaults = try makeDefaults()
        defaults.set("com.example.Editor", forKey: AppPreferences.editorBundleIDKey)
        let actions = RepositoryActions(git: FakeGit(), workspace: workspace, defaults: defaults)

        await actions.openInEditor("/repos/api")
        await actions.openInTerminal("/repos/api")
        actions.revealInFinder("/repos/api")

        #expect(workspace.opened.map(\.bundleID) == ["com.example.Editor", AppPreferences.defaultTerminalBundleID])
        #expect(workspace.opened.first?.folder.path == "/repos/api")
        #expect(workspace.revealed.map(\.path) == ["/repos/api"])
    }

    @Test("A missing app is reported")
    func missingApp() async throws {
        let workspace = FakeWorkspace()
        workspace.missingApps = [AppPreferences.defaultEditorBundleID]
        let actions = RepositoryActions(git: FakeGit(), workspace: workspace, defaults: try makeDefaults())

        await actions.openInEditor("/repos/api")

        #expect(actions.failures.count == 1)
        #expect(workspace.opened.isEmpty)
    }

    @Test("Copy and Open on GitHub use origin, or the first remote")
    func remoteActions() async throws {
        let git = FakeGit()
        await git.setRemotes(
            [
                Remote(name: "fork", fetchURL: "https://gitlab.com/me/web.git"),
                Remote(name: "origin", fetchURL: "https://github.com/acme/web.git"),
            ],
            for: "/repos/web"
        )
        await git.setRemotes([Remote(name: "fork", fetchURL: "https://gitlab.com/me/lib.git")], for: "/repos/lib")
        await git.setRemotes([], for: "/repos/local")
        let workspace = FakeWorkspace()
        let actions = RepositoryActions(git: git, workspace: workspace, defaults: try makeDefaults())

        await actions.copyRemoteURL("/repos/web")
        await actions.openOnGitHub("/repos/web")
        #expect(workspace.clipboard == "https://github.com/acme/web.git")
        #expect(workspace.browsed.map(\.absoluteString) == ["https://github.com/acme/web"])

        await actions.openOnGitHub("/repos/lib")
        await actions.copyRemoteURL("/repos/local")
        #expect(workspace.browsed.count == 1)
        #expect(actions.failures.map(\.repository) == ["lib", "local"])
    }
}
