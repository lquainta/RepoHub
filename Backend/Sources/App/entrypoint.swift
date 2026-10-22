import Foundation
import Logging
import Vapor

@main
enum Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()
        try LogFormat.bootstrap(&env)

        let app = try await Application.make(env)

        do {
            try await configure(app)
            try await app.execute()
        } catch {
            // Report and exit with a failure status. Rethrowing would crash with
            // a backtrace for expected failures like a refused command.
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            exit(1)
        }
        try await app.asyncShutdown()
    }
}
