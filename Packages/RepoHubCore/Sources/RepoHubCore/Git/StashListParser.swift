import Foundation

/// Parses `git stash list` output printed with ``StashListParser/format``.
public enum StashListParser {
    /// The `stash list --format` string whose output this parser reads:
    /// selector (`stash@{0}`), date, and message, separated by 0x1F.
    public static let format = "%gd%x1f%cI%x1f%gs"

    /// Parses the stash list.
    ///
    /// - Returns: Entries newest first, as git lists them.
    /// - Throws: ``GitError/unexpectedOutput(_:)`` if a line is malformed.
    public static func parse(_ output: String) throws -> [StashEntry] {
        try output.split(separator: "\n", omittingEmptySubsequences: true).map { line in
            let fields = line.split(separator: "\u{1F}", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3,
                fields[0].hasPrefix("stash@{"), fields[0].hasSuffix("}"),
                let index = Int(fields[0].dropFirst("stash@{".count).dropLast())
            else {
                throw GitError.unexpectedOutput("Malformed stash entry: \(line)")
            }
            guard let date = try? Date(String(fields[1]), strategy: .iso8601) else {
                throw GitError.unexpectedOutput("Invalid stash date: \(fields[1])")
            }
            return StashEntry(index: index, message: String(fields[2]), date: date)
        }
    }
}
