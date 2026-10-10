import Foundation
import RepoHubCore
import Testing

@testable import RepoHub

/// A login item that records changes and can be told to fail.
@MainActor
private final class FakeLoginItem: LoginItemManaging {
    var isEnabled = false
    var failure: (any Error)?

    func setEnabled(_ enabled: Bool) throws {
        if let failure {
            throw failure
        }
        isEnabled = enabled
    }
}

private struct RegistrationDenied: LocalizedError {
    var errorDescription: String? { "Operation not permitted" }
}

@MainActor
@Suite("SettingsModel")
struct SettingsModelTests {
    private let suiteName = "SettingsModelTests-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("Defaults match AppPreferences when nothing is stored")
    func defaultsWhenEmpty() {
        let settings = SettingsModel(defaults: defaults, loginItem: FakeLoginItem())
        #expect(settings.editorBundleID == AppPreferences.defaultEditorBundleID)
        #expect(settings.terminalBundleID == AppPreferences.defaultTerminalBundleID)
        #expect(settings.backgroundFetchMinutes == 0)
        #expect(settings.staleBranchDays == AppPreferences.defaultStaleBranchDays)
        #expect(Set(settings.ignoredFolderNames) == RepositoryScanner.defaultIgnoredNames)
        #expect(settings.showMenuBarExtra)
        #expect(!settings.launchAtLogin)
    }

    @Test("Every change is stored immediately and read back by a new model and by AppPreferences")
    func persists() {
        let settings = SettingsModel(defaults: defaults, loginItem: FakeLoginItem())
        settings.editorBundleID = "dev.zed.Zed"
        settings.terminalBundleID = "com.mitchellh.ghostty"
        settings.backgroundFetchMinutes = 15
        settings.staleBranchDays = 0
        settings.showMenuBarExtra = false
        settings.menuBarOnly = true
        settings.addIgnoredFolderName("vendor")

        let reloaded = SettingsModel(defaults: defaults, loginItem: FakeLoginItem())
        #expect(reloaded.editorBundleID == "dev.zed.Zed")
        #expect(reloaded.terminalBundleID == "com.mitchellh.ghostty")
        #expect(reloaded.backgroundFetchMinutes == 15)
        #expect(reloaded.staleBranchDays == 0)
        #expect(!reloaded.showMenuBarExtra)
        #expect(reloaded.menuBarOnly)
        #expect(reloaded.ignoredFolderNames.contains("vendor"))

        #expect(AppPreferences.editorBundleID(defaults) == "dev.zed.Zed")
        #expect(AppPreferences.backgroundFetchMinutes(defaults) == 15)
        #expect(AppPreferences.staleBranchDays(defaults) == nil)
        #expect(AppPreferences.ignoredFolderNames(defaults).contains("vendor"))
    }

    @Test("Ignored folder names are trimmed, deduplicated, and can't contain a slash")
    func ignoredNames() {
        let settings = SettingsModel(defaults: defaults, loginItem: FakeLoginItem())
        #expect(settings.addIgnoredFolderName("  target "))
        #expect(!settings.addIgnoredFolderName("target"))
        #expect(!settings.addIgnoredFolderName("a/b"))
        #expect(!settings.addIgnoredFolderName("   "))
        #expect(settings.ignoredFolderNames == settings.ignoredFolderNames.sorted())

        settings.removeIgnoredFolderName("node_modules")
        #expect(!AppPreferences.ignoredFolderNames(defaults).contains("node_modules"))

        settings.resetIgnoredFolderNames()
        #expect(AppPreferences.ignoredFolderNames(defaults) == RepositoryScanner.defaultIgnoredNames)
    }

    @Test("Open at login registers the app, and reverts with an error if registration fails")
    func launchAtLogin() {
        let loginItem = FakeLoginItem()
        let settings = SettingsModel(defaults: defaults, loginItem: loginItem)

        settings.launchAtLogin = true
        #expect(loginItem.isEnabled)

        loginItem.failure = RegistrationDenied()
        settings.launchAtLogin = false
        #expect(settings.launchAtLogin)
        #expect(settings.errorMessage?.contains("Operation not permitted") == true)
    }
}
