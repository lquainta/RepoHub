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

extension UITestSupport {
    /// `1`: create real git repositories (`clean`, `dirty`, and `stale`, which
    /// has a merged `old-feature` branch) and scan them at launch.
    static let gitFixturesKey = "REPOHUB_UI_TEST_GIT_FIXTURES"
    /// `1`: use ``UITestBackend`` instead of the real backend, and don't open a browser.
    static let stubBackendKey = "REPOHUB_UI_TEST_STUB_BACKEND"

    static func usesStubBackend(_ environment: [String: String]) -> Bool {
        environment[stubBackendKey] == "1"
    }

    /// Creates the git fixtures, if requested, and returns their folder.
    static func makeGitFixtures(_ environment: [String: String]) throws -> URL? {
        guard environment[gitFixturesKey] == "1" else {
            return nil
        }
        let root = FileManager.default.temporaryDirectory
            .appending(path: "repohub-ui-git-\(UUID().uuidString)", directoryHint: .isDirectory)
        for name in ["clean", "dirty", "stale"] {
            let repository = root.appending(path: name, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
            try git(["init", "--quiet", "--initial-branch=main"], in: repository)
            try Data("# \(name)\n".utf8).write(to: repository.appending(path: "README.md"))
            try git(["add", "README.md"], in: repository)
            try git(["commit", "--quiet", "-m", "Initial commit"], in: repository)
        }
        try Data("draft\n".utf8).write(to: root.appending(path: "dirty/notes.txt"))
        try git(["branch", "old-feature"], in: root.appending(path: "stale", directoryHint: .isDirectory))
        return root
    }

    /// Runs git with a fixed identity and none of the user's configuration.
    private static func git(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = [
            "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "RepoHub UI Test", "GIT_AUTHOR_EMAIL": "ui-test@example.com",
            "GIT_COMMITTER_NAME": "RepoHub UI Test", "GIT_COMMITTER_EMAIL": "ui-test@example.com",
            "PATH": "/usr/bin:/bin",
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.executableLoad, userInfo: [NSLocalizedDescriptionKey: "git \(arguments) failed"])
        }
    }
}
