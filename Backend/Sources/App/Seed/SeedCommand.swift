import Fluent
import Vapor

/// `swift run App seed`: fills the development database with realistic data.
///
/// Refuses to run in production. Migrations must have run first (`migrate`).
struct SeedCommand: AsyncCommand {
    struct Signature: CommandSignature {}

    var help: String {
        "Seeds the database with development data. Refuses to run in production."
    }

    func run(using context: CommandContext, signature: Signature) async throws {
        let app = context.application
        try Self.ensureAllowed(in: app.environment)
        let summary = try await SeedData.seed(on: app.db)
        context.console.success("Seeded \(summary).")
    }

    /// Seeding is for development and tests only.
    static func ensureAllowed(in environment: Environment) throws {
        guard environment != .production else {
            throw SeedError.productionRefused
        }
    }
}

/// Why seeding didn't run.
enum SeedError: Error, Equatable, CustomStringConvertible {
    case productionRefused

    var description: String {
        "Refusing to seed the production database. Seed data is for development and tests only."
    }
}
