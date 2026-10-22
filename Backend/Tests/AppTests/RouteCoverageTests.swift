import Foundation
import Testing
import Vapor
import VaporTesting

@testable import App

/// An operation in openapi.yaml, with its path parameters filled in.
private struct SpecOperation {
    var method: HTTPMethod
    var path: String
    var operationID: String
}

/// Every operation in openapi.yaml.
private func specOperations() throws -> [SpecOperation] {
    let specURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "openapi/openapi.yaml")
    let lines = try String(contentsOf: specURL, encoding: .utf8).components(separatedBy: .newlines)
    var operations: [SpecOperation] = []
    var path: String?
    var method: HTTPMethod?
    for line in lines {
        if line.hasPrefix("  /"), line.hasSuffix(":") {
            path = String(line.dropFirst(2).dropLast())
                .replacingOccurrences(of: #"\{[^}]+\}"#, with: UUID().uuidString, options: .regularExpression)
        } else if line.hasPrefix("components:") {
            path = nil
        } else if path != nil,
            let match = ["get", "post", "put", "patch", "delete"].first(where: { line == "    \($0):" })
        {
            method = HTTPMethod(rawValue: match.uppercased())
        } else if let path, let method, line.hasPrefix("      operationId: ") {
            operations.append(
                SpecOperation(
                    method: method,
                    path: path,
                    operationID: String(line.dropFirst("      operationId: ".count))
                )
            )
        }
    }
    return operations
}

@Suite("Route coverage")
struct RouteCoverageTests {
    @Test("The spec lists every operation the server implements")
    func parsesSpec() throws {
        let operations = try specOperations()
        #expect(operations.count >= 16)
        #expect(operations.contains { $0.operationID == "getRepositoryStatuses" && $0.method == .POST })
    }

    @Test("Every protected operation rejects a request without a token with 401")
    func everyProtectedOperationNeedsAToken() async throws {
        let operations = try specOperations()
            .filter { !AuthenticationMiddleware.publicOperations.contains($0.operationID) }
        try await withApp { app in
            try await configure(app, reader: TestDatabase.reader())
            for operation in operations {
                let json = [.POST, .PUT, .PATCH].contains(operation.method) ? "{}" : nil
                let response = try await app.send(operation.method, String(operation.path.dropFirst()), json: json)
                #expect(response.status == .unauthorized, "\(operation.method) \(operation.path)")
            }
        }
    }
}

@Suite("GitHub pagination")
struct GitHubPaginationTests {
    @Test("The next page comes from the Link header, only on the same API")
    func nextPath() {
        let base = "https://api.github.com"
        let link =
            #"<https://api.github.com/repos/o/r/pulls?page=2>; rel="next", <https://api.github.com/repos/o/r/pulls?page=5>; rel="last""#
        #expect(GitHubResponse.nextPath(fromLink: link, baseURL: base) == "/repos/o/r/pulls?page=2")
        #expect(
            GitHubResponse.nextPath(fromLink: #"<https://api.github.com/x?page=1>; rel="prev""#, baseURL: base) == nil
        )
        #expect(GitHubResponse.nextPath(fromLink: #"<https://evil.example/x>; rel="next""#, baseURL: base) == nil)
        #expect(GitHubResponse.nextPath(fromLink: nil, baseURL: base) == nil)
    }

    @Test("Open pull requests are combined across pages, up to five")
    func combinesPages() async throws {
        let api = FakeGitHubAPI()
        let first = GitHubResource.pullRequests.path(owner: "o", name: "r")
        for page in 1...7 {
            let path = page == 1 ? first : "/repos/o/r/pulls?page=\(page)"
            await api.respond(
                to: path,
                with: .success(
                    GitHubResponse(
                        status: .ok,
                        body: Data("[{\"number\":\(page)}]".utf8),
                        etag: page == 1 ? "\"v1\"" : nil,
                        nextPath: "/repos/o/r/pulls?page=\(page + 1)"
                    )
                )
            )
        }
        let cache = GitHubCache(store: InMemoryCacheStore(), api: api)

        let result = try await cache.fetch(.pullRequests, owner: "o", name: "r", userID: UUID(), token: "t")

        let numbers = try JSONDecoder().decode([[String: Int]].self, from: result.body).compactMap { $0["number"] }
        #expect(numbers == [1, 2, 3, 4, 5])
        #expect(await api.calls.count == GitHubCache.maxPages)
    }

    @Test("Check runs, which aren't lists of pages, are fetched once")
    func singlePageResources() async throws {
        let api = FakeGitHubAPI()
        let path = GitHubResource.checkRuns(ref: "main").path(owner: "o", name: "r")
        await api.respond(
            to: path,
            with: .success(GitHubResponse(status: .ok, body: Data("{}".utf8), etag: nil, nextPath: "/more"))
        )

        _ = try await GitHubCache(store: InMemoryCacheStore(), api: api)
            .fetch(.checkRuns(ref: "main"), owner: "o", name: "r", userID: UUID(), token: "t")

        #expect(await api.calls.map(\.path) == [path])
    }
}
