import OSLog
import SwiftData
import SwiftUI

/// Application entry point.
@main
struct RepoHubApp: App {
    private let container: ModelContainer
    @State private var library: LibraryViewModel
    private let launchFolders: [URL]

    init() {
        let environment = ProcessInfo.processInfo.environment
        let container = Self.makeContainer(environment: environment)
        self.container = container
        _library = State(initialValue: LibraryViewModel(store: LibraryStore(container: container)))
        launchFolders = Self.launchFolders(environment: environment)
    }

    var body: some Scene {
        WindowGroup {
            LibraryView(model: library)
                .task {
                    library.load()
                    if !launchFolders.isEmpty {
                        await library.addFolders(launchFolders)
                    }
                }
        }
        .modelContainer(container)
    }

    /// Opens the on-disk store, or an in-memory store for UI tests (see
    /// ``UITestSupport``), which must never touch the user's data.
    /// Falls back to memory if the on-disk store can't be opened, so the app
    /// still launches; the failure is logged.
    private static func makeContainer(environment: [String: String]) -> ModelContainer {
        let logger = Logger(subsystem: "com.lquainta.RepoHub", category: "Persistence")
        do {
            if UITestSupport.usesInMemoryStore(environment) {
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

    /// The UI test fixture folder, if one was requested, scanned at launch.
    private static func launchFolders(environment: [String: String]) -> [URL] {
        do {
            return try UITestSupport.makeFixtureFolder(environment).map { [$0] } ?? []
        } catch {
            Logger(subsystem: "com.lquainta.RepoHub", category: "UITest")
                .error("Could not create UI test fixture: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
