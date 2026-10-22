import Foundation
import Testing
import Vapor
import VaporTesting

@testable import App

/// Answers each request with the next canned JSON body and records requests.
private final class ScriptedClient: Client, @unchecked Sendable {
    let eventLoop: any EventLoop
    private var bodies: [(HTTPStatus, String)]
    private(set) var requests: [ClientRequest] = []

    init(eventLoop: any EventLoop, _ bodies: [(HTTPStatus, String)]) {
        self.eventLoop = eventLoop
        self.bodies = bodies
    }

    func send(_ request: ClientRequest) -> EventLoopFuture<ClientResponse> {
        requests.append(request)
        let (status, body) = bodies.isEmpty ? (.internalServerError, "{}") : bodies.removeFirst()
        return eventLoop.makeSucceededFuture(
            ClientResponse(
                status: status,
                headers: ["Content-Type": "application/json"],
                body: ByteBuffer(string: body)
            )
        )
    }

    func delegating(to eventLoop: any EventLoop) -> any Client { self }
}

@Suite("VaporGitHubOAuth")
struct GitHubOAuthTests {
    private static let deviceCodeJSON =
        #"{"device_code":"dc","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device","#
        + #""expires_in":899,"interval":5}"#
    private static let userJSON =
        #"{"id":583231,"login":"octocat","name":"The Octocat","#
        + #""avatar_url":"https://avatars.githubusercontent.com/u/583231"}"#

    @Test("Parses the device code and sends the client ID and scopes as a form")
    func deviceCode() async throws {
        try await withApp { app in
            let client = ScriptedClient(
                eventLoop: app.eventLoopGroup.any(),
                [
                    (
                        .ok,
                        Self.deviceCodeJSON
                    )
                ]
            )
            let code = try await VaporGitHubOAuth(client: client, clientID: "Ov23li").requestDeviceCode(scopes: [
                "repo", "read:user",
            ])

            #expect(
                code
                    == DeviceCode(
                        deviceCode: "dc",
                        userCode: "WDJB-MJHT",
                        verificationURI: "https://github.com/login/device",
                        expiresIn: 899,
                        interval: 5
                    )
            )
            let request = try #require(client.requests.first)
            #expect(request.url.string == "https://github.com/login/device/code")
            #expect(request.body.map { String(buffer: $0) }?.contains("client_id=Ov23li") == true)
            let form = request.body.map { String(buffer: $0) } ?? ""
            #expect(form.contains("scope=repo%20read%3Auser"))
        }
    }

    @Test(
        "Maps every device flow response",
        arguments: [
            (
                #"{"access_token":"gho_x","token_type":"bearer","scope":"repo,read:user"}"#,
                DeviceTokenResult.approved(token: "gho_x", scopes: "repo,read:user")
            ),
            (#"{"error":"authorization_pending"}"#, .pending),
            (#"{"error":"slow_down","interval":15}"#, .slowDown(interval: 15)),
            (#"{"error":"expired_token"}"#, .expired),
            (#"{"error":"access_denied"}"#, .denied),
        ]
    )
    func pollResults(body: String, expected: DeviceTokenResult) async throws {
        try await withApp { app in
            let client = ScriptedClient(eventLoop: app.eventLoopGroup.any(), [(.ok, body)])
            let result = try await VaporGitHubOAuth(client: client, clientID: "id").pollToken(deviceCode: "dc")
            #expect(result == expected)
        }
    }

    @Test("Unknown device flow errors and failed requests throw")
    func pollErrors() async throws {
        try await withApp { app in
            let client = ScriptedClient(
                eventLoop: app.eventLoopGroup.any(),
                [
                    (.ok, #"{"error":"incorrect_client_credentials"}"#), (.badGateway, "{}"),
                ]
            )
            let oauth = VaporGitHubOAuth(client: client, clientID: "id")
            await #expect(throws: GitHubOAuthError.self) { try await oauth.pollToken(deviceCode: "dc") }
            await #expect(throws: GitHubOAuthError.self) { try await oauth.pollToken(deviceCode: "dc") }
        }
    }

    @Test("Reads the user's profile with the token")
    func user() async throws {
        try await withApp { app in
            let client = ScriptedClient(
                eventLoop: app.eventLoopGroup.any(),
                [
                    (
                        .ok,
                        Self.userJSON
                    )
                ]
            )
            let profile = try await VaporGitHubOAuth(client: client, clientID: "id").user(token: "gho_x")
            #expect(
                profile
                    == GitHubProfile(
                        id: 583_231,
                        login: "octocat",
                        name: "The Octocat",
                        avatarURL: "https://avatars.githubusercontent.com/u/583231"
                    )
            )
            #expect(client.requests.first?.headers.bearerAuthorization?.token == "gho_x")
        }
    }
}
