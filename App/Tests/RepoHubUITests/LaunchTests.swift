import XCTest

/// End-to-end tests that launch the real app and drive its UI.
///
/// Swift Testing does not support UI automation, so UI tests use XCTest.
@MainActor
final class LaunchTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testLaunchShowsMainWindow() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["RepoHub"].exists)
    }
}
