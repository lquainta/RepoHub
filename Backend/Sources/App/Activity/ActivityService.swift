import Fluent
import Foundation

/// One repository's day, as uploaded by the app.
struct SnapshotInput: Equatable, Sendable {
    /// Remote identity, such as `github.com/owner/repo`.
    var repository: String
    /// `YYYY-MM-DD` on the Mac.
    var day: String
    var commits: Int
    /// The state when captured; only sent for today, and `nil` keeps the stored values.
    var capture: Capture?

    struct Capture: Equatable, Sendable {
        var dirty: Bool
        var ahead: Int
        var behind: Int
    }
}

/// One repository's activity over a range of days.
struct RepositoryActivity: Equatable, Sendable {
    struct Day: Equatable, Sendable {
        var day: String
        var commits: Int
        var dirty: Bool
    }

    var repository: String
    var name: String
    /// Oldest first.
    var days: [Day]
}

/// Stores and reads the daily snapshots behind the activity chart (#81).
struct ActivityService: Sendable {
    let database: any Database

    /// Days are calendar dates without a time zone, stored as UTC midnight.
    static func date(from day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else {
            return nil
        }
        var components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        components.timeZone = TimeZone(identifier: "UTC")
        return utcCalendar.date(from: components)
    }

    static func day(from date: Date) -> String {
        let components = utcCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// Stores `snapshots` in the user's workspace, one per repository and day.
    ///
    /// - Throws: ``ActivityError/invalidDay(_:)`` for a malformed day, or a database error.
    func upload(_ snapshots: [SnapshotInput], userID: UUID) async throws {
        let workspaceID = try await FluentSyncStore(database: database).defaultWorkspace(userID: userID).requireID()
        let sync = WorkspaceSync(database: database)
        try await database.transaction { database in
            var repositoryIDs: [String: UUID] = [:]
            for input in snapshots {
                guard let day = Self.date(from: input.day) else {
                    throw ActivityError.invalidDay(input.day)
                }
                let identity = input.repository.lowercased()
                let repositoryID: UUID
                if let known = repositoryIDs[identity] {
                    repositoryID = known
                } else {
                    repositoryID = try await sync.trackedRepository(identity, workspaceID: workspaceID, on: database)
                        .requireID()
                    repositoryIDs[identity] = repositoryID
                }
                let snapshot =
                    try await RepoSnapshot.query(on: database)
                    .filter(\.$trackedRepo.$id == repositoryID)
                    .filter(\.$day == day)
                    .first()
                    ?? RepoSnapshot(
                        trackedRepoID: repositoryID,
                        day: day,
                        commits: 0,
                        dirty: false,
                        ahead: 0,
                        behind: 0
                    )
                snapshot.commits = max(0, input.commits)
                if let capture = input.capture {
                    snapshot.dirty = capture.dirty
                    snapshot.ahead = max(0, capture.ahead)
                    snapshot.behind = max(0, capture.behind)
                }
                snapshot.capturedAt = .now
                try await snapshot.save(on: database)
            }
        }
    }

    /// Activity in the user's workspace for the `days` days ending `today`.
    func history(userID: UUID, days: Int, today: Date = .now) async throws -> [RepositoryActivity] {
        let workspaceID = try await FluentSyncStore(database: database).defaultWorkspace(userID: userID).requireID()
        let repositories = try await TrackedRepo.query(on: database)
            .filter(\.$workspace.$id == workspaceID)
            .filter(\.$deletedAt == nil)
            .all()
        let ids = try repositories.map { try $0.requireID() }
        guard !ids.isEmpty, let end = Self.date(from: Self.day(from: today)) else {
            return []
        }
        let start = end.addingTimeInterval(-Double(max(1, days) - 1) * 86_400)
        let snapshots = try await FluentSnapshotStore(database: database).snapshots(
            repositoryIDs: ids,
            from: start,
            through: end
        )
        let byRepository = Dictionary(grouping: snapshots) { $0.$trackedRepo.id }
        return repositories.compactMap { repository in
            guard let id = repository.id, let rows = byRepository[id], !rows.isEmpty else {
                return nil
            }
            return RepositoryActivity(
                repository: repository.remoteURL,
                name: repository.displayName,
                days: rows.map { .init(day: Self.day(from: $0.day), commits: $0.commits, dirty: $0.dirty) }
            )
        }
        .sorted { $0.repository < $1.repository }
    }
}

enum ActivityError: Error, Equatable {
    case invalidDay(String)
}
