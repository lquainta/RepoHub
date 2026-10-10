import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

// `Client` and the `Components`/`Operations` types are generated at build time
// from openapi/openapi.yaml by the OpenAPIGenerator plugin.

extension Client {
    /// A client for the backend at `baseURL` using `URLSession`.
    public static func repoHub(baseURL: URL, session: URLSession = .shared) -> Client {
        Client(serverURL: baseURL, transport: URLSessionTransport(configuration: .init(session: session)))
    }
}
