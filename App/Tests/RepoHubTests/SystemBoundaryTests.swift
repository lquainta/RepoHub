import AppKit
import Foundation
import Testing

@testable import RepoHub

/// The thin types that talk to macOS: the Keychain, `NSWorkspace`, and notifications.
/// Tests use throwaway Keychain items and never open another app.
@MainActor
@Suite("System boundaries")
struct SystemBoundaryTests {
    @Test("Credentials round-trip through the Keychain, are replaced on save, and are gone after delete")
    func keychain() throws {
        let store = KeychainCredentialStore(service: "com.lquainta.RepoHub.tests.\(UUID().uuidString)")
        defer { try? store.delete() }
        let first = StoredCredentials(refreshToken: "r1", user: .octocat)
        do {
            try store.save(first)
        } catch let error as KeychainError where Self.keychainUnavailable.contains(error.status) {
            // A machine without an unlocked login Keychain (some CI runners) can't run this.
            return
        }

        #expect(try store.load() == first)
        let second = StoredCredentials(refreshToken: "r2", user: .octocat)
        try store.save(second)
        #expect(try store.load() == second)

        try store.delete()
        #expect(try store.load() == nil)
        // Deleting what isn't there isn't an error.
        try store.delete()
    }

    private static let keychainUnavailable: Set<OSStatus> = [
        errSecInteractionNotAllowed, errSecNotAvailable, errSecNoDefaultKeychain, errSecMissingEntitlement,
    ]

    @Test("A Keychain error names the system's reason")
    func keychainErrorDescription() {
        let description = KeychainError(status: errSecAuthFailed).localizedDescription
        #expect(description.hasPrefix("Keychain error: "))
        #expect(description.count > "Keychain error: ".count)
    }

    @Test("The in-memory store keeps credentials until they're deleted")
    func inMemoryStore() throws {
        let store = InMemoryCredentialStore()
        #expect(try store.load() == nil)
        let credentials = StoredCredentials(refreshToken: "r1", user: .octocat)
        try store.save(credentials)
        #expect(try store.load() == credentials)
        try store.delete()
        #expect(try store.load() == nil)
    }

    @Test("Opening a folder with an app that isn't installed fails with the app's identifier")
    func missingApplication() async {
        let bundleID = "com.example.not-installed-\(UUID().uuidString)"
        await #expect(throws: WorkspaceError.applicationNotFound(bundleID: bundleID)) {
            try await SystemWorkspace().open(URL(fileURLWithPath: NSTemporaryDirectory()), withApplication: bundleID)
        }
        #expect(WorkspaceError.applicationNotFound(bundleID: bundleID).localizedDescription.contains(bundleID))
    }

    @Test("Known apps lists the installed candidates, plus the selected app when it's another installed one")
    func knownApps() throws {
        let finder = try #require(KnownApps.app(bundleID: "com.apple.finder"))
        #expect(finder.name.contains("Finder"))
        #expect(finder.id == "com.apple.finder")
        #expect(KnownApps.app(bundleID: "com.example.not-installed") == nil)

        let candidates = [
            KnownApps.App(name: "TextEdit", bundleID: "com.apple.TextEdit"),
            KnownApps.App(name: "Missing", bundleID: "com.example.not-installed"),
        ]
        #expect(
            KnownApps.installed(candidates, including: "com.apple.TextEdit").map(\.bundleID) == ["com.apple.TextEdit"]
        )
        #expect(
            KnownApps.installed(candidates, including: "com.apple.finder").map(\.bundleID)
                == ["com.apple.TextEdit", "com.apple.finder"]
        )
        #expect(
            KnownApps.installed(candidates, including: "com.example.also-missing").map(\.bundleID)
                == ["com.apple.TextEdit"]
        )
        #expect(Set(KnownApps.editors.map(\.id)).count == KnownApps.editors.count)
        #expect(Set(KnownApps.terminals.map(\.id)).count == KnownApps.terminals.count)
    }

    @Test("The silent notifier never asks for permission")
    func silentNotifier() async {
        let notifier = SilentNotifier()
        #expect(await notifier.requestAuthorization() == false)
    }
}
