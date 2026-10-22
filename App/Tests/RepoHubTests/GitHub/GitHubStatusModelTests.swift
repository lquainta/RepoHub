import Foundation
import RepoHubCore
import Testing

@testable import RepoHub

extension GitHubRepositoryStatus {
    static func fixture(
        _ name: String,
        pulls: [PullRequest] = [],
        checks: CheckState? = nil
    ) -> GitHubRepositoryStatus {
        let repository = GitHubRepository(owner: "owner", name: name)
        return GitHubRepositoryStatus(
            repository: repository,
            pullRequests: pulls,
            checks: checks.map {
                Checks(
                    state: $0,
                    total: 3,
                    failed: $0 == .failure ? 1 : 0,
                    pending: $0 == .pending ? 1 : 0,
                    url: repository.webURL.appending(path: "actions")
                )
            }
        )
    }
}

extension GitHubRepositoryStatus.PullRequest {
    static func fixture(_ number: Int, head: String = "feature", review: Bool = false) -> Self {
        Self(
            number: number,
            title: "PR \(number)",
            url: GitHubRepository(owner: "owner", name: "r").webURL.appending(path: "pull/\(number)"),
            author: "ada",
            isDraft: false,
            headBranch: head,
            reviewRequested: review
        )
    }
}

@MainActor
@Suite("GitHub status")
struct GitHubStatusModelTests {
    let api = FakeAPI()

    /// An account signed in through the fake device flow.
    func signedIn() async -> AccountModel {
        await api.setPolls([.success(.signedIn(.fixture()))])
        let account = AccountModel(
            api: api,
            credentials: InMemoryCredentialStore(),
            workspace: FakeWorkspace(),
            sleep: { _ in }
        )
        account.signIn()
        await account.waitForSignIn()
        return account
    }

    func request(_ name: String, branch: String? = "main") -> GitHubStatusRequest {
        GitHubStatusRequest(repository: GitHubRepository(owner: "owner", name: name), branch: branch)
    }

    @Test("Signed out, nothing is requested and nothing is shown")
    func signedOut() async {
        let model = GitHubStatusModel(
            account: AccountModel(api: api, credentials: InMemoryCredentialStore(), workspace: FakeWorkspace()),
            api: api
        )

        await model.refresh([request("a")])

        #expect(model.statuses.isEmpty)
        #expect(await api.statusBatches.isEmpty)
    }

    @Test("Statuses are stored per repository and branch; duplicates are requested once")
    func refresh() async {
        await api.setGitHubStatus(.fixture("a", pulls: [.fixture(1)], checks: .success))
        let model = GitHubStatusModel(account: await signedIn(), api: api)

        await model.refresh([request("a"), request("a"), request("missing")])

        let alpha = GitHubRepository(owner: "owner", name: "a")
        #expect(model.status(for: alpha, branch: "main")?.pullRequests.map(\.number) == [1])
        #expect(model.status(for: alpha, branch: "other") == nil)
        let missing = GitHubRepository(owner: "owner", name: "missing")
        #expect(model.status(for: missing, branch: "main")?.error == "notFound")
        #expect(await api.statusBatches.map(\.count) == [2])
        #expect(model.lastUpdated != nil)
    }

    @Test("More than 100 repositories are sent in batches of 100")
    func batches() async {
        let model = GitHubStatusModel(account: await signedIn(), api: api)

        await model.refresh((0..<250).map { request("r\($0)") })

        #expect(await api.statusBatches.map(\.count).sorted() == [50, 100, 100])
        #expect(model.statuses.count == 250)
    }

    @Test("A failed refresh keeps the last statuses and reports the error")
    func failureKeepsStatuses() async {
        await api.setGitHubStatus(.fixture("a", checks: .failure))
        let model = GitHubStatusModel(account: await signedIn(), api: api)
        await model.refresh([request("a")])

        await api.setGitHubError(.unavailable("down"))
        await model.refresh([request("a")])

        #expect(model.statuses.count == 1)
        #expect(model.errorMessage != nil)
    }

    @Test("Updates report the previous and new statuses")
    func onUpdate() async {
        let model = GitHubStatusModel(account: await signedIn(), api: api)
        var updates: [(Int, Int)] = []
        model.onUpdate = { old, new in updates.append((old.count, new.count)) }

        await model.refresh([request("a")])
        await model.refresh([request("a"), request("b")])

        #expect(updates.map(\.0) == [0, 1] && updates.map(\.1) == [1, 2])
    }

    @Test("Rows sort failing CI first, then review requests, then running CI, then the rest")
    func sortKey() {
        func row(_ gitHub: GitHubRepositoryStatus?) -> DashboardRow {
            var row = DashboardRow(id: "/r", name: "r", path: "/r", state: nil)
            row.gitHub = gitHub
            return row
        }

        #expect(row(.fixture("a", checks: .failure)).gitHubSortKey == 3)
        #expect(row(.fixture("a", pulls: [.fixture(1, review: true)], checks: .success)).gitHubSortKey == 2)
        #expect(row(.fixture("a", checks: .pending)).gitHubSortKey == 1)
        #expect(row(.fixture("a")).gitHubSortKey == 0)
        #expect(row(nil).gitHubSortKey == -1)
        let notFound = GitHubRepositoryStatus(repository: .init(owner: "o", name: "a"), error: "notFound")
        #expect(row(notFound).gitHubSortKey == -1)
    }

    @Test("The current branch's pull request is found by head branch")
    func currentBranchPullRequest() {
        let status = GitHubRepositoryStatus.fixture("a", pulls: [.fixture(1, head: "x"), .fixture(2, head: "main")])

        #expect(status.pullRequest(for: "main")?.number == 2)
        #expect(status.pullRequest(for: nil) == nil)
        #expect(status.pullRequest(for: "none") == nil)
    }
}
