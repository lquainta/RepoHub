import Foundation
import RepoHubCore
import Testing

@testable import RepoHub

@MainActor
@Suite("StaleBranchModel")
struct StaleBranchModelTests {
    private func candidate(_ name: String, _ reasons: [StaleReason]) -> StaleBranch {
        StaleBranch(
            branch: Branch(name: name, upstream: "origin/\(name)", commit: "abc", lastCommitDate: .now),
            reasons: reasons
        )
    }

    private func makeModel() async -> (StaleBranchModel, FakeGit) {
        let git = FakeGit()
        await git.setStaleReport(
            StaleBranchReport(
                defaultBranch: "main",
                currentBranch: "main",
                candidates: [
                    candidate("merged", [.merged]),
                    candidate("gone", [.upstreamGone]),
                    candidate("old", [.inactive(days: 200)]),
                ]
            )
        )
        let model = StaleBranchModel(path: "/repos/api", git: git, inactiveAfterDays: 90)
        await model.load()
        return (model, git)
    }

    @Test("Loading preselects only merged branches")
    func preselectsMerged() async {
        let (model, _) = await makeModel()
        #expect(model.phase == .reviewing)
        #expect(model.selection == ["merged"])
        #expect(model.selectedUnmerged.isEmpty)
    }

    @Test("Deleting merged branches doesn't ask for confirmation and never forces")
    func deleteMerged() async {
        let (model, git) = await makeModel()
        await model.deleteSelected()

        #expect(model.phase == .finished)
        #expect(model.deleted == ["merged"])
        let deletions = await git.deletions
        #expect(deletions.count == 1)
        #expect(deletions.first?.names == ["merged"] && deletions.first?.force == false)
    }

    @Test("Selecting unmerged branches requires confirmation before force deleting")
    func unmergedNeedsConfirmation() async {
        let (model, git) = await makeModel()
        model.selection = ["merged", "old"]

        await model.deleteSelected()
        #expect(model.phase == .confirmingForce(["old"]))
        #expect(await git.deletions.isEmpty)

        await model.confirmForceDelete()
        #expect(model.phase == .finished)
        let deletions = await git.deletions
        #expect(deletions.first?.force == true)
        #expect(deletions.first?.names.sorted() == ["merged", "old"])
    }

    @Test("Cancelling the confirmation deletes nothing")
    func cancelConfirmation() async {
        let (model, git) = await makeModel()
        model.selection = ["gone"]

        await model.deleteSelected()
        model.cancelForceDelete()
        await model.confirmForceDelete()

        #expect(model.phase == .reviewing)
        #expect(await git.deletions.isEmpty)
    }

    @Test("Failures are reported per branch and remote deletion is passed through")
    func failuresAndRemote() async {
        let (model, git) = await makeModel()
        await git.setUndeletable(["merged"])
        model.deleteRemote = true

        await model.deleteSelected()

        #expect(model.deleted.isEmpty)
        #expect(model.failures.keys.sorted() == ["merged"])
        #expect(await git.deletions.first?.deleteRemote == true)
    }
}
