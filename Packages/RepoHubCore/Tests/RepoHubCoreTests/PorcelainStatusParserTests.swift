import Testing

@testable import RepoHubCore

@Suite("PorcelainStatusParser")
struct PorcelainStatusParserTests {
    @Test("Clean branch tracking an upstream")
    func clean() throws {
        let status = try PorcelainStatusParser.parse(Fixture.gitOutput("clean"))
        #expect(status.head == .branch("main"))
        #expect(status.upstream == "origin/main")
        #expect(status.ahead == 0 && status.behind == 0)
        #expect(status.isClean)
        #expect(status.stashCount == 0)
        #expect(status.lastCommit == nil)
    }

    @Test("Ahead and behind counts come from branch.ab")
    func aheadBehind() throws {
        let status = try PorcelainStatusParser.parse(Fixture.gitOutput("ahead-behind"))
        #expect(status.ahead == 2)
        #expect(status.behind == 1)
    }

    @Test("Staged, unstaged, renamed, and untracked paths are counted")
    func dirty() throws {
        // Fixture: M. added A. both MM keep .M renamed R. + 2 untracked (one with spaces, one unicode)
        let status = try PorcelainStatusParser.parse(Fixture.gitOutput("dirty"))
        #expect(status.changes == FileChangeCounts(staged: 4, unstaged: 2, untracked: 2, conflicted: 0))
        #expect(!status.isClean)
    }

    @Test("Changed files are listed per area, keeping spaces, unicode, and rename origins")
    func dirtyFiles() throws {
        let (status, files) = try PorcelainStatusParser.parseWithFiles(Fixture.gitOutput("dirty"))
        #expect(status.changes == FileChangeCounts(staged: 4, unstaged: 2, untracked: 2, conflicted: 0))
        #expect(
            files == [
                FileChange(path: "README.md", area: .staged, kind: .modified),
                FileChange(path: "added.txt", area: .staged, kind: .added),
                FileChange(path: "both.txt", area: .staged, kind: .modified),
                FileChange(path: "both.txt", area: .unstaged, kind: .modified),
                FileChange(path: "keep.txt", area: .unstaged, kind: .modified),
                FileChange(path: "new name é.txt", originalPath: "old-name.txt", area: .staged, kind: .renamed),
                FileChange(path: "untracked file.txt", area: .untracked, kind: .untracked),
                FileChange(path: "ünïcode.txt", area: .untracked, kind: .untracked),
            ]
        )
    }

    @Test("Conflicted paths are listed as unmerged")
    func conflictedFiles() throws {
        let (_, files) = try PorcelainStatusParser.parseWithFiles(Fixture.gitOutput("conflicted"))
        #expect(files == [FileChange(path: "c.txt", area: .conflicted, kind: .unmerged)])
    }

    @Test("Unknown change codes are rejected")
    func unknownChangeCode() {
        let output = "# branch.oid abc\0# branch.head main\01 X. N... 100644 100644 100644 a b f.txt\0"
        #expect(throws: GitError.self) { try PorcelainStatusParser.parseWithFiles(output) }
    }

    @Test("Unmerged paths are counted as conflicts and branch without upstream has no ahead/behind")
    func conflicted() throws {
        let status = try PorcelainStatusParser.parse(Fixture.gitOutput("conflicted"))
        #expect(status.changes.conflicted == 1)
        #expect(status.upstream == nil)
    }

    @Test("Stash count comes from the stash header")
    func stash() throws {
        let status = try PorcelainStatusParser.parse(Fixture.gitOutput("stash"))
        #expect(status.stashCount == 2)
        #expect(status.isClean)
    }

    @Test("Detached HEAD reports the commit and has no branch name")
    func detached() throws {
        let status = try PorcelainStatusParser.parse(Fixture.gitOutput("detached"))
        #expect(status.head == .detached(commit: "059a39eb8d43a22dd3763fdf73e0f99529ec3adf"))
        #expect(status.head.branchName == nil)
    }

    @Test("Local-only branch has no upstream")
    func noUpstream() throws {
        let status = try PorcelainStatusParser.parse(Fixture.gitOutput("no-upstream"))
        #expect(status.head == .branch("feature/local"))
        #expect(status.upstream == nil)
    }

    @Test("Repository without commits is unborn")
    func unborn() throws {
        let status = try PorcelainStatusParser.parse(Fixture.gitOutput("unborn"))
        #expect(status.head == .unborn(branch: "main"))
        #expect(status.head.branchName == "main")
        #expect(status.changes.untracked == 1)
    }

    @Test(
        "Malformed output throws unexpectedOutput",
        arguments: [
            "",  // no headers
            "# branch.oid abc\0",  // missing branch.head
            "# branch.oid abc\0# branch.head main\0# branch.ab 3 4\0",
            "# branch.oid abc\0# branch.head main\0# stash many\0",
            "# branch.oid abc\0# branch.head main\0Z unknown entry\0",
            "# branch.oid abc\0# branch.head main\01 MMM N... 1 2 3 a b path\0",
            "# branch.oid abc\0# branch.head main\02 R. N... 1 2 3 a b R100 new\0",  // rename without original path
        ]
    )
    func malformed(output: String) {
        #expect {
            try PorcelainStatusParser.parse(output)
        } throws: { error in
            guard case GitError.unexpectedOutput = error else { return false }
            return true
        }
    }

    @Test("Unknown headers from newer git versions are ignored")
    func unknownHeader() throws {
        let status = try PorcelainStatusParser.parse("# branch.oid abc\0# branch.head main\0# future.header x\0")
        #expect(status.head == .branch("main"))
    }
}
