import Foundation

/// Loads recorded git output from `Fixtures/git-output`.
/// Regenerate with `Fixtures/generate-fixtures.sh`.
enum Fixture {
    struct NotFound: Error {
        let name: String
    }

    static func gitOutput(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "git-output") else {
            throw NotFound(name: name)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
