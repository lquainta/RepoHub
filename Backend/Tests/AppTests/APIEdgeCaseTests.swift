import Fluent
import Foundation
import RepoHubAPI
import Testing
import Vapor
import VaporTesting

@testable import App

/// A GitHub whose device flow always fails.
private struct BrokenGitHubOAuth: GitHubOAuth {
    func requestDeviceCode(scopes: [String]) async throws -> DeviceCode {
        throw GitHubOAuthError(reason: "Device code request failed with 500")
    }

    func pollToken(deviceCode: String) async throws -> DeviceTokenResult {
        throw GitHubOAuthError(reason: "Token request failed with 500")
    }

    func user(token: String) async throws -> GitHubProfile {
        throw GitHubOAuthError(reason: "User request failed with 500")
    }
}

private struct PendingBody: Decodable {
    let status: String
    let interval: Int
}

/// Sign-in failures that don't need a database.
@Suite("Sign-in failures")
struct SignInFailureTests {
    private let poll = #"{"deviceCode":"dc-1","deviceName":"Mac"}"#

    private func withConfiguredApp(_ body: (Application) async throws -> Void) async throws {
        try await withApp { app in
            try await configure(app, reader: TestDatabase.reader())
            try await body(app)
        }
    }

    @Test("When GitHub fails, starting and polling a sign-in answer 502 without GitHub's details")
    func gitHubFails() async throws {
        try await withConfiguredApp { app in
            app.githubOAuth = BrokenGitHubOAuth()
            let start = try await app.send(.POST, "auth/device", json: "")
            #expect(start.status == .badGateway)
            #expect(try !start.content.decode(ErrorResponse.self).reason.contains("500"))
            #expect(try await app.send(.POST, "auth/device/token", json: poll).status == .badGateway)
        }
    }

    @Test("When GitHub asks the app to slow down, the poll answers 202 with the new interval")
    func slowDown() async throws {
        try await withConfiguredApp { app in
            app.githubOAuth = FakeGitHubOAuth(results: [.slowDown(interval: 15)])
            let response = try await app.send(.POST, "auth/device/token", json: poll)
            #expect(response.status == .accepted)
            let body = try response.content.decode(PendingBody.self)
            #expect(body.status == "slowDown" && body.interval == 15)
        }
    }

    @Test("Polling answers 503 when GITHUB_CLIENT_ID isn't configured")
    func pollNotConfigured() async throws {
        try await withConfiguredApp { app in
            let status = try await app.send(.POST, "auth/device/token", json: poll).status
            #expect(status == .serviceUnavailable)
        }
    }

    @Test("A handler that runs without a signed-in user fails with 401")
    func requireUser() async throws {
        #expect(throws: Abort.self) { try APIHandler.requireUser() }
        let user = AuthenticatedUser(userID: UUID(), deviceID: UUID())
        let found = try RequestContext.$user.withValue(user) { try APIHandler.requireUser() }
        #expect(found == user)
    }
}

private struct SettingsBody: Decodable {
    let staleBranchDays: Int?
}

private struct StatusBody: Decodable {
    struct Checks: Decodable {
        let state: String
        let total: Int
        let failed: Int
        let pending: Int
        let url: String
    }

    struct Repository: Decodable {
        let checks: Checks?
    }

    let repositories: [Repository]
}

extension DatabaseIntegrationTests {
    /// Routes and branches the other route tests don't reach.
    @Suite("API edge cases")
    struct APIEdgeCaseTests {
        private func bearer(_ token: String) -> HTTPHeaders {
            var headers = HTTPHeaders()
            headers.bearerAuthorization = BearerAuthorization(token: token)
            return headers
        }

