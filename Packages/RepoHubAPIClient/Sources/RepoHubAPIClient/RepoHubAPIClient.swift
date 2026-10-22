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

extension Operations.streamEvents.Output.Ok {
    /// The stream's `repository` events, decoded. Keep-alive events and
    /// events whose data doesn't decode are skipped.
    public func repositoryChanges() throws -> AsyncThrowingStream<Components.Schemas.RepositoryChanged, any Error> {
        let events = try body.text_event_hyphen_stream.asDecodedServerSentEvents()
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let decoder = JSONDecoder()
                    for try await event in events where event.event == "repository" {
                        guard let data = event.data.map({ Data($0.utf8) }),
                            let change = try? decoder.decode(Components.Schemas.RepositoryChanged.self, from: data)
                        else {
                            continue
                        }
                        continuation.yield(change)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
