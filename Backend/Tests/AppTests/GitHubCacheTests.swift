import Foundation
import Testing
import Vapor
import VaporTesting

@testable import App

/// Returns canned GitHub responses and records requests.
private actor FakeGitHubAPI: GitHubAPI {
    struct Call: Equatable {
        var path: String
        var etag: String?
    }

    private(set) var calls: [Call] = []
    var responses: [String: Result<GitHubResponse, GitHubError>] = [:]

    func respond(to path: String, with result: Result<GitHubResponse, GitHubError>) {
        responses[path] = result
    }

    func get(_ path: String, token: String, etag: String?) async throws -> GitHubResponse {
        calls.append(Call(path: path, etag: etag))
        guard let result = responses[path] else {
            throw GitHubError.notFound
        }
        let response = try result.get()
        // Like GitHub: a matching ETag gets 304 with no body.
        if let etag, etag == response.etag {
            return GitHubResponse(status: .notModified, body: Data(), etag: etag)
        }
        return response
    }
}

/// A cache whose every operation fails, as if Redis were down.
private struct FailingCacheStore: CacheStore {
    struct Down: Error {}
    func get<Value: Decodable & Sendable>(_ key: String, as type: Value.Type) async throws -> Value? { throw Down() }
    func set<Value: Encodable & Sendable>(_ key: String, to value: Value, expiresIn seconds: Int) async throws {
        throw Down()
    }
    func delete(_ keys: [String]) async throws { throw Down() }
    func addToSet(_ key: String, member: String, expiresIn seconds: Int) async throws { throw Down() }
    func members(ofSet key: String) async throws -> [String] { throw Down() }
    func increment(_ key: String, expiresIn seconds: Int) async throws -> Int { throw Down() }
    func ping() async throws { throw Down() }
}

/// A clock tests can advance.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}

@Suite("GitHubCache")
struct GitHubCacheTests {
    private let pullsPath = GitHubResource.pullRequests.path(owner: "o", name: "r")
    private let alice = UUID()
    private let bob = UUID()

    private func body(_ text: String) -> Data { Data(text.utf8) }

    private func makeCache(_ api: FakeGitHubAPI, clock: TestClock, store: (any CacheStore)? = nil) -> GitHubCache {
        GitHubCache(store: store ?? InMemoryCacheStore { clock.now }, api: api, now: { clock.now })
    }

    @Test("A repeated request within the TTL is a hit and doesn't call GitHub")
    func hitWithinTTL() async throws {
        let api = FakeGitHubAPI()
        await api.respond(to: pullsPath, with: .success(GitHubResponse(status: .ok, body: body("[1]"), etag: "\"v1\"")))
        let clock = TestClock()
        let cache = makeCache(api, clock: clock)

        let first = try await cache.fetch(.pullRequests, owner: "o", name: "r", userID: alice, token: "t")
        clock.advance(30)
        let second = try await cache.fetch(.pullRequests, owner: "O", name: "R", userID: alice, token: "t")

        #expect(first.outcome == .miss && second.outcome == .hit)
        #expect(second.body == body("[1]"))
        #expect(await api.calls.count == 1)
    }

    @Test("After the TTL, the ETag is revalidated and a 304 keeps the cached body")
    func revalidatesWithETag() async throws {
        let api = FakeGitHubAPI()
        await api.respond(to: pullsPath, with: .success(GitHubResponse(status: .ok, body: body("[1]"), etag: "\"v1\"")))
        let clock = TestClock()
        let cache = makeCache(api, clock: clock)

        _ = try await cache.fetch(.pullRequests, owner: "o", name: "r", userID: alice, token: "t")
        clock.advance(61)
        let revalidated = try await cache.fetch(.pullRequests, owner: "o", name: "r", userID: alice, token: "t")
        clock.advance(30)
        let hit = try await cache.fetch(.pullRequests, owner: "o", name: "r", userID: alice, token: "t")

        #expect(revalidated.outcome == .revalidated && revalidated.body == body("[1]"))
        #expect(hit.outcome == .hit)
        #expect(await api.calls == [.init(path: pullsPath, etag: nil), .init(path: pullsPath, etag: "\"v1\"")])
    }

    @Test("A changed resource replaces the cached body and ETag")
    func changedResource() async throws {
        let api = FakeGitHubAPI()
        await api.respond(to: pullsPath, with: .success(GitHubResponse(status: .ok, body: body("[1]"), etag: "\"v1\"")))
        let clock = TestClock()
        let cache = makeCache(api, clock: clock)
        _ = try await cache.fetch(.pullRequests, owner: "o", name: "r", userID: alice, token: "t")

        await api.respond(
            to: pullsPath,
            with: .success(GitHubResponse(status: .ok, body: body("[1,2]"), etag: "\"v2\""))
        )
        clock.advance(61)
        let updated = try await cache.fetch(.pullRequests, owner: "o", name: "r", userID: alice, token: "t")

        #expect(updated.outcome == .miss && updated.body == body("[1,2]"))
    }

