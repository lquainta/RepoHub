import AppKit
import Foundation
import RepoHubCore
import SnapshotTesting
import SwiftUI
import Testing

@testable import RepoHub

/// Where reference images come from (#63).
///
/// Text renders slightly differently on each macOS version, so references are
/// recorded on CI's runner (macOS 26) and the tests run only there. A missing
/// reference is recorded on CI, the test fails, and the image is uploaded as
/// the `app-snapshots` artifact to commit. See docs/testing.md.
enum SnapshotReference {
    static let macOSMajorVersion = 26

    static var matchesThisMac: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion == macOSMajorVersion
    }
}

/// Renders `view` in light and dark mode, in English and Spanish, and compares
/// each image with its reference.
@MainActor
func assertSnapshots(
    of view: some View,
    size: CGSize,
    fileID: StaticString = #fileID,
    file filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    for language in ["en", "es"] {
        for dark in [false, true] {
            let host = NSHostingView(
                rootView:
                    view
                    .environment(\.locale, Locale(identifier: language))
                    .frame(width: size.width, height: size.height)
                    .background(Color(nsColor: .windowBackgroundColor))
            )
            host.frame = CGRect(origin: .zero, size: size)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            assertSnapshot(
                of: host,
                as: .image(precision: 1, perceptualPrecision: 0.98),
                named: "\(language)-\(dark ? "dark" : "light")",
                fileID: fileID,
                file: filePath,
                testName: testName,
                line: line,
                column: column
            )
        }
    }
}

@MainActor
@Suite("Snapshots", .enabled(if: SnapshotReference.matchesThisMac, "References are recorded on macOS 26 (CI)"))
struct SnapshotTests {
    @Test("Empty state with an action")
    func emptyState() {
        assertSnapshots(
            of: EmptyStateView(
                "No Folders",
                systemImage: "folder.badge.plus",
                description: Text("Add a folder and RepoHub will find the git repositories inside it.")
            ) {
                Button("Add Folder…") {}
            },
            size: CGSize(width: 420, height: 260)
        )
    }

    @Test("Statuses: clean, changes, unavailable, unmerged")
    func statuses() {
        assertSnapshots(
            of: VStack(alignment: .leading, spacing: 10) {
                StatusLabel("Clean", systemImage: "checkmark.circle", tint: .green)
                StatusLabel("Unavailable", systemImage: "exclamationmark.triangle", tint: .orange)
                StatusLabel("Unmerged", systemImage: "exclamationmark.circle.fill", tint: .orange)
                Text("Working tree clean").foregroundStyle(.secondaryText)
            }
            .padding(),
            size: CGSize(width: 260, height: 160)
        )
    }

    @Test("GitHub section: CI and pull requests")
    func gitHubSection() {
        let status = GitHubRepositoryStatus.fixture(
            "api",
            pulls: [.fixture(12, head: "main", review: true), .fixture(9, head: "docs")],
            checks: .failure
        )
        assertSnapshots(
            of: Form { GitHubSection(status: status, branch: "main") }.formStyle(.grouped),
            size: CGSize(width: 420, height: 260)
        )
    }

    @Test("Account settings, signed out")
    func accountSignedOut() throws {
        let defaults = try #require(UserDefaults(suiteName: "SnapshotTests-\(UUID().uuidString)"))
        let account = AccountModel(api: FakeAPI(), credentials: InMemoryCredentialStore(), workspace: FakeWorkspace())
        assertSnapshots(
            of: AccountSettings(
                account: account,
                settings: SettingsModel(defaults: defaults, loginItem: NoLoginItem())
            ),
            size: CGSize(width: 520, height: 360)
        )
    }
}

/// A login item that's never registered, for views that only show it.
private struct NoLoginItem: LoginItemManaging {
    var isEnabled: Bool { false }
    func setEnabled(_ enabled: Bool) throws {}
}
