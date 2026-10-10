import Fluent
import Foundation

/// Daily activity snapshots for the history chart (#81).
protocol SnapshotStore: Sendable {
    /// Stores the snapshot for its repository and day, replacing an earlier upload of the same day.
    func upsert(_ snapshot: RepoSnapshot) async throws
    /// Snapshots for `repositoryIDs` with `day` in `start...end`, oldest first.
    func snapshots(repositoryIDs: [UUID], from start: Date, through end: Date) async throws -> [RepoSnapshot]
}

struct FluentSnapshotStore: SnapshotStore {
    let database: any Database

    func upsert(_ snapshot: RepoSnapshot) async throws {
        if let existing = try await RepoSnapshot.query(on: database)
            .filter(\.$trackedRepo.$id == snapshot.$trackedRepo.id)
            .filter(\.$day == snapshot.day)
            .first()
        {
            existing.commits = snapshot.commits
            existing.dirty = snapshot.dirty
            existing.ahead = snapshot.ahead
            existing.behind = snapshot.behind
            existing.capturedAt = snapshot.capturedAt
            try await existing.update(on: database)
        } else {
            try await snapshot.create(on: database)
        }
    }

    func snapshots(repositoryIDs: [UUID], from start: Date, through end: Date) async throws -> [RepoSnapshot] {
        try await RepoSnapshot.query(on: database)
            .filter(\.$trackedRepo.$id ~~ repositoryIDs)
            .filter(\.$day >= start)
            .filter(\.$day <= end)
            .sort(\.$day)
            .all()
    }
}