    @Test("Entries are per user, and invalidation clears every user's entries for the repository")
    func perUserAndInvalidation() async throws {
        let api = FakeGitHubAPI()
        await api.respond(to: pullsPath, with: .success(GitHubResponse(status: .ok, body: body("[1]"), etag: "\"v1\"")))
        let clock = TestClock()
        let cache = makeCache(api, clock: clock)

        _ = try await cache.fetch(.pullRequests, owner: "o", name: "r", userID: alice, token: "a")
        let bobsFirst = try await cache.fetch(.pullRequests, owner: "o", name: "r", userID: bob, token: "b")
        #expect(bobsFirst.outcome == .miss)

        await cache.invalidate(owner: "O", name: "r")
        let aliceAfter = try await cache.fetch(.pullRequests, owner: "o", name: "r", userID: alice, token: "a")
        let bobAfter = try await cache.fetch(.pullRequests, owner: "o", name: "r", userID: bob, token: "b")
        #expect(aliceAfter.outcome == .miss && bobAfter.outcome == .miss)
        #expect(await api.calls.count == 4)
    }

    @Test("When the cache is down, requests go to GitHub instead of failing")
    func cacheDown() async throws {
        let api = FakeGitHubAPI()
        await api.respond(to: pullsPath, with: .success(GitHubResponse(status: .ok, body: body("[1]"), etag: "\"v1\"")))
        let cache = makeCache(api, clock: TestClock(), store: FailingCacheStore())

        let first = try await cache.fetch(.pullRequests, owner: "o", name: "r", userID: alice, token: "t")
        let second = try await cache.fetch(.pullRequests, owner: "o", name: "r", userID: alice, token: "t")
        #expect(first.body == body("[1]") && second.outcome == .miss)
        await cache.invalidate(owner: "o", name: "r")
    }

    @Test("GitHub errors are thrown and never cached")
    func errorsNotCached() async throws {
        let api = FakeGitHubAPI()
        await api.respond(to: pullsPath, with: .failure(.unauthorized))
        let cache = makeCache(api, clock: TestClock())

        await #expect(throws: GitHubError.unauthorized) {
            try await cache.fetch(.pullRequests, owner: "o", name: "r", userID: alice, token: "t")
        }
        await #expect(throws: GitHubError.unauthorized) {
            try await cache.fetch(.pullRequests, owner: "o", name: "r", userID: alice, token: "t")
        }
        #expect(await api.calls.count == 2)
    }

    @Test("Resources have per-resource TTLs and paths; refs are percent-encoded")
    func resources() {
        #expect(GitHubResource.repository.timeToLive > GitHubResource.pullRequests.timeToLive)
        #expect(GitHubResource.pullRequests.timeToLive > GitHubResource.checkRuns(ref: "x").timeToLive)
        #expect(GitHubResource.repository.path(owner: "o", name: "r") == "/repos/o/r")
        #expect(
            GitHubResource.checkRuns(ref: "feature/login").path(owner: "o", name: "r")
                == "/repos/o/r/commits/feature%2Flogin/check-runs?per_page=100"
        )
    }
}

/// Answers every request with a fixed response and records the last request.
private final class StubClient: Client, @unchecked Sendable {
    let eventLoop: any EventLoop
    let status: HTTPStatus
    let headers: HTTPHeaders
    private(set) var lastRequest: ClientRequest?

    init(eventLoop: any EventLoop, status: HTTPStatus, headers: HTTPHeaders = [:]) {
        self.eventLoop = eventLoop
        self.status = status
        self.headers = headers
    }

    func send(_ request: ClientRequest) -> EventLoopFuture<ClientResponse> {
        lastRequest = request
        return eventLoop.makeSucceededFuture(
            ClientResponse(status: status, headers: headers, body: ByteBuffer(string: "[]"))
        )
    }

    func delegating(to eventLoop: any EventLoop) -> any Client { self }
}

