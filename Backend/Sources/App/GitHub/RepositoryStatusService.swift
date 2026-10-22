import Foundation
import Logging

/// The combined result of a commit's check runs.
enum CheckState: String, Sendable {
    case success, failure, pending
}

/// Pull requests and CI for one repository, as the app shows them.
struct RepositoryGitHubStatus: Sendable, Equatable {
    struct PullRequest: Sendable, Equatable {
        var number: Int
        var title: String
        var url: String
        var author: String
        var isDraft: Bool
        var headBranch: String
        /// Whether the signed-in user is a requested reviewer.
        var reviewRequested: Bool
    }

    struct Checks: Sendable, Equatable {
        var state: CheckState
        var total: Int
        var failed: Int
        var pending: Int
        /// The failing run if there is one, otherwise the most recent run.
        var url: String
    }

    enum Failure: String, Sendable {
        case notFound, unauthorized, rateLimited, unavailable
    }

    var owner: String
    var name: String
    var pullRequests: [PullRequest] = []
    var checks: Checks?
    var error: Failure?
}

/// Combines cached GitHub responses into ``RepositoryGitHubStatus`` values.
struct RepositoryStatusService: Sendable {
    /// A repository to report on, with the local branch whose checks matter.
    struct Reference: Sendable, Equatable {
        var owner: String
        var name: String
        var branch: String?
    }

    /// How many repositories are fetched from GitHub at once.
    static let concurrency = 8

    let cache: GitHubCache
    var logger = Logger(label: "com.lquainta.RepoHub.RepositoryStatus")

    /// One status per reference, in the same order. A failure for one
    /// repository is reported in its ``RepositoryGitHubStatus/error`` and
    /// doesn't affect the others.
    func statuses(
        for references: [Reference],
        userID: UUID,
        login: String,
        token: String
    ) async -> [RepositoryGitHubStatus] {
        await withTaskGroup(of: (Int, RepositoryGitHubStatus).self) { group in
            var results = [RepositoryGitHubStatus?](repeating: nil, count: references.count)
            var next = 0
            func addNext() {
                guard next < references.count else {
                    return
                }
                let index = next
                next += 1
                group.addTask {
                    (index, await status(for: references[index], userID: userID, login: login, token: token))
                }
            }
            for _ in 0..<Self.concurrency {
                addNext()
            }
            for await (index, status) in group {
                results[index] = status
                addNext()
            }
            return results.compactMap(\.self)
        }
    }

    private func status(
        for reference: Reference,
        userID: UUID,
        login: String,
        token: String
    ) async -> RepositoryGitHubStatus {
        var status = RepositoryGitHubStatus(owner: reference.owner, name: reference.name)
        do {
            let pulls = try await cache.fetch(
                .pullRequests,
                owner: reference.owner,
                name: reference.name,
                userID: userID,
                token: token
            )
            status.pullRequests = try Self.pullRequests(from: pulls.body, login: login)
        } catch {
            status.error = failure(error, reference)
            return status
        }
        guard let branch = reference.branch else {
            return status
        }
        do {
            let runs = try await cache.fetch(
                .checkRuns(ref: branch),
                owner: reference.owner,
                name: reference.name,
                userID: userID,
                token: token
            )
            status.checks = try Self.checks(from: runs.body)
        } catch GitHubError.notFound {
            // The branch was never pushed, so it has no checks.
        } catch {
            // Pull requests are still worth showing without checks.
            _ = failure(error, reference)
        }
        return status
    }

    private func failure(_ error: any Error, _ reference: Reference) -> RepositoryGitHubStatus.Failure {
        switch error as? GitHubError {
        case .notFound: return .notFound
        case .unauthorized: return .unauthorized
        case .rateLimited: return .rateLimited
        case .unexpectedStatus, nil:
            logger.warning(
                "GitHub status failed",
                metadata: ["repo": "\(reference.owner)/\(reference.name)", "error": "\(error)"]
            )
            return .unavailable
        }
    }

    // MARK: - Decoding GitHub's JSON

    private struct GitHubUser: Decodable {
        var login: String
    }

    private struct GitHubRef: Decodable {
        var ref: String
    }

    private struct GitHubPull: Decodable {
        var number: Int
        var title: String
        var htmlUrl: String
        var user: GitHubUser?
        var draft: Bool
        var head: GitHubRef
        var requestedReviewers: [GitHubUser]?
    }

    private struct GitHubCheckRun: Decodable {
        var status: String
        var conclusion: String?
        var htmlUrl: String?
    }

    private struct GitHubCheckRuns: Decodable {
        var checkRuns: [GitHubCheckRun]
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// Conclusions that mean the run failed. `neutral` and `skipped` don't.
    private static let failedConclusions: Set<String> = [
        "failure", "timed_out", "cancelled", "action_required", "startup_failure", "stale",
    ]

    static func pullRequests(from body: Data, login: String) throws -> [RepositoryGitHubStatus.PullRequest] {
        try decoder.decode([GitHubPull].self, from: body).map { pull in
            RepositoryGitHubStatus.PullRequest(
                number: pull.number,
                title: pull.title,
                url: pull.htmlUrl,
                author: pull.user?.login ?? "ghost",
                isDraft: pull.draft,
                headBranch: pull.head.ref,
                reviewRequested: pull.requestedReviewers?.contains {
                    $0.login.caseInsensitiveCompare(login) == .orderedSame
                } ?? false
            )
        }
    }

    static func checks(from body: Data) throws -> RepositoryGitHubStatus.Checks? {
        let runs = try decoder.decode(GitHubCheckRuns.self, from: body).checkRuns
        guard let latest = runs.first else {
            return nil
        }
        let failed = runs.filter { $0.status == "completed" && failedConclusions.contains($0.conclusion ?? "") }
        let pending = runs.filter { $0.status != "completed" }
        let state: CheckState =
            !failed.isEmpty ? .failure : !pending.isEmpty ? .pending : .success
        return RepositoryGitHubStatus.Checks(
            state: state,
            total: runs.count,
            failed: failed.count,
            pending: pending.count,
            url: (failed.first ?? latest).htmlUrl ?? ""
        )
    }
}
