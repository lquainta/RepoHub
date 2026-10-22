import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting

@testable import App

@Suite("Activity days")
struct ActivityDayTests {
    @Test("Days round-trip as UTC midnight; malformed days are rejected")
    func days() throws {
        let date = try #require(ActivityService.date(from: "2026-10-21"))
        #expect(ActivityService.day(from: date) == "2026-10-21")
        #expect(date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400) == 0)
        #expect(ActivityService.date(from: "2026-13-01") == nil)
        #expect(ActivityService.date(from: "yesterday") == nil)
    }
}

/// The parts of `GET /activity` the route test reads.
private struct ActivityDayBody: Decodable {
    let day: String
    let commits: Int
    let dirty: Bool
}

private struct RepositoryActivityBody: Decodable {
    let repository: String
    let name: String
    let days: [ActivityDayBody]
}

private struct ActivityBody: Decodable {
    let repositories: [RepositoryActivityBody]
}

extension DatabaseIntegrationTests {
    @Suite("Activity")
    struct ActivityTests {
        private func user(_ app: Application) async throws -> UUID {
            let user = User(githubID: 7, login: "octocat", githubTokenCiphertext: Data(), githubTokenScopes: "")
            try await user.create(on: app.db)
            return try user.requireID()
        }

        @Test("Re-uploading a day replaces its commits but keeps dirty unless sent; history is limited to the range")
        func uploadAndHistory() async throws {
            try await withMigratedApp { app in
                let service = ActivityService(database: app.db)
                let userID = try await user(app)
                try await service.upload(
                    [
                        SnapshotInput(
                            repository: "github.com/o/api",
                            day: "2026-10-20",
                            commits: 2,
                            capture: .init(dirty: true, ahead: 0, behind: 0)
                        ),
                        SnapshotInput(
                            repository: "github.com/o/api",
                            day: "2026-10-21",
                            commits: 1,
                            capture: .init(dirty: false, ahead: 0, behind: 0)
                        ),
                        SnapshotInput(repository: "github.com/o/api", day: "2026-08-01", commits: 9),
                    ],
                    userID: userID
                )
                try await service.upload(
                    [SnapshotInput(repository: "GitHub.com/o/api", day: "2026-10-20", commits: 3)],
                    userID: userID
                )

                let today = try #require(ActivityService.date(from: "2026-10-21"))
                let history = try await service.history(userID: userID, days: 30, today: today)

                #expect(history.map(\.repository) == ["github.com/o/api"])
                #expect(history.first?.name == "api")
                #expect(history.first?.days.map(\.day) == ["2026-10-20", "2026-10-21"])
                #expect(history.first?.days.map(\.commits) == [3, 1])
                #expect(history.first?.days.first?.dirty == true)
                #expect(try await TrackedRepo.query(on: app.db).count() == 1)
            }
        }

        @Test("With no snapshots the history is empty")
        func emptyHistory() async throws {
            try await withMigratedApp { app in
                let userID = try await user(app)
                let history = try await ActivityService(database: app.db).history(userID: userID, days: 30)
                #expect(history.isEmpty)
            }
        }

        @Test("The routes need sign-in, reject bad days, and return the uploaded activity")
        func routes() async throws {
            try await withMigratedApp { app in
                let token = try await app.signInWithFakeGitHub()
                var headers = HTTPHeaders()
                headers.bearerAuthorization = BearerAuthorization(token: token)
                let today = ActivityService.day(from: .now)
                let upload =
                    #"{"snapshots":[{"repository":"github.com/o/web","day":"\#(today)","commits":4,"dirty":true}]}"#

                #expect(try await app.send(.POST, "activity/snapshots", json: upload).status == .unauthorized)
                #expect(
                    try await app.send(.POST, "activity/snapshots", json: upload, headers: headers).status == .noContent
                )
                let bad = #"{"snapshots":[{"repository":"github.com/o/web","day":"2026-02-31x","commits":1}]}"#
                #expect(
                    try await app.send(.POST, "activity/snapshots", json: bad, headers: headers).status == .badRequest
                )

                let response = try await app.send(.GET, "activity?days=7", headers: headers)
                #expect(response.status == .ok)
                let body = try response.content.decode(ActivityBody.self)
                #expect(body.repositories.first?.days.first?.commits == 4)
                #expect(body.repositories.first?.days.first?.dirty == true)
            }
        }
    }
}
