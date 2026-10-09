import Foundation

/// Launch arguments used only by UI tests.
///
/// - `-UITestInMemoryStore`: use an empty in-memory store instead of the user's data.
/// - `-UITestFixtureRepositories <paths>`: create a temporary folder containing the
///   comma-separated relative directories (for example `alpha/.git,web/node_modules/x/.git`)
///   and scan it at launch. The app creates the fixture itself because the UI test
///   runner is sandboxed and the app may not read files inside the runner's container.
enum UITestSupport {
    static func usesInMemoryStore(_ arguments: [String]) -> Bool {
        arguments.contains("-UITestInMemoryStore")
    }

    /// Creates the fixture folder, if requested, and returns it.
    static func makeFixtureFolder(_ arguments: [String]) throws -> URL? {
        guard let index = arguments.firstIndex(of: "-UITestFixtureRepositories"),
            arguments.indices.contains(index + 1)
        else {
            return nil
        }
        let root = FileManager.default.temporaryDirectory
            .appending(path: "repohub-ui-fixture-\(UUID().uuidString)", directoryHint: .isDirectory)
        for path in arguments[index + 1].split(separator: ",") {
            try FileManager.default.createDirectory(
                at: root.appending(path: String(path), directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
        }
        return root
    }
}
