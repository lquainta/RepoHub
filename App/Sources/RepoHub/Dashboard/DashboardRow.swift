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
    case name, branch, changes, sync, stashes, lastCommit

    /// The comparator the table uses for this column.
    func comparator(order: SortOrder) -> KeyPathComparator<DashboardRow> {
        switch self {
        case .name: KeyPathComparator(\.name, comparator: .localizedStandard, order: order)
        case .branch: KeyPathComparator(\.branchSortKey, comparator: .localizedStandard, order: order)
        case .changes: KeyPathComparator(\.changeCountSortKey, order: order)
        case .sync: KeyPathComparator(\.syncSortKey, order: order)
        case .stashes: KeyPathComparator(\.stashSortKey, order: order)
        case .lastCommit: KeyPathComparator(\.lastCommitSortKey, order: order)
        }
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
