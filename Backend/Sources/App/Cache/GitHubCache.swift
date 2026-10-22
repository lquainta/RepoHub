import Foundation
import Logging
import Vapor

/// A cacheable GitHub resource for one repository, with its time to live.
enum GitHubResource: Sendable, Equatable {
    /// Repository metadata (default branch, visibility). Changes rarely.
    case repository
    /// Open pull requests.
    case pullRequests
    /// Check runs for a commit or branch.
    case checkRuns(ref: String)

    /// How long a cached response is served without asking GitHub.
    var timeToLive: Int {
        switch self {
        case .repository: 3_600
        case .pullRequests: 60
        case .checkRuns: 30
        }
    }

    func path(owner: String, name: String) -> String {
        let base = "/repos/\(owner)/\(name)"
        switch self {
        case .repository: return base
        case .pullRequests: return base + "/pulls?state=open&per_page=100"
        case .checkRuns(let ref):
            let encoded = ref.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? ref
            return base + "/commits/\(encoded)/check-runs?per_page=100"
        }
    }

    /// Whether every page is fetched and combined (lists), or only the first.
    var isPaginated: Bool {
        if case .pullRequests = self {
            return true
        }
        return false
    }

    var keySuffix: String {
        switch self {
        case .repository: "repo"
        case .pullRequests: "pulls"
        case .checkRuns(let ref): "checks:\(ref)"
        }
    }
}

/// Cache-aside for GitHub API responses (ADR 0006).
///
/// - **Fresh** entries (younger than the resource's TTL) are served from the cache.
/// - **Stale** entries are kept for a day so their ETag can be revalidated:
///   GitHub's `304 Not Modified` doesn't count against the rate limit.
/// - Entries are **per user**, because responses for private repositories
///   must never be served to someone else. A per-repository index of keys
///   lets a webhook invalidate every user's entries for that repository.
/// - If the cache fails, requests go to GitHub directly.
struct GitHubCache: Sendable {
    /// Cached response body with its ETag.
    struct Entry: Codable, Sendable, Equatable {
        var etag: String?
        var body: Data
        var fetchedAt: Date
    }

    /// How a request was answered, for logging and tests.
    enum Outcome: String, Sendable {
        case hit, revalidated, miss
    }

    /// How long stale entries are kept for ETag revalidation.
    static let staleRetention = 86_400

    let store: any CacheStore
    let api: any GitHubAPI
    var logger = Logger(label: "com.lquainta.RepoHub.GitHubCache")
    var now: @Sendable () -> Date = { .now }

    /// Returns the resource's JSON, from the cache when fresh.
    func fetch(
        _ resource: GitHubResource,
        owner: String,
        name: String,
        userID: UUID,
        token: String
    ) async throws -> (body: Data, outcome: Outcome) {
        let repo = "\(owner)/\(name)".lowercased()
        let key = "gh:v1:\(userID.uuidString.lowercased()):\(repo):\(resource.keySuffix)"
        let cached = await read(key)

        if let cached, now().timeIntervalSince(cached.fetchedAt) < Double(resource.timeToLive) {
            log(.hit, resource: resource, repo: repo)
            return (cached.body, .hit)
        }

        let response = try await api.get(resource.path(owner: owner, name: name), token: token, etag: cached?.etag)
        let entry: Entry
        let outcome: Outcome
        if response.status == .notModified, let cached {
            entry = Entry(etag: cached.etag, body: cached.body, fetchedAt: now())
            outcome = .revalidated
        } else {
            let body = resource.isPaginated ? try await allPages(from: response, token: token) : response.body
            entry = Entry(etag: response.etag, body: body, fetchedAt: now())
            outcome = .miss
        }
        await write(entry, key: key, repo: repo, ttl: resource.timeToLive)
        log(outcome, resource: resource, repo: repo, remaining: response.rateLimitRemaining)
        return (entry.body, outcome)
    }

    /// The most pages fetched for one list (500 pull requests at 100 per page).
    static let maxPages = 5

    /// `first` combined with the pages after it, up to ``maxPages`` in total.
    /// The cached ETag is the first page's, so a list only changes when its
    /// first page does or the entry expires; for open pull requests, newest
    /// first, that's when a pull request is opened or updated.
    private func allPages(from first: GitHubResponse, token: String) async throws -> Data {
        guard first.nextPath != nil else {
            return first.body
        }
        var items = try Self.jsonArray(first.body)
        var next = first.nextPath
        var pages = 1
        while let path = next, pages < Self.maxPages {
            let page = try await api.get(path, token: token, etag: nil)
            items += try Self.jsonArray(page.body)
            next = page.nextPath
            pages += 1
        }
        return try JSONSerialization.data(withJSONObject: items)
    }

    private static func jsonArray(_ data: Data) throws -> [Any] {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw GitHubError.unexpectedStatus(200)
        }
        return array
    }

    /// Deletes every user's cached responses for `owner/name` (for webhooks)
    /// and returns the users who had any, so their apps can be told (#77).
    @discardableResult
    func invalidate(owner: String, name: String) async -> Set<UUID> {
        let index = Self.indexKey("\(owner)/\(name)".lowercased())
        do {
            let keys = try await store.members(ofSet: index)
            try await store.delete(keys + [index])
            logger.debug("GitHub cache invalidated", metadata: ["repo": "\(owner)/\(name)", "keys": "\(keys.count)"])
            return Set(keys.compactMap(Self.userID(fromKey:)))
        } catch {
            logger.warning("GitHub cache invalidation failed: \(error)")
            return []
        }
    }

    /// The user ID in a key such as `gh:v1:<user>:<owner>/<name>:pulls`.
    static func userID(fromKey key: String) -> UUID? {
        let parts = key.split(separator: ":", maxSplits: 3)
        guard parts.count >= 3, parts[0] == "gh", parts[1] == "v1" else {
            return nil
        }
        return UUID(uuidString: String(parts[2]))
    }

    private static func indexKey(_ repo: String) -> String {
        "gh:v1:index:\(repo)"
    }

    private func read(_ key: String) async -> Entry? {
        do {
            return try await store.get(key, as: Entry.self)
        } catch {
            logger.warning("GitHub cache read failed, asking GitHub: \(error)")
            return nil
        }
    }

    private func write(_ entry: Entry, key: String, repo: String, ttl: Int) async {
        let expiry = ttl + Self.staleRetention
        do {
            try await store.set(key, to: entry, expiresIn: expiry)
            try await store.addToSet(Self.indexKey(repo), member: key, expiresIn: expiry)
        } catch {
            logger.warning("GitHub cache write failed: \(error)")
        }
    }

    private func log(_ outcome: Outcome, resource: GitHubResource, repo: String, remaining: Int? = nil) {
        var metadata: Logger.Metadata = [
            "cache": "\(outcome.rawValue)", "resource": "\(resource.keySuffix)", "repo": "\(repo)",
        ]
        if let remaining {
            metadata["rate_limit_remaining"] = "\(remaining)"
        }
        logger.info("GitHub request", metadata: metadata)
    }
}
