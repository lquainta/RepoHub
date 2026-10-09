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
        let arguments = ProcessInfo.processInfo.arguments
        let container = Self.makeContainer(arguments: arguments)
        self.container = container
        _library = State(initialValue: LibraryViewModel(store: LibraryStore(container: container)))
        launchFolders = Self.launchFolders(arguments: arguments)
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

    /// Folders passed with `-UITestScanFolder <path>`, scanned at launch by UI tests.
    private static func launchFolders(arguments: [String]) -> [URL] {
        zip(arguments, arguments.dropFirst())
            .filter { $0.0 == "-UITestScanFolder" }
            .map { URL(fileURLWithPath: $0.1, isDirectory: true) }
    }
}
