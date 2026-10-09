import Foundation

/// Environment variables used only by UI tests.
///
/// Environment variables are used instead of launch arguments because AppKit
/// parses arguments as `-Key value` pairs and treats leftovers as files to
/// open, in which case it skips creating the app's initial window.
///
/// - `REPOHUB_UI_TEST_IN_MEMORY_STORE=1`: use an empty in-memory store instead of the user's data.
/// - `REPOHUB_UI_TEST_FIXTURE_REPOSITORIES=<paths>`: create a temporary folder containing the
///   comma-separated relative directories (for example `alpha/.git,web/node_modules/x/.git`)
///   and scan it at launch. The app creates the fixture itself because the UI test
///   runner is sandboxed and the app may not read files inside the runner's container.
enum UITestSupport {
    static let inMemoryStoreKey = "REPOHUB_UI_TEST_IN_MEMORY_STORE"
    static let fixtureRepositoriesKey = "REPOHUB_UI_TEST_FIXTURE_REPOSITORIES"

    static func usesInMemoryStore(_ environment: [String: String]) -> Bool {
        environment[inMemoryStoreKey] == "1"
    }

    /// Creates the fixture folder, if requested, and returns it.
    static func makeFixtureFolder(_ environment: [String: String]) throws -> URL? {
        guard let paths = environment[fixtureRepositoriesKey], !paths.isEmpty else {
            return nil
        }
        let root = FileManager.default.temporaryDirectory
            .appending(path: "repohub-ui-fixture-\(UUID().uuidString)", directoryHint: .isDirectory)
        for path in paths.split(separator: ",") {
            try FileManager.default.createDirectory(
                at: root.appending(path: String(path), directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
        }
        return root
    }
}
