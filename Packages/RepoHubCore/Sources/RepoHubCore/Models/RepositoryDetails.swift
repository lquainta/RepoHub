import Foundation

/// Everything the detail view shows about one repository.
public struct RepositoryDetails: Sendable, Equatable {
    /// The repository's status, including ``RepoStatus/lastCommit``.
    public var status: RepoStatus
    /// Changed paths. A path changed in both the index and the working tree appears twice.
    public var files: [FileChange]
    /// Local branches first, then remote-tracking branches, each sorted by name.
    public var branches: [Branch]
    /// The most recent commits on `HEAD`, newest first.
    public var recentCommits: [CommitSummary]
    /// Configured remotes, sorted by name.
    public var remotes: [Remote]
    /// Stash entries, newest first.
    public var stashes: [StashEntry]

    /// Creates repository details.
    public init(
        status: RepoStatus,
        files: [FileChange] = [],
        branches: [Branch] = [],
        recentCommits: [CommitSummary] = [],
        remotes: [Remote] = [],
        stashes: [StashEntry] = []
    ) {
        self.status = status
        self.files = files
        self.branches = branches
        self.recentCommits = recentCommits
        self.remotes = remotes
        self.stashes = stashes
    }
}

/// A changed path reported by `git status`.
public struct FileChange: Sendable, Equatable, Hashable {
    /// Where the change is.
    public enum Area: Sendable, Equatable, Hashable, CaseIterable {
        /// In the index (will be committed).
        case staged
        /// In the working tree, not staged.
        case unstaged
        /// Not tracked by git.
        case untracked
        /// Unresolved merge conflict.
        case conflicted
    }

    /// What happened to the path.
    public enum Kind: Sendable, Equatable, Hashable {
        case added, modified, deleted, renamed, copied, typeChanged, unmerged, untracked
    }

    /// Path relative to the repository root.
    public var path: String
    /// The previous path, for renames and copies.
    public var originalPath: String?
    /// Where the change is.
    public var area: Area
    /// What happened to the path.
    public var kind: Kind

    /// Creates a file change.
    public init(path: String, originalPath: String? = nil, area: Area, kind: Kind) {
        self.path = path
        self.originalPath = originalPath
        self.area = area
        self.kind = kind
    }
}

/// A local or remote-tracking branch.
public struct Branch: Sendable, Equatable, Hashable {
    /// Short name, such as `main` or `origin/main`.
    public var name: String
    /// Whether this is a remote-tracking branch (`refs/remotes/...`).
    public var isRemote: Bool
    /// Whether `HEAD` points at this branch.
    public var isCurrent: Bool
    /// The configured upstream, such as `origin/main`.
    public var upstream: String?
    /// Whether the upstream is configured but no longer exists (deleted on the remote and pruned).
    public var isUpstreamGone: Bool
    /// Commits ahead of the upstream.
    public var ahead: Int
    /// Commits behind the upstream.
    public var behind: Int
    /// Full SHA of the branch tip.
    public var commit: String
    /// Committer date of the branch tip.
    public var lastCommitDate: Date

    /// Creates a branch.
    public init(
        name: String,
        isRemote: Bool = false,
        isCurrent: Bool = false,
        upstream: String? = nil,
        isUpstreamGone: Bool = false,
        ahead: Int = 0,
        behind: Int = 0,
        commit: String,
        lastCommitDate: Date
    ) {
        self.name = name
        self.isRemote = isRemote
        self.isCurrent = isCurrent
        self.upstream = upstream
        self.isUpstreamGone = isUpstreamGone
        self.ahead = ahead
        self.behind = behind
        self.commit = commit
        self.lastCommitDate = lastCommitDate
    }
}

/// A configured remote.
public struct Remote: Sendable, Equatable, Hashable {
    /// Remote name, such as `origin`.
    public var name: String
    /// Fetch URL.
    public var fetchURL: String
    /// Push URL, if it differs from the fetch URL.
    public var pushURL: String?

    /// Creates a remote.
    public init(name: String, fetchURL: String, pushURL: String? = nil) {
        self.name = name
        self.fetchURL = fetchURL
        self.pushURL = pushURL
    }
}

/// An entry in the stash.
public struct StashEntry: Sendable, Equatable, Hashable {
    /// Position in the stash, `0` being the newest (`stash@{0}`).
    public var index: Int
    /// The stash message, such as `WIP on main: 1a2b3c4 Subject`.
    public var message: String
    /// When the stash was created.
    public var date: Date

    /// Creates a stash entry.
    public init(index: Int, message: String, date: Date) {
        self.index = index
        self.message = message
        self.date = date
    }
}
