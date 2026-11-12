import Foundation
import RepoHubCore

/// One row of the dashboard table: a tracked repository and its status.
///
/// Sort keys place repositories whose status is unknown after those with a status.
struct DashboardRow: Identifiable, Equatable {
    /// The repository's path, which is unique.
    let id: String
    /// Display name.
    let name: String
    /// Absolute path of the working tree.
    let path: String
    /// The latest known status, or `nil` if it hasn't been read yet.
    let state: RepositoryStatusState?
    /// Remote and stale-branch counts, or `nil` if unknown.
    var facts: RepositoryFacts?
    /// Pull requests and CI from GitHub, or `nil` when signed out or not on GitHub.
    var gitHub: GitHubRepositoryStatus?

    /// The checked-out branch, or `nil` for a detached HEAD or unknown status.
    var currentBranch: String? {
        switch status?.head {
        case .branch(let name), .unborn(let name): name
        case .detached, nil: nil
        }
    }

    /// Higher needs more attention: failing CI, then review requests, then
    /// running CI, then other GitHub repositories, then the rest.
    var gitHubSortKey: Int {
        guard let gitHub, gitHub.error == nil else {
            return -1
        }
        if gitHub.checks?.state == .failure {
            return 3
        }
        if !gitHub.reviewRequests.isEmpty {
            return 2
        }
        return gitHub.checks?.state == .pending ? 1 : 0
    }

    /// The status, if it was read successfully.
    var status: RepoStatus? {
        if case .loaded(let status) = state {
            return status
        }
        return nil
    }

    /// Branch name; detached heads sort by commit.
    var branchSortKey: String {
        switch status?.head {
        case .branch(let name), .unborn(let name): name
        case .detached(let commit): "~detached \(commit)"
        case nil: "~~"
        }
    }

    /// Total changed paths, or `Int.max` when unknown.
    var changeCountSortKey: Int {
        guard let changes = status?.changes else {
            return .max
        }
        return changes.staged + changes.unstaged + changes.untracked + changes.conflicted
    }

    /// Commits ahead plus behind; `Int.max` when unknown or without upstream.
    var syncSortKey: Int {
        guard let status, status.upstream != nil else {
            return .max
        }
        return status.ahead + status.behind
    }

    /// Stash entries, or `Int.max` when unknown.
    var stashSortKey: Int {
        status?.stashCount ?? .max
    }

    /// Date of the last commit, or the distant past when unknown.
    var lastCommitSortKey: Date {
        status?.lastCommit?.date ?? .distantPast
    }
}

/// A dashboard column that can be sorted.
enum DashboardColumn: String, CaseIterable {
    case name, branch, changes, sync, stashes, lastCommit, gitHub

    /// The comparator the table uses for this column.
    func comparator(order: SortOrder) -> KeyPathComparator<DashboardRow> {
        switch self {
        case .name: KeyPathComparator(\.name, comparator: .localizedStandard, order: order)
        case .branch: KeyPathComparator(\.branchSortKey, comparator: .localizedStandard, order: order)
        case .changes: KeyPathComparator(\.changeCountSortKey, order: order)
        case .sync: KeyPathComparator(\.syncSortKey, order: order)
        case .stashes: KeyPathComparator(\.stashSortKey, order: order)
        case .lastCommit: KeyPathComparator(\.lastCommitSortKey, order: order)
        case .gitHub: KeyPathComparator(\.gitHubSortKey, order: order)
        }
    }

    /// The narrowest the column gets (its `TableColumn.width(min:)`).
    var minWidth: CGFloat {
        switch self {
        case .name: 140
        case .branch: 90
        case .changes: 90
        case .sync: 80
        case .stashes: 60
        case .lastCommit: 90
        case .gitHub: 70
        }
    }

    /// The order columns are dropped in when the table gets narrow, least
    /// important first. The name is never dropped.
    static let hidingOrder: [DashboardColumn] = [.stashes, .sync, .lastCommit, .gitHub, .branch, .changes]

    /// Padding and divider the table adds to each column.
    static let columnSpacing: CGFloat = 10

    /// The columns that fit side by side, at their minimum widths, in a table
    /// `width` points wide, so a narrow window drops columns instead of
    /// scrolling sideways (#59).
    ///
    /// Columns the user hid take no space. Before the table is measured
    /// (`width` 0), every column is shown.
    static func fitting(width: CGFloat, hidden: Set<DashboardColumn> = []) -> Set<DashboardColumn> {
        var shown = Set(allCases).subtracting(hidden)
        guard width > 0 else {
            return shown
        }
        func needed() -> CGFloat { shown.reduce(0) { $0 + $1.minWidth + columnSpacing } }
        for column in hidingOrder where needed() > width {
            shown.remove(column)
        }
        return shown
    }

    /// The column a comparator sorts by.
    init?(comparator: KeyPathComparator<DashboardRow>) {
        guard
            let column = Self.allCases.first(where: { $0.comparator(order: .forward).keyPath == comparator.keyPath })
        else {
            return nil
        }
        self = column
    }
}

/// The dashboard's sort, persisted as a string such as `"changes:desc"`.
struct DashboardSort: Equatable, RawRepresentable {
    /// The column to sort by.
    var column: DashboardColumn
    /// Ascending (`.forward`) or descending (`.reverse`).
    var order: SortOrder

    /// Sorted by name, A to Z.
    static let `default` = DashboardSort(column: .name, order: .forward)

    init(column: DashboardColumn, order: SortOrder) {
        self.column = column
        self.order = order
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":")
        guard parts.count == 2, let column = DashboardColumn(rawValue: String(parts[0])) else {
            return nil
        }
        switch parts[1] {
        case "asc": self.init(column: column, order: .forward)
        case "desc": self.init(column: column, order: .reverse)
        default: return nil
        }
    }

    var rawValue: String {
        "\(column.rawValue):\(order == .forward ? "asc" : "desc")"
    }

    /// The table's sort order: this column first, then name as a tie-breaker.
    var comparators: [KeyPathComparator<DashboardRow>] {
        var result = [column.comparator(order: order)]
        if column != .name {
            result.append(DashboardColumn.name.comparator(order: .forward))
        }
        return result
    }

    /// The sort a table's comparators describe (its first comparator), or `nil` if unknown.
    init?(comparators: [KeyPathComparator<DashboardRow>]) {
        guard let first = comparators.first, let column = DashboardColumn(comparator: first) else {
            return nil
        }
        self.init(column: column, order: first.order)
    }
}
