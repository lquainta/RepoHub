import Foundation
import RepoHubCore
import Testing

@testable import RepoHub

@MainActor
@Suite("Activity")
struct ActivityModelTests {
    let api = FakeAPI()
    let git = FakeGit()
    /// A fixed calendar and "now", so days don't depend on where tests run.
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver") ?? .gmt
        return calendar
    }()
    /// 2026-10-21 12:00 in Denver.
    let now = Date(timeIntervalSince1970: 1_792_605_600)

    func makeModel(signedIn: Bool = true) async -> ActivityModel {
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
        return ActivityModel(account: account, api: api, git: git, calendar: calendar, now: { now })
    }

    func day(_ string: String, commits: Int, dirty: Bool = false) -> RepositoryActivity.Day {
        .init(day: string, commits: commits, dirty: dirty)
    }

    @Test("Commits are counted per local day; today carries the uncommitted state; older dates are skipped")
    func upload() async throws {
        let hour: TimeInterval = 3_600
        await git.setCommitDates(
            [now - hour, now - 2 * hour, now - 24 * hour, now - 40 * 24 * hour],
            for: "/dev/api"
        )
        let model = await makeModel()
        let dirty = RepoStatus(head: .branch("main"), ahead: 1, changes: FileChangeCounts(unstaged: 2))

        await model.upload([ActivitySource(path: "/dev/api", identity: "github.com/o/api", name: "api", status: dirty)])

        let snapshots = await api.snapshots
        #expect(snapshots.count == 2)
        let today = try #require(snapshots["github.com/o/api@2026-10-21"])
        #expect(today.commits == 2 && today.capture == SnapshotCapture(dirty: true, ahead: 1, behind: 0))
        let yesterday = try #require(snapshots["github.com/o/api@2026-10-20"])
        #expect(yesterday.commits == 1 && yesterday.capture == nil)
    }

    @Test("Signed out, nothing is uploaded or loaded")
    func signedOut() async {
        let model = await makeModel(signedIn: false)

        await model.upload([ActivitySource(path: "/dev/api", identity: "github.com/o/api", name: "api")])
        await model.load()

        #expect(await api.calls.isEmpty)
        #expect(!model.isSignedIn && !model.hasLoaded)
    }

    @Test("The busiest repositories are named and the rest are combined as Other")
    func points() async {
        let history = (1...10).map { index in
            RepositoryActivity(
                repository: "github.com/o/r\(index)",
                name: "r\(index)",
                days: [
                    day("2026-10-20", commits: index), day("2026-10-21", commits: 0, dirty: index.isMultiple(of: 2)),
                ]
            )
        }
        await api.setActivity(.success(history))
        let model = await makeModel()

        await model.load()
        let points = model.points()

        #expect(Set(points.map(\.series)) == Set((3...10).map { "r\($0)" } + ["Other"]))
        #expect(points.first { $0.series == "Other" }?.commits == 1 + 2)
        #expect(points.allSatisfy { $0.day == calendar.date(from: DateComponents(year: 2026, month: 10, day: 20)) })
        #expect(model.dirtyCounts().last?.repositories == 5)
        #expect(model.dirtyCounts().count == ActivityModel.days)
    }

    @Test("A group's scope limits the chart, and an empty history is reported as empty")
    func scopeAndEmpty() async {
        await api.setActivity(
            .success([
                RepositoryActivity(repository: "github.com/o/a", name: "a", days: [day("2026-10-21", commits: 3)]),
                RepositoryActivity(repository: "github.com/o/b", name: "b", days: [day("2026-10-21", commits: 5)]),
            ])
        )
        let model = await makeModel()
        await model.load()

        #expect(model.points(in: ["github.com/o/b"]).map(\.commits) == [5])
        #expect(model.isEmpty(in: ["github.com/o/none"]))
        #expect(!model.isEmpty())

        await api.setActivity(.success([]))
        await model.load()
        #expect(model.isEmpty() && model.hasLoaded)
    }

    @Test("A failed load is reported and keeps the previous history")
    func failedLoad() async {
        await api.setActivity(
            .success([
                RepositoryActivity(repository: "github.com/o/a", name: "a", days: [day("2026-10-21", commits: 1)])
            ])
        )
        let model = await makeModel()
        await model.load()

        await api.setActivity(.failure(.unavailable("down")))
        await model.load()

        #expect(model.errorMessage != nil)
        #expect(model.history.count == 1)
    }
}
