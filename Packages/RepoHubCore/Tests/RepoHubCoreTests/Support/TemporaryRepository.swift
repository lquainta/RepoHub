import Foundation

@testable import RepoHubCore

/// A git repository in a temporary directory, isolated from the developer's
/// git configuration. Call ``remove()`` when done.
struct TemporaryRepository {
    let url: URL
    let runner: ProcessGitRunner

    /// Runner with deterministic identity and no global or system config
    /// (so commit signing or hooks on the developer's machine can't interfere).
    static let isolatedRunner = ProcessGitRunner(environmentOverrides: [
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_AUTHOR_NAME": "Test User",
        "GIT_AUTHOR_EMAIL": "test@example.com",
        "GIT_COMMITTER_NAME": "Test User",
        "GIT_COMMITTER_EMAIL": "test@example.com",
    ])

    /// Creates an empty directory under the system temporary directory.
    static func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("repohub-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Initializes a repository on branch `main`.
    static func make(bare: Bool = false) async throws -> TemporaryRepository {
        let repo = TemporaryRepository(url: try makeDirectory(), runner: isolatedRunner)
        try await repo.git(bare ? ["init", "-q", "--bare", "-b", "main"] : ["init", "-q", "-b", "main"])
        return repo
    }

    /// Clones `origin` into a new temporary directory.
    static func clone(_ origin: TemporaryRepository) async throws -> TemporaryRepository {
        let url = try makeDirectory()
        _ = try await isolatedRunner.run(["clone", "-q", origin.url.path, url.path], in: url)
        return TemporaryRepository(url: url, runner: isolatedRunner)
    }

    @discardableResult
    func git(_ arguments: [String]) async throws -> String {
        try await runner.run(arguments, in: url)
    }

    func write(_ path: String, _ contents: String) throws {
        try contents.write(to: url.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }

    /// Writes `path` and commits it with `message`.
    func commit(_ message: String, file path: String = "file.txt", contents: String? = nil) async throws {
        try write(path, contents ?? UUID().uuidString)
        try await git(["add", path])
        try await git(["commit", "-q", "-m", message])
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
