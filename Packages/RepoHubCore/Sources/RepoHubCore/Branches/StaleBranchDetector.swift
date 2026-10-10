import Foundation

/// Why a branch is suggested for deletion.
public enum StaleReason: Sendable, Equatable, Hashable, Comparable {
    /// Fully merged into the default branch; deleting it loses no work.
    case merged
    /// Its upstream was deleted on the remote (usually after a PR merged).
    case upstreamGone
    /// No commits for at least this many days.
    case inactive(days: Int)
}

/// A local branch that may be safe to delete.
public struct StaleBranch: Sendable, Equatable, Hashable {
    /// The branch.
    public var branch: Branch
    /// Every reason that applies, in a stable order.
    public var reasons: [StaleReason]

    /// Whether the branch is merged into the default branch. Unmerged
    /// branches can only be deleted with explicit force confirmation.
    public var isMerged: Bool { reasons.contains(.merged) }

    /// Creates a stale branch candidate.
    public init(branch: Branch, reasons: [StaleReason]) {
        self.branch = branch
        self.reasons = reasons
    }
}

/// Finds local branches that are merged, whose upstream is gone, or that are inactive.
public enum StaleBranchDetector {
    /// Returns deletion candidates among `branches`.
    ///
    /// The current branch and the default branch are never candidates, and
    /// remote-tracking branches are ignored.
    ///
    /// - Parameters:
    ///   - branches: All branches (from ``BranchListParser``).
    ///   - mergedNames: Local branch names merged into `defaultBranch`.
    ///   - defaultBranch: The repository's main line, such as `main`.
    ///   - inactiveAfterDays: Branches with no commits for this many days are
    ///     candidates. `nil` or a value below 1 turns the check off.
    ///   - now: The current date.
    /// - Returns: Candidates sorted by name.
    public static func candidates(
        in branches: [Branch],
        mergedNames: Set<String>,
        defaultBranch: String,
        inactiveAfterDays: Int?,
        now: Date = .now
    ) -> [StaleBranch] {
        branches
            .filter { !$0.isRemote && !$0.isCurrent && $0.name != defaultBranch }
            .compactMap { branch in
                var reasons: [StaleReason] = []
                if mergedNames.contains(branch.name) {
                    reasons.append(.merged)
                }
                if branch.isUpstreamGone {
                    reasons.append(.upstreamGone)
                }
                if let inactiveAfterDays, inactiveAfterDays > 0 {
                    let days =
                        Calendar(identifier: .gregorian)
                        .dateComponents([.day], from: branch.lastCommitDate, to: now).day ?? 0
                    if days >= inactiveAfterDays {
                        reasons.append(.inactive(days: days))
                    }
                }
                return reasons.isEmpty ? nil : StaleBranch(branch: branch, reasons: reasons)
            }
            .sorted { $0.branch.name < $1.branch.name }
    }
}

/// The result of looking for stale branches in a repository.
public struct StaleBranchReport: Sendable, Equatable {
    /// The branch others were compared against.
    public var defaultBranch: String
    /// The current branch, which is never deleted.
    public var currentBranch: String?
    /// Deletion candidates.
    public var candidates: [StaleBranch]

    /// Creates a report.
    public init(defaultBranch: String, currentBranch: String?, candidates: [StaleBranch]) {
        self.defaultBranch = defaultBranch
        self.currentBranch = currentBranch
        self.candidates = candidates
    }
}

/// The outcome of deleting one branch.
public struct BranchDeletionResult: Sendable, Equatable {
    /// The local branch name.
    public var name: String
    /// `nil` on success; otherwise what went wrong.
    public var error: GitError?
    /// Whether the matching remote branch was deleted too.
    public var deletedRemote: Bool

    /// Creates a result.
    public init(name: String, error: GitError? = nil, deletedRemote: Bool = false) {
        self.name = name
        self.error = error
        self.deletedRemote = deletedRemote
    }
}
