import Fluent
import Foundation
import OpenAPIRuntime
import RepoHubAPI

/// The activity history chart (#81).
extension APIHandler {
    func getActivity(_ input: Operations.getActivity.Input) async throws -> Operations.getActivity.Output {
        guard let user = RequestContext.user else {
            return .unauthorized(.init(body: .json(Self.error("Not signed in."))))
        }
        let days = min(max(input.query.days ?? 30, 1), 365)
        let history = try await ActivityService(database: app.db).history(userID: user.userID, days: days)
        let repositories = history.map { activity in
            Components.Schemas.RepositoryActivity(
                repository: activity.repository,
                name: activity.name,
                days: activity.days.map { .init(day: $0.day, commits: $0.commits, dirty: $0.dirty) }
            )
        }
        return .ok(.init(body: .json(.init(repositories: repositories))))
    }

    func uploadSnapshots(_ input: Operations.uploadSnapshots.Input) async throws -> Operations.uploadSnapshots.Output {
        guard let user = RequestContext.user else {
            return .unauthorized(.init(body: .json(Self.error("Not signed in."))))
        }
        let body: Components.Schemas.SnapshotUpload
        switch input.body {
        case .json(let json): body = json
        }
        guard (1...5_000).contains(body.snapshots.count) else {
            return .badRequest(.init(body: .json(Self.error("Send between 1 and 5000 snapshots."))))
        }
        let snapshots = body.snapshots.map { snapshot in
            SnapshotInput(
                repository: snapshot.repository,
                day: snapshot.day,
                commits: snapshot.commits,
                // The state is all or nothing: `dirty` says whether it was captured.
                capture: snapshot.dirty.map { dirty in
                    .init(dirty: dirty, ahead: snapshot.ahead ?? 0, behind: snapshot.behind ?? 0)
                }
            )
        }
        do {
            try await ActivityService(database: app.db).upload(snapshots, userID: user.userID)
        } catch ActivityError.invalidDay(let day) {
            return .badRequest(.init(body: .json(Self.error("Invalid day \(day); expected YYYY-MM-DD."))))
        }
        return .noContent(.init())
    }
}
