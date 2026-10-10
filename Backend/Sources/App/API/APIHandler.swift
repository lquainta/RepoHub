import OpenAPIRuntime
import RepoHubAPI
import RepoHubCore
import Vapor

/// Implements the operations in openapi/openapi.yaml.
///
/// The protocol is generated from the spec, so an operation added to the spec
/// fails to compile until it's implemented here, and a handler can't return
/// a response the spec doesn't allow.
struct APIHandler: APIProtocol {
    let buildCommit: String

    func getHealth(_ input: Operations.getHealth.Input) async throws -> Operations.getHealth.Output {
        .ok(.init(body: .json(.init(status: .ok, version: RepoHubCore.version, commit: buildCommit))))
    }
}
