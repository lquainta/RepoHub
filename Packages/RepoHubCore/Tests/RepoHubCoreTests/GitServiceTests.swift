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

    @Test("Details combine status, files, branches, commits, remotes, and stashes")
    func details() async throws {
        let runner = FakeGitRunner([
            "status": .success(try Fixture.gitOutput("dirty")),
            "for-each-ref": .success(try Fixture.gitOutput("for-each-ref")),
            "remote": .success(try Fixture.gitOutput("remote-v")),
            "stash": .success(try Fixture.gitOutput("stash-list")),
            "log": .success(try Fixture.gitOutput("log-recent")),
        ])
        let details = try await GitService(runner: runner).details(of: repo)
        #expect(details.files.count == 8)
        #expect(details.branches.count == 6)
        #expect(details.remotes.map(\.name) == ["origin", "upstream"])
        #expect(details.stashes.count == 2)
        #expect(details.recentCommits.count == 2)
        #expect(details.status.lastCommit == details.recentCommits.first)
        #expect(Set(runner.invokedSubcommands) == ["status", "for-each-ref", "remote", "stash", "log"])
    }

    @Test("Details skip git log for a repository with no commits")
    func detailsUnborn() async throws {
        let runner = FakeGitRunner([
            "status": .success(try Fixture.gitOutput("unborn")),
            "for-each-ref": .success(""),
            "remote": .success(""),
            "stash": .success(""),
        ])
        let details = try await GitService(runner: runner).details(of: repo)
        #expect(details.recentCommits.isEmpty)
        #expect(details.files == [FileChange(path: "file.txt", area: .untracked, kind: .untracked)])
        #expect(!runner.invokedSubcommands.contains("log"))
    }

    @Test("Fetch prunes all remotes and pull only fast-forwards")
    func fetchAndPullArguments() async throws {
        let runner = RecordingRunner()
        let service = GitService(runner: runner)
        try await service.fetch(repo)
        try await service.pull(repo)
        #expect(runner.calls == [["fetch", "--all", "--prune", "--quiet"], ["pull", "--ff-only", "--quiet"]])
    }

    @Test("Propagates runner errors")
    func propagatesErrors() async {
        let runner = FakeGitRunner(["status": .failure(.notARepository(path: "/tmp/repo"))])
        await #expect(throws: GitError.notARepository(path: "/tmp/repo")) {
            try await GitService(runner: runner).status(of: repo)
        }
    }
}

/// Records the full arguments of every command.
private final class RecordingRunner: GitCommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    var calls: [[String]] { lock.withLock { recorded } }

    func run(_ arguments: [String], in directory: URL) async throws -> String {
        lock.withLock { recorded.append(arguments) }
        return ""
    }
}
