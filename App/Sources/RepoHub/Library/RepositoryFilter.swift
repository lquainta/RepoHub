import Foundation

/// A one-click filter in the dashboard's Filter menu.
enum QuickFilter: String, CaseIterable, Identifiable, Codable {
    case dirty, behind, ahead, stashes, staleBranches, noRemote

    var id: Self { self }

    /// Menu title.
    var title: String {
        switch self {
        case .dirty: String(localized: "Uncommitted Changes")
        case .behind: String(localized: "Behind Remote")
        case .ahead: String(localized: "Ahead of Remote")
        case .stashes: String(localized: "Has Stashes")
        case .staleBranches: String(localized: "Has Stale Branches")
        case .noRemote: String(localized: "No Remote")
        }
    }

    /// SF Symbol shown in the menu.
    var systemImage: String {
        switch self {
        case .dirty: "pencil.circle"
        case .behind: "arrow.down"
        case .ahead: "arrow.up"
        case .stashes: "tray.full"
        case .staleBranches: "scissors"
        case .noRemote: "icloud.slash"
        }
    }
}

/// What the sidebar is showing.
enum SidebarScope: Hashable {
    /// Every tracked repository.
    case all
    /// Repositories in the group with this name.
    case group(String)
    /// Repositories found in the scan folder at this path.
    case folder(String)
}

/// Search text and quick filters for the dashboard. All conditions must match.
struct RepositoryFilter: Equatable {
    /// Matches name, path, or branch; every word must match, ignoring case and accents.
    var searchText = ""
    /// Every selected filter must match. A repository whose status (or, for
    /// remote and stale-branch filters, facts) isn't known yet doesn't match.
    var quickFilters: Set<QuickFilter> = []

    /// Whether any search text or filter is active.
    var isActive: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty || !quickFilters.isEmpty
    }

    /// Returns the rows that match.
    func apply(to rows: [DashboardRow]) -> [DashboardRow] {
        let words = searchText.split(whereSeparator: \.isWhitespace).map(String.init)
        return rows.filter { row in
            matchesSearch(row, words: words) && quickFilters.allSatisfy { matches(row, filter: $0) }
        }
    }

    private func matchesSearch(_ row: DashboardRow, words: [String]) -> Bool {
        let fields = [row.name, row.path, row.status?.head.branchName ?? ""]
        return words.allSatisfy { word in
            fields.contains { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    private func matches(_ row: DashboardRow, filter: QuickFilter) -> Bool {
        switch filter {
        case .dirty: row.status.map { !$0.isClean } ?? false
        case .behind: (row.status?.behind ?? 0) > 0
        case .ahead: (row.status?.ahead ?? 0) > 0
        case .stashes: (row.status?.stashCount ?? 0) > 0
        case .staleBranches: (row.facts?.staleBranchCount ?? 0) > 0
        case .noRemote: row.facts?.remoteCount == 0
        }
    }
}
