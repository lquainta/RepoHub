import Foundation
import Testing

@testable import RepoHub

@Suite("Dashboard columns at narrow widths")
struct DashboardColumnFittingTests {
    /// The width every column in `columns` needs, at minimum widths.
    private func needed(_ columns: Set<DashboardColumn>) -> CGFloat {
        columns.reduce(0) { $0 + $1.minWidth + DashboardColumn.columnSpacing }
    }

    @Test("Before the table is measured, every column is shown")
    func unmeasured() {
        #expect(DashboardColumn.fitting(width: 0) == Set(DashboardColumn.allCases))
    }

    @Test("A table wide enough for every column shows them all")
    func wide() {
        let all = Set(DashboardColumn.allCases)
        #expect(DashboardColumn.fitting(width: needed(all)) == all)
        #expect(DashboardColumn.fitting(width: 2000) == all)
    }

    @Test("Columns are dropped least important first")
    func dropsInOrder() {
        var expected = Set(DashboardColumn.allCases)
        for column in DashboardColumn.hidingOrder {
            // One point short of fitting the current set drops the next column.
            let shown = DashboardColumn.fitting(width: needed(expected) - 1)
            expected.remove(column)
            #expect(shown == expected, "Expected \(column) to be dropped next")
        }
    }

    @Test("The name is shown at any width", arguments: [1, 50, 140, 300] as [CGFloat])
    func nameAlwaysShown(width: CGFloat) {
        #expect(DashboardColumn.fitting(width: width).contains(.name))
    }

    @Test("Every column except the name can be dropped")
    func hidingOrderCoversOptionalColumns() {
        #expect(Set(DashboardColumn.hidingOrder) == Set(DashboardColumn.allCases).subtracting([.name]))
        #expect(DashboardColumn.hidingOrder.count == DashboardColumn.allCases.count - 1)
    }

    @Test("Columns the user hid stay hidden and leave room for the others")
    func userHidden() {
        let hidden: Set<DashboardColumn> = [.branch, .changes]
        let rest = Set(DashboardColumn.allCases).subtracting(hidden)
        // Too narrow for every column, but wide enough once the hidden ones
        // don't count: nothing else is dropped.
        let shown = DashboardColumn.fitting(width: needed(rest), hidden: hidden)
        #expect(shown == rest)
        #expect(DashboardColumn.fitting(width: 0, hidden: hidden) == rest)
    }

    @Test("The default content column fits every column")
    func defaultWidthShowsAll() {
        // LibraryView's content column is 700 points wide by default.
        #expect(DashboardColumn.fitting(width: 700) == Set(DashboardColumn.allCases))
    }
}
