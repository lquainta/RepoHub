import Foundation
import Testing

@testable import RepoHubCore

@Suite("StaleBranchDetector")
struct StaleBranchDetectorTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func branch(
        _ name: String,
        daysOld: Int = 0,
        current: Bool = false,
        remote: Bool = false,
        gone: Bool = false
    ) -> Branch {
        Branch(
            name: name,
            isRemote: remote,
            isCurrent: current,
            upstream: gone ? "origin/\(name)" : nil,
            isUpstreamGone: gone,
            commit: "abc",
            lastCommitDate: now.addingTimeInterval(-Double(daysOld) * 86_400)
        )
    }

    @Test("Finds merged, upstream-gone, and inactive branches with every reason")
    func reasons() {
        let candidates = StaleBranchDetector.candidates(
            in: [
                branch("merged"),
                branch("gone", gone: true),
                branch("old", daysOld: 120),
                branch("everything", daysOld: 200, gone: true),
                branch("fresh", daysOld: 3),
            ],
            mergedNames: ["merged", "everything", "main"],
            defaultBranch: "main",
            inactiveAfterDays: 90,
            now: now
        )
        #expect(candidates.map(\.branch.name) == ["everything", "gone", "merged", "old"])
        #expect(candidates[0].reasons == [.merged, .upstreamGone, .inactive(days: 200)])
        #expect(candidates[1].reasons == [.upstreamGone] && !candidates[1].isMerged)
        #expect(candidates[2].isMerged)
        #expect(candidates[3].reasons == [.inactive(days: 120)])
    }

    @Test("Never suggests the current branch, the default branch, or remote branches")
    func protectedBranches() {
        let candidates = StaleBranchDetector.candidates(
            in: [
                branch("main", daysOld: 500),
                branch("feature", daysOld: 500, current: true, gone: true),
                branch("origin/old", daysOld: 500, remote: true),
            ],
            mergedNames: ["main", "feature", "origin/old"],
            defaultBranch: "main",
            inactiveAfterDays: 1,
            now: now
        )
        #expect(candidates.isEmpty)
    }

    @Test("The inactivity threshold is inclusive and can be turned off")
    func threshold() {
        let branches = [branch("exactly", daysOld: 30), branch("almost", daysOld: 29)]
        let enabled = StaleBranchDetector.candidates(
            in: branches,
            mergedNames: [],
            defaultBranch: "main",
            inactiveAfterDays: 30,
            now: now
        )
        let disabled = StaleBranchDetector.candidates(
            in: branches,
            mergedNames: [],
            defaultBranch: "main",
            inactiveAfterDays: nil,
            now: now
        )
        let zero = StaleBranchDetector.candidates(
            in: branches,
            mergedNames: [],
            defaultBranch: "main",
            inactiveAfterDays: 0,
            now: now
        )
        #expect(enabled.map(\.branch.name) == ["exactly"])
        #expect(disabled.isEmpty)
        #expect(zero.isEmpty)
    }
}

@Suite("Stale branches against real repositories", .tags(.integration))
struct StaleBranchIntegrationTests {
    private let service = GitService(runner: TemporaryRepository.isolatedRunner)

