import Foundation

/// Counts and a list of repositories that need attention, computed from the
/// same rows as the dashboard so the menu bar always agrees with it.
struct AttentionSummary: Equatable {
    /// Repositories with uncommitted changes (including conflicts).
    var dirty = 0
    /// Repositories behind their upstream.
    var behind = 0
    /// Repositories ahead of their upstream (unpushed commits).
    var ahead = 0
    /// Repositories with merge conflicts.
    var conflicted = 0
    /// Repositories whose status couldn't be read.
    var failed = 0
    /// Rows needing attention: conflicts first, then behind, dirty, ahead, failed; by name within each.
    var rows: [DashboardRow] = []

    /// Total number of repositories needing attention, shown next to the menu bar icon.
    var count: Int { rows.count }

    init(rows: [DashboardRow]) {
        var ranked: [(rank: Int, row: DashboardRow)] = []
        for row in rows {
            if case .failed = row.state {
                failed += 1
            } else if let status = row.status {
                if status.changes.conflicted > 0 { conflicted += 1 }
                if !status.isClean { dirty += 1 }
                if status.behind > 0 { behind += 1 }
                if status.ahead > 0 { ahead += 1 }
            }
            if let rank = Self.rank(of: row) {
                ranked.append((rank, row))
            }
        }
        self.rows = ranked.sorted {
            ($0.rank, $0.row.name.localizedLowercase) < ($1.rank, $1.row.name.localizedLowercase)
        }.map(\.row)
    }

    /// Sort rank for a row needing attention, or `nil` if it doesn't need any.
    private static func rank(of row: DashboardRow) -> Int? {
        if case .failed = row.state {
            return 4
        }
        guard let status = row.status else {
            return nil
        }
        if status.changes.conflicted > 0 { return 0 }
        if status.behind > 0 { return 1 }
        if !status.isClean { return 2 }
        if status.ahead > 0 { return 3 }
        return nil
    }
}
