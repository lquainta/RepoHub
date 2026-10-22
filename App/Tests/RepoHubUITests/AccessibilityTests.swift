import XCTest

/// Automated accessibility audits (#58) of each main screen, with the same
/// fixtures and stub backend as `FlowTests`.
@MainActor
final class AccessibilityTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = true
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["REPOHUB_UI_TEST_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["REPOHUB_UI_TEST_GIT_FIXTURES"] = "1"
        app.launchEnvironment["REPOHUB_UI_TEST_STUB_BACKEND"] = "1"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["repository-dirty"].waitForExistence(timeout: 20))
    }

    override func tearDown() async throws {
        app.terminate()
    }

    /// Audits the app, failing on every issue except the framework-owned ones
    /// in ``isFrameworkIssue(_:)`` (documented in docs/accessibility.md).
    private func audit(_ screen: String) throws {
        // A row under the pointer is highlighted, which changes its contrast;
        // park the pointer on the frontmost window's title bar.
        app.windows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)).hover()
        try app.performAccessibilityAudit { issue in
            if self.isFrameworkIssue(issue) {
                return true
            }
            let element =
                issue.element.map { "'\($0.identifier)' \(String(describing: $0.value)) at \($0.frame)" } ?? "none"
            XCTFail("\(screen): \(issue.compactDescription) [\(issue.auditType.rawValue)] on \(element)")
            return true
        }
    }

    /// Issues about elements an app can't change:
    /// - SwiftUI's unlabeled layout containers and the system Touch Bar, which
    ///   VoiceOver doesn't stop on;
    /// - native pop-up and menu buttons (SwiftUI `Picker` and `Menu`), which
    ///   the audit reports as having no action although they open;
    /// - contrast of text outside the frontmost sheet or window, which macOS
    ///   dims on purpose, and of toolbar tab titles, which AppKit draws;
    /// - contrast inside the selected row of a SwiftUI `Table`, whose cells
    ///   don't learn they're selected (`backgroundProminence`), so they keep
    ///   their colors on the selection highlight, as AppKit tables do.
    private func isFrameworkIssue(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard let element = issue.element else {
            return false
        }
        switch issue.auditType {
        case .sufficientElementDescription:
            return [.group, .touchBar].contains(element.elementType) && element.identifier.isEmpty
        case .action:
            return [.popUpButton, .menuButton].contains(element.elementType)
        case .contrast:
            // With a sheet open, only the sheet's own text counts: the window
            // behind it is covered but still in the accessibility tree.
            let sheet = app.descendants(matching: .sheet).firstMatch
            if sheet.exists {
                return !sheet.descendants(matching: element.elementType).allElementsBoundByIndex.contains {
                    $0.frame == element.frame && ($0.value as? String) == (element.value as? String)
                }
            }
            if !app.windows.element(boundBy: 0).frame.contains(element.frame) {
                return true
            }
            if let title = element.value as? String, app.toolbars.buttons[title].exists {
                return true
            }
            let selected = app.outlines["repositoryTable"].outlineRows.matching(NSPredicate(format: "selected == true"))
            return selected.allElementsBoundByIndex.contains { $0.frame.contains(element.frame) }
        default:
            return false
        }
    }

    func testDashboardAndDetail() throws {
        try audit("Dashboard")
        app.descendants(matching: .any)["repository-dirty"].click()
        XCTAssertTrue(app.descendants(matching: .any)["repositoryDetail"].waitForExistence(timeout: 10))
        try audit("Detail")
    }

    func testSettings() throws {
        // Only the Settings window, so nothing behind it is dimmed.
        app.typeKey("w", modifierFlags: .command)
        app.typeKey(",", modifierFlags: .command)
        for tab in ["General", "Folders", "Apps", "Account"] {
            let button = app.toolbars.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.click()
            try audit("Settings \(tab)")
        }
    }

    func testActivity() throws {
        app.typeKey("a", modifierFlags: [.command, .shift])
        app.windows["Activity"].click()
        XCTAssertTrue(app.windows["Activity"].waitForExistence(timeout: 10))
        try audit("Activity")
    }

    func testStaleBranches() throws {
        app.descendants(matching: .any)["repository-stale"].click()
        app.menuBars.menuBarItems["Repository"].click()
        app.menuItems["Clean Up Branches…"].click()
        XCTAssertTrue(app.descendants(matching: .any)["staleBranchList"].waitForExistence(timeout: 10))
        try audit("Clean Up Branches")
    }

    /// The menu shortcuts open and close the cleanup sheet and the Activity window.
    func testKeyboardShortcuts() {
        app.descendants(matching: .any)["repository-stale"].click()

        // Repository > Clean Up Branches… (⌥⌘B), then Escape cancels.
        app.typeKey("b", modifierFlags: [.command, .option])
        let sheet = app.descendants(matching: .sheet).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        app.typeKey(.escape, modifierFlags: [])
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: sheet)
        wait(for: [closed], timeout: 5)

        // The Activity window (⇧⌘A).
        app.typeKey("a", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.windows["Activity"].waitForExistence(timeout: 10))
    }
}
