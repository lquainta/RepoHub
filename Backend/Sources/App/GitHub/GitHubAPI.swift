import Foundation
import Vapor

/// A response from the GitHub REST API.
struct GitHubResponse: Sendable, Equatable {
    /// 200 with a body, or 304 when the `If-None-Match` ETag still matches.
    var status: HTTPStatus
    var body: Data
    var etag: String?
    /// `X-RateLimit-Remaining`, for logging.
    var rateLimitRemaining: Int?
    /// The next page's path, from the `Link` header's `rel="next"`.
    var nextPath: String?
}

extension GitHubResponse {
    /// The path of the `rel="next"` link in a `Link` header such as
    /// `<https://api.github.com/repos/o/r/pulls?page=2>; rel="next", <…>; rel="last"`.
    static func nextPath(fromLink header: String?, baseURL: String) -> String? {
        guard let header else {
            return nil
        }
        for link in header.split(separator: ",") {
            let parts = link.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2, parts.dropFirst().contains(#"rel="next""#),
                parts[0].hasPrefix("<"), parts[0].hasSuffix(">")
            else {
                continue
            }
            let url = String(parts[0].dropFirst().dropLast())
            // Only follow links to the same API, never elsewhere with the user's token.
            guard url.hasPrefix(baseURL + "/") else {
                return nil
            }
            return String(url.dropFirst(baseURL.count))
        }
        return nil
    }
}

/// Errors from the GitHub API.
enum GitHubError: Error, Equatable {
    /// The token is missing, expired, or revoked (401).
    case unauthorized
    /// The repository doesn't exist or the token can't see it (404).
    case notFound
    /// The rate limit is exhausted (403 or 429 with no remaining requests).
    case rateLimited(resetAt: Date?)
    /// Any other unexpected status.
    case unexpectedStatus(UInt)
}

/// Calls the GitHub REST API. ``VaporGitHubAPI`` is the real implementation;
/// tests use fakes.
protocol GitHubAPI: Sendable {
    /// `GET` `path` (such as `/repos/o/r/pulls`) with the user's token, sending
    /// `If-None-Match: etag` when given.
    func get(_ path: String, token: String, etag: String?) async throws -> GitHubResponse
}

/// Uses Vapor's HTTP client against `https://api.github.com`.
struct VaporGitHubAPI: GitHubAPI {
    let client: any Client
    var baseURL = "https://api.github.com"

    func get(_ path: String, token: String, etag: String?) async throws -> GitHubResponse {
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token)
        headers.replaceOrAdd(name: .accept, value: "application/vnd.github+json")
        headers.replaceOrAdd(name: "X-GitHub-Api-Version", value: "2022-11-28")
        headers.replaceOrAdd(name: .userAgent, value: "RepoHub")
        if let etag {
            headers.replaceOrAdd(name: .ifNoneMatch, value: etag)
        }
        let response = try await client.get(URI(string: baseURL + path), headers: headers)
        let remaining = response.headers.first(name: "X-RateLimit-Remaining").flatMap(Int.init)

        switch response.status {
        case .ok, .notModified:
            return GitHubResponse(
                status: response.status,
                body: response.body.map { Data($0.readableBytesView) } ?? Data(),
                etag: response.headers.first(name: .eTag),
                rateLimitRemaining: remaining,
                nextPath: GitHubResponse.nextPath(fromLink: response.headers.first(name: "Link"), baseURL: baseURL)
            )
        case .unauthorized:
            throw GitHubError.unauthorized
        case .notFound:
            throw GitHubError.notFound
        // 429 is always a rate limit (including secondary limits); 403 is one
        // only when no requests remain, otherwise it's a permission error.
        case .tooManyRequests:
            throw Self.rateLimited(response.headers)
        case .forbidden where remaining == 0:
            throw Self.rateLimited(response.headers)
        default:
            throw GitHubError.unexpectedStatus(response.status.code)
        }
    }

    private static func rateLimited(_ headers: HTTPHeaders) -> GitHubError {
        let reset = headers.first(name: "X-RateLimit-Reset").flatMap(TimeInterval.init)
        return .rateLimited(resetAt: reset.map(Date.init(timeIntervalSince1970:)))
    }
}
