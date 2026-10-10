import SwiftUI

/// The menu bar window: a summary of every repository and the ones that need attention.
struct MenuBarContent: View {
    let library: LibraryViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let summary = AttentionSummary(rows: library.rows)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Count(value: summary.dirty, title: "Uncommitted", systemImage: "pencil.circle")
                Count(value: summary.behind, title: "Behind", systemImage: "arrow.down.circle")
                Count(value: summary.ahead, title: "Unpushed", systemImage: "arrow.up.circle")
                if summary.conflicted > 0 {
                    Count(value: summary.conflicted, title: "Conflicts", systemImage: "exclamationmark.triangle")
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            if library.repositories.isEmpty {
                Text("Add a folder in RepoHub to see your repositories here.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else if summary.rows.isEmpty {
                Label("Everything is committed and up to date", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(summary.rows) { row in
                            AttentionRow(row: row, actions: library.actions)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            Divider()

            HStack {
                Button("Open RepoHub") {
                    openDashboard()
                }
                Spacer()
                Button("Fetch All", systemImage: "arrow.down.circle.dotted") {
                    Task { await library.fetchAll() }
                }
                .disabled(library.repositories.isEmpty || library.actions.fetchAllProgress != nil)
                Button("Quit", systemImage: "power") { NSApplication.shared.terminate(nil) }
                    .labelStyle(.iconOnly)
                    .help("Quit RepoHub")
            }
        }
        .padding(12)
        .frame(width: 340)
        .accessibilityIdentifier("menuBarSummary")
    }

    private func openDashboard() {
        openWindow(id: RepoHubApp.mainWindowID)
        NSApplication.shared.activate()
        dismiss()
    }
}

private struct Count: View {
    let value: Int
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage).foregroundStyle(.secondary)
            Text(value, format: .number).font(.title3.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A repository needing attention, with its status in words and quick actions.
private struct AttentionRow: View {
    let row: DashboardRow
    let actions: RepositoryActions

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).fontWeight(.medium)
                Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Menu {
                RepositoryMenu(actions: actions, paths: [row.id])
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Actions for \(row.name)")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            Task { await actions.openInEditor(row.id) }
        }
    }

    private var description: String {
        switch row.state {
        case .failed(let message): return message
        case .loaded(let status):
            var parts: [String] = []
            if !status.isClean { parts.append(StatusText.changes(status.changes)) }
            if status.upstream != nil && (status.ahead > 0 || status.behind > 0) {
                parts.append(StatusText.sync(status))
            }
            return parts.joined(separator: " · ")
        case nil: return ""
        }
    }
}

/// The menu bar icon: a symbol, plus the number of repositories needing attention.
struct MenuBarLabel: View {
    let library: LibraryViewModel

    var body: some View {
        let count = AttentionSummary(rows: library.rows).count
        if count > 0 {
            Label("\(count)", systemImage: "arrow.triangle.branch")
                .labelStyle(.titleAndIcon)
                .accessibilityLabel("RepoHub: \(count) repositories need attention")
        } else {
            Image(systemName: "arrow.triangle.branch")
                .accessibilityLabel("RepoHub")
        }
    }
}
