import Fluent
import Foundation
import OpenAPIRuntime
import Testing
import Vapor
import VaporTesting

@testable import App

@Suite("Live events")
struct EventTests {
    private let change = RepositoryChange(owner: "o", name: "r", event: "check_run")

    @Test("Changes reach only the streams of the users they concern, and closed streams unsubscribe")
    func hub() async throws {
        let hub = EventHub()
        let alice = UUID()
        let bob = UUID()
        let aliceStream = await hub.subscribe(user: alice)
        var bobStream: AsyncStream<RepositoryChange>? = await hub.subscribe(user: bob)
        #expect(await hub.subscriberCount == 2)

        await hub.publish(change, to: [alice])
        var iterator = aliceStream.makeAsyncIterator()
        #expect(await iterator.next() == change)

        bobStream = nil
        _ = bobStream
        try await Task.sleep(for: .milliseconds(50))
        #expect(await hub.subscriberCount == 1)
    }

    @Test("The stream sends repository events as JSON, keep-alives, and ends after its lifetime")
    func eventStream() async throws {
        let (changes, continuation) = AsyncStream.makeStream(of: RepositoryChange.self)
        let events = APIHandler.eventStream(changes, keepAlive: .milliseconds(40), lifetime: .milliseconds(150))
        continuation.yield(change)

        var received: [ServerSentEvent] = []
        for await event in events {
            received.append(event)
        }

        let json = #"{"event":"check_run","name":"r","owner":"o"}"#
        #expect(received.first == ServerSentEvent(event: "repository", data: json))
        #expect(received.dropFirst().allSatisfy { $0.event == "keep-alive" && $0.data == nil })
        #expect(received.count >= 3)
    }

    @Test("Cache keys name the user they belong to")
    func userIDFromKey() {
        let user = UUID()
        #expect(GitHubCache.userID(fromKey: "gh:v1:\(user.uuidString.lowercased()):o/r:pulls") == user)
        #expect(GitHubCache.userID(fromKey: "gh:v1:index:o/r") == nil)
        #expect(GitHubCache.userID(fromKey: "other") == nil)
    }

    @Test("Invalidating a repository returns the users who had it cached")
    func invalidateReturnsUsers() async throws {
        let api = FakeGitHubAPI()
        let path = GitHubResource.pullRequests.path(owner: "o", name: "r")
        await api.respond(to: path, with: .success(GitHubResponse(status: .ok, body: Data("[]".utf8), etag: nil)))
        let cache = GitHubCache(store: InMemoryCacheStore(), api: api)
        let alice = UUID()
        let bob = UUID()
        _ = try await cache.fetch(.pullRequests, owner: "o", name: "r", userID: alice, token: "a")
        _ = try await cache.fetch(.pullRequests, owner: "o", name: "r", userID: bob, token: "b")

        #expect(await cache.invalidate(owner: "o", name: "r") == [alice, bob])
        #expect(await cache.invalidate(owner: "o", name: "r").isEmpty)
    }
}

/// The first change on `stream`, or `nil` if none arrives within `timeout`.
private func firstChange(
    in stream: AsyncStream<RepositoryChange>,
    within timeout: Duration
) async -> RepositoryChange? {
    await withTaskGroup(of: RepositoryChange?.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }
        let first = await group.next()
        group.cancelAll()
        return first.flatMap { $0 }
    }
}

extension DatabaseIntegrationTests {
    @Suite("Live events route")
    struct LiveEventsRouteTests {
        @Test("A check run webhook for a repository the user asked about reaches their event stream")
        func webhookToStream() async throws {
            try await withApp { app in
                try await configure(app, reader: TestDatabase.reader(["GITHUB_WEBHOOK_SECRET": "s3cret"]))
                try await app.autoRevert()
                try await app.autoMigrate()
                let api = FakeGitHubAPI()
                await api.respond(
                    to: GitHubResource.pullRequests.path(owner: "octocat", name: "hello"),
                    with: .success(GitHubResponse(status: .ok, body: Data("[]".utf8), etag: nil))
                )
                app.githubAPI = api
                let token = try await app.signInWithFakeGitHub()
                var headers = HTTPHeaders()
                headers.bearerAuthorization = BearerAuthorization(token: token)
                let status = try await app.send(
                    .POST,
                    "github/status",
                    json: #"{"repositories":[{"owner":"octocat","name":"hello"}]}"#,
                    headers: headers
                )
                #expect(status.status == .ok)
                let user = try await app.userID(forAccessToken: token)
                let stream = await app.eventHub.subscribe(user: user)
                let other = await app.eventHub.subscribe(user: UUID())

                let body = #"{"action":"completed","repository":{"full_name":"octocat/hello"}}"#
                let pingBody = #"{"zen":"hi","repository":{"full_name":"octocat/hello"}}"#
                #expect(try await app.sendWebhook(pingBody, event: "star", secret: "s3cret").status == .accepted)
                #expect(try await app.sendWebhook(body, event: "check_run", secret: "s3cret").status == .accepted)

                // The star doesn't notify; the check run does.
                let received = await firstChange(in: stream, within: .seconds(2))
                #expect(received == RepositoryChange(owner: "octocat", name: "hello", event: "check_run"))
                // The other user never asked about the repository.
                #expect(await firstChange(in: other, within: .milliseconds(100)) == nil)
                try await app.autoRevert()
            }
        }

        @Test("The event stream requires sign-in")
        func requiresSignIn() async throws {
            try await withApp { app in
                try await configure(app, reader: TestDatabase.reader())
                let response = try await app.send(.GET, "events")
                #expect(response.status == .unauthorized)
            }
        }
    }
}
