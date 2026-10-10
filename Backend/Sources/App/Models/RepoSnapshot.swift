import Fluent
import Foundation

/// One day of activity for a repository, uploaded by the app (#81).
final class RepoSnapshot: Model, @unchecked Sendable {
    static let schema = "repo_snapshots"

    @ID(key: .id) var id: UUID?
    @Parent(key: "tracked_repo_id") var trackedRepo: TrackedRepo
    /// The calendar day (stored as a SQL `date`).
    @Field(key: "day") var day: Date
    @Field(key: "commits") var commits: Int
    @Field(key: "dirty") var dirty: Bool
    @Field(key: "ahead") var ahead: Int
    @Field(key: "behind") var behind: Int
    @Field(key: "captured_at") var capturedAt: Date

    init() {}

    init(
        id: UUID? = nil,
        trackedRepoID: TrackedRepo.IDValue,
        day: Date,
        commits: Int,
        dirty: Bool,
        ahead: Int,
        behind: Int,
        capturedAt: Date = .now
    ) {
        self.id = id
        self.$trackedRepo.id = trackedRepoID
        self.day = day
        self.commits = commits
        self.dirty = dirty
        self.ahead = ahead
        self.behind = behind
        self.capturedAt = capturedAt
    }
}
