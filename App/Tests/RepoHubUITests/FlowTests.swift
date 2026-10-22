import XCTest

/// The main user flows, end to end, against real git repositories the app
/// creates in a temporary folder (`clean`, `dirty`, and `stale`, which has a
/// merged `old-feature` branch) and a stubbed backend. See `UITestSupport`.
@MainActor
final class FlowTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["REPOHUB_UI_TEST_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["REPOHUB_UI_TEST_GIT_FIXTURES"] = "1"
        app.launchEnvironment["REPOHUB_UI_TEST_STUB_BACKEND"] = "1"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    override func tearDown() async throws {
        if let run = testRun, run.failureCount > 0 {
            let attachment = XCTAttachment(string: app.debugDescription)
            attachment.name = "Accessibility tree"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app.terminate()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Any element in `container` whose label or value contains `text`
    /// (SwiftUI often combines a row's texts into one value).
    private func element(in container: XCUIElement, containing text: String) -> XCUIElement {
        container.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text))
            .firstMatch
    }

    /// Waits for the three fixture repositories to be scanned.
    private func waitForRepositories() {
        for name in ["clean", "dirty", "stale"] {
            XCTAssertTrue(element("repository-\(name)").waitForExistence(timeout: 20), "\(name) never appeared")
        }
    }

    func testAddingAFolderListsItsRepositories() {
        waitForRepositories()
        // Each row shows the repository's path inside the scanned folder.
        let row = element("repository-clean")
        XCTAssertTrue(
            (row.value as? String)?.contains("repohub-ui-git") == true,
            "Row: \(String(describing: row.value))"
        )
    }

    func testFilteringByUncommittedChangesShowsOnlyDirtyRepositories() {
        waitForRepositories()

        element("quickFilterMenu").click()
        app.menuItems["Uncommitted Changes"].click()

        XCTAssertTrue(element("repository-dirty").waitForExistence(timeout: 5))
        let cleanGone = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: element("repository-clean")
        )
        wait(for: [cleanGone], timeout: 5)
        XCTAssertFalse(element("repository-stale").exists)
    }

    func testSelectingARepositoryShowsItsDetails() {
        waitForRepositories()

        element("repository-clean").click()

        let detail = element("repositoryDetail")
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        XCTAssertTrue(element(in: detail, containing: "Initial commit").waitForExistence(timeout: 5))
    }

    func testCleaningUpAMergedBranchDeletesIt() {
        waitForRepositories()
        element("repository-stale").click()

        app.menuBars.menuBarItems["Repository"].click()
        app.menuItems["Clean Up Branches…"].click()

        let list = element("staleBranchList")
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        XCTAssertTrue(element(in: list, containing: "old-feature").waitForExistence(timeout: 5))
        app.buttons["Delete 1 Branches"].click()

        XCTAssertTrue(element(in: app, containing: "Deleted (1)").waitForExistence(timeout: 10))
        app.buttons["Done"].click()
    }

    func testSigningInAndOut() {
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows.matching(NSPredicate(format: "title CONTAINS 'Account' OR title CONTAINS 'General'"))
            .firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        app.toolbars.buttons["Account"].click()

        element("signIn").click()

        let user = element("signedInUser")
        XCTAssertTrue(user.waitForExistence(timeout: 10))
        XCTAssertTrue(element(in: app, containing: "octocat").waitForExistence(timeout: 5))

        app.buttons["Sign Out"].click()
        XCTAssertTrue(element("signIn").waitForExistence(timeout: 10))
    }
}
