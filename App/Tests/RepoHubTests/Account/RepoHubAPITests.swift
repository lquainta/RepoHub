import Foundation
import RepoHubCore
import Testing

@testable import RepoHub

/// ``RepoHubAPI`` through the generated client, against responses served from memory.
@Suite("RepoHub API client")
struct RepoHubAPITests {
    let server = StubServer()

    func api(_ status: Int, _ body: String = "", contentType: String = "application/json") -> RepoHubAPI {
        RepoHubAPI(
            baseURL: server.baseURL,
            session: server.session(answering: .init(status: status, body: body, contentType: contentType))
        )
    }

    static let user = """
        {"id":"7B0C1C4E-0000-4000-8000-000000000001","login":"octocat","name":"Octo",
         "avatarURL":"https://example.com/a.png"}
        """
    static let session = """
        {"accessToken":"a","refreshToken":"r","tokenType":"Bearer","expiresIn":900,"user":\(user)}
        """
    static let error = #"{"error":true,"reason":"because"}"#
    static let date = Date(timeIntervalSince1970: 1_750_000_000)
    static let groupID = UUID()
    static var group: String {
        """
        {"id":"\(groupID.uuidString)","name":"Work","sortOrder":2,"members":["github.com/o/r"],
         "updatedAt":"2025-06-15T15:06:40Z"}
        """
    }

    // MARK: - Success

