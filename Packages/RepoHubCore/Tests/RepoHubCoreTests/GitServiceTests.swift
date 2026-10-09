import Foundation
import Testing

@testable import RepoHubCore

/// Returns canned output per git subcommand and records invocations.
private final class FakeGitRunner: GitCommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: Result<String, GitError>]
    private(set) var invokedSubcommands: [String] = []

    init(_ responses: [String: Result<String, GitError>]) {
        self.responses = responses
    }

    func run(_ arguments: [String], in directory: URL) async throws -> String {
        let subcommand = arguments.first { !$0.hasPrefix("-") } ?? ""
        let response = lock.withLock {
            invokedSubcommands.append(subcommand)
            return responses[subcommand]
        }
        guard let response else {
            throw GitError.commandFailed(command: subcommand, exitCode: 1, stderr: "unexpected")
        }
        return try response.get()
    }
}

@Suite("GitService")
struct GitServiceTests {
    private let repo = URL(fileURLWithPath: "/tmp/repo")

    @Test("Combines status and last commit")
    func combinesStatusAndLog() async throws {
        let runner = FakeGitRunner([
            "status": .success(try Fixture.gitOutput("ahead-behind")),
            "log": .success(try Fixture.gitOutput("log-last-commit")),
        ])
        let status = try await GitService(runner: runner).status(of: repo)
        #expect(status.ahead == 2)
        #expect(status.lastCommit?.subject == "Initial commit")
        #expect(runner.invokedSubcommands == ["status", "log"])
    }

    @Test("Skips git log for a repository with no commits")
    func unbornSkipsLog() async throws {
        let runner = FakeGitRunner(["status": .success(try Fixture.gitOutput("unborn"))])
        let status = try await GitService(runner: runner).status(of: repo)
        #expect(status.lastCommit == nil)
        #expect(runner.invokedSubcommands == ["status"])
    }

    @Test("Propagates runner errors")
    func propagatesErrors() async {
        let runner = FakeGitRunner(["status": .failure(.notARepository(path: "/tmp/repo"))])
        await #expect(throws: GitError.notARepository(path: "/tmp/repo")) {
            try await GitService(runner: runner).status(of: repo)
        }
    }
}