@Suite("VaporGitHubAPI")
struct VaporGitHubAPITests {
    @Test("Sends the token, API version, and ETag, and reads the response")
    func request() async throws {
        try await withApp { app in
            let client = StubClient(
                eventLoop: app.eventLoopGroup.any(),
                status: .ok,
                headers: ["ETag": "\"abc\"", "X-RateLimit-Remaining": "4999"]
            )
            let response = try await VaporGitHubAPI(client: client).get("/repos/o/r", token: "secret", etag: "\"old\"")

            let sent = try #require(client.lastRequest)
            #expect(sent.url.string == "https://api.github.com/repos/o/r")
            #expect(sent.headers.bearerAuthorization?.token == "secret")
            #expect(sent.headers.first(name: .ifNoneMatch) == "\"old\"")
            #expect(sent.headers.first(name: "X-GitHub-Api-Version") == "2022-11-28")
            #expect(
                response
                    == GitHubResponse(status: .ok, body: Data("[]".utf8), etag: "\"abc\"", rateLimitRemaining: 4999)
            )
        }
    }

    /// A response status and headers, and the error it should map to.
    struct ErrorCase: Sendable, CustomTestStringConvertible {
        var status: HTTPStatus
        var headers: [String: String] = [:]
        var expected: GitHubError
        var testDescription: String { "\(status.code) \(headers)" }
    }

    @Test(
        "Maps error statuses",
        arguments: [
            ErrorCase(status: .unauthorized, expected: .unauthorized),
            ErrorCase(status: .notFound, expected: .notFound),
            ErrorCase(
                status: .forbidden,
                headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1700000000"],
                expected: .rateLimited(resetAt: Date(timeIntervalSince1970: 1_700_000_000))
            ),
            ErrorCase(status: .tooManyRequests, expected: .rateLimited(resetAt: nil)),
            ErrorCase(status: .forbidden, headers: ["X-RateLimit-Remaining": "12"], expected: .unexpectedStatus(403)),
            ErrorCase(status: .internalServerError, expected: .unexpectedStatus(500)),
        ]
    )
    func errors(_ errorCase: ErrorCase) async throws {
        try await withApp { app in
            let client = StubClient(
                eventLoop: app.eventLoopGroup.any(),
                status: errorCase.status,
                headers: HTTPHeaders(errorCase.headers.map { ($0, $1) })
            )
            let expected = errorCase.expected
            await #expect(throws: expected) {
                try await VaporGitHubAPI(client: client).get("/repos/o/r", token: "t", etag: nil)
            }
        }
    }
}

/// The cache against a real Redis (`TEST_REDIS_URL`).
@Suite("Redis cache", .serialized, .tags(.integration), .enabled(if: TestRedis.isAvailable))
struct RedisCacheIntegrationTests {
    private func withRedis(_ body: (any CacheStore) async throws -> Void) async throws {
        try await withApp { app in
            try app.configureCache(redisURL: TestRedis.url)
            // The Redis connection pool starts when the app boots (`serve` does this in production).
            try await app.asyncBoot()
            try await body(app.cacheStore)
        }
    }

    @Test("Values round-trip as JSON, expire after their TTL, and sets collect members")
    func storeBasics() async throws {
        try await withRedis { store in
            let key = "test:\(UUID())"
            try await store.set(key, to: ["a": 1], expiresIn: 1)
            #expect(try await store.get(key, as: [String: Int].self) == ["a": 1])
            try await Task.sleep(for: .milliseconds(1_300))
            #expect(try await store.get(key, as: [String: Int].self) == nil)

            let set = "test:set:\(UUID())"
            try await store.addToSet(set, member: "x", expiresIn: 60)
            try await store.addToSet(set, member: "y", expiresIn: 60)
            #expect(try await store.members(ofSet: set).sorted() == ["x", "y"])
            try await store.delete([set])
            #expect(try await store.members(ofSet: set).isEmpty)
        }
    }

    @Test("A second app instance is served from Redis within the TTL, and invalidation clears it")
    func sharedAcrossInstances() async throws {
        let name = "repo-\(UUID().uuidString.prefix(8))"
        let path = GitHubResource.pullRequests.path(owner: "o", name: name)
        let api = FakeGitHubAPI()
        await api.respond(to: path, with: .success(GitHubResponse(status: .ok, body: Data("[7]".utf8), etag: "\"e\"")))
        let user = UUID()

        try await withRedis { store in
            let first = try await GitHubCache(store: store, api: api).fetch(
                .pullRequests,
                owner: "o",
                name: name,
                userID: user,
                token: "t"
            )
            #expect(first.outcome == .miss)
        }
        try await withRedis { store in
            let cache = GitHubCache(store: store, api: api)
            let second = try await cache.fetch(.pullRequests, owner: "o", name: name, userID: user, token: "t")
            #expect(second.outcome == .hit && second.body == Data("[7]".utf8))

            await cache.invalidate(owner: "o", name: name)
            let third = try await cache.fetch(.pullRequests, owner: "o", name: name, userID: user, token: "t")
            // Invalidation deletes the entry and its ETag, so this is a full request.
            #expect(third.outcome == .miss)
        }
        #expect(await api.calls.count == 2)
    }
}
