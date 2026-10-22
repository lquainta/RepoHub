import Foundation
import RepoHubCore

// App-level types for the backend API, independent of the generated client.

/// A GitHub user, as the backend describes them.
struct UserProfile: Equatable, Sendable, Codable {
    var id: String
    var login: String
    var name: String?
    var avatarURL: URL?
}

/// A code for the user to enter on GitHub.
struct DeviceAuthorization: Equatable, Sendable {
    /// Sent back while polling; never shown.
    var deviceCode: String
    /// Shown to the user, for example `WDJB-MJHT`.
    var userCode: String
    var verificationURL: URL
    /// When the code stops working.
    var expiresIn: Duration
    /// The minimum time between polls.
    var interval: Duration
}

/// Tokens for one signed-in device.
struct Session: Equatable, Sendable {
    var accessToken: String
    /// Single-use; exchanged for a new session when the access token expires.
    var refreshToken: String
    var expiresIn: Duration
    var user: UserProfile
}

/// The result of one poll for a device sign-in.
enum DeviceSignInPoll: Equatable, Sendable {
    /// The user hasn't approved yet; poll again after `interval`.
    case pending(interval: Duration)
    case signedIn(Session)
}

/// A repository to ask the backend about, with the local branch whose checks matter.
struct GitHubStatusRequest: Equatable, Hashable, Sendable {
    var repository: GitHubRepository
    /// `nil` for a detached HEAD.
    var branch: String?
}

/// The combined result of a commit's check runs.
enum CheckState: String, Sendable {
    case success, failure, pending
}

/// Pull requests and CI for one GitHub repository.
struct GitHubRepositoryStatus: Equatable, Sendable {
    struct PullRequest: Equatable, Sendable, Identifiable {
        var number: Int
        var title: String
        var url: URL
        var author: String
        var isDraft: Bool
        var headBranch: String
        /// Whether the signed-in user is a requested reviewer.
        var reviewRequested: Bool

        var id: Int { number }
    }

    struct Checks: Equatable, Sendable {
        var state: CheckState
        var total: Int
        var failed: Int
        var pending: Int
        /// The failing run, or the most recent one.
        var url: URL
    }

    var repository: GitHubRepository
    /// Open pull requests, newest first.
    var pullRequests: [PullRequest] = []
    /// Checks on the requested branch, if it has any.
    var checks: Checks?
    /// Why GitHub data isn't available (`notFound`, `unauthorized`, `rateLimited`, `unavailable`).
    var error: String?

    /// Pull requests waiting for the user's review.
    var reviewRequests: [PullRequest] { pullRequests.filter(\.reviewRequested) }

    /// The open pull request for `branch`, if there is one.
    func pullRequest(for branch: String?) -> PullRequest? {
        branch.flatMap { branch in pullRequests.first { $0.headBranch == branch } }
    }
}

/// A group as Macs sync it (#80). Members are remote identities
/// (``RemoteIdentity``), because local paths differ between Macs.
struct SyncedGroup: Equatable, Sendable {
    var id: UUID
    var name: String
    var sortOrder: Int
    var members: [String]
    /// When it last changed, by the clock of the Mac that changed it.
    var updatedAt: Date
    var deletedAt: Date?
}

/// Settings synced between Macs.
struct SyncedSettings: Equatable, Sendable {
    /// `nil` means the app's default.
    var staleBranchDays: Int?
    var updatedAt: Date
}

/// The user's synced workspace.
struct SyncedWorkspace: Equatable, Sendable {
    /// The server's time of the response; pass it as `since` next time.
    var serverTime: Date
    var settings: SyncedSettings
    var groups: [SyncedGroup]
}

/// One repository's day, uploaded for the activity history (#81).
struct ActivitySnapshot: Equatable, Sendable {
    /// Remote identity, such as `github.com/owner/repo`.
    var repository: String
    /// `YYYY-MM-DD` in the Mac's calendar.
    var day: String
    var commits: Int
    /// The repository's state when captured; only sent for today, and `nil`
    /// keeps what the server has.
    var capture: SnapshotCapture?
}

/// A repository's state at the moment a snapshot was taken.
struct SnapshotCapture: Equatable, Sendable {
    /// Whether there were uncommitted changes.
    var dirty: Bool
    var ahead: Int
    var behind: Int
}

/// One repository's activity, oldest day first. Days without data are absent.
struct RepositoryActivity: Equatable, Sendable {
    struct Day: Equatable, Sendable {
        /// `YYYY-MM-DD`.
        var day: String
        var commits: Int
        var dirty: Bool
    }

    var repository: String
    var name: String
    var days: [Day]
}
