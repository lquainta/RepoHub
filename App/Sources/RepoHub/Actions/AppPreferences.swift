import Foundation

/// Keys and defaults for preferences stored in `UserDefaults` (edited in Settings, #74).
enum AppPreferences {
    /// Bundle identifier of the editor that "Open in Editor" uses.
    static let editorBundleIDKey = "editorBundleID"
    /// Bundle identifier of the terminal that "Open in Terminal" uses.
    static let terminalBundleIDKey = "terminalBundleID"

    /// Days without commits after which a branch counts as stale; `0` turns the check off.
    static let staleBranchDaysKey = "staleBranchDays"
    /// Branches untouched for 90 days are suggested for cleanup.
    static let defaultStaleBranchDays = 90

    /// Minutes between background fetches of every repository; `0` turns it off (the default).
    static let backgroundFetchMinutesKey = "backgroundFetchMinutes"

    /// Visual Studio Code.
    static let defaultEditorBundleID = "com.microsoft.VSCode"
    /// Terminal.app.
    static let defaultTerminalBundleID = "com.apple.Terminal"

    static func editorBundleID(_ defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: editorBundleIDKey) ?? defaultEditorBundleID
    }

    static func terminalBundleID(_ defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: terminalBundleIDKey) ?? defaultTerminalBundleID
    }

    /// Minutes between background fetches; `0` means off.
    static func backgroundFetchMinutes(_ defaults: UserDefaults = .standard) -> Int {
        max(0, defaults.integer(forKey: backgroundFetchMinutesKey))
    }

    /// The inactivity threshold, or `nil` when the check is off.
    static func staleBranchDays(_ defaults: UserDefaults = .standard) -> Int? {
        let days = defaults.object(forKey: staleBranchDaysKey) as? Int ?? defaultStaleBranchDays
        return days > 0 ? days : nil
    }
}
