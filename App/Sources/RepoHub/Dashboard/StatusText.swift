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

    /// Section title for a change area.
    static func title(for area: FileChange.Area) -> String {
        switch area {
        case .staged: String(localized: "Staged")
        case .unstaged: String(localized: "Not Staged")
        case .untracked: String(localized: "Untracked")
        case .conflicted: String(localized: "Conflicts")
        }
    }

    /// For example "Added" or "Renamed".
    static func description(of kind: FileChange.Kind) -> String {
        switch kind {
        case .added: String(localized: "Added")
        case .modified: String(localized: "Modified")
        case .deleted: String(localized: "Deleted")
        case .renamed: String(localized: "Renamed")
        case .copied: String(localized: "Copied")
        case .typeChanged: String(localized: "Type changed")
        case .unmerged: String(localized: "Conflict")
        case .untracked: String(localized: "Untracked")
        }
    }

    /// SF Symbol for a kind of change.
    static func symbol(for kind: FileChange.Kind) -> String {
        switch kind {
        case .added: "plus.circle"
        case .modified: "pencil.circle"
        case .deleted: "minus.circle"
        case .renamed: "arrow.right.circle"
        case .copied: "doc.on.doc"
        case .typeChanged: "arrow.triangle.swap"
        case .unmerged: "exclamationmark.triangle"
        case .untracked: "questionmark.circle"
        }
    }

    /// For example "origin/main · 2 ahead", "origin/old · deleted on remote", or `nil` without upstream.
    static func tracking(of branch: Branch) -> String? {
        guard let upstream = branch.upstream else {
            return nil
        }
        if branch.isUpstreamGone {
            return String(localized: "\(upstream) · deleted on remote")
        }
        let sync = sync(
            RepoStatus(head: .branch(branch.name), upstream: upstream, ahead: branch.ahead, behind: branch.behind)
        )
        return "\(upstream) · \(sync)"
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
