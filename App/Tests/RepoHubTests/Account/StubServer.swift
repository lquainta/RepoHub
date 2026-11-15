import Foundation

/// Answers a `URLSession`'s requests from memory, so ``RepoHubAPI`` can be
/// tested through the real generated client without a network.
///
/// Each server has its own host, so tests can run in parallel.
final class StubServer: Sendable {
    struct Response: Sendable {
        var status: Int
        var body: String = ""
        var contentType = "application/json"
    }

    struct Request: Sendable {
        var method: String
        /// Path and query, for example `/activity?days=30`.
        var target: String
        var authorization: String?
        /// JSON without whitespace, keys sorted.
        var body: String
    }

    let host = "\(UUID().uuidString.lowercased()).test"
    var baseURL: URL { URL(string: "https://\(host)") ?? URL(fileURLWithPath: "/") }

    /// A session whose requests to ``baseURL`` get `response`.
    func session(answering response: Response) -> URLSession {
        StubURLProtocol.registry.set(response, for: host)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// The requests received so far.
    var requests: [Request] { StubURLProtocol.registry.requests(for: host) }

    deinit {
        StubURLProtocol.registry.remove(host)
    }
}

final class StubURLProtocol: URLProtocol {
    final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [String: StubServer.Response] = [:]
        private var received: [String: [StubServer.Request]] = [:]

        func set(_ response: StubServer.Response, for host: String) {
            lock.withLock { responses[host] = response }
        }

        func response(for host: String) -> StubServer.Response? {
            lock.withLock { responses[host] }
        }

        func record(_ request: StubServer.Request, for host: String) {
            lock.withLock { received[host, default: []].append(request) }
        }

        func requests(for host: String) -> [StubServer.Request] {
            lock.withLock { received[host] ?? [] }
        }

        func remove(_ host: String) {
            lock.withLock {
                responses[host] = nil
                received[host] = nil
            }
        }
    }

    static let registry = Registry()

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host(),
            let stub = Self.registry.response(for: host),
            let response = HTTPURLResponse(
                url: url,
                statusCode: stub.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": stub.contentType]
            )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        Self.registry.record(
            .init(
                method: request.httpMethod ?? "",
                target: url.path() + (url.query().map { "?\($0)" } ?? ""),
                authorization: request.value(forHTTPHeaderField: "Authorization"),
                body: Self.compactJSON(Self.body(of: request))
            ),
            for: host
        )
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// A JSON body without whitespace and with sorted keys, so tests can look
    /// for `"key":value` however the client formats it. Other bodies as text.
    private static func compactJSON(_ body: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: body),
            let compact = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else {
            return String(bytes: body, encoding: .utf8) ?? ""
        }
        return String(bytes: compact, encoding: .utf8) ?? ""
    }

    /// The request body, which `URLSession` hands to a protocol as a stream.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
