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

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(
                NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@ OR title CONTAINS %@", text, text, text)
            )
            .firstMatch
    }

    func testDashboardIsInSpanish() {
        XCTAssertTrue(app.descendants(matching: .any)["repository-clean"].waitForExistence(timeout: 20))

        // Column titles, a status, and the empty details pane.
        for text in ["Rama", "Cambios", "Limpio", "Ningún repositorio seleccionado"] {
            XCTAssertTrue(element(containing: text).waitForExistence(timeout: 5), "Missing Spanish text: \(text)")
        }
        for english in ["Branch", "Changes", "No Repository Selected", "Last Commit", "Ahead/Behind", "Clean"] {
            let match = app.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@ OR value == %@ OR title == %@", english, english, english)
            )
            XCTAssertFalse(match.firstMatch.exists, "English text in the Spanish UI: \(english)")
        }
    }

    func testSettingsAreInSpanish() {
        app.typeKey(",", modifierFlags: .command)
        let account = app.toolbars.buttons["Cuenta"]
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        account.click()
        XCTAssertTrue(element(containing: "Iniciar sesión con GitHub").waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Avisarme cuando").exists)
    }
}
