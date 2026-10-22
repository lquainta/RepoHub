import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

// `Client` and the `Components`/`Operations` types are generated at build time
// from openapi/openapi.yaml by the OpenAPIGenerator plugin.

extension Client {
    /// A client for the backend at `baseURL` using `URLSession`. Requests carry
    /// `Authorization: Bearer <accessToken>` when an access token is given.
    public static func repoHub(baseURL: URL, accessToken: String? = nil, session: URLSession = .shared) -> Client {
        Client(
            serverURL: baseURL,
            transport: URLSessionTransport(configuration: .init(session: session)),
            middlewares: accessToken.map { [BearerTokenMiddleware(token: $0)] } ?? []
        )
    }
}

/// Adds `Authorization: Bearer <token>` to every request.
public struct BearerTokenMiddleware: ClientMiddleware {
    let token: String

    /// Sends `token` with every request.
    public init(token: String) {
        self.token = token
    }

    /// Sets the `Authorization` header and passes the request on.
    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        request.headerFields[.authorization] = "Bearer \(token)"
        return try await next(request, body, baseURL)
    }
}
