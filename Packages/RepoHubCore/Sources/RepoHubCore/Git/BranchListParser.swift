import Foundation

/// Parses `git for-each-ref` output printed with ``BranchListParser/format``.
public enum BranchListParser {
    /// The `for-each-ref --format` string whose output this parser reads.
    ///
    /// Fields are separated by the ASCII unit separator (0x1F); one ref per line
    /// (ref names cannot contain newlines).
    public static let format = [
        "%(refname)", "%(upstream:short)", "%(upstream:track,nobracket)",
        "%(objectname)", "%(committerdate:iso-strict)", "%(HEAD)",
    ].joined(separator: "%1f")

    /// The refs to list: local branches and remote-tracking branches.
    public static let refPatterns = ["refs/heads", "refs/remotes"]

    /// Parses the listing. Remote `HEAD` symbolic refs (such as `origin/HEAD`) are skipped.
    ///
    /// - Returns: Local branches first, then remote-tracking branches, each sorted by name.
    /// - Throws: ``GitError/unexpectedOutput(_:)`` if a line is malformed.
    public static func parse(_ output: String) throws -> [Branch] {
        var branches: [Branch] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: "\u{1F}", omittingEmptySubsequences: false)
            guard fields.count == 6 else {
                throw GitError.unexpectedOutput("Expected 6 branch fields, got \(fields.count): \(line)")
            }
            let refname = fields[0]
            let isRemote: Bool
            let name: Substring
            if refname.hasPrefix("refs/heads/") {
                isRemote = false
                name = refname.dropFirst("refs/heads/".count)
            } else if refname.hasPrefix("refs/remotes/") {
                isRemote = true
                name = refname.dropFirst("refs/remotes/".count)
                if name.hasSuffix("/HEAD") {
                    continue
                }
            } else {
                throw GitError.unexpectedOutput("Unexpected ref: \(refname)")
            }
            guard let date = try? Date(String(fields[4]), strategy: .iso8601) else {
                throw GitError.unexpectedOutput("Invalid branch date: \(fields[4])")
            }
            let track = try parseTrack(fields[2])
            branches.append(
                Branch(
                    name: String(name),
                    isRemote: isRemote,
                    isCurrent: fields[5] == "*",
                    upstream: fields[1].isEmpty ? nil : String(fields[1]),
                    isUpstreamGone: track.gone,
                    ahead: track.ahead,
                    behind: track.behind,
                    commit: String(fields[3]),
                    lastCommitDate: date
                )
            )
        }
        return branches.sorted { ($0.isRemote ? 1 : 0, $0.name) < ($1.isRemote ? 1 : 0, $1.name) }
    }

    /// Parses `upstream:track,nobracket`: empty, `gone`, `ahead 1`, `behind 2`, or `ahead 1, behind 2`.
    private static func parseTrack(_ value: Substring) throws -> Tracking {
        if value.isEmpty {
            return Tracking()
        }
        if value == "gone" {
            return Tracking(gone: true)
        }
        var ahead = 0
        var behind = 0
        for part in value.split(separator: ",") {
            let words = part.split(separator: " ")
            guard words.count == 2, let count = Int(words[1]) else {
                throw GitError.unexpectedOutput("Malformed upstream tracking: \(value)")
            }
            switch words[0] {
            case "ahead": ahead = count
            case "behind": behind = count
            default: throw GitError.unexpectedOutput("Malformed upstream tracking: \(value)")
            }
        }
        return Tracking(ahead: ahead, behind: behind)
    }

    private struct Tracking {
        var ahead = 0
        var behind = 0
        var gone = false
    }
}
