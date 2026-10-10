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

    @Test("Details match git for branches, commits, remotes, and stashes")
    func details() async throws {
        let origin = try await TemporaryRepository.make(bare: true)
        let local = try await TemporaryRepository.make()
        defer {
            origin.remove()
            local.remove()
        }
        try await local.commit("First", file: "a.txt")
        try await local.git(["remote", "add", "origin", origin.url.path])
        try await local.git(["push", "-q", "-u", "origin", "main"])
        try await local.git(["switch", "-q", "-c", "topic"])
        try await local.commit("Second", file: "b.txt")
        try await local.git(["switch", "-q", "main"])
        try local.write("a.txt", "stash me")
        try await local.git(["stash", "push", "-q", "-m", "Saved work"])
        try local.write("a.txt", "edited")
        try local.write("new.txt", "new")

        let details = try await service.details(of: local.url)

        #expect(details.branches.map(\.name) == ["main", "topic", "origin/main"])
        #expect(details.branches.first { $0.name == "main" }?.isCurrent == true)
        #expect(details.branches.first { $0.name == "main" }?.upstream == "origin/main")
        #expect(details.recentCommits.map(\.subject) == ["First"])
        #expect(details.remotes == [Remote(name: "origin", fetchURL: origin.url.path)])
        #expect(details.stashes.map(\.message) == ["On main: Saved work"])
        #expect(
            details.files == [
                FileChange(path: "a.txt", area: .unstaged, kind: .modified),
                FileChange(path: "new.txt", area: .untracked, kind: .untracked),
            ]
        )
    }

    @Test("Fetch updates behind counts, pull fast-forwards, and diverged pulls fail without merging")
    func fetchAndPull() async throws {
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
        try await other.commit("Remote one", file: "r1.txt")
        try await other.git(["push", "-q", "origin", "main"])

        #expect(try await service.status(of: local.url).behind == 0)
        try await service.fetch(local.url)
        #expect(try await service.status(of: local.url).behind == 1)

        try await service.pull(local.url)
        let pulled = try await service.status(of: local.url)
        #expect(pulled.behind == 0 && pulled.lastCommit?.subject == "Remote one")

        // Diverge: a local and a remote commit. Pull must refuse rather than merge.
        try await other.commit("Remote two", file: "r2.txt")
        try await other.git(["push", "-q", "origin", "main"])
        try await local.commit("Local", file: "l.txt")
        try await service.fetch(local.url)
        await #expect(throws: GitError.self) { try await service.pull(local.url) }
        let after = try await service.details(of: local.url)
        #expect(after.recentCommits.first?.subject == "Local")
        #expect(after.status.ahead == 1 && after.status.behind == 1)
    }

    @Test("Scanning real repositories finds working trees, linked worktrees, and not submodules or bare repositories")
    func scanRealRepositories() async throws {
        let root = try TemporaryRepository.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let git = TemporaryRepository.isolatedRunner
        func run(_ arguments: [String], in directory: URL) async throws {
            _ = try await git.run(arguments, in: directory)
        }

        // projects/app: a normal repository with a commit and a submodule.
        let library = TemporaryRepository(url: root.appending(path: "libraries/lib"), runner: git)
        try FileManager.default.createDirectory(at: library.url, withIntermediateDirectories: true)
        try await run(["init", "-q", "-b", "main"], in: library.url)
        try await library.commit("Library")

        let app = TemporaryRepository(url: root.appending(path: "projects/app"), runner: git)
        try FileManager.default.createDirectory(at: app.url, withIntermediateDirectories: true)
        try await run(["init", "-q", "-b", "main"], in: app.url)
        try await app.commit("App")
        try await run(
            ["-c", "protocol.file.allow=always", "submodule", "add", "-q", library.url.path, "Vendor/lib"],
            in: app.url
        )
        try await run(["commit", "-q", "-m", "Add submodule"], in: app.url)

        // projects/app-feature: a linked worktree (its .git is a file).
        try await run(
            ["worktree", "add", "-q", "-b", "feature", root.appending(path: "projects/app-feature").path],
            in: app.url
        )

        // archive/backup.git: a bare repository, which has no working tree to show.
        let bare = root.appending(path: "archive/backup.git")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        try await run(["init", "-q", "--bare"], in: bare)

        let found = try await RepositoryScanner().scan(root, maxDepth: 4)
        let relative = found.map {
            String($0.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
        }
        #expect(relative == ["libraries/lib", "projects/app", "projects/app-feature"])

        // Every scanned repository's status can be read.
        var branches: [String] = []
        for url in found {
            let status = try await service.status(of: url)
            branches.append(status.head.branchName ?? "")
        }
        #expect(branches == ["main", "main", "feature"])
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
