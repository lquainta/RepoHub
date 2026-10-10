import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting

@testable import App

/// Plays GitHub's side of the device flow.
private actor FakeGitHubOAuth: GitHubOAuth {
    private var results: [DeviceTokenResult]
    let profile = GitHubProfile(id: 583_231, login: "octocat", name: "The Octocat")

    init(results: [DeviceTokenResult]) {
        self.results = results
    }

    func requestDeviceCode(scopes: [String]) async throws -> DeviceCode {
        DeviceCode(
            deviceCode: "dc-1",
            userCode: "WDJB-MJHT",
            verificationURI: "https://github.com/login/device",
            expiresIn: 899,
            interval: 5
        )
    }

    func pollToken(deviceCode: String) async throws -> DeviceTokenResult {
        results.isEmpty ? .expired : results.removeFirst()
    }

    func user(token: String) async throws -> GitHubProfile {
        profile
    }
}

/// Decodes the parts of a session response the tests need.
private struct SessionBody: Decodable {
    struct Profile: Decodable {
        let id: String
        let login: String
    }

    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let user: Profile
}

extension DatabaseIntegrationTests {
    @Suite("Auth flow")
    struct AuthFlowTests {
        private func post(
            _ app: Application,
            _ path: String,
            json: String,
            token: String? = nil
        ) async throws -> TestingHTTPResponse {
            var headers = HTTPHeaders()
            if let token {
                headers.bearerAuthorization = BearerAuthorization(token: token)
            }
            return try await app.send(.POST, path, json: json, headers: headers)
        }

        private func me(_ app: Application, token: String) async throws -> HTTPStatus {
            var status: HTTPStatus = .internalServerError
            try await app.testing().test(.GET, "me", headers: ["Authorization": "Bearer \(token)"]) { res async in
                status = res.status
            }
            return status
        }

        @Test("Sign in, use, refresh, and sign out; tokens stop working when they should")
        func fullFlow() async throws {
            try await withMigratedApp { app in
                let github = FakeGitHubOAuth(results: [
                    .pending, .approved(token: "gho_real_token", scopes: "repo,read:user"),
                ])
                app.githubOAuth = github

                let start = try await post(app, "auth/device", json: "")
                #expect(start.status == .ok)
                #expect(start.body.string.contains("WDJB-MJHT"))

                let poll = #"{"deviceCode":"dc-1","deviceName":"Ada's MacBook"}"#
                let pending = try await post(app, "auth/device/token", json: poll)
                #expect(pending.status == .accepted)

                let signedIn = try await post(app, "auth/device/token", json: poll)
                #expect(signedIn.status == .ok)
                let session = try signedIn.content.decode(SessionBody.self)
                #expect(session.tokenType == "Bearer" && session.expiresIn == 900 && session.user.login == "octocat")

                // The GitHub token is stored encrypted, never in plain text.
                let user = try #require(try await User.query(on: app.db).first())
                #expect(user.githubTokenCiphertext.range(of: Data("gho_real_token".utf8)) == nil)
                #expect(try app.authService(on: app.db).githubToken(for: user) == "gho_real_token")

                #expect(try await me(app, token: session.accessToken) == .ok)

                // Refresh rotates: the new refresh token works, the old one doesn't.
                let refreshed = try await post(
                    app,
                    "auth/refresh",
                    json: #"{"refreshToken":"\#(session.refreshToken)"}"#
                )
                #expect(refreshed.status == .ok)
                let second = try refreshed.content.decode(SessionBody.self)
                #expect(second.refreshToken != session.refreshToken)
                let reused = try await post(app, "auth/refresh", json: #"{"refreshToken":"\#(session.refreshToken)"}"#)
                #expect(reused.status == .unauthorized)

                // Signing out revokes the device: its access tokens stop working at once.
                let signOut = try await post(app, "auth/signout", json: "", token: second.accessToken)
                #expect(signOut.status == .noContent)
                #expect(try await me(app, token: second.accessToken) == .unauthorized)
                let afterSignOut = try await post(
                    app,
                    "auth/refresh",
                    json: #"{"refreshToken":"\#(second.refreshToken)"}"#
                )
                #expect(afterSignOut.status == .unauthorized)

                // That was the only device, so the GitHub token is erased.
                let erased = try #require(try await User.query(on: app.db).first())
                #expect(erased.githubTokenCiphertext.isEmpty)
            }
        }

        @Test("An expired or denied device code is a 400")
        func expiredAndDenied() async throws {
            try await withMigratedApp { app in
                app.githubOAuth = FakeGitHubOAuth(results: [.expired, .denied])
                let poll = #"{"deviceCode":"dc-1","deviceName":"Mac"}"#
                let expired = try await post(app, "auth/device/token", json: poll).status
                let denied = try await post(app, "auth/device/token", json: poll).status
                let blankName = try await post(
                    app,
                    "auth/device/token",
                    json: #"{"deviceCode":"dc-1","deviceName":"   "}"#
                ).status
                #expect(expired == .badRequest)
                #expect(denied == .badRequest)
                #expect(blankName == .badRequest)
            }
        }

        @Test("A signed webhook is stored once, even when GitHub redelivers it")
        func webhookStoredOnce() async throws {
            try await withApp { app in
                try await configure(app, reader: TestDatabase.reader(["GITHUB_WEBHOOK_SECRET": "s3cret"]))
                try await app.autoRevert()
                try await app.autoMigrate()
                let body = #"{"action":"completed","repository":{"full_name":"octocat/hello"}}"#
                for _ in 0..<2 {
                    let response = try await app.sendWebhook(body, delivery: "delivery-42", secret: "s3cret")
                    #expect(response.status == .accepted)
                }
                let events = try await WebhookEvent.query(on: app.db).all()
                #expect(events.map(\.deliveryID) == ["delivery-42"])
                #expect(events.first?.action == "completed" && events.first?.repoFullName == "octocat/hello")
                try await app.autoRevert()
            }
        }
    }
}
