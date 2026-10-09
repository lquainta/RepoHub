import Foundation

/// A snapshot of a git repository's working state.
public struct RepoStatus: Sendable, Equatable {
    /// What `HEAD` points at.
    public var head: HeadState
    /// The upstream branch, such as `origin/main`, or `nil` if none is configured.
    public var upstream: String?
    /// Commits on `HEAD` that are not on the upstream.
    public var ahead: Int
    /// Commits on the upstream that are not on `HEAD`.
    public var behind: Int
    /// Counts of changed files in the index and working tree.
    public var changes: FileChangeCounts
    /// Number of entries in the stash.
    public var stashCount: Int
    /// The most recent commit on `HEAD`, or `nil` for a repository with no commits.
    public var lastCommit: CommitSummary?

    /// Creates a status snapshot.
    public init(
        head: HeadState,
        upstream: String? = nil,
        ahead: Int = 0,
        behind: Int = 0,
        changes: FileChangeCounts = FileChangeCounts(),
        stashCount: Int = 0,
        lastCommit: CommitSummary? = nil
    ) {
        self.head = head
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.changes = changes
        self.stashCount = stashCount
        self.lastCommit = lastCommit
    }

    /// Whether the working tree and index have no changes, untracked files, or conflicts.
    public var isClean: Bool { changes.isEmpty }
}

/// What a repository's `HEAD` points at.
public enum HeadState: Sendable, Equatable {
    /// On a branch with at least one commit.
    case branch(String)
    /// Detached at a specific commit.
    case detached(commit: String)
    /// On a branch that has no commits yet (a freshly initialized repository).
    case unborn(branch: String)

    /// The branch name, or `nil` when detached.
    public var branchName: String? {
        switch self {
        case .branch(let name), .unborn(let name): name
        case .detached: nil
        }
    }
}

/// Counts of changed paths, as reported by `git status`.
///
/// A file can be counted as both staged and unstaged when it has changes in
/// the index and further changes in the working tree.
public struct FileChangeCounts: Sendable, Equatable {
    /// Paths with changes in the index (added, modified, deleted, renamed, copied).
    public var staged: Int
    /// Paths with changes in the working tree that are not staged.
    public var unstaged: Int
    /// Paths not tracked by git and not ignored.
    public var untracked: Int
    /// Paths with unresolved merge conflicts.
    public var conflicted: Int

    /// Creates change counts.
    public init(staged: Int = 0, unstaged: Int = 0, untracked: Int = 0, conflicted: Int = 0) {
        self.staged = staged
        self.unstaged = unstaged
        self.untracked = untracked
        self.conflicted = conflicted
    }

    /// Whether every count is zero.
    public var isEmpty: Bool {
        staged == 0 && unstaged == 0 && untracked == 0 && conflicted == 0
    }
}

/// Summary of a single commit.
public struct CommitSummary: Sendable, Equatable {
    /// Full object name (SHA).
    public var hash: String
    /// Author name.
    public var author: String
    /// Author date.
    public var date: Date
    /// First line of the commit message.
    public var subject: String

    /// Creates a commit summary.
    public init(hash: String, author: String, date: Date, subject: String) {
        self.hash = hash
        self.author = author
        self.date = date
        self.subject = subject
    }
}
