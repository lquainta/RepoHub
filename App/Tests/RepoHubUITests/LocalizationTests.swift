import XCTest

/// The app in Spanish (#57): translated text and no English leftovers on the
/// main screens.
@MainActor
final class LocalizationTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES",
        ]
        app.launchEnvironment["REPOHUB_UI_TEST_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["REPOHUB_UI_TEST_GIT_FIXTURES"] = "1"
        app.launchEnvironment["REPOHUB_UI_TEST_STUB_BACKEND"] = "1"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    override func tearDown() async throws {
        app.terminate()
    }

    /// The frontmost window.
    private var window: XCUIElement { app.windows.element(boundBy: 0) }

    // CI's accessibility tree shows where each text lives: column headers are
    // buttons with a title, statuses are static texts with a value, and
    // headings are static texts with a label. Each check queries that exact
    // attribute on that element type, since searching every element for a
    // substring times out on CI. Labels are matched with the subscript:
    // `label ==` in a predicate didn't match on CI.

    /// A column header titled exactly `title`.
    private func column(_ title: String) -> XCUIElement {
        window.buttons.matching(NSPredicate(format: "title == %@", title)).firstMatch
    }

    /// A static text whose value is exactly `value`, such as a status.
    private func value(_ value: String) -> XCUIElement {
        window.staticTexts.matching(NSPredicate(format: "value == %@", value)).firstMatch
    }

    /// A static text labeled exactly `label`, such as a heading.
    private func heading(_ label: String) -> XCUIElement {
        window.staticTexts[label]
    }

    func testDashboardIsInSpanish() {
        XCTAssertTrue(window.descendants(matching: .any)["repository-clean"].waitForExistence(timeout: 20))

        // Text that's on screen at any window size: the Name column (the
        // dashboard drops the others when it's narrow, as on CI's 900-point
        // window), the search prompt, and the empty details pane. Statuses
        // such as "Limpio" are covered at a fixed size by SnapshotTests.
        XCTAssertTrue(column("Nombre").waitForExistence(timeout: 5), "Missing Spanish column: Nombre")
        XCTAssertEqual(window.searchFields.firstMatch.placeholderValue, "Nombre, ruta o rama")
        XCTAssertTrue(
            heading("Ningún repositorio seleccionado").waitForExistence(timeout: 5),
            "Missing Spanish text: Ningún repositorio seleccionado"
        )
        // No English, in any column that is shown.
        for english in ["Name", "Branch", "Changes", "Last Commit", "Ahead/Behind"] {
            XCTAssertFalse(column(english).exists, "English column in the Spanish UI: \(english)")
        }
        XCTAssertFalse(value("Clean").exists, "English status in the Spanish UI: Clean")
        XCTAssertFalse(heading("No Repository Selected").exists, "English text in the Spanish UI")
    }

    func testSettingsAreInSpanish() {
        app.typeKey(",", modifierFlags: .command)
        let account = app.toolbars.buttons["Cuenta"]
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        account.click()
        let signIn = window.descendants(matching: .any)["signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        XCTAssertTrue(
            [signIn.label, signIn.title].contains("Iniciar sesión con GitHub…"),
            "Sign-in button: \(signIn.label) / \(signIn.title)"
        )
        XCTAssertTrue(heading("Avisarme cuando").exists)
    }
}
