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

    /// A static text in the frontmost window whose label or value is exactly
    /// `text`. (Searching every element for a substring times out on CI, so
    /// these queries name the element type and match exactly.)
    private func text(_ text: String) -> XCUIElement {
        window.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", text, text)).firstMatch
    }

    /// A button, such as a column header, titled exactly `title`.
    private func button(_ title: String) -> XCUIElement {
        window.buttons.matching(NSPredicate(format: "title == %@ OR label == %@", title, title)).firstMatch
    }

    func testDashboardIsInSpanish() {
        XCTAssertTrue(window.descendants(matching: .any)["repository-clean"].waitForExistence(timeout: 20))

        // Column titles, a status, and the empty details pane.
        for title in ["Rama", "Cambios"] {
            XCTAssertTrue(button(title).waitForExistence(timeout: 5), "Missing Spanish column: \(title)")
        }
        for spanish in ["Limpio", "Ningún repositorio seleccionado"] {
            XCTAssertTrue(text(spanish).waitForExistence(timeout: 5), "Missing Spanish text: \(spanish)")
        }
        for english in ["Branch", "Changes", "Last Commit", "Ahead/Behind"] {
            XCTAssertFalse(button(english).exists, "English column in the Spanish UI: \(english)")
        }
        for english in ["No Repository Selected", "Clean"] {
            XCTAssertFalse(text(english).exists, "English text in the Spanish UI: \(english)")
        }
    }

    func testSettingsAreInSpanish() {
        app.typeKey(",", modifierFlags: .command)
        let account = app.toolbars.buttons["Cuenta"]
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        account.click()
        XCTAssertTrue(button("Iniciar sesión con GitHub…").waitForExistence(timeout: 5))
        XCTAssertTrue(text("Avisarme cuando").exists)
    }
}
