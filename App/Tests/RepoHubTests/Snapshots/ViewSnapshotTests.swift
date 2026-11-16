import AppKit
import Foundation
import RepoHubCore
import SwiftUI
import Testing

@testable import RepoHub

/// Finds the repositories it was given, whatever the folder.
private struct FixedScanner: RepositoryScanning {
    var repositories: [URL]

    func scan(_ root: URL, maxDepth: Int) async throws -> [URL] { repositories }
}

/// Snapshots of whole panels and windows with fixture data (#184): the menu
/// bar panel, the dashboard table, GitHub badges, and the Activity window.
@MainActor
@Suite("View snapshots", .enabled(if: SnapshotReference.matchesThisMac, "References are recorded on macOS 26 (CI)"))
struct ViewSnapshotTests {
    /// One repository per kind of status the dashboard and menu bar show.
    static let statuses: [String: Result<RepoStatus, GitError>] = [
        "/dev/clean": .success(RepoStatus(head: .branch("main"), upstream: "origin/main")),
        "/dev/dirty": .success(
            RepoStatus(
                head: .branch("feature/login"),
                upstream: "origin/feature/login",
                ahead: 2,
                changes: FileChangeCounts(staged: 1, unstaged: 3, untracked: 2),
                stashCount: 1
            )
        ),
        "/dev/behind": .success(RepoStatus(head: .branch("main"), upstream: "origin/main", ahead: 1, behind: 4)),
        "/dev/conflicted": .success(
            RepoStatus(head: .detached(commit: "abc1234"), changes: FileChangeCounts(conflicted: 2))
        ),
        "/dev/missing": .failure(.directoryNotFound(path: "/dev/missing")),
    ]

    /// A library that has scanned `paths` and read their statuses from ``statuses``.
    private func library(_ paths: [String]) async throws -> LibraryViewModel {
        let git = FakeGit(Self.statuses.filter { paths.contains($0.key) })
        let model = LibraryViewModel(
            store: LibraryStore(container: try Persistence.makeInMemoryContainer()),
            scanner: FixedScanner(repositories: paths.map { URL(fileURLWithPath: $0) }),
            statuses: StatusMonitor(git: git, staleBranchDays: { nil }),
            detail: RepositoryDetailModel(git: git),
            actions: RepositoryActions(git: git, workspace: FakeWorkspace())
        )
        if !paths.isEmpty {
            await model.addFolders([URL(fileURLWithPath: "/dev")])
        }
        return model
    }

    // MARK: Menu bar

    @Test("Menu bar panel before any folder is added")
    func menuBarEmpty() async throws {
        let library = try await library([])
        assertSnapshots(of: MenuBarContent(library: library), size: CGSize(width: 340, height: 150))
    }

    @Test("Menu bar panel when nothing needs attention")
    func menuBarAllClean() async throws {
        let library = try await library(["/dev/clean"])
        assertSnapshots(
            of: HStack(alignment: .top) {
                MenuBarContent(library: library)
                MenuBarLabel(library: library).padding()
            },
            size: CGSize(width: 420, height: 150)
        )
    }

    @Test("Menu bar panel listing repositories that need attention, with counts and conflicts")
    func menuBarAttention() async throws {
        let library = try await library(Array(Self.statuses.keys))
        #expect(AttentionSummary(rows: library.rows).count == 4)
        assertSnapshots(
            of: HStack(alignment: .top) {
                MenuBarContent(library: library)
                MenuBarLabel(library: library).padding()
            },
            size: CGSize(width: 420, height: 330)
        )
    }

    // MARK: Dashboard

    @Test("GitHub badges: CI passing, failing, and running; pull requests; review requests")
    func gitHubBadges() {
        let pulls: [GitHubRepositoryStatus.PullRequest] = [.fixture(12, head: "main"), .fixture(9, review: true)]
        assertSnapshots(
            of: VStack(alignment: .leading, spacing: 10) {
                GitHubBadges(status: .fixture("passing", checks: .success), branch: "main")
                GitHubBadges(status: .fixture("failing", pulls: pulls, checks: .failure), branch: "main")
                GitHubBadges(status: .fixture("running", pulls: [.fixture(3)], checks: .pending), branch: nil)
                GitHubBadges(status: .fixture("pulls-only", pulls: pulls), branch: "other")
            }
            .padding(),
            size: CGSize(width: 200, height: 140)
        )
    }

    @Test("Dashboard table with every column: clean, changed, diverged, conflicted, and unavailable rows")
    func dashboardTable() async throws {
        let library = try await library(Array(Self.statuses.keys))
        var rows = library.rows
        let failing = try #require(rows.firstIndex { $0.name == "dirty" })
        rows[failing].gitHub = .fixture(
            "dirty",
            pulls: [.fixture(7, head: "feature/login", review: true)],
            checks: .failure
        )
        let passing = try #require(rows.firstIndex { $0.name == "clean" })
        rows[passing].gitHub = .fixture("clean", checks: .success)

        try await assertWindowSnapshots(
            of: DashboardTable(
                rows: rows,
                refreshing: [],
                actions: library.actions,
                selection: .constant(nil)
            ) { _ in
                EmptyView()
            },
            size: CGSize(width: 1100, height: 320)
        )
    }
}

/// Snapshots of the main window's empty states and of error states elsewhere.
///
/// Offscreen, the sidebar's material draws as a blank panel, so the main
/// window snapshots check the dashboard and details columns only.
@MainActor
@Suite("State snapshots", .enabled(if: SnapshotReference.matchesThisMac, "References are recorded on macOS 26 (CI)"))
struct StateSnapshotTests {
    private func library(repositories: [String]) async throws -> LibraryViewModel {
        let git = FakeGit()
        let model = LibraryViewModel(
            store: LibraryStore(container: try Persistence.makeInMemoryContainer()),
            scanner: FixedScanner(repositories: repositories.map { URL(fileURLWithPath: $0) }),
            statuses: StatusMonitor(git: git, staleBranchDays: { nil }),
            detail: RepositoryDetailModel(git: git),
            actions: RepositoryActions(git: git, workspace: FakeWorkspace())
        )
        await model.addFolders([URL(fileURLWithPath: "/dev")])
        return model
    }

