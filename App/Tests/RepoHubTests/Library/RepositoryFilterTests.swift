import Foundation
import RepoHubCore
import Testing

@testable import RepoHub

@Suite("RepositoryFilter")
struct RepositoryFilterTests {
    private static func row(
        _ name: String,
        path: String? = nil,
        branch: String = "main",
        changes: FileChangeCounts = FileChangeCounts(),
        ahead: Int = 0,
        behind: Int = 0,
        stashes: Int = 0,
        facts: RepositoryFacts? = RepositoryFacts(remoteCount: 1, staleBranchCount: 0),
        known: Bool = true
    ) -> DashboardRow {
        let status = RepoStatus(
            head: .branch(branch),
            upstream: "origin/\(branch)",
            ahead: ahead,
            behind: behind,
            changes: changes,
            stashCount: stashes
        )
        return DashboardRow(
            id: path ?? "/dev/\(name)",
            name: name,
            path: path ?? "/dev/\(name)",
            state: known ? .loaded(status) : nil,
            facts: facts
        )
    }

    private let rows: [DashboardRow]

    init() {
        rows = [
            Self.row("api", branch: "feature/login", changes: FileChangeCounts(unstaged: 1)),
            Self.row("web", path: "/school/cs471/web", ahead: 2),
            Self.row("Résumé", behind: 3, stashes: 1),
            Self.row("tools", facts: RepositoryFacts(remoteCount: 0, staleBranchCount: 2)),
            Self.row("pending", known: false),
        ]
    }

    private func names(_ filter: RepositoryFilter) -> [String] {
        filter.apply(to: rows).map(\.name)
    }

    @Test("An empty filter keeps every row")
    func emptyFilter() {
        #expect(names(RepositoryFilter()) == rows.map(\.name))
        #expect(!RepositoryFilter().isActive)
        #expect(!RepositoryFilter(searchText: "   ").isActive)
    }

    @Test("Search matches name, path, or branch, ignoring case and accents; every word must match")
    func search() {
        #expect(names(RepositoryFilter(searchText: "API")) == ["api"])
        #expect(names(RepositoryFilter(searchText: "cs471")) == ["web"])
        #expect(names(RepositoryFilter(searchText: "login")) == ["api"])
        #expect(names(RepositoryFilter(searchText: "resume")) == ["Résumé"])
        #expect(names(RepositoryFilter(searchText: "school web")) == ["web"])
        #expect(names(RepositoryFilter(searchText: "school api")).isEmpty)
    }

    @Test(
        "Each quick filter selects the matching repositories",
        arguments: [
            (QuickFilter.dirty, ["api"]),
            (.ahead, ["web"]),
            (.behind, ["Résumé"]),
            (.stashes, ["Résumé"]),
            (.staleBranches, ["tools"]),
            (.noRemote, ["tools"]),
        ]
    )
    func quickFilter(filter: QuickFilter, expected: [String]) {
        #expect(names(RepositoryFilter(quickFilters: [filter])) == expected)
    }

    @Test("Filters and search combine: every condition must match")
    func combined() {
        #expect(names(RepositoryFilter(quickFilters: [.behind, .stashes])) == ["Résumé"])
        #expect(names(RepositoryFilter(quickFilters: [.behind, .ahead])).isEmpty)
        #expect(names(RepositoryFilter(searchText: "web", quickFilters: [.ahead])) == ["web"])
        #expect(names(RepositoryFilter(searchText: "api", quickFilters: [.ahead])).isEmpty)
    }

    @Test("Repositories with unknown status or facts don't match quick filters")
    func unknownExcluded() {
        let unknown = [Self.row("x", facts: nil, known: false)]
        for filter in QuickFilter.allCases {
            #expect(RepositoryFilter(quickFilters: [filter]).apply(to: unknown).isEmpty)
        }
    }
}
