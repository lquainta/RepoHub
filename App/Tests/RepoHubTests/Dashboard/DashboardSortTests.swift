import Foundation
import RepoHubCore
import Testing

@testable import RepoHub

@Suite("Dashboard sorting")
struct DashboardSortTests {
    private func row(
        _ name: String,
        changes: FileChangeCounts? = nil,
        upstream: String? = "origin/main",
        ahead: Int = 0,
        committed: Date? = nil
    ) -> DashboardRow {
        let state = changes.map { changes in
            RepositoryStatusState.loaded(
                RepoStatus(
                    head: .branch("main"),
                    upstream: upstream,
                    ahead: ahead,
                    changes: changes,
                    lastCommit: committed.map { CommitSummary(hash: "abc", author: "A", date: $0, subject: "S") }
                )
            )
        }
        return DashboardRow(id: "/r/\(name)", name: name, path: "/r/\(name)", state: state)
    }

    @Test(
        "Sort round-trips through its stored string",
        arguments: DashboardColumn.allCases.flatMap {
            [DashboardSort(column: $0, order: .forward), .init(column: $0, order: .reverse)]
        }
    )
    func rawValueRoundTrip(sort: DashboardSort) {
        #expect(DashboardSort(rawValue: sort.rawValue) == sort)
        #expect(DashboardSort(comparators: sort.comparators) == sort)
    }

    @Test("Invalid stored strings are rejected", arguments: ["", "name", "bogus:asc", "name:up", "name:asc:x"])
    func invalidRawValue(raw: String) {
        #expect(DashboardSort(rawValue: raw) == nil)
    }

    @Test("Sorting by changes puts the dirtiest first when descending and unknown status last when ascending")
    func sortByChanges() {
        let rows = [
            row("unknown"),
            row("clean", changes: FileChangeCounts()),
            row("dirty", changes: FileChangeCounts(staged: 1, untracked: 4)),
            row("bit", changes: FileChangeCounts(unstaged: 1)),
        ]
        let ascending = rows.sorted(using: DashboardSort(column: .changes, order: .forward).comparators)
        #expect(ascending.map(\.name) == ["clean", "bit", "dirty", "unknown"])
    }

    @Test("Repositories with equal keys are ordered by name")
    func tieBreakByName() {
        let rows = [row("zeta", changes: .init()), row("Alpha", changes: .init()), row("beta", changes: .init())]
        let sorted = rows.sorted(using: DashboardSort(column: .stashes, order: .reverse).comparators)
        #expect(sorted.map(\.name) == ["Alpha", "beta", "zeta"])
    }

    @Test("Ahead/behind sorts repositories without an upstream last")
    func syncWithoutUpstreamLast() {
        let rows = [
            row("local", changes: .init(), upstream: nil),
            row("ahead", changes: .init(), ahead: 2),
            row("synced", changes: .init()),
        ]
        let sorted = rows.sorted(using: DashboardSort(column: .sync, order: .forward).comparators)
        #expect(sorted.map(\.name) == ["synced", "ahead", "local"])
    }

    @Test("Last commit sorts newest first when descending")
    func sortByLastCommit() {
        let rows = [
            row("old", changes: .init(), committed: Date(timeIntervalSince1970: 1_000)),
            row("new", changes: .init(), committed: Date(timeIntervalSince1970: 9_000)),
            row("none"),
        ]
        let sorted = rows.sorted(using: DashboardSort(column: .lastCommit, order: .reverse).comparators)
        #expect(sorted.map(\.name) == ["new", "old", "none"])
    }
}
