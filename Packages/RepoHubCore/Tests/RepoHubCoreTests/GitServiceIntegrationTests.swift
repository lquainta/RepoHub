import Foundation
import Testing

@testable import RepoHubCore

@Suite("GitService against real repositories", .tags(.integration))
struct GitServiceIntegrationTests {
    private let service = GitService(runner: TemporaryRepository.isolatedRunner)

    @Test("Fresh repository is unborn with untracked files")
    func freshRepository() async throws {
        let repo = try await TemporaryRepository.make()
        defer { repo.remove() }
        try repo.write("notes.txt", "hi")

        let status = try await service.status(of: repo.url)
        #expect(status.head == .unborn(branch: "main"))
        #expect(status.changes.untracked == 1)
        #expect(status.lastCommit == nil)
    }

    @Test("Committed repository reports branch, last commit, and changes")
    func committedRepository() async throws {
        let repo = try await TemporaryRepository.make()
        defer { repo.remove() }
        try await repo.commit("Initial commit", file: "a.txt")
        #expect(try await service.status(of: repo.url).isClean)

        try repo.write("a.txt", "modified")
        try repo.write("b.txt", "new")
        let status = try await service.status(of: repo.url)
        #expect(status.head == .branch("main"))
        #expect(status.lastCommit?.subject == "Initial commit")
        #expect(status.lastCommit?.author == "Test User")
        #expect(status.changes == FileChangeCounts(staged: 0, unstaged: 1, untracked: 1, conflicted: 0))
    }

    @Test("Ahead and behind are measured against the upstream after fetch")
    func aheadBehind() async throws {
        let origin = try await TemporaryRepository.make(bare: true)
        let local = try await TemporaryRepository.make()
        defer {
            origin.remove()
            local.remove()
        }
        try await local.commit("Initial commit")
        try await local.git(["remote", "add", "origin", origin.url.path])
        try await local.git(["push", "-q", "-u", "origin", "main"])

        let other = try await TemporaryRepository.clone(origin)
        defer { other.remove() }
        try await other.commit("Remote change", file: "remote.txt")
        try await other.git(["push", "-q", "origin", "main"])

        try await local.commit("Local one", file: "one.txt")
        try await local.commit("Local two", file: "two.txt")
        try await local.git(["fetch", "-q", "origin"])

        let status = try await service.status(of: local.url)
        #expect(status.upstream == "origin/main")
        #expect(status.ahead == 2)
        #expect(status.behind == 1)
    }

    @Test("Directory that is not a repository throws notARepository")
    func notARepository() async throws {
        let directory = try TemporaryRepository.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        await #expect(throws: GitError.notARepository(path: directory.path)) {
            try await service.status(of: directory)
        }
    }

    @Test("Missing directory throws directoryNotFound")
    func missingDirectory() async {
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")
        await #expect(throws: GitError.directoryNotFound(path: missing.path)) {
            try await service.status(of: missing)
        }
    }
}
