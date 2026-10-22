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
    @State private var account: AccountModel
    @AppStorage(AppPreferences.showMenuBarExtraKey) private var showMenuBarExtra = true
    @AppStorage(AppPreferences.menuBarOnlyKey) private var menuBarOnly = false
    private let launchFolders: [URL]

    init() {
        let environment = ProcessInfo.processInfo.environment
        let container = Self.makeContainer(environment: environment)
        self.container = container
        let api = RepoHubAPI(baseURL: AppPreferences.backendURL(environment))
        let account = AccountModel(
            api: api,
            credentials: UITestSupport.usesInMemoryStore(environment)
                ? InMemoryCredentialStore() : KeychainCredentialStore()
        )
        _account = State(initialValue: account)
        let gitHub = GitHubStatusModel(account: account, api: api)
        let notifier = AttentionNotifier(
            notifier: UITestSupport.usesInMemoryStore(environment) ? SilentNotifier() : SystemNotifier()
        )
        gitHub.onUpdate = { _, new in
            Task { await notifier.update(new) }
        }
        let store = LibraryStore(container: container)
        let library = LibraryViewModel(store: store, autoRefresh: AutoRefreshController(), gitHub: gitHub)
        let sync = SyncModel(account: account, api: api, store: store) { [weak library] repository in
            library?.remoteIdentity(of: repository)
        }
        sync.onApplied = { [weak library] in library?.load() }
        library.sync = sync
        _library = State(initialValue: library)
        launchFolders = Self.launchFolders(environment: environment)
    }

    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
            LibraryView(model: library)
                .task { await library.start(addingFolders: launchFolders) }
                .task { await account.restore() }
                .task(id: account.user?.id) {
                    await library.refreshGitHub()
                    await library.sync?.sync()
                }
        }
        .modelContainer(container)
        .defaultLaunchBehavior(menuBarOnly && showMenuBarExtra ? .suppressed : .presented)
        .commands {
            RepositoryCommands(model: library)
        }

        Settings {
            SettingsView(settings: settings, library: library, account: account)
        }

        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuBarContent(library: library)
                .task { await library.start(addingFolders: launchFolders) }
                .task { await account.restore() }
        } label: {
            MenuBarLabel(library: library)
                .task { await library.start(addingFolders: launchFolders) }
                .task { await account.restore() }
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
