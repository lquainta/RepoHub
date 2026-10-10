import Foundation

/// Parses a commit summary printed with ``CommitSummaryParser/format``.
public enum CommitSummaryParser {
    /// The `git log --format` string whose output this parser reads.
    ///
    /// Fields are separated by the ASCII unit separator (0x1F), which cannot
    /// appear in author names or subjects.
    public static let format = "%H%x1f%an%x1f%aI%x1f%s"

    /// Parses one commit per line, as printed by `git log --format=<format>`.
    ///
    /// - Throws: ``GitError/unexpectedOutput(_:)`` if any line is malformed.
    public static func parseList(_ output: String) throws -> [CommitSummary] {
        try output.split(separator: "\n", omittingEmptySubsequences: true).map { try parse(String($0)) }
    }

    /// Parses a single commit line.
    ///
    /// - Throws: ``GitError/unexpectedOutput(_:)`` if a field is missing or the date is invalid.
    public static func parse(_ output: String) throws -> CommitSummary {
        let line = output.trimmingCharacters(in: .newlines)
        let fields = line.split(separator: "\u{1F}", omittingEmptySubsequences: false)
        guard fields.count == 4, !fields[0].isEmpty else {
            throw GitError.unexpectedOutput("Expected 4 commit fields, got \(fields.count): \(line)")
        }
        guard let date = try? Date(String(fields[2]), strategy: .iso8601) else {
            throw GitError.unexpectedOutput("Invalid commit date: \(fields[2])")
        }
        return CommitSummary(
            hash: String(fields[0]),
            author: String(fields[1]),
            date: date,
            subject: String(fields[3])
        )
    }
}
