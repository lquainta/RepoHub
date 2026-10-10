import RepoHubCore
import SwiftUI

/// The main dashboard: every tracked repository and its status in a sortable table.
///
/// The sort and the column layout (visibility, order, widths) are remembered per window.
struct DashboardTable: View {
    let rows: [DashboardRow]
    let refreshing: Set<String>
    @Binding var selection: String?

    @SceneStorage("dashboard.sort") private var savedSort = DashboardSort.default
    @SceneStorage("dashboard.columns") private var columnCustomization = TableColumnCustomization<DashboardRow>()
    @State private var sortOrder = DashboardSort.default.comparators

    var body: some View {
        Table(
            rows.sorted(using: sortOrder),
            selection: $selection,
            sortOrder: $sortOrder,
            columnCustomization: $columnCustomization
        ) {
            TableColumn("Name", value: \.name) { row in
                NameCell(row: row, isRefreshing: refreshing.contains(row.id))
            }
            .width(min: 140, ideal: 200)
            .customizationID(DashboardColumn.name.rawValue)
            .disabledCustomizationBehavior(.visibility)

            TableColumn("Branch", value: \.branchSortKey) { row in
                if let status = row.status {
                    Label(StatusText.branch(status.head), systemImage: "arrow.triangle.branch")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                }
            }
            .width(min: 90, ideal: 140)
            .customizationID(DashboardColumn.branch.rawValue)

            TableColumn("Changes", value: \.changeCountSortKey) { row in
                ChangesCell(state: row.state)
            }
            .width(min: 90, ideal: 160)
            .customizationID(DashboardColumn.changes.rawValue)

            TableColumn("Ahead/Behind", value: \.syncSortKey) { row in
                if let status = row.status {
                    SyncCell(status: status)
                }
            }
            .width(min: 80, ideal: 110)
            .customizationID(DashboardColumn.sync.rawValue)

            TableColumn("Stashes", value: \.stashSortKey) { row in
                if let status = row.status, status.stashCount > 0 {
                    Label("\(status.stashCount)", systemImage: "tray.full")
                        .accessibilityLabel(Text("\(status.stashCount) stashes"))
                }
            }
            .width(min: 60, ideal: 70)
            .customizationID(DashboardColumn.stashes.rawValue)

            TableColumn("Last Commit", value: \.lastCommitSortKey) { row in
                if let commit = row.status?.lastCommit {
                    Text(commit.date, format: .relative(presentation: .named))
                        .help("\(commit.subject) — \(commit.author)")
                }
            }
            .width(min: 90, ideal: 120)
            .customizationID(DashboardColumn.lastCommit.rawValue)
        }
        .onAppear { sortOrder = savedSort.comparators }
        .onChange(of: sortOrder) { _, newValue in
            if let sort = DashboardSort(comparators: newValue) {
                savedSort = sort
            }
        }
        .accessibilityIdentifier("repositoryTable")
    }
}

/// Repository name and path, with an indicator while its status refreshes.
private struct NameCell: View {
    let row: DashboardRow
    let isRefreshing: Bool

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .fontWeight(.medium)
                Text(row.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if isRefreshing {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Refreshing")
            }
        }
        .help(row.path)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("repository-\(row.name)")
    }
}

/// Changed-file counts with an icon per kind. Counts are always shown as text.
private struct ChangesCell: View {
    let state: RepositoryStatusState?

    var body: some View {
        switch state {
        case nil:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Loading status")
        case .failed(let message):
            Label("Unavailable", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .help(message)
                .accessibilityLabel(Text("Status unavailable: \(message)"))
        case .loaded(let status) where status.isClean:
            Label("Clean", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .loaded(let status):
            HStack(spacing: 8) {
                count(status.changes.conflicted, systemImage: "exclamationmark.triangle.fill", tint: .red)
                count(status.changes.staged, systemImage: "plus.circle", tint: .green)
                count(status.changes.unstaged, systemImage: "pencil.circle", tint: .orange)
                count(status.changes.untracked, systemImage: "questionmark.circle", tint: .secondary)
            }
            .help(StatusText.changes(status.changes))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(StatusText.changes(status.changes))
        }
    }

    @ViewBuilder
    private func count(_ value: Int, systemImage: String, tint: Color) -> some View {
        if value > 0 {
            Label {
                Text(value, format: .number)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(tint)
            }
            .labelStyle(.titleAndIcon)
        }
    }
}

/// Commits ahead of and behind the upstream.
private struct SyncCell: View {
    let status: RepoStatus

    var body: some View {
        Group {
            if status.upstream == nil {
                Text("—")
                    .foregroundStyle(.secondary)
            } else if status.ahead == 0 && status.behind == 0 {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    if status.ahead > 0 {
                        Label("\(status.ahead)", systemImage: "arrow.up")
                    }
                    if status.behind > 0 {
                        Label("\(status.behind)", systemImage: "arrow.down")
                    }
                }
                .labelStyle(.titleAndIcon)
            }
        }
        .help(StatusText.sync(status))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StatusText.sync(status))
    }
}
