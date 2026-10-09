import XCTest

/// End-to-end tests that launch the real app and drive its UI.
///
/// Swift Testing does not support UI automation, so UI tests use XCTest.
/// The app is always launched with an in-memory store so the developer's
/// real folders and data are never touched (see `UITestSupport`).
@MainActor
final class LaunchTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// Launches the app with an in-memory store and window restoration disabled.
    ///
    /// Test settings go in the environment, not launch arguments (see
    /// `UITestSupport`). `-ApplePersistenceIgnoreState YES` stops macOS from
    /// restoring the previous test's killed session.
    private func launchApp(fixtureRepositories: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["REPOHUB_UI_TEST_IN_MEMORY_STORE"] = "1"
        if !fixtureRepositories.isEmpty {
            app.launchEnvironment["REPOHUB_UI_TEST_FIXTURE_REPOSITORIES"] = fixtureRepositories.joined(separator: ",")
        }
        app.launch()
        return app
    }

    func testFirstLaunchShowsEmptyState() {
        let app = launchApp()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["emptyState"].waitForExistence(timeout: 5))
    }

    func testScanningAFolderListsItsRepositories() {
        let app = launchApp(fixtureRepositories: [
            "alpha/.git", "nested/beta/.git", "node_modules/ignored/.git", "plain-folder",
        ])
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        let alpha = app.descendants(matching: .any)["repository-alpha"]
        guard alpha.waitForExistence(timeout: 15) else {
            attachAccessibilityTree(of: app)
            XCTFail("Scanned repository 'alpha' never appeared")
            return
        }
        XCTAssertTrue(app.descendants(matching: .any)["repository-beta"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["repository-ignored"].exists)
    }

    /// Attaches the app's accessibility hierarchy to the test result to diagnose failures.
    private func attachAccessibilityTree(of app: XCUIApplication) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = "Accessibility tree"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
