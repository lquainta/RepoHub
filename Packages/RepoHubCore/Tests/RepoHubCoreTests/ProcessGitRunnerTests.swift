import Foundation
import Testing

@testable import RepoHubCore

@Suite("ProcessGitRunner", .tags(.integration))
struct ProcessGitRunnerTests {
    /// `sleep` stands in for a hung git command.
    private let sleep = URL(fileURLWithPath: "/bin/sleep")

    @Test("Missing executable throws gitNotFound")
    func missingExecutable() async {
        let runner = ProcessGitRunner(executableURL: URL(fileURLWithPath: "/nonexistent/git"))
        await #expect(throws: GitError.gitNotFound(path: "/nonexistent/git")) {
            try await runner.run(["status"], in: FileManager.default.temporaryDirectory)
        }
    }

    @Test("Commands exceeding the timeout are terminated")
    func timeout() async {
        let runner = ProcessGitRunner(executableURL: sleep, timeout: .milliseconds(200))
        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            await #expect(throws: GitError.timedOut(command: "sleep 10")) {
                try await runner.run(["10"], in: FileManager.default.temporaryDirectory)
            }
        }
        #expect(elapsed < .seconds(5))
    }

    @Test("Cancelling the task terminates the process")
    func cancellation() async {
        let runner = ProcessGitRunner(executableURL: sleep, timeout: .seconds(30))
        let task = Task {
            try await runner.run(["10"], in: FileManager.default.temporaryDirectory)
        }
        try? await Task.sleep(for: .milliseconds(200))
        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            task.cancel()
            await #expect(throws: CancellationError.self) {
                try await task.value
            }
        }
        #expect(elapsed < .seconds(5))
    }

    @Test("A fast command finishes while a slow one is still running")
    func concurrentCommandsDoNotBlockEachOther() async throws {
        // Each command's output and exit must be independent of other running children.
        let slowRunner = ProcessGitRunner(executableURL: sleep, timeout: .seconds(30))
        let slow = Task {
            try await slowRunner.run(["10"], in: FileManager.default.temporaryDirectory)
        }
        defer { slow.cancel() }
        try await Task.sleep(for: .milliseconds(100))

        let repo = try await TemporaryRepository.make()
        defer { repo.remove() }
        let clock = ContinuousClock()
        let elapsed = try await clock.measure {
            _ = try await GitService(runner: TemporaryRepository.isolatedRunner).status(of: repo.url)
        }
        #expect(elapsed < .seconds(5))
    }

    @Test("Many long-running commands do not starve other commands")
    func longRunningCommandsDoNotStarveThePool() async throws {
        // Regression test for #105: blocking on a capped thread pool (libdispatch
        // on Linux) made every other command wait for a free worker. Swift
        // concurrency shares that pool there, so the stall also delays this
        // test's own awaits: measure from before the slow commands start.
        let repo = try await TemporaryRepository.make()
        defer { repo.remove() }
        let slowRunner = ProcessGitRunner(executableURL: sleep, timeout: .seconds(30))
        let clock = ContinuousClock()
        let start = clock.now
        let slow = (0..<16).map { _ in
            Task { try await slowRunner.run(["10"], in: FileManager.default.temporaryDirectory) }
        }
        defer {
            for task in slow { task.cancel() }
        }
        try await Task.sleep(for: .milliseconds(200))

        _ = try await GitService(runner: TemporaryRepository.isolatedRunner).status(of: repo.url)
        #expect(clock.now - start < .seconds(3))
    }

    @Test("Non-zero exit includes stderr")
    func commandFailure() async throws {
        let repo = try await TemporaryRepository.make()
        defer { repo.remove() }
        await #expect {
            try await repo.git(["checkout", "does-not-exist"])
        } throws: { error in
            guard case GitError.commandFailed(_, let exitCode, let stderr) = error else { return false }
            return exitCode != 0 && stderr.contains("does-not-exist")
        }
    }

    @Test("Large output does not deadlock")
    func largeOutput() async throws {
        let repo = try await TemporaryRepository.make()
        defer { repo.remove() }
        for index in 0..<2_000 {
            try repo.write("untracked-file-with-a-long-name-\(index).txt", "")
        }
        let status = try await GitService(runner: TemporaryRepository.isolatedRunner).status(of: repo.url)
        #expect(status.changes.untracked == 2_000)
    }
}
