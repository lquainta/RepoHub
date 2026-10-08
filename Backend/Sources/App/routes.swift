import RepoHubCore
import Vapor

/// Response body for the liveness endpoint.
struct HealthResponse: Content {
    let status: String
    let version: String
    let commit: String
}

/// Registers all HTTP routes.
func routes(_ app: Application) throws {
    let commit = app.config.buildCommit
    app.get("health") { _ async -> HealthResponse in
        HealthResponse(status: "ok", version: RepoHubCore.version, commit: commit)
    }
}