    @Test("Starting a sign-in returns the code and where to enter it")
    func startDeviceSignIn() async throws {
        let body = """
            {"deviceCode":"dc","userCode":"WDJB-MJHT","verificationURI":"https://github.com/login/device",
             "expiresIn":900,"interval":5}
            """
        let authorization = try await api(200, body).startDeviceSignIn()
        #expect(
            authorization
                == DeviceAuthorization(
                    deviceCode: "dc",
                    userCode: "WDJB-MJHT",
                    verificationURL: try #require(URL(string: "https://github.com/login/device")),
                    expiresIn: .seconds(900),
                    interval: .seconds(5)
                )
        )
        #expect(server.requests.map(\.target) == ["/auth/device"])
        #expect(server.requests.first?.authorization == nil)
    }

    @Test("A verification address that isn't a URL is an unexpected response")
    func startDeviceSignInBadURL() async {
        let body = #"{"deviceCode":"dc","userCode":"c","verificationURI":"","expiresIn":900,"interval":5}"#
        await #expect(throws: APIError.unexpectedResponse(statusCode: 200)) {
            try await api(200, body).startDeviceSignIn()
        }
    }

    @Test("Polling returns the session once approved, and the interval while pending")
    func pollDeviceSignIn() async throws {
        let signedIn = try await api(200, Self.session).pollDeviceSignIn(deviceCode: "dc", deviceName: "Mac")
        guard case .signedIn(let session) = signedIn else {
            Issue.record("Expected a session, got \(signedIn)")
            return
        }
        #expect(session.accessToken == "a")
        #expect(session.refreshToken == "r")
        #expect(session.expiresIn == .seconds(900))
        #expect(session.user.login == "octocat")
        #expect(session.user.name == "Octo")
        #expect(session.user.avatarURL == URL(string: "https://example.com/a.png"))
        let sent = try #require(server.requests.first)
        #expect(sent.body.contains(#""deviceCode":"dc""#))
        #expect(sent.body.contains(#""deviceName":"Mac""#))

        let pending = try await api(202, #"{"status":"pending","interval":10}"#)
            .pollDeviceSignIn(deviceCode: "dc", deviceName: "Mac")
        #expect(pending == .pending(interval: .seconds(10)))
    }

    @Test("A rejected sign-in carries the server's reason")
    func pollRejected() async {
        await #expect(throws: APIError.signInRejected("because")) {
            try await api(400, Self.error).pollDeviceSignIn(deviceCode: "dc", deviceName: "Mac")
        }
    }

    @Test("Refreshing exchanges the refresh token for a new session")
    func refreshSession() async throws {
        let session = try await api(200, Self.session).refreshSession(refreshToken: "old")
        #expect(session.accessToken == "a")
        #expect(server.requests.first?.body.contains(#""refreshToken":"old""#) == true)
    }

    @Test("Authenticated calls send the access token as a bearer token")
    func bearerToken() async throws {
        try await api(204).signOut(accessToken: "token")
        let user = try await api(200, Self.user).currentUser(accessToken: "token")
        #expect(user.login == "octocat")
        #expect(server.requests.map(\.target) == ["/auth/signout", "/me"])
        #expect(server.requests.map(\.authorization) == ["Bearer token", "Bearer token"])
    }

    @Test("Statuses map pull requests and checks, and drop ones whose links aren't URLs")
    func repositoryStatuses() async throws {
        let body = """
            {"repositories":[
              {"owner":"o","name":"r",
               "pullRequests":[
                 {"number":7,"title":"Fix","url":"https://github.com/o/r/pull/7","author":"me","isDraft":true,
                  "headBranch":"fix","reviewRequested":true},
                 {"number":8,"title":"Bad link","url":"","author":"me","isDraft":false,
                  "headBranch":"bad","reviewRequested":false}],
               "checks":{"state":"failure","total":3,"failed":1,"pending":0,"url":"https://github.com/o/r/runs/1"}},
              {"owner":"o","name":"gone","pullRequests":[],"error":"notFound"},
              {"owner":"o","name":"badchecks","pullRequests":[],
               "checks":{"state":"success","total":1,"failed":0,"pending":0,"url":""}}
            ]}
            """
        let requests = [
            GitHubStatusRequest(repository: GitHubRepository(owner: "o", name: "r"), branch: "fix"),
            GitHubStatusRequest(repository: GitHubRepository(owner: "o", name: "gone"), branch: nil),
        ]
        let statuses = try await api(200, body).repositoryStatuses(requests, accessToken: "t")

        #expect(statuses.count == 3)
        #expect(statuses[0].repository == GitHubRepository(owner: "o", name: "r"))
        #expect(
            statuses[0].pullRequests == [
                .init(
                    number: 7,
                    title: "Fix",
                    url: try #require(URL(string: "https://github.com/o/r/pull/7")),
                    author: "me",
                    isDraft: true,
                    headBranch: "fix",
                    reviewRequested: true
                )
            ]
        )
        #expect(
            statuses[0].checks
                == .init(
                    state: .failure,
                    total: 3,
                    failed: 1,
                    pending: 0,
                    url: try #require(URL(string: "https://github.com/o/r/runs/1"))
                )
        )
        #expect(statuses[1].error == "notFound")
        #expect(statuses[1].checks == nil)
        #expect(statuses[2].checks == nil)
        let sent = try #require(server.requests.first)
        #expect(sent.target == "/github/status")
        #expect(sent.body.contains(#""branch":"fix""#))
    }

    @Test("The workspace maps settings and groups, skipping a group whose ID isn't a UUID")
    func workspace() async throws {
        let body = """
            {"serverTime":"2025-06-15T15:06:40Z",
             "settings":{"staleBranchDays":45,"updatedAt":"2025-06-15T15:06:40Z"},
             "groups":[\(Self.group),
               {"id":"nope","name":"Bad","sortOrder":0,"members":[],"updatedAt":"2025-06-15T15:06:40Z"}]}
            """
        let workspace = try await api(200, body).workspace(since: Self.date, accessToken: "t")
        #expect(workspace.serverTime == Self.date)
        #expect(workspace.settings == SyncedSettings(staleBranchDays: 45, updatedAt: Self.date))
        #expect(
            workspace.groups == [
                SyncedGroup(
                    id: Self.groupID,
                    name: "Work",
                    sortOrder: 2,
                    members: ["github.com/o/r"],
                    updatedAt: Self.date,
                    deletedAt: nil
                )
            ]
        )
        #expect(server.requests.first?.target.hasPrefix("/workspace?since=2025-06-15") == true)

        _ = try await api(200, body).workspace(since: nil, accessToken: "t")
        #expect(server.requests.last?.target == "/workspace")
    }

    @Test("Updating settings sends them and returns what's stored")
    func updateSettings() async throws {
        let stored = try await api(200, #"{"updatedAt":"2025-06-15T15:06:40Z"}"#)
            .updateSettings(SyncedSettings(staleBranchDays: 30, updatedAt: Self.date), accessToken: "t")
        #expect(stored == SyncedSettings(staleBranchDays: nil, updatedAt: Self.date))
        let sent = try #require(server.requests.first)
        #expect(sent.method == "PATCH")
        #expect(sent.body.contains(#""staleBranchDays":30"#))
    }

    @Test("Saving a group returns the stored group; deleting one sends when it was deleted")
    func groups() async throws {
        let group = SyncedGroup(
            id: Self.groupID,
            name: "Work",
            sortOrder: 2,
            members: ["github.com/o/r"],
            updatedAt: Self.date,
            deletedAt: nil
        )
        #expect(try await api(200, Self.group).putGroup(group, accessToken: "t") == group)
        #expect(server.requests.first?.target == "/workspace/groups/\(Self.groupID.uuidString)")
        #expect(server.requests.first?.body.contains(#""name":"Work""#) == true)

        try await api(204).deleteGroup(id: Self.groupID, deletedAt: Self.date, accessToken: "t")
        let delete = try #require(server.requests.last)
        #expect(delete.method == "DELETE")
        #expect(delete.target.hasPrefix("/workspace/groups/\(Self.groupID.uuidString)?deletedAt=2025-06-15"))
    }

    @Test("A stored group whose ID isn't a UUID is an unexpected response")
    func putGroupBadID() async {
        let group = SyncedGroup(id: Self.groupID, name: "Work", sortOrder: 0, members: [], updatedAt: Self.date)
        let body = #"{"id":"nope","name":"Work","sortOrder":0,"members":[],"updatedAt":"2025-06-15T15:06:40Z"}"#
        await #expect(throws: APIError.unexpectedResponse(statusCode: 200)) {
            try await api(200, body).putGroup(group, accessToken: "t")
        }
    }

    @Test("Snapshots send the capture only when there is one; activity maps each repository's days")
    func activity() async throws {
        try await api(204).uploadSnapshots(
            [
                ActivitySnapshot(
                    repository: "github.com/o/r",
                    day: "2025-06-15",
                    commits: 3,
                    capture: SnapshotCapture(dirty: true, ahead: 1, behind: 2)
                ),
                ActivitySnapshot(repository: "github.com/o/r", day: "2025-06-14", commits: 1, capture: nil),
            ],
            accessToken: "t"
        )
        let sent = try #require(server.requests.first)
        #expect(sent.target == "/activity/snapshots")
        #expect(sent.body.contains(#""dirty":true"#))
        #expect(sent.body.components(separatedBy: #""ahead""#).count == 2)

        let body = """
            {"days":30,"repositories":[{"repository":"github.com/o/r","name":"r",
              "days":[{"day":"2025-06-15","commits":3,"dirty":true}]}]}
            """
        let activity = try await api(200, body).activity(days: 30, accessToken: "t")
        #expect(
            activity == [
                RepositoryActivity(
                    repository: "github.com/o/r",
                    name: "r",
                    days: [.init(day: "2025-06-15", commits: 3, dirty: true)]
                )
            ]
        )
        #expect(server.requests.last?.target == "/activity?days=30")
    }

    @Test("The event stream yields each changed repository and skips keep-alives and bad data")
    func repositoryChanges() async throws {
        let body = """
            : keep-alive

            event: repository
            data: {"owner":"o","name":"r","event":"push"}

            event: repository
            data: not json

            event: other
            data: {"owner":"x","name":"y","event":"push"}

            event: repository
            data: {"owner":"o","name":"second","event":"check_run"}


            """
        let stream = try await api(200, body, contentType: "text/event-stream").repositoryChanges(accessToken: "t")
        var changed: [GitHubRepository] = []
        for try await repository in stream {
            changed.append(repository)
        }
        #expect(changed == [GitHubRepository(owner: "o", name: "r"), GitHubRepository(owner: "o", name: "second")])
        #expect(server.requests.first?.authorization == "Bearer t")
    }
}

