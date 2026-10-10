import Foundation
import RepoHubCore

/// User-facing descriptions of repository status, used for visible text,
/// VoiceOver labels, and tooltips so status is never conveyed by color alone.
enum StatusText {
    /// For example "Clean", or "2 staged, 1 modified, 3 untracked".
    static func changes(_ counts: FileChangeCounts) -> String {
        guard !counts.isEmpty else {
            return String(localized: "Clean")
        }
        var parts: [String] = []
        if counts.conflicted > 0 {
            parts.append(String(localized: "\(counts.conflicted) conflicted"))
        }
        if counts.staged > 0 {
            parts.append(String(localized: "\(counts.staged) staged"))
        }
        if counts.unstaged > 0 {
            parts.append(String(localized: "\(counts.unstaged) modified"))
        }
        if counts.untracked > 0 {
            parts.append(String(localized: "\(counts.untracked) untracked"))
        }
        return parts.formatted(.list(type: .and, width: .narrow))
    }

    /// For example "Up to date", "2 ahead, 1 behind", or "No upstream".
    static func sync(_ status: RepoStatus) -> String {
        guard status.upstream != nil else {
            return String(localized: "No upstream")
        }
        switch (status.ahead, status.behind) {
        case (0, 0): return String(localized: "Up to date")
        case (let ahead, 0): return String(localized: "\(ahead) ahead")
        case (0, let behind): return String(localized: "\(behind) behind")
        case (let ahead, let behind): return String(localized: "\(ahead) ahead, \(behind) behind")
        }
    }

    /// For example "main", "Detached at 1a2b3c4", or "main (no commits)".
    static func branch(_ head: HeadState) -> String {
        switch head {
        case .branch(let name): name
        case .detached(let commit): String(localized: "Detached at \(String(commit.prefix(7)))")
        case .unborn(let name): String(localized: "\(name) (no commits)")
        }
    }

    /// A short explanation of why a repository's status couldn't be read.
    static func message(for error: GitError) -> String {
        switch error {
        case .gitNotFound: String(localized: "Git isn't installed. Install the Xcode Command Line Tools.")
        case .directoryNotFound: String(localized: "The folder no longer exists.")
        case .notARepository: String(localized: "This folder isn't a git repository.")
        case .timedOut: String(localized: "Git took too long to respond.")
        case .commandFailed(_, _, let stderr): stderr.isEmpty ? String(localized: "Git reported an error.") : stderr
        case .unexpectedOutput: String(localized: "Git's output couldn't be read.")
        }
    }
}
