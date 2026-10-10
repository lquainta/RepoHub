import AppKit

/// Editors and terminals offered in Settings when installed.
enum KnownApps {
    /// An app the user can pick.
    struct App: Identifiable, Hashable {
        let name: String
        let bundleID: String
        var id: String { bundleID }
    }

    static let editors: [App] = [
        App(name: "Visual Studio Code", bundleID: "com.microsoft.VSCode"),
        App(name: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92"),
        App(name: "Zed", bundleID: "dev.zed.Zed"),
        App(name: "Xcode", bundleID: "com.apple.dt.Xcode"),
        App(name: "Sublime Text", bundleID: "com.sublimetext.4"),
        App(name: "Nova", bundleID: "com.panic.Nova"),
        App(name: "BBEdit", bundleID: "com.barebones.bbedit"),
        App(name: "TextEdit", bundleID: "com.apple.TextEdit"),
    ]

    static let terminals: [App] = [
        App(name: "Terminal", bundleID: "com.apple.Terminal"),
        App(name: "iTerm", bundleID: "com.googlecode.iterm2"),
        App(name: "Ghostty", bundleID: "com.mitchellh.ghostty"),
        App(name: "Warp", bundleID: "dev.warp.Warp-Stable"),
        App(name: "kitty", bundleID: "net.kovidgoyal.kitty"),
        App(name: "Alacritty", bundleID: "org.alacritty"),
    ]

    /// The apps in `candidates` that are installed, plus `selected` if it's
    /// another installed app (chosen with "Other…").
    @MainActor
    static func installed(_ candidates: [App], including selected: String) -> [App] {
        var apps = candidates.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
        if !apps.contains(where: { $0.bundleID == selected }), let other = app(bundleID: selected) {
            apps.append(other)
        }
        return apps
    }

    /// The installed app with this bundle identifier, named as Finder shows it.
    @MainActor
    static func app(bundleID: String) -> App? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return App(name: FileManager.default.displayName(atPath: url.path), bundleID: bundleID)
    }

    /// Asks the user to pick any app and returns its bundle identifier.
    @MainActor
    static func chooseOtherApp() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }
        return Bundle(url: url)?.bundleIdentifier
    }
}