/// The error statuses of every operation.
@Suite("RepoHub API client errors")
struct RepoHubAPIErrorTests {
    typealias Fixture = RepoHubAPITests

    let server = StubServer()

    func api(_ status: Int, _ body: String = "") -> RepoHubAPI {
        RepoHubAPI(baseURL: server.baseURL, session: server.session(answering: .init(status: status, body: body)))
    }

    static let date = Fixture.date
    static let groupID = Fixture.groupID

    /// Every operation, so each error status can be checked against all of them.
    static let operations: [(name: String, call: @Sendable (RepoHubAPI) async throws -> Void)] = [
        ("startDeviceSignIn", { _ = try await $0.startDeviceSignIn() }),
        ("pollDeviceSignIn", { _ = try await $0.pollDeviceSignIn(deviceCode: "dc", deviceName: "Mac") }),
        ("refreshSession", { _ = try await $0.refreshSession(refreshToken: "r") }),
        ("signOut", { try await $0.signOut(accessToken: "t") }),
        ("currentUser", { _ = try await $0.currentUser(accessToken: "t") }),
        (
            "repositoryStatuses",
            {
                _ = try await $0.repositoryStatuses(
                    [.init(repository: GitHubRepository(owner: "o", name: "r"), branch: nil)],
                    accessToken: "t"
                )
            }
        ),
        ("workspace", { _ = try await $0.workspace(since: nil, accessToken: "t") }),
        (
            "updateSettings",
            { _ = try await $0.updateSettings(SyncedSettings(staleBranchDays: nil, updatedAt: date), accessToken: "t") }
        ),
        (
            "putGroup",
            {
                _ = try await $0.putGroup(
                    SyncedGroup(id: groupID, name: "Work", sortOrder: 0, members: [], updatedAt: date),
                    accessToken: "t"
                )
            }
        ),
        ("deleteGroup", { try await $0.deleteGroup(id: groupID, deletedAt: date, accessToken: "t") }),
        ("uploadSnapshots", { try await $0.uploadSnapshots([], accessToken: "t") }),
        ("activity", { _ = try await $0.activity(days: 30, accessToken: "t") }),
        ("repositoryChanges", { _ = try await $0.repositoryChanges(accessToken: "t") }),
    ]

