import Foundation
import RepoHubCore
import Testing

@testable import RepoHub

@Suite("StatusText")
struct StatusTextTests {
    @Test("Changes describe every kind of change, or Clean")
    func changes() {
        #expect(StatusText.changes(FileChangeCounts()) == "Clean")
        #expect(StatusText.changes(FileChangeCounts(unstaged: 1)) == "1 modified")
        #expect(
            StatusText.changes(FileChangeCounts(staged: 2, unstaged: 1, untracked: 3, conflicted: 1))
                == "1 conflicted, 2 staged, 1 modified, 3 untracked"
        )
    }

    @Test("Sync describes ahead and behind relative to the upstream")
    func sync() {
        #expect(StatusText.sync(RepoStatus(head: .branch("main"))) == "No upstream")
        #expect(StatusText.sync(RepoStatus(head: .branch("main"), upstream: "origin/main")) == "Up to date")
        #expect(StatusText.sync(RepoStatus(head: .branch("main"), upstream: "o/m", ahead: 2)) == "2 ahead")
        #expect(StatusText.sync(RepoStatus(head: .branch("main"), upstream: "o/m", behind: 1)) == "1 behind")
        #expect(
            StatusText.sync(RepoStatus(head: .branch("main"), upstream: "o/m", ahead: 2, behind: 1))
                == "2 ahead, 1 behind"
        )
    }

    @Test("Branch describes detached and unborn heads")
    func branch() {
        #expect(StatusText.branch(.branch("main")) == "main")
        #expect(StatusText.branch(.detached(commit: "1a2b3c4d5e6f")) == "Detached at 1a2b3c4")
        #expect(StatusText.branch(.unborn(branch: "main")) == "main (no commits)")
    }

    @Test("Git errors become short explanations")
    func errorMessages() {
        #expect(StatusText.message(for: .notARepository(path: "/x")) == "This folder isn't a git repository.")
        #expect(
            StatusText.message(for: .commandFailed(command: "git", exitCode: 128, stderr: "fatal: bad")) == "fatal: bad"
        )
    }
}
