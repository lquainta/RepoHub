import Fluent
import SQLKit
import Vapor

private struct ReadinessCheckerKey: StorageKey {
    typealias Value = ReadinessChecker
}

extension Application {
    /// Checks PostgreSQL (`SELECT 1`) and the cache (`PING`). Tests replace it.
    var readinessChecker: ReadinessChecker {
        get {
            storage[ReadinessCheckerKey.self]
                ?? ReadinessChecker(
                    database: { [db] in
                        guard let sql = db as? any SQLDatabase else {
                            throw Abort(.internalServerError, reason: "Not a SQL database")
                        }
                        try await sql.raw("SELECT 1").run()
                    },
                    cache: { [cacheStore] in try await cacheStore.ping() }
                )
        }
        set { storage[ReadinessCheckerKey.self] = newValue }
    }
}
