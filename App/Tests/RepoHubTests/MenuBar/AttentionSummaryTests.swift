import Foundation
import RepoHubCore
import Testing

@testable import RepoHub

@Suite("AttentionSummary")
struct AttentionSummaryTests {
    private func row(_ name: String, _ state: RepositoryStatusState?) -> DashboardRow {
        DashboardRow(id: "/r/\(name)", name: name, path: "/r/\(name)", state: state)
    }

    private func status(changes: FileChangeCounts = .init(), ahead: Int = 0, behind: Int = 0) -> RepositoryStatusState {
        .loaded(
            RepoStatus(head: .branch("main"), upstream: "origin/main", ahead: ahead, behind: behind, changes: changes)
        )
    }

    @Test("Counts match the dashboard's rows and attention is ordered by urgency, then name")
    func countsAndOrder() {
        let summary = AttentionSummary(rows: [
            row("clean", status()),
            row("zeta-dirty", status(changes: .init(unstaged: 1))),
            row("Alpha-dirty", status(changes: .init(untracked: 2), ahead: 1)),
            row("behind", status(behind: 2)),
            row("conflict", status(changes: .init(conflicted: 1))),
            row("unpushed", status(ahead: 3)),
            row("broken", .failed("not a repository")),
            row("loading", nil),
        ])

        #expect(summary.dirty == 3)
        #expect(summary.behind == 1)
        #expect(summary.ahead == 2)
        #expect(summary.conflicted == 1)
        #expect(summary.failed == 1)
        #expect(summary.rows.map(\.name) == ["conflict", "behind", "Alpha-dirty", "zeta-dirty", "unpushed", "broken"])
        #expect(summary.count == 6)
    }

    @Test("Nothing needs attention when every repository is clean and in sync")
    func allClean() {
        let summary = AttentionSummary(rows: [row("a", status()), row("b", status())])
        #expect(summary == AttentionSummary(rows: []))
        #expect(summary.rows.isEmpty)
    }

    @Test("The summary agrees with the dashboard's quick filters")
    func matchesFilters() {
        let rows = [
            row("a", status(changes: .init(staged: 1), behind: 1)),
            row("b", status(ahead: 2)),
            row("c", status()),
        ]
        let summary = AttentionSummary(rows: rows)
        #expect(summary.dirty == RepositoryFilter(quickFilters: [.dirty]).apply(to: rows).count)
        #expect(summary.behind == RepositoryFilter(quickFilters: [.behind]).apply(to: rows).count)
        #expect(summary.ahead == RepositoryFilter(quickFilters: [.ahead]).apply(to: rows).count)
    }
}