        @Test("PATCH /workspace stores settings, keeping the stale-branch days within 0...3650")
        func settingsRoute() async throws {
            try await withMigratedApp { app in
                let headers = bearer(try await app.signInWithFakeGitHub())
                let patch = #"{"staleBranchDays":99999,"updatedAt":"2027-01-01T00:00:00Z"}"#
                let response = try await app.send(.PATCH, "workspace", json: patch, headers: headers)
                #expect(response.status == .ok)
                #expect(try response.content.decode(SettingsBody.self).staleBranchDays == 3_650)

                let older = #"{"staleBranchDays":7,"updatedAt":"2026-01-01T00:00:00Z"}"#
                let ignored = try await app.send(.PATCH, "workspace", json: older, headers: headers)
                #expect(try ignored.content.decode(SettingsBody.self).staleBranchDays == 3_650)
                #expect(try await app.send(.PATCH, "workspace", json: patch).status == .unauthorized)
            }
        }

        @Test("A group with a blank name and an upload without snapshots are 400s")
        func invalidBodies() async throws {
            try await withMigratedApp { app in
                let headers = bearer(try await app.signInWithFakeGitHub())
                let id = UUID().uuidString
                let group =
                    #"{"id":"\#(id)","name":"   ","sortOrder":0,"members":[],"updatedAt":"2027-01-01T00:00:00Z"}"#
                #expect(
                    try await app.send(.PUT, "workspace/groups/\(id)", json: group, headers: headers).status
                        == .badRequest
                )
                #expect(
                    try await app.send(.POST, "activity/snapshots", json: #"{"snapshots":[]}"#, headers: headers)
                        .status == .badRequest
                )
            }
        }

        @Test("Checks on the requested branch are returned with the status")
        func statusWithChecks() async throws {
            try await withMigratedApp { app in
                let api = FakeGitHubAPI()
                await api.respond(
                    to: GitHubResource.pullRequests.path(owner: "o", name: "r"),
                    with: .success(GitHubResponse(status: .ok, body: GitHubFixtures.pulls(), etag: nil))
                )
                let runs = GitHubFixtures.runs(
                    GitHubFixtures.run("completed", "failure", id: 1),
                    GitHubFixtures.run("in_progress", nil, id: 2)
                )
                await api.respond(
                    to: GitHubResource.checkRuns(ref: "main").path(owner: "o", name: "r"),
                    with: .success(GitHubResponse(status: .ok, body: runs, etag: nil))
                )
                app.githubAPI = api
                let headers = bearer(try await app.signInWithFakeGitHub())

                let response = try await app.send(
                    .POST,
                    "github/status",
                    json: #"{"repositories":[{"owner":"o","name":"r","branch":"main"}]}"#,
                    headers: headers
                )
                let checks = try #require(try response.content.decode(StatusBody.self).repositories.first?.checks)
                #expect(checks.state == "failure" && checks.total == 2 && checks.failed == 1 && checks.pending == 1)
                #expect(checks.url == "https://github.com/o/r/runs/1")
            }
        }

        @Test("An access token that outlives its account gets 401 from the account and status operations")
        func deletedAccount() async throws {
            try await withMigratedApp { app in
                let ghost = AuthenticatedUser(userID: UUID(), deviceID: UUID())
                let handler = APIHandler(app: app)
                try await RequestContext.$user.withValue(ghost) {
                    guard case .unauthorized = try await handler.getCurrentUser(.init()) else {
                        Issue.record("Expected 401 for a deleted account")
                        return
                    }
                    let body = Components.Schemas.RepositoryStatusRequest(repositories: [.init(owner: "o", name: "r")])
                    guard case .unauthorized = try await handler.getRepositoryStatuses(.init(body: .json(body))) else {
                        Issue.record("Expected 401 for a deleted account")
                        return
                    }
                }
            }
        }

        @Test("Opening the event stream subscribes the signed-in user")
        func eventStreamSubscribes() async throws {
            try await withMigratedApp { app in
                let user = AuthenticatedUser(userID: UUID(), deviceID: UUID())
                try await RequestContext.$user.withValue(user) {
                    guard case .ok = try await APIHandler(app: app).streamEvents(.init()) else {
                        Issue.record("Expected the stream to open")
                        return
                    }
                }
                #expect(await app.eventHub.subscriberCount == 1)
            }
        }
    }
}
