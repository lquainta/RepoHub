import OSLog
import SwiftData
import SwiftUI

/// Application entry point.
@main
struct RepoHubApp: App {
    private let container: ModelContainer

    init() {
        container = Self.makeContainer(arguments: ProcessInfo.processInfo.arguments)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }

    /// Opens the on-disk store, or an in-memory store when launched with
    /// `-UITestInMemoryStore` (UI tests must never touch the user's data).
    /// Falls back to memory if the on-disk store can't be opened, so the app
    /// still launches; the failure is logged.
    private static func makeContainer(arguments: [String]) -> ModelContainer {
        let logger = Logger(subsystem: "com.lquainta.RepoHub", category: "Persistence")
        do {
            if arguments.contains("-UITestInMemoryStore") {
                return try Persistence.makeInMemoryContainer()
            }
            return try Persistence.makeContainer()
        } catch {
            logger.error("Could not open data store, using memory: \(error.localizedDescription, privacy: .public)")
            do {
                return try Persistence.makeInMemoryContainer()
            } catch {
                preconditionFailure("Could not create an in-memory store: \(error)")
            }
        }
    }
}
