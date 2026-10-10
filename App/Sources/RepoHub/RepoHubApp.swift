import OSLog
import SwiftData
import SwiftUI

/// Application entry point.
@main
struct RepoHubApp: App {
    /// Identifies the dashboard window so the menu bar can reopen it.
    static let mainWindowID = "main"

    private let container: ModelContainer
    @State private var library: LibraryViewModel
    @State private var settings = SettingsModel()
    @AppStorage(AppPreferences.showMenuBarExtraKey) private var showMenuBarExtra = true
    @AppStorage(AppPreferences.menuBarOnlyKey) private var menuBarOnly = false
    private let launchFolders: [URL]

    init() {
        let environment = ProcessInfo.processInfo.environment
        let container = Self.makeContainer(environment: environment)
        self.container = container
        _library = State(
            initialValue: LibraryViewModel(
                store: LibraryStore(container: container),
                autoRefresh: AutoRefreshController()
            )
        )
        launchFolders = Self.launchFolders(environment: environment)
    }

    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
            LibraryView(model: library)
                .task { await library.start(addingFolders: launchFolders) }
        }
        .modelContainer(container)
        .defaultLaunchBehavior(menuBarOnly && showMenuBarExtra ? .suppressed : .presented)
        .commands {
            RepositoryCommands(model: library)
        }

        Settings {
            SettingsView(settings: settings, library: library)
        }

        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuBarContent(library: library)
                .task { await library.start(addingFolders: launchFolders) }
        } label: {
            MenuBarLabel(library: library)
                .task { await library.start(addingFolders: launchFolders) }
                .onChange(of: menuBarOnly && showMenuBarExtra, initial: true) { _, accessory in
                    // Menu-bar-only hides the Dock icon; it needs the menu bar icon to stay reachable.
                    NSApplication.shared.setActivationPolicy(accessory ? .accessory : .regular)
                }
        }
        .menuBarExtraStyle(.window)
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
