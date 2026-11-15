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

    @Test("Commit dates come from git log --all since the given time")
    func commitDates() async throws {
        let runner = FakeGitRunner(["log": .success("1800000100\n1800000000\n")])
        let since = Date(timeIntervalSince1970: 1_799_000_000)

        let dates = try await GitService(runner: runner).commitDates(of: repo, since: since)

        #expect(dates == [Date(timeIntervalSince1970: 1_800_000_100), Date(timeIntervalSince1970: 1_800_000_000)])
        #expect(runner.invokedSubcommands == ["log"])
        let malformed = FakeGitRunner(["log": .success("yesterday\n")])
        await #expect(throws: GitError.unexpectedOutput("yesterday")) {
            try await GitService(runner: malformed).commitDates(of: repo, since: since)
        }
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

    @Test("Details ask for the 20 most recent commits unless told otherwise")
    func detailsDefaultLimit() async throws {
        let runner = RecordingRunner(output: ["status": try Fixture.gitOutput("clean")])
        _ = try await GitService(runner: runner).details(of: repo)
        #expect(runner.calls.contains { $0.contains("log") && $0.contains("-20") })
    }

    /// One `for-each-ref` line for a local branch.
    private func ref(_ name: String, upstream: String = "", current: Bool = false) -> String {
        ["refs/heads/\(name)", upstream, "", "abc", "2026-10-01T09:30:00Z", current ? "*" : " "]
            .joined(separator: "\u{1F}")
    }

    @Test("Without origin/HEAD the default branch is main or master, else the current branch, else main")
    func defaultBranchFallbacks() async throws {
        func report(_ refs: [String]) async throws -> StaleBranchReport {
            let runner = FakeGitRunner(["for-each-ref": .success(refs.joined(separator: "\n"))])
            return try await GitService(runner: runner).staleBranches(of: repo, inactiveAfterDays: nil)
        }
        #expect(try await report([ref("master"), ref("topic", current: true)]).defaultBranch == "master")
        #expect(try await report([ref("trunk", current: true), ref("topic")]).defaultBranch == "trunk")
        let detached = try await report([])
        #expect(detached.defaultBranch == "main")
        #expect(detached.currentBranch == nil)
        #expect(detached.candidates.isEmpty)
    }

    @Test("A branch whose remote delete fails is still deleted locally, with the error reported")
    func remoteDeleteFails() async throws {
        let failure = GitError.commandFailed(command: "git push", exitCode: 1, stderr: "remote rejected")
        let runner = FakeGitRunner([
            "for-each-ref": .success(
                [ref("main", current: true), ref("old", upstream: "origin/old")].joined(separator: "\n")
            ),
            "remote": .success("origin\thttps://example.com/o/r.git (fetch)\n"),
            "branch": .success(""),
            "push": .failure(failure),
        ])
        let service = GitService(runner: runner)
        let old = Branch(name: "old", upstream: "origin/old", commit: "abc", lastCommitDate: .distantPast)
        let results = try await service.deleteBranches([old], in: repo, force: false, deleteRemote: true)
        #expect(results == [BranchDeletionResult(name: "old", error: failure, deletedRemote: false)])
        #expect(runner.invokedSubcommands.contains("branch"))
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
    private let output: [String: String]
    var calls: [[String]] { lock.withLock { recorded } }

    /// - Parameter output: What each subcommand prints; others print nothing.
    init(output: [String: String] = [:]) {
        self.output = output
    }

    func run(_ arguments: [String], in directory: URL) async throws -> String {
        lock.withLock { recorded.append(arguments) }
        return output[arguments.first { !$0.hasPrefix("-") } ?? ""] ?? ""
    }
}
