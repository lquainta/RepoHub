import Foundation
import Testing

@testable import RepoHubCore

@Suite("BranchListParser")
struct BranchListParserTests {
    @Test("Parses local and remote branches with tracking info, skipping origin/HEAD")
    func recorded() throws {
        let branches = try BranchListParser.parse(Fixture.gitOutput("for-each-ref"))
        let date = try Date("2026-10-01T09:30:00-06:00", strategy: .iso8601)

        #expect(
            branches.map(\.name) == [
                "feature/ahead", "feature/gone", "local-only", "main", "origin/feature/ahead", "origin/main",
            ]
        )
        #expect(
            branches[0]
                == Branch(
                    name: "feature/ahead",
                    upstream: "origin/feature/ahead",
                    ahead: 1,
                    commit: "b672986897c7d79c149fdfc42819bdacf829e721",
                    lastCommitDate: date
                )
        )
        #expect(branches[1].isUpstreamGone)
        #expect(branches[1].upstream == "origin/feature/gone")
        #expect(branches[2].upstream == nil && !branches[2].isUpstreamGone)
        #expect(branches[3].isCurrent && branches[3].behind == 1)
        #expect(branches.filter(\.isCurrent).count == 1)
        let remote = branches[4...].allSatisfy { $0.isRemote }
        #expect(remote)
    }

    @Test("Ahead and behind together are both parsed")
    func aheadAndBehind() throws {
        let line = "refs/heads/x\u{1F}origin/x\u{1F}ahead 2, behind 3\u{1F}abc\u{1F}2026-10-01T09:30:00Z\u{1F} "
        let branch = try #require(try BranchListParser.parse(line).first)
        #expect(branch.ahead == 2 && branch.behind == 3)
    }

    @Test(
        "Malformed lines are rejected",
        arguments: [
            "refs/heads/x\u{1F}\u{1F}\u{1F}abc\u{1F}2026-10-01T09:30:00Z",
            "refs/tags/v1\u{1F}\u{1F}\u{1F}abc\u{1F}2026-10-01T09:30:00Z\u{1F} ",
            "refs/heads/x\u{1F}\u{1F}\u{1F}abc\u{1F}yesterday\u{1F} ",
            "refs/heads/x\u{1F}o/x\u{1F}sideways 2\u{1F}abc\u{1F}2026-10-01T09:30:00Z\u{1F} ",
        ]
    )
    func malformed(line: String) {
        #expect(throws: GitError.self) { try BranchListParser.parse(line) }
    }

    @Test("Empty output means no branches")
    func empty() throws {
        #expect(try BranchListParser.parse("").isEmpty)
    }
}

@Suite("RemoteListParser")
struct RemoteListParserTests {
    @Test("Parses fetch URLs and keeps a push URL only when it differs")
    func recorded() throws {
        let remotes = try RemoteListParser.parse(Fixture.gitOutput("remote-v"))
        #expect(
            remotes == [
                Remote(name: "origin", fetchURL: "/work/origin.git", pushURL: "git@example.com:ada/repo.git"),
                Remote(name: "upstream", fetchURL: "https://example.com/upstream/repo.git"),
            ]
        )
    }

    @Test("Malformed lines are rejected")
    func malformed() {
        #expect(throws: GitError.self) { try RemoteListParser.parse("origin https://x (fetch)") }
        #expect(throws: GitError.self) { try RemoteListParser.parse("origin\thttps://x") }
    }
}

@Suite("StashListParser")
struct StashListParserTests {
    @Test("Parses stash entries newest first")
    func recorded() throws {
        let stashes = try StashListParser.parse(Fixture.gitOutput("stash-list"))
        #expect(stashes.map(\.index) == [0, 1])
        #expect(stashes.map(\.message) == ["On main: Second stash", "On main: First stash"])
    }

    @Test("Messages may contain the separator-free text git allows, including colons and braces")
    func messageWithPunctuation() throws {
        let stash = try #require(
            try StashListParser.parse("stash@{3}\u{1F}2026-10-01T09:30:00Z\u{1F}On main: fix {x}: y").first
        )
        #expect(stash.index == 3)
        #expect(stash.message == "On main: fix {x}: y")
    }

    @Test(
        "Malformed entries are rejected",
        arguments: ["stash@{x}\u{1F}2026-10-01T09:30:00Z\u{1F}m", "stash@{0}\u{1F}bad\u{1F}m", "nope"]
    )
    func malformed(line: String) {
        #expect(throws: GitError.self) { try StashListParser.parse(line) }
    }
}

@Suite("CommitSummaryParser list")
struct CommitListParserTests {
    @Test("Parses one commit per line, newest first")
    func recorded() throws {
        let commits = try CommitSummaryParser.parseList(Fixture.gitOutput("log-recent"))
        #expect(commits.map(\.subject) == ["Ahead of upstream", "Initial commit"])
    }
}
