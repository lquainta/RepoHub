import Foundation
import RepoHubCore
import Testing

@testable import RepoHub

@MainActor
@Suite("RepositoryDetailModel")
struct RepositoryDetailModelTests {
    @Test("Showing a repository loads its details")
    func showLoads() async {
        let model = RepositoryDetailModel(git: FakeGit())
        #expect(model.state == .empty)

        await model.show("/repos/a")

        guard case .loaded(let details) = model.state else {
            Issue.record("Expected loaded details, got \(model.state)")
            return
        }
        #expect(details.remotes.first?.fetchURL == "/repos/a")
        #expect(model.path == "/repos/a")
    }

    @Test("A git failure is shown as a message")
    func showFailure() async {
        let model = RepositoryDetailModel(
            git: FakeGit(["/repos/gone": .failure(.directoryNotFound(path: "/repos/gone"))])
        )
        await model.show("/repos/gone")
        #expect(model.state == .failed(StatusText.message(for: .directoryNotFound(path: "/repos/gone"))))
    }

    @Test("Showing nothing clears the pane")
    func showNil() async {
        let model = RepositoryDetailModel(git: FakeGit())
        await model.show("/repos/a")
        await model.show(nil)
        #expect(model.state == .empty)
        #expect(model.path == nil)
    }

    @Test("A slow load for a previous selection doesn't replace the current one")
    func staleLoadIgnored() async {
        let git = FakeGit()
        await git.setDetailDelay(.milliseconds(300), for: "/repos/slow")
        let model = RepositoryDetailModel(git: git)

        let slow = Task { await model.show("/repos/slow") }
        try? await Task.sleep(for: .milliseconds(50))
        await model.show("/repos/fast")
        await slow.value

        #expect(model.path == "/repos/fast")
        guard case .loaded(let details) = model.state else {
            Issue.record("Expected loaded details, got \(model.state)")
            return
        }
        #expect(details.remotes.first?.fetchURL == "/repos/fast")
    }

    @Test("Reload picks up changes")
    func reload() async {
        let git = FakeGit()
        let model = RepositoryDetailModel(git: git)
        await model.show("/repos/a")

        let dirty = RepoStatus(head: .branch("main"), changes: FileChangeCounts(untracked: 1))
        await git.setResult(.success(dirty), for: "/repos/a")
        await model.reload()

        guard case .loaded(let details) = model.state else {
            Issue.record("Expected loaded details")
            return
        }
        #expect(details.status == dirty)
    }
}
