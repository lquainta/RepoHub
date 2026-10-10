import Foundation
import OSLog
import Observation
import RepoHubCore

/// Review-and-delete flow for one repository's stale branches.
///
/// Merged branches are preselected. Deleting any unmerged branch requires an
/// explicit force confirmation, so unmerged work is never lost by accident.
@MainActor
@Observable
final class StaleBranchModel: Identifiable {
    /// What the sheet shows.
    enum Phase: Equatable {
        case loading
        case reviewing
        /// The user must confirm force-deleting these unmerged branches.
        case confirmingForce([String])
        case deleting
        /// Deletion finished; failures (if any) are in ``failures``.
        case finished
        case failed(String)
    }

    /// The repository being cleaned up.
    let path: String
    nonisolated var id: String { path }
    private(set) var phase: Phase = .loading
    private(set) var report: StaleBranchReport?
    /// Names of the branches the user chose to delete.
    var selection: Set<String> = []
    /// Whether to delete each branch's upstream on the remote too.
    var deleteRemote = false
    /// Branches that couldn't be deleted, with the reason.
    private(set) var failures: [String: String] = [:]
    /// Branches that were deleted.
    private(set) var deleted: [String] = []

    private let git: any GitServicing
    private let inactiveAfterDays: Int?
    private let logger = Logger(subsystem: "com.lquainta.RepoHub", category: "Branches")

    init(path: String, git: any GitServicing = GitService(), inactiveAfterDays: Int?) {
        self.path = path
        self.git = git
        self.inactiveAfterDays = inactiveAfterDays
    }

    /// Candidates from the last load.
    var candidates: [StaleBranch] { report?.candidates ?? [] }

    /// Selected candidates that aren't merged into the default branch.
    var selectedUnmerged: [String] {
        candidates.filter { selection.contains($0.branch.name) && !$0.isMerged }.map(\.branch.name)
    }

    /// Finds stale branches and preselects the merged ones.
    func load() async {
        phase = .loading
        do {
            let report = try await git.staleBranches(of: url, inactiveAfterDays: inactiveAfterDays)
            self.report = report
            selection = Set(report.candidates.filter(\.isMerged).map(\.branch.name))
            phase = .reviewing
        } catch let error as GitError {
            phase = .failed(StatusText.message(for: error))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Deletes the selected branches, first asking to confirm any unmerged ones.
    func deleteSelected() async {
        let unmerged = selectedUnmerged
        if !unmerged.isEmpty {
            phase = .confirmingForce(unmerged)
            return
        }
        await delete(force: false)
    }

    /// Deletes the selected branches, including unmerged ones, after the user confirmed.
    func confirmForceDelete() async {
        guard case .confirmingForce = phase else {
            return
        }
        await delete(force: true)
    }

    /// Returns to the review list without deleting.
    func cancelForceDelete() {
        if case .confirmingForce = phase {
            phase = .reviewing
        }
    }

    private var url: URL { URL(fileURLWithPath: path, isDirectory: true) }

    private func delete(force: Bool) async {
        let branches = candidates.map(\.branch).filter { selection.contains($0.name) }
        guard !branches.isEmpty else {
            return
        }
        phase = .deleting
        do {
            let results = try await git.deleteBranches(branches, in: url, force: force, deleteRemote: deleteRemote)
            deleted = results.filter { $0.error == nil }.map(\.name)
            failures = Dictionary(
                uniqueKeysWithValues: results.compactMap { result in
                    result.error.map { (result.name, StatusText.message(for: $0)) }
                }
            )
            logger.info("Deleted \(self.deleted.count) branches, \(self.failures.count) failed")
            phase = .finished
        } catch let error as GitError {
            phase = .failed(StatusText.message(for: error))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
