import Fluent
import Vapor

/// Configures services, middleware, and routes for the application.
func configure(_ app: Application, reader: EnvironmentReader = EnvironmentReader()) async throws {
    app.config = try AppConfig(reader: reader, environment: app.environment)
    // First, so even error responses carry X-Request-Id.
    app.middleware.use(RequestIDMiddleware(), at: .beginning)
    app.configureDatabase(app.config.database)
    try app.configureCache(redisURL: app.config.redisURL)
    await app.configureSecurity(app.config.security)
    app.asyncCommands.use(SeedCommand(), as: "seed")
    try routes(app)
}
