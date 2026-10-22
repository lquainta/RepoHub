import Foundation
import Testing
import Vapor
import VaporTesting

@testable import App

/// GitHub JSON for the tests, trimmed to the fields RepoHub reads.
enum GitHubFixtures {
    static func pull(
        _ number: Int,
        author: String = "octocat",
        head: String = "feature",
        draft: Bool = false,
        reviewers: [String] = []
    ) -> String {
        let requested = reviewers.map { #"{"login":"\#($0)"}"# }.joined(separator: ",")
        return #"""
            {"number":\#(number),"title":"PR \#(number)","html_url":"https://github.com/o/r/pull/\#(number)",\#
            "user":{"login":"\#(author)"},"draft":\#(draft),"head":{"ref":"\#(head)"},\#
            "requested_reviewers":[\#(requested)]}
            """#
    }

    static func pulls(_ pulls: String...) -> Data {
        Data("[\(pulls.joined(separator: ","))]".utf8)
    }

    static func run(_ status: String, _ conclusion: String?, id: Int) -> String {
        let conclusion = conclusion.map { #""\#($0)""# } ?? "null"
        return #"""
            {"status":"\#(status)","conclusion":\#(conclusion),"html_url":"https://github.com/o/r/runs/\#(id)"}
            """#
    }

    static func runs(_ runs: String...) -> Data {
        Data(#"{"total_count":\#(runs.count),"check_runs":[\#(runs.joined(separator: ","))]}"#.utf8)
    }
}

@Suite("Repository status")
struct RepositoryStatusTests {
    private let pullsPath = GitHubResource.pullRequests.path(owner: "o", name: "r")
    private let mainChecksPath = GitHubResource.checkRuns(ref: "main").path(owner: "o", name: "r")

    private func service(_ api: FakeGitHubAPI) -> RepositoryStatusService {
        RepositoryStatusService(cache: GitHubCache(store: InMemoryCacheStore(), api: api))
    }

    private func ok(_ body: Data) -> Result<GitHubResponse, GitHubError> {
        .success(GitHubResponse(status: .ok, body: body, etag: nil))
    }

    @Test("Pull requests are summarized and review requests for the user are marked, ignoring case")
    func pullRequests() throws {
        let body = GitHubFixtures.pulls(
            GitHubFixtures.pull(2, author: "ada", head: "fix", draft: true, reviewers: ["OctoCat", "bob"]),
            GitHubFixtures.pull(1, reviewers: ["bob"])
        )

        let pulls = try RepositoryStatusService.pullRequests(from: body, login: "octocat")

        #expect(pulls.map(\.number) == [2, 1])
        #expect(pulls[0].reviewRequested && !pulls[1].reviewRequested)
        #expect(pulls[0].isDraft && pulls[0].author == "ada" && pulls[0].headBranch == "fix")
        #expect(pulls[0].url == "https://github.com/o/r/pull/2")
    }

    @Test(
        "Checks combine to failure, then pending, then success",
        arguments: [
            (["completed:success", "completed:failure", "in_progress:-"], "failure", 1, 1, 2),
            (["completed:success", "queued:-"], "pending", 0, 1, 1),
            (["completed:success", "completed:skipped", "completed:neutral"], "success", 0, 0, 1),
            (["completed:timed_out"], "failure", 1, 0, 1),
        ]
    )
    func combinedChecks(runs: [String], state: String, failed: Int, pending: Int, urlID: Int) throws {
        let body = runs.enumerated().map { index, run in
            let parts = run.split(separator: ":").map(String.init)
            return GitHubFixtures.run(parts[0], parts[1] == "-" ? nil : parts[1], id: index + 1)
        }
        let data = Data(#"{"total_count":\#(body.count),"check_runs":[\#(body.joined(separator: ","))]}"#.utf8)

        let checks = try #require(try RepositoryStatusService.checks(from: data))

        #expect(checks.state.rawValue == state)
        #expect(checks.total == runs.count && checks.failed == failed && checks.pending == pending)
        // The failing run if there is one, otherwise the most recent.
        #expect(checks.url == "https://github.com/o/r/runs/\(urlID)")
    }

    @Test("A commit without check runs has no checks")
    func noChecks() throws {
        #expect(try RepositoryStatusService.checks(from: GitHubFixtures.runs()) == nil)
    }

    @Test("Results come back in request order; a missing repository fails alone")
    func batch() async throws {
        let api = FakeGitHubAPI()
        await api.respond(to: pullsPath, with: ok(GitHubFixtures.pulls(GitHubFixtures.pull(7))))
        await api.respond(
            to: mainChecksPath,
            with: ok(GitHubFixtures.runs(GitHubFixtures.run("completed", "success", id: 1)))
        )
        let references = [
            RepositoryStatusService.Reference(owner: "gone", name: "repo", branch: "main"),
            RepositoryStatusService.Reference(owner: "o", name: "r", branch: "main"),
        ]

        let statuses = await service(api).statuses(for: references, userID: UUID(), login: "octocat", token: "t")

        #expect(statuses.map(\.owner) == ["gone", "o"])
        #expect(statuses[0].error == .notFound && statuses[0].pullRequests.isEmpty && statuses[0].checks == nil)
        #expect(statuses[1].error == nil && statuses[1].pullRequests.map(\.number) == [7])
        #expect(statuses[1].checks?.state == .success)
    }

    @Test("A branch that was never pushed has no checks but keeps its pull requests")
    func unpushedBranch() async throws {
        let api = FakeGitHubAPI()
        await api.respond(to: pullsPath, with: ok(GitHubFixtures.pulls(GitHubFixtures.pull(1))))

        let statuses = await service(api).statuses(
            for: [.init(owner: "o", name: "r", branch: "local-only")],
            userID: UUID(),
            login: "octocat",
            token: "t"
        )

        #expect(statuses[0].error == nil && statuses[0].checks == nil && statuses[0].pullRequests.count == 1)
    }

    @Test("No branch (detached HEAD) skips the check runs request")
    func detachedHead() async throws {
        let api = FakeGitHubAPI()
        await api.respond(to: pullsPath, with: ok(GitHubFixtures.pulls()))

        _ = await service(api).statuses(
            for: [.init(owner: "o", name: "r")],
            userID: UUID(),
            login: "octocat",
            token: "t"
        )

        #expect(await api.calls.map(\.path) == [pullsPath])
    }

    @Test(
        "GitHub errors map to the API's error codes",
        arguments: [
            (GitHubError.unauthorized, RepositoryGitHubStatus.Failure.unauthorized),
            (.rateLimited(resetAt: nil), .rateLimited),
            (.unexpectedStatus(502), .unavailable),
        ]
    )
    func errors(error: GitHubError, expected: RepositoryGitHubStatus.Failure) async throws {
        let api = FakeGitHubAPI()
        await api.respond(to: pullsPath, with: .failure(error))

        let statuses = await service(api).statuses(
            for: [.init(owner: "o", name: "r", branch: "main")],
            userID: UUID(),
            login: "octocat",
            token: "t"
        )

        #expect(statuses[0].error == expected)
    }

    @Test("Requests within the TTL are served from the cache")
    func cached() async throws {
        let api = FakeGitHubAPI()
        await api.respond(to: pullsPath, with: ok(GitHubFixtures.pulls()))
        let service = service(api)
        let user = UUID()

        for _ in 0..<3 {
            _ = await service.statuses(for: [.init(owner: "o", name: "r")], userID: user, login: "u", token: "t")
        }

        #expect(await api.calls.count == 1)
    }

    @Test("At most 8 repositories are fetched at once")
    func boundedConcurrency() async throws {
        let api = FakeGitHubAPI(delay: .milliseconds(20))
        let references = (0..<20).map { RepositoryStatusService.Reference(owner: "o", name: "r\($0)") }
        for reference in references {
            await api.respond(
                to: GitHubResource.pullRequests.path(owner: reference.owner, name: reference.name),
                with: ok(GitHubFixtures.pulls())
            )
        }

        let statuses = await service(api).statuses(for: references, userID: UUID(), login: "u", token: "t")

        #expect(statuses.map(\.name) == references.map(\.name))
        #expect(await api.peakConcurrency <= RepositoryStatusService.concurrency)
        #expect(await api.peakConcurrency > 1)
    }
}

/// The parts of `POST /github/status` responses the route test reads.
private struct PullBody: Decodable {
    let number: Int
    let reviewRequested: Bool
}

private struct RepositoryBody: Decodable {
    let owner: String
    let pullRequests: [PullBody]
    let checks: String?
    let error: String?
}

private struct StatusListBody: Decodable {
    let repositories: [RepositoryBody]
}

extension DatabaseIntegrationTests {
    @Suite("GitHub status route")
    struct GitHubStatusRouteTests {
        @Test("Signed-in users get pull requests and checks; others get 401; bad batches get 400")
        func route() async throws {
            try await withMigratedApp { app in
                let api = FakeGitHubAPI()
                await api.respond(
                    to: GitHubResource.pullRequests.path(owner: "o", name: "r"),
                    with: .success(
                        GitHubResponse(
                            status: .ok,
                            body: GitHubFixtures.pulls(GitHubFixtures.pull(3, reviewers: ["octocat"])),
                            etag: nil
                        )
                    )
                )
                app.githubAPI = api
                let token = try await app.signInWithFakeGitHub()
                let request = #"{"repositories":[{"owner":"o","name":"r","branch":"main"}]}"#

                let unauthenticated = try await app.send(.POST, "github/status", json: request)
                #expect(unauthenticated.status == .unauthorized)

                var headers = HTTPHeaders()
                headers.bearerAuthorization = BearerAuthorization(token: token)
                let response = try await app.send(.POST, "github/status", json: request, headers: headers)
                #expect(response.status == .ok)
                let body = try response.content.decode(StatusListBody.self)
                #expect(body.repositories.count == 1)
                #expect(body.repositories[0].pullRequests.first?.number == 3)
                #expect(body.repositories[0].pullRequests.first?.reviewRequested == true)
                // `main` has no check runs in the fake, which answers 404 like an unpushed branch.
                #expect(body.repositories[0].checks == nil && body.repositories[0].error == nil)

                let empty = try await app.send(.POST, "github/status", json: #"{"repositories":[]}"#, headers: headers)
                #expect(empty.status == .badRequest)
            }
        }
    }
}