    /// A repository on `main` with an origin and branches `merged`, `gone`, `old` (unmerged, 200 days old),
    /// `wip` (unmerged, recent, pushed), and the current branch `current` (merged).
    private func makeRepository() async throws -> (local: TemporaryRepository, origin: TemporaryRepository) {
        let origin = try await TemporaryRepository.make(bare: true)
        let local = try await TemporaryRepository.make()
        try await local.commit("Initial commit")
        try await local.git(["remote", "add", "origin", origin.url.path])
        try await local.git(["push", "-q", "-u", "origin", "main"])
        try await local.git(["remote", "set-head", "origin", "main"])

        try await local.git(["branch", "merged"])

        try await local.git(["switch", "-q", "-c", "gone"])
        try await local.commit("Gone work", file: "gone.txt")
        try await local.git(["push", "-q", "-u", "origin", "gone"])
        try await local.git(["push", "-q", "origin", "--delete", "gone"])
        try await local.git(["fetch", "-q", "--prune"])

        try await local.git(["switch", "-q", "-c", "old", "main"])
        try local.write("old.txt", "old")
        try await local.git(["add", "old.txt"])
        let oldDate = ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-200 * 86_400))
        let backdated = ProcessGitRunner(
            environmentOverrides: TemporaryRepository.isolatedRunner.environmentOverrides.merging([
                "GIT_COMMITTER_DATE": oldDate, "GIT_AUTHOR_DATE": oldDate,
            ]) { _, new in new }
        )
        _ = try await backdated.run(["commit", "-q", "-m", "Old work"], in: local.url)

        try await local.git(["switch", "-q", "-c", "wip", "main"])
        try await local.commit("Work in progress", file: "wip.txt")
        try await local.git(["push", "-q", "-u", "origin", "wip"])

        try await local.git(["switch", "-q", "-c", "current", "main"])
        return (local, origin)
    }

    @Test("Report lists merged, gone, and inactive branches but not main or the current branch")
    func report() async throws {
        let (local, origin) = try await makeRepository()
        defer {
            local.remove()
            origin.remove()
        }

        let report = try await service.staleBranches(of: local.url, inactiveAfterDays: 90)

        #expect(report.defaultBranch == "main")
        #expect(report.currentBranch == "current")
        #expect(report.candidates.map(\.branch.name) == ["gone", "merged", "old"])
        #expect(report.candidates.first { $0.branch.name == "gone" }?.reasons == [.upstreamGone])
        #expect(report.candidates.first { $0.branch.name == "merged" }?.reasons == [.merged])
        #expect(report.candidates.first { $0.branch.name == "old" }?.reasons.count == 1)
    }

    @Test("Safe delete refuses unmerged work; force deletes it; main and current are always refused")
    func deletion() async throws {
        let (local, origin) = try await makeRepository()
        defer {
            local.remove()
            origin.remove()
        }
        let branches = try BranchListParser.parse(
            try await local.git(["for-each-ref", "--format=\(BranchListParser.format)", "refs/heads"])
        )
        func named(_ names: String...) -> [Branch] { branches.filter { names.contains($0.name) } }

        let safe = try await service.deleteBranches(
            named("merged", "old", "main", "current"),
            in: local.url,
            force: false,
            deleteRemote: false
        )
        #expect(safe.map(\.name) == ["current", "main", "merged", "old"])
        #expect(safe.filter { $0.error == nil }.map(\.name) == ["merged"])

        let forced = try await service.deleteBranches(
            named("old", "main"),
            in: local.url,
            force: true,
            deleteRemote: false
        )
        #expect(forced.filter { $0.error == nil }.map(\.name) == ["old"])

        let remaining = try await local.git(["for-each-ref", "--format=%(refname:short)", "refs/heads"])
        #expect(remaining.split(separator: "\n").sorted() == ["current", "gone", "main", "wip"])
    }

    @Test("Deleting with deleteRemote removes the upstream branch on the remote")
    func deleteRemote() async throws {
        let (local, origin) = try await makeRepository()
        defer {
            local.remove()
            origin.remove()
        }
        let wip = try #require(
            try BranchListParser.parse(
                try await local.git(["for-each-ref", "--format=\(BranchListParser.format)", "refs/heads/wip"])
            ).first
        )

        let results = try await service.deleteBranches([wip], in: local.url, force: true, deleteRemote: true)

        #expect(results == [BranchDeletionResult(name: "wip", deletedRemote: true)])
        let remoteBranches = try await origin.git(["for-each-ref", "--format=%(refname:short)", "refs/heads"])
        #expect(!remoteBranches.contains("wip"))
    }
}
