import Foundation
import Testing

@testable import RepoHubCore

@Suite("CommitSummaryParser")
struct CommitSummaryParserTests {
    @Test("Parses hash, author, ISO 8601 date, and subject")
    func parsesRecordedOutput() throws {
        let commit = try CommitSummaryParser.parse(Fixture.gitOutput("log-last-commit"))
        #expect(commit.hash == "059a39eb8d43a22dd3763fdf73e0f99529ec3adf")
        #expect(commit.author == "Ada Lovelace")
        #expect(commit.subject == "Initial commit")
        // 2026-10-01T09:30:00-06:00
        #expect(commit.date == Date(timeIntervalSince1970: 1_790_868_600))
    }

    @Test("Subjects may contain spaces, colons, and unicode")
    func subjectWithPunctuation() throws {
        let line = "abc\u{1F}Zoë\u{1F}2026-01-02T03:04:05Z\u{1F}feat(core): handle naïve dates: done\n"
        let commit = try CommitSummaryParser.parse(line)
        #expect(commit.author == "Zoë")
        #expect(commit.subject == "feat(core): handle naïve dates: done")
    }

    @Test(
        "Malformed lines throw",
        arguments: [
            "",
            "abc\u{1F}author\u{1F}2026-01-02T03:04:05Z",  // missing subject
            "abc\u{1F}author\u{1F}not-a-date\u{1F}subject",
            "\u{1F}author\u{1F}2026-01-02T03:04:05Z\u{1F}subject",  // empty hash
        ]
    )
    func malformed(line: String) {
        #expect {
            try CommitSummaryParser.parse(line)
        } throws: { error in
            guard case GitError.unexpectedOutput = error else { return false }
            return true
        }
    }
}
