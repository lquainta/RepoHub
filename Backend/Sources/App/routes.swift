import OpenAPIVapor
import RepoHubAPI
import Vapor

/// Registers all HTTP routes: the generated API operations plus the docs.
func routes(_ app: Application) throws {
    let transport = VaporTransport(routesBuilder: app)
    try APIHandler(buildCommit: app.config.buildCommit).registerHandlers(on: transport)
    try DocumentationRoutes.register(on: app)
}