    /// The operations that don't need a session.
    static let signInOperations: Set<String> = ["startDeviceSignIn", "pollDeviceSignIn"]
    /// The operations that validate a request body.
    static let validatingOperations: Set<String> = ["repositoryStatuses", "putGroup", "uploadSnapshots"]

    @Test("Every operation maps 429 to rate limited and an undocumented status to an unexpected response")
    func commonErrors() async {
        for operation in Self.operations {
            await #expect(throws: APIError.rateLimited, "\(operation.name)") {
                try await operation.call(api(429, Fixture.error))
            }
            await #expect(throws: APIError.unexpectedResponse(statusCode: 418), "\(operation.name)") {
                try await operation.call(api(418))
            }
        }
    }

    @Test("Every operation that needs a session maps 401 to unauthorized")
    func unauthorized() async {
        for operation in Self.operations where !Self.signInOperations.contains(operation.name) {
            await #expect(throws: APIError.unauthorized, "\(operation.name)") {
                try await operation.call(api(401, Fixture.error))
            }
        }
    }

    @Test("Sign-in maps 502 and 503 to unavailable, with the server's reason")
    func signInUnavailable() async {
        for operation in Self.operations where Self.signInOperations.contains(operation.name) {
            for status in [502, 503] {
                await #expect(throws: APIError.unavailable("because"), "\(operation.name) \(status)") {
                    try await operation.call(api(status, Fixture.error))
                }
            }
        }
    }

    @Test("A request the server rejects as invalid carries its reason")
    func badRequest() async {
        for operation in Self.operations where Self.validatingOperations.contains(operation.name) {
            await #expect(throws: APIError.unavailable("because"), "\(operation.name)") {
                try await operation.call(api(400, Fixture.error))
            }
        }
    }

    @Test("Each error has a message for the user")
    func errorDescriptions() {
        let errors: [APIError] = [
            .unauthorized, .signInRejected("denied"), .rateLimited, .unavailable("down"),
            .unexpectedResponse(statusCode: 500),
        ]
        let messages = errors.compactMap(\.errorDescription)
        #expect(messages.count == errors.count)
        #expect(Set(messages).count == errors.count)
        #expect(messages[1].contains("denied"))
        #expect(messages[3].contains("down"))
        #expect(messages[4].contains("500"))
    }
}
