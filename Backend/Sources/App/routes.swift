import RepoHubCore
import Vapor

/// Response body for the liveness endpoint.
struct HealthResponse: Content {
    let status: String
    let version: String
}

/// Registers all HTTP routes.
func routes(_ app: Application) throws {
    app.get("health") { _ async -> HealthResponse in
        HealthResponse(status: "ok", version: RepoHubCore.version)
    }
}
