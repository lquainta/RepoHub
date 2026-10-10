import Fluent
import Vapor

/// Configures services, middleware, and routes for the application.
func configure(_ app: Application, reader: EnvironmentReader = EnvironmentReader()) async throws {
    app.config = try AppConfig(reader: reader, environment: app.environment)
    app.configureDatabase(app.config.database)
    try routes(app)
}
