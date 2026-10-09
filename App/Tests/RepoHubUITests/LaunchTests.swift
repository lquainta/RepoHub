import XCTest

/// End-to-end tests that launch the real app and drive its UI.
///
/// Swift Testing does not support UI automation, so UI tests use XCTest.
/// The app is always launched with an in-memory store so the developer's
/// real folders and data are never touched.
@MainActor
final class LaunchTests: XCTestCase {
    private var fixtureRoot: URL?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        if let fixtureRoot {
            try? FileManager.default.removeItem(at: fixtureRoot)
        }
    }

    func testFirstLaunchShowsEmptyState() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestInMemoryStore"]
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["emptyState"].waitForExistence(timeout: 5))
    }

    func testScanningAFolderListsItsRepositories() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("repohub-ui-\(UUID().uuidString)", isDirectory: true)
        fixtureRoot = root
        for path in ["alpha/.git", "nested/beta/.git", "node_modules/ignored/.git", "plain-folder"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(path),
                withIntermediateDirectories: true
            )
        }

        let app = XCUIApplication()
        app.launchArguments = ["-UITestInMemoryStore", "-UITestScanFolder", root.path]
        app.launch()

        let list = app.descendants(matching: .any)["repositoryList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["repository-alpha"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["repository-beta"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["repository-ignored"].exists)
    }
}
