import Foundation

/// Keys and defaults for preferences stored in `UserDefaults` (edited in Settings, #74).
enum AppPreferences {
    /// Bundle identifier of the editor that "Open in Editor" uses.
    static let editorBundleIDKey = "editorBundleID"
    /// Bundle identifier of the terminal that "Open in Terminal" uses.
    static let terminalBundleIDKey = "terminalBundleID"

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
}
