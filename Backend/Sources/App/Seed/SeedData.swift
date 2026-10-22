import Fluent
import Foundation

/// Realistic data for a fresh development database.
///
/// Seeding is idempotent: rows have fixed ids and are upserted, so running it
/// again refreshes the data instead of duplicating it. The GitHub tokens are
/// random placeholder bytes, not real tokens, so seeded users can't call GitHub.
enum SeedData {
    /// What a seed run wrote.
    struct Summary: Equatable, CustomStringConvertible {
        var users = 0
        var repositories = 0
        var groups = 0
        var snapshots = 0
        var webhookEvents = 0

        var description: String {
            "\(users) users, \(repositories) repositories, \(groups) groups, "
                + "\(snapshots) snapshots, \(webhookEvents) webhook events"
        }
    }

    /// Seeds `database`, ending the 30 days of snapshots on `today`.
    @discardableResult
    static func seed(on database: any Database, today: Date = .now) async throws -> Summary {
        try await database.transaction { database in
            var summary = Summary()
            let stores = Stores(database: database)
            for person in people {
                let user = try await stores.users.upsert(
                    person.profile,
                    tokenCiphertext: Data(repeating: 0, count: 32),
                    scopes: "repo read:user"
                )
                summary.users += 1
                let workspaceID = try await stores.sync.defaultWorkspace(userID: try user.requireID()).requireID()

                for repository in person.repositories {
                    _ = try await stores.sync.upsert(repository.change, workspaceID: workspaceID)
                    summary.repositories += 1
                    summary.snapshots += try await seedSnapshots(
                        for: repository,
                        workspaceID: workspaceID,
                        today: today,
                        stores: stores
                    )
                }
                for group in person.groups {
                    _ = try await stores.sync.upsert(group, workspaceID: workspaceID)
                    summary.groups += 1
                }
            }
            summary.webhookEvents = try await seedWebhookEvents(on: database, today: today)
            return summary
        }
    }

    // MARK: - Data

    private struct Person {
        var profile: GitHubProfile
        var repositories: [Repository]
        var groups: [RepoGroupChange]
    }

    private struct Repository {
        var change: TrackedRepoChange
        /// Average commits per active day, for generated snapshots.
        var activity: Int
    }

    private static let seededAt = Date(timeIntervalSince1970: 1_791_000_000)

    private static func repository(
        _ id: String,
        _ remote: String,
        owner: String? = nil,
        name: String? = nil,
        activity: Int
    ) -> Repository {
        Repository(
            change: TrackedRepoChange(
                id: uuid(id),
                remoteURL: remote,
                githubOwner: owner,
                githubName: name,
                displayName: String(remote.split(separator: "/").last ?? ""),
                updatedAt: seededAt
            ),
            activity: activity
        )
    }

    private static let people: [Person] = [
        Person(
            profile: GitHubProfile(
                id: 1_000_001,
                login: "ada-dev",
                name: "Ada Lovelace",
                avatarURL: "https://avatars.githubusercontent.com/u/1000001"
            ),
            repositories: [
                repository(
                    "00000000-0000-4000-8000-000000000101",
                    "https://github.com/lquainta/repohub",
                    owner: "lquainta",
                    name: "RepoHub",
                    activity: 6
                ),
                repository(
                    "00000000-0000-4000-8000-000000000102",
                    "https://github.com/vapor/vapor",
                    owner: "vapor",
                    name: "vapor",
                    activity: 2
                ),
                repository(
                    "00000000-0000-4000-8000-000000000103",
                    "https://github.com/ada-dev/cs471-homework",
                    owner: "ada-dev",
                    name: "cs471-homework",
                    activity: 3
                ),
                repository("00000000-0000-4000-8000-000000000104", "https://gitlab.com/ada-dev/notes", activity: 1),
            ],
            groups: [
                RepoGroupChange(
                    id: uuid("00000000-0000-4000-8000-000000000201"),
                    name: "School",
                    sortOrder: 0,
                    memberIDs: [uuid("00000000-0000-4000-8000-000000000103")],
                    updatedAt: seededAt
                ),
                RepoGroupChange(
                    id: uuid("00000000-0000-4000-8000-000000000202"),
                    name: "Open Source",
                    sortOrder: 1,
                    memberIDs: [
                        uuid("00000000-0000-4000-8000-000000000101"), uuid("00000000-0000-4000-8000-000000000102"),
                    ],
                    updatedAt: seededAt
                ),
            ]
        ),
        Person(
            profile: GitHubProfile(id: 1_000_002, login: "grace-dev", name: "Grace Hopper"),
            repositories: [
                repository(
                    "00000000-0000-4000-8000-000000000111",
                    "https://github.com/grace-dev/compiler",
                    owner: "grace-dev",
                    name: "compiler",
                    activity: 4
                )
            ],
            groups: [
                RepoGroupChange(
                    id: uuid("00000000-0000-4000-8000-000000000211"),
                    name: "Work",
                    sortOrder: 0,
                    memberIDs: [uuid("00000000-0000-4000-8000-000000000111")],
                    updatedAt: seededAt
                )
            ]
        ),
    ]

    private static func uuid(_ string: String) -> UUID {
        guard let uuid = UUID(uuidString: string) else {
            preconditionFailure("Invalid seed UUID \(string)")
        }
        return uuid
    }

    /// 30 days of activity with a deterministic pattern (quiet weekends, busier weekdays).
    private static func seedSnapshots(
        for repository: Repository,
        workspaceID: UUID,
        today: Date,
        stores: Stores
    ) async throws -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let start = calendar.startOfDay(for: today)
        var count = 0
        for offset in 0..<30 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: start) else {
                continue
            }
            let weekday = calendar.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7
            let weekdayCommits = (repository.activity + offset * 7) % (repository.activity * 2 + 1)
            let commits = isWeekend ? (offset.isMultiple(of: 3) ? 1 : 0) : weekdayCommits
            try await stores.snapshots.upsert(
                RepoSnapshot(
                    trackedRepoID: repository.change.id,
                    day: day,
                    commits: commits,
                    dirty: offset.isMultiple(of: 4),
                    ahead: offset == 0 ? 1 : 0,
                    behind: offset.isMultiple(of: 5) ? 2 : 0,
                    capturedAt: day.addingTimeInterval(18 * 3_600)
                )
            )
            count += 1
        }
        return count
    }

    private static func seedWebhookEvents(on database: any Database, today: Date) async throws -> Int {
        let events = [
            WebhookEvent(
                deliveryID: "seed-check-run-1",
                event: "check_run",
                action: "completed",
                repoFullName: "lquainta/RepoHub",
                payload: .object([
                    "action": .string("completed"),
                    "check_run": .object(["name": .string("CI"), "conclusion": .string("success")]),
                ]),
                receivedAt: today.addingTimeInterval(-3_600)
            ),
            WebhookEvent(
                deliveryID: "seed-pull-request-1",
                event: "pull_request",
                action: "opened",
                repoFullName: "lquainta/RepoHub",
                payload: .object([
                    "action": .string("opened"),
                    "pull_request": .object(["number": .number(42), "title": .string("Add seed data")]),
                ]),
                receivedAt: today.addingTimeInterval(-1_800)
            ),
        ]
        let store = FluentWebhookEventStore(database: database)
        for event in events {
            _ = try await store.insertIfNew(event)
        }
        return events.count
    }
}
