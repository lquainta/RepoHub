import Fluent
import OpenAPIVapor
import RepoHubAPI
import Vapor

/// Registers all HTTP routes: the generated API operations plus the docs.
func routes(_ app: Application) throws {
    let transport = VaporTransport(routesBuilder: app)
    let authentication = AuthenticationMiddleware(
        authenticate: { [app] token in try await app.authService(on: app.db).authenticate(accessToken: token) },
        limiter: app.security.limiter,
        limitPerMinute: app.config.security.rateLimitPerMinute
    )
    try APIHandler(app: app).registerHandlers(on: transport, middlewares: [authentication])
    try DocumentationRoutes.register(on: app)
}
