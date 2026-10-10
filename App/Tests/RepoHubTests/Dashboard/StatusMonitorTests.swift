import Foundation
import RepoHubCore
import Testing

@testable import RepoHub

@MainActor
@Suite("StatusMonitor")
struct StatusMonitorTests {
    @Test("Refresh stores each repository's status or failure")
    func refreshStoresResults() async {
        let dirty = RepoStatus(head: .branch("dev"), changes: FileChangeCounts(unstaged: 2))
        let git = FakeGit([
            "/repos/a": .success(dirty),
            "/repos/b": .failure(.notARepository(path: "/repos/b")),
        ])
        let monitor = StatusMonitor(git: git)

        await monitor.refresh(["/repos/a", "/repos/b"])

        #expect(monitor.state(for: "/repos/a") == .loaded(dirty))
        #expect(monitor.state(for: "/repos/b") == .failed(StatusText.message(for: .notARepository(path: "/repos/b"))))
        #expect(monitor.state(for: "/repos/c") == nil)
        #expect(monitor.refreshing.isEmpty)
    }

    @Test("No more than the configured number of reads run at once")
    func limitsConcurrency() async {
        let git = FakeGit(delay: .milliseconds(20))
        let monitor = StatusMonitor(git: git, maxConcurrentReads: 3)

        await monitor.refresh((0..<12).map { "/repos/\($0)" })

        #expect(await git.peakConcurrency == 3)
        #expect(await git.reads.count == 12)
        #expect(monitor.states.count == 12)
    }

    @Test("A later refresh replaces the previous status")
    func refreshReplacesStatus() async {
        let git = FakeGit()
        let monitor = StatusMonitor(git: git)
        await monitor.refresh(["/repos/a"])

        let behind = RepoStatus(head: .branch("main"), upstream: "origin/main", behind: 3)
        await git.setResult(.success(behind), for: "/repos/a")
        await monitor.refresh(["/repos/a"])

        #expect(monitor.state(for: "/repos/a") == .loaded(behind))
    }

    @Test("A refresh requested while one is running reads the repository again afterwards")
    func refreshDuringRefresh() async {
        let git = FakeGit(delay: .milliseconds(150))
        let monitor = StatusMonitor(git: git)
        let first = Task { await monitor.refresh(["/repos/a"]) }
        try? await Task.sleep(for: .milliseconds(50))

        let changed = RepoStatus(head: .branch("main"), changes: FileChangeCounts(untracked: 1))
        await git.setResult(.success(changed), for: "/repos/a")
        await monitor.refresh(["/repos/a"])
        await first.value

        #expect(monitor.state(for: "/repos/a") == .loaded(changed))
        #expect(await git.reads.count == 2)
    }

    @Test("Retain drops repositories that are no longer tracked")
    func retainDropsUntracked() async {
        let monitor = StatusMonitor(git: FakeGit())
        await monitor.refresh(["/repos/a", "/repos/b"])

        monitor.retain(only: ["/repos/b"])

        #expect(Set(monitor.states.keys) == ["/repos/b"])
    }
}