    private let windowSize = CGSize(width: 1000, height: 420)

    @Test("Main window when the folders contain no repositories")
    func noRepositories() async throws {
        let library = try await library(repositories: [])
        try await assertWindowSnapshots(of: LibraryView(model: library), size: windowSize)
    }

    @Test("Main window when search and filters match nothing")
    func noMatches() async throws {
        let library = try await library(repositories: ["/dev/api"])
        library.filter.searchText = "nothing-like-this"
        try await assertWindowSnapshots(of: LibraryView(model: library), size: windowSize)
    }

    @Test("Main window showing an empty group, with the group in the sidebar")
    func emptyGroup() async throws {
        let library = try await library(repositories: ["/dev/api"])
        #expect(library.createGroup(named: "Work"))
        library.scope = .group("Work")
        try await assertWindowSnapshots(of: LibraryView(model: library), size: windowSize)
    }

    @Test("Details pane for a repository that can't be read")
    func detailFailed() async throws {
        let git = FakeGit(["/dev/gone": .failure(.directoryNotFound(path: "/dev/gone"))])
        let model = RepositoryDetailModel(git: git)
        await model.show("/dev/gone")
        assertSnapshots(of: RepositoryDetailView(model: model, name: "gone"), size: CGSize(width: 360, height: 300))
    }

    @Test("Branch cleanup when the branches can't be read")
    func staleBranchesFailed() async throws {
        let git = FakeGit()
        await git.setBranchFailure(GitError.notARepository(path: "/repos/api"))
        let model = StaleBranchModel(path: "/repos/api", git: git, inactiveAfterDays: 90)
        await model.load()
        try await assertWindowSnapshots(
            of: StaleBranchSheet(model: model, repositoryName: "api") {},
            size: CGSize(width: 560, height: 440)
        ) {
            model.phase != .loading
        }
    }

    @Test("Branch cleanup when there's nothing to clean up")
    func staleBranchesNone() async throws {
        let git = FakeGit()
        await git.setStaleReport(StaleBranchReport(defaultBranch: "main", currentBranch: "main", candidates: []))
        let model = StaleBranchModel(path: "/repos/api", git: git, inactiveAfterDays: 90)
        await model.load()
        try await assertWindowSnapshots(
            of: StaleBranchSheet(model: model, repositoryName: "api") {},
            size: CGSize(width: 560, height: 440)
        ) {
            model.phase != .loading
        }
    }
}

/// Snapshots of the Activity window in each of its states.
@MainActor
@Suite("Activity snapshots", .enabled(if: SnapshotReference.matchesThisMac, "References are recorded on macOS 26 (CI)"))
struct ActivitySnapshotTests {
    let api = FakeAPI()
    /// 2026-10-21 12:00 UTC, in a fixed calendar, so the charts don't depend on today.
    let now = Date(timeIntervalSince1970: 1_792_584_000)
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
    let size = CGSize(width: 640, height: 480)

    private func model(signedIn: Bool = true) async -> ActivityModel {
        let account = AccountModel(
            api: api,
            credentials: InMemoryCredentialStore(),
            workspace: FakeWorkspace(),
            sleep: { _ in }
        )
        if signedIn {
            await api.setPolls([.success(.signedIn(.fixture()))])
            account.signIn()
            await account.waitForSignIn()
        }
        let now = now
        return ActivityModel(account: account, api: api, git: FakeGit(), calendar: calendar, now: { now })
    }

    private func library() throws -> LibraryViewModel {
        LibraryViewModel(store: LibraryStore(container: try Persistence.makeInMemoryContainer()))
    }

    @Test("Activity asks a signed-out user to sign in")
    func signedOut() async throws {
        let model = await model(signedIn: false)
        try await assertWindowSnapshots(of: ActivityView(model: model, library: try library()), size: size)
    }

    @Test("Activity explains an empty history")
    func empty() async throws {
        await api.setActivity(.success([]))
        let model = await model()
        await model.load()
        try await assertWindowSnapshots(of: ActivityView(model: model, library: try library()), size: size) {
            !model.isLoading
        }
    }

    @Test("Activity reports a history that couldn't be loaded")
    func failed() async throws {
        await api.setActivity(.failure(.unexpectedResponse(statusCode: 500)))
        let model = await model()
        await model.load()
        try await assertWindowSnapshots(of: ActivityView(model: model, library: try library()), size: size) {
            !model.isLoading
        }
    }

    @Test("Activity charts commits per day by repository and repositories with uncommitted changes")
    func charts() async throws {
        let days = (0..<10).map { String(format: "2026-10-%02d", 12 + $0) }
        await api.setActivity(
            .success([
                RepositoryActivity(
                    repository: "github.com/o/api",
                    name: "api",
                    days: days.enumerated().map { .init(day: $1, commits: ($0 * 3) % 5, dirty: $0 > 6) }
                ),
                RepositoryActivity(
                    repository: "github.com/o/web",
                    name: "web",
                    days: days.enumerated().map { .init(day: $1, commits: ($0 * 2) % 4, dirty: $0.isMultiple(of: 3)) }
                ),
            ])
        )
        let model = await model()
        await model.load()
        #expect(!model.isEmpty())
        try await assertWindowSnapshots(of: ActivityView(model: model, library: try library()), size: size) {
            !model.isLoading
        }
    }
}
