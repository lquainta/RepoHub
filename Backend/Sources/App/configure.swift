import Vapor

/// Configures services, middleware, and routes for the application.
func configure(_ app: Application) async throws {
    try routes(app)
}
