/// Parses the output of
/// `git status --porcelain=v2 --branch --show-stash -z`.
///
/// The `-z` format separates entries with NUL bytes, so paths containing
/// spaces, newlines, or non-ASCII characters never need unquoting. Rename and
/// copy entries (`2`) are followed by an extra NUL-separated original path.
///
/// See https://git-scm.com/docs/git-status#_porcelain_format_version_2
public enum PorcelainStatusParser {
    /// Parses status output into a ``RepoStatus`` with no ``RepoStatus/lastCommit``.
    ///
    /// - Throws: ``GitError/unexpectedOutput(_:)`` if the output is malformed.
    public static func parse(_ output: String) throws -> RepoStatus {
        try parseWithFiles(output).status
    }

    /// Parses status output into a ``RepoStatus`` and the individual changed paths.
    ///
    /// A path with changes in both the index and the working tree yields one
    /// ``FileChange`` for each area.
    ///
    /// - Throws: ``GitError/unexpectedOutput(_:)`` if the output is malformed.
    public static func parseWithFiles(_ output: String) throws -> (status: RepoStatus, files: [FileChange]) {
        var state = State()
        var entries = output.split(separator: "\0", omittingEmptySubsequences: true).makeIterator()

        while let entry = entries.next() {
            if entry.hasPrefix("# ") {
                try state.applyHeader(entry.dropFirst(2))
                continue
            }
            switch entry.first {
            case "1":
                // 1 XY sub mH mI mW hH hI <path>
                try state.addChange(statusCode: field(1, of: entry), path: path(after: 8, in: entry))
            case "2":
                // 2 XY sub mH mI mW hH hI Xscore <path>, then the original path as its own entry
                guard let original = entries.next() else {
                    throw GitError.unexpectedOutput("Rename entry is missing its original path: \(entry)")
                }
                try state.addChange(
                    statusCode: field(1, of: entry),
                    path: path(after: 9, in: entry),
                    originalPath: String(original)
                )
            case "u":
                // u XY sub m1 m2 m3 mW h1 h2 h3 <path>
                state.changes.conflicted += 1
                state.files.append(FileChange(path: try path(after: 10, in: entry), area: .conflicted, kind: .unmerged))
            case "?":
                state.changes.untracked += 1
                state.files.append(FileChange(path: try path(after: 1, in: entry), area: .untracked, kind: .untracked))
            case "!":
                continue
            default:
                throw GitError.unexpectedOutput("Unrecognized status entry: \(entry)")
            }
        }
        return (try state.makeStatus(), state.files)
    }

    /// Returns the space-separated field at `index` in `entry`.
    private static func field(_ index: Int, of entry: Substring) throws -> Substring {
        let fields = entry.split(separator: " ", maxSplits: index + 1, omittingEmptySubsequences: false)
        guard fields.count > index else {
            throw GitError.unexpectedOutput("Status entry has too few fields: \(entry)")
        }
        return fields[index]
    }

    /// Returns everything after the first `count` space-separated fields: the
    /// path, which may itself contain spaces.
    private static func path(after count: Int, in entry: Substring) throws -> String {
        let fields = entry.split(separator: " ", maxSplits: count, omittingEmptySubsequences: false)
        guard fields.count == count + 1, let path = fields.last, !path.isEmpty else {
            throw GitError.unexpectedOutput("Status entry has no path: \(entry)")
        }
        return String(path)
    }

    /// Accumulates header and entry data while parsing.
    private struct State {
        var oid: Substring?
        var head: Substring?
        var upstream: String?
        var ahead = 0
        var behind = 0
        var stashCount = 0
        var changes = FileChangeCounts()
        var files: [FileChange] = []

        mutating func applyHeader(_ header: Substring) throws {
            let parts = header.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else {
                throw GitError.unexpectedOutput("Malformed header: # \(header)")
            }
            let (key, value) = (parts[0], parts[1])
            switch key {
            case "branch.oid":
                oid = value
            case "branch.head":
                head = value
            case "branch.upstream":
                upstream = String(value)
            case "branch.ab":
                (ahead, behind) = try Self.parseAheadBehind(value)
            case "stash":
                guard let count = Int(value) else {
                    throw GitError.unexpectedOutput("Malformed stash header: # \(header)")
                }
                stashCount = count
            default:
                // Ignore headers added by future git versions.
                break
            }
        }

        /// Records an entry from its two-character `XY` code: `X` is the index
        /// (staged) state and `Y` the working tree state; `.` means unchanged.
        mutating func addChange(statusCode: Substring, path: String, originalPath: String? = nil) throws {
            guard statusCode.count == 2, let index = statusCode.first, let worktree = statusCode.last else {
                throw GitError.unexpectedOutput("Malformed XY status: \(statusCode)")
            }
            if index != "." {
                changes.staged += 1
                let kind = try Self.kind(index, statusCode)
                files.append(FileChange(path: path, originalPath: originalPath, area: .staged, kind: kind))
            }
            if worktree != "." {
                changes.unstaged += 1
                let kind = try Self.kind(worktree, statusCode)
                files.append(FileChange(path: path, area: .unstaged, kind: kind))
            }
        }

        private static func kind(_ code: Character, _ statusCode: Substring) throws -> FileChange.Kind {
            switch code {
            case "A": .added
            case "M": .modified
            case "D": .deleted
            case "R": .renamed
            case "C": .copied
            case "T": .typeChanged
            case "U": .unmerged
            default: throw GitError.unexpectedOutput("Unknown change code '\(code)' in \(statusCode)")
            }
        }

        func makeStatus() throws -> RepoStatus {
            guard let oid, let head else {
                throw GitError.unexpectedOutput("Missing branch headers; was --branch passed?")
            }
            let headState: HeadState
            if oid == "(initial)" {
                headState = .unborn(branch: String(head))
            } else if head == "(detached)" {
                headState = .detached(commit: String(oid))
            } else {
                headState = .branch(String(head))
            }
            return RepoStatus(
                head: headState,
                upstream: upstream,
                ahead: ahead,
                behind: behind,
                changes: changes,
                stashCount: stashCount
            )
        }

        /// Parses `+<ahead> -<behind>`.
        private static func parseAheadBehind(_ value: Substring) throws -> (Int, Int) {
            let parts = value.split(separator: " ")
            guard parts.count == 2,
                parts[0].first == "+", let ahead = Int(parts[0].dropFirst()),
                parts[1].first == "-", let behind = Int(parts[1].dropFirst())
            else {
                throw GitError.unexpectedOutput("Malformed branch.ab header: \(value)")
            }
            return (ahead, behind)
        }
    }
}
