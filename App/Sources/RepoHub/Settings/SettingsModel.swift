import Foundation
import OSLog
import Observation
import RepoHubCore
import ServiceManagement

/// Registers the app to open at login. ``SystemLoginItem`` is the real
/// implementation; tests inject fakes.
@MainActor
protocol LoginItemManaging {
    /// Whether the app is registered to open at login.
    var isEnabled: Bool { get }
    /// Registers or unregisters the app.
    func setEnabled(_ enabled: Bool) throws
}

/// Uses `SMAppService.mainApp`.
struct SystemLoginItem: LoginItemManaging {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// The Settings window's state. Every change is written to `UserDefaults`
/// immediately, so it takes effect without a relaunch.
@MainActor
@Observable
final class SettingsModel {
    private let defaults: UserDefaults
    private let loginItem: any LoginItemManaging
    private let logger = Logger(subsystem: "com.lquainta.RepoHub", category: "Settings")

    /// A user-facing error from the last change, if any.
    var errorMessage: String?

    init(defaults: UserDefaults = .standard, loginItem: any LoginItemManaging = SystemLoginItem()) {
        self.defaults = defaults
        self.loginItem = loginItem
        editorBundleID = AppPreferences.editorBundleID(defaults)
        terminalBundleID = AppPreferences.terminalBundleID(defaults)
        backgroundFetchMinutes = AppPreferences.backgroundFetchMinutes(defaults)
        staleBranchDays = AppPreferences.staleBranchDays(defaults) ?? 0
        ignoredFolderNames = AppPreferences.ignoredFolderNames(defaults).sorted()
        showMenuBarExtra = AppPreferences.showMenuBarExtra(defaults)
        menuBarOnly = defaults.bool(forKey: AppPreferences.menuBarOnlyKey)
        launchAtLogin = loginItem.isEnabled
    }

    /// Bundle identifier of the editor for "Open in Editor".
    var editorBundleID: String {
        didSet { defaults.set(editorBundleID, forKey: AppPreferences.editorBundleIDKey) }
    }

    /// Bundle identifier of the terminal for "Open in Terminal".
    var terminalBundleID: String {
        didSet { defaults.set(terminalBundleID, forKey: AppPreferences.terminalBundleIDKey) }
    }

    /// Minutes between background fetches; 0 is off.
    var backgroundFetchMinutes: Int {
        didSet { defaults.set(max(0, backgroundFetchMinutes), forKey: AppPreferences.backgroundFetchMinutesKey) }
    }

    /// Days without commits before a branch counts as stale; 0 turns the check off.
    var staleBranchDays: Int {
        didSet { defaults.set(max(0, staleBranchDays), forKey: AppPreferences.staleBranchDaysKey) }
    }

    /// Folder names the scanner skips, sorted.
    private(set) var ignoredFolderNames: [String] {
        didSet { defaults.set(ignoredFolderNames, forKey: AppPreferences.ignoredFolderNamesKey) }
    }

    /// Whether the menu bar summary is shown.
    var showMenuBarExtra: Bool {
        didSet { defaults.set(showMenuBarExtra, forKey: AppPreferences.showMenuBarExtraKey) }
    }

    /// Whether RepoHub runs from the menu bar only (no Dock icon). Only has an
    /// effect while the menu bar summary is shown.
    var menuBarOnly: Bool {
        didSet { defaults.set(menuBarOnly, forKey: AppPreferences.menuBarOnlyKey) }
    }

    /// Whether RepoHub opens at login. Reverts if registration fails.
    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != loginItem.isEnabled else {
                return
            }
            do {
                try loginItem.setEnabled(launchAtLogin)
            } catch {
                logger.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = String(localized: "Couldn't change Open at Login: \(error.localizedDescription)")
                launchAtLogin = loginItem.isEnabled
            }
        }
    }

    /// Adds a folder name to skip. Names with a slash, empty names, and duplicates are ignored.
    ///
    /// - Returns: Whether the name was added.
    @discardableResult
    func addIgnoredFolderName(_ name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !ignoredFolderNames.contains(name) else {
            return false
        }
        ignoredFolderNames = (ignoredFolderNames + [name]).sorted()
        return true
    }

    /// Stops skipping `name`.
    func removeIgnoredFolderName(_ name: String) {
        ignoredFolderNames.removeAll { $0 == name }
    }

    /// Restores the default ignored folder names.
    func resetIgnoredFolderNames() {
        ignoredFolderNames = RepositoryScanner.defaultIgnoredNames.sorted()
    }
}
