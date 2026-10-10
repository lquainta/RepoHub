import Foundation
import HTTPTypes
import OpenAPIRuntime
import RepoHubAPIClient
import Testing

/// Answers every request with a fixed response and records the request.
private actor StubTransport: ClientTransport {
    let status: HTTPResponse.Status
    let json: String
    private(set) var requests: [HTTPRequest] = []

    init(status: HTTPResponse.Status = .ok, json: String) {
        self.status = status
        self.json = json
    }

    func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        requests.append(request)
        var response = HTTPResponse(status: status)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(json))
    }
}

@Suite("RepoHubAPIClient")
struct RepoHubAPIClientTests {
    @Test("getHealth calls /health and decodes the generated response type")
    func health() async throws {
        let transport = StubTransport(json: #"{"status":"ok","version":"0.1.0","commit":"abc1234"}"#)
        let client = Client(serverURL: try #require(URL(string: "https://example.com")), transport: transport)

        let health = try await client.getHealth().ok.body.json

        #expect(health.status == .ok)
        #expect(health.commit == "abc1234")
        #expect(await transport.requests.map(\.path) == ["/health"])
    }

    @Test("A response the spec doesn't define is reported, not silently accepted")
    func undocumentedStatus() async throws {
        let transport = StubTransport(status: .serviceUnavailable, json: #"{"error":true,"reason":"down"}"#)
        let client = Client(serverURL: try #require(URL(string: "https://example.com")), transport: transport)

        let output = try await client.getHealth()
        guard case .undocumented(let statusCode, _) = output else {
            Issue.record("Expected an undocumented response, got \(output)")
            return
        }
        #expect(statusCode == 503)
    }
}
