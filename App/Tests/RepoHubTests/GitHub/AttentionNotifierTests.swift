import Foundation
import RepoHubCore
import Testing

@testable import RepoHub

/// Records notifications instead of posting them.
@MainActor
final class FakeNotifier: UserNotifying {
    var allowed = true
    private(set) var authorizationRequests = 0
    private(set) var posted: [AttentionNotification] = []

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return allowed
    }

    func post(_ notification: AttentionNotification) async {
        posted.append(notification)
    }
}

@MainActor
@Suite("Notifications")
struct AttentionNotifierTests {
    let notifier = FakeNotifier()
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "AttentionNotifierTests-\(UUID().uuidString)"))
    }

    func request(_ name: String, branch: String? = "main") -> GitHubStatusRequest {
        GitHubStatusRequest(repository: GitHubRepository(owner: "owner", name: name), branch: branch)
    }

    func failing(_ name: String, run: Int = 1) -> GitHubRepositoryStatus {
        var status = GitHubRepositoryStatus.fixture(name, checks: .failure)
        status.checks?.url = status.repository.webURL.appending(path: "actions/runs/\(run)")
        return status
    }

    @Test("Existing failures and review requests don't notify; ones that appear later notify once")
    func baselineThenOnce() async {
        let model = AttentionNotifier(notifier: notifier, defaults: defaults)
        await model.update([request("old"): failing("old")])
        #expect(notifier.posted.isEmpty && notifier.authorizationRequests == 0)

        let changed = [
            request("old"): failing("old"),
            request("new"): failing("new"),
            request("reviews"): .fixture("reviews", pulls: [.fixture(9, review: true), .fixture(10)]),
        ]
        await model.update(changed)
        await model.update(changed)
        await model.update(changed)

        #expect(notifier.posted.map(\.kind) == [.ciFailure, .reviewRequest])
        #expect(notifier.posted[0].title == "CI failed on main")
        #expect(notifier.posted[0].url.absoluteString.hasSuffix("/actions/runs/1"))
        #expect(notifier.posted[1].body.contains("#9"))
        #expect(notifier.posted[1].url.absoluteString.hasSuffix("/pull/9"))
        #expect(notifier.authorizationRequests == 1)
    }

    @Test("A new failing run after a fix notifies again; the same run doesn't")
    func newRunNotifiesAgain() async {
        let model = AttentionNotifier(notifier: notifier, defaults: defaults)
        await model.update([:])

        await model.update([request("a"): failing("a", run: 1)])
        await model.update([request("a"): .fixture("a", checks: .success)])
        await model.update([request("a"): failing("a", run: 1)])
        await model.update([request("a"): failing("a", run: 2)])

        #expect(notifier.posted.map(\.url.lastPathComponent) == ["1", "2"])
    }

    @Test("A detached HEAD's failing checks don't notify, and worktrees share review requests")
    func detachedAndWorktrees() async {
        let model = AttentionNotifier(notifier: notifier, defaults: defaults)
        await model.update([:])
        let reviews = GitHubRepositoryStatus.fixture("a", pulls: [.fixture(3, review: true)])

        await model.update([
            request("a", branch: nil): failing("a"),
            request("a", branch: "main"): reviews,
            request("a", branch: "other"): reviews,
        ])

        #expect(notifier.posted.map(\.kind) == [.reviewRequest])
    }

    @Test("Each kind can be turned off in Settings")
    func toggles() async {
        defaults.set(false, forKey: AppPreferences.notifyCIFailuresKey)
        let model = AttentionNotifier(notifier: notifier, defaults: defaults)
        await model.update([:])

        await model.update([
            request("a"): failing("a"),
            request("b"): .fixture("b", pulls: [.fixture(1, review: true)]),
        ])
        #expect(notifier.posted.map(\.kind) == [.reviewRequest])

        defaults.set(false, forKey: AppPreferences.notifyReviewRequestsKey)
        await model.update([request("c"): .fixture("c", pulls: [.fixture(2, review: true)])])
        #expect(notifier.posted.count == 1)
    }

    @Test("Without permission nothing is posted, and permission is asked only when there's something to show")
    func permission() async {
        notifier.allowed = false
        let model = AttentionNotifier(notifier: notifier, defaults: defaults)
        await model.update([:])
        await model.update([request("a"): .fixture("a", checks: .success)])
        #expect(notifier.authorizationRequests == 0)

        await model.update([request("a"): failing("a")])

        #expect(notifier.authorizationRequests == 1)
        #expect(notifier.posted.isEmpty)
    }
}
