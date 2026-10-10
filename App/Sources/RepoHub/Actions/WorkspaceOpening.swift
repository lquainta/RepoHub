import AppKit

/// Opens files, folders, and URLs in other apps and uses the clipboard.
/// ``SystemWorkspace`` is the real implementation; tests inject fakes.
@MainActor
protocol WorkspaceOpening {
    /// Opens `folder` with the app whose bundle identifier is `bundleID`.
    func open(_ folder: URL, withApplication bundleID: String) async throws
    /// Shows `url` selected in a Finder window.
    func revealInFinder(_ url: URL)
    /// Opens a web URL in the default browser.
    func openInBrowser(_ url: URL)
    /// Replaces the clipboard's contents with `string`.
    func copyToClipboard(_ string: String)
}

/// Errors from opening other apps.
enum WorkspaceError: LocalizedError, Equatable {
    /// No app with this bundle identifier is installed.
    case applicationNotFound(bundleID: String)

    var errorDescription: String? {
        switch self {
        case .applicationNotFound(let bundleID):
            String(localized: "The app \(bundleID) isn't installed. Choose another in Settings.")
        }
    }
}

/// Uses `NSWorkspace` and `NSPasteboard`.
struct SystemWorkspace: WorkspaceOpening {
    func open(_ folder: URL, withApplication bundleID: String) async throws {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw WorkspaceError.applicationNotFound(bundleID: bundleID)
        }
        try await NSWorkspace.shared.open(
            [folder],
            withApplicationAt: app,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openInBrowser(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
