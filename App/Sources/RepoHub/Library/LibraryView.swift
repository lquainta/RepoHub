import SwiftUI
import UniformTypeIdentifiers

/// Main window: scan folders in the sidebar, discovered repositories in the detail.
struct LibraryView: View {
    @Bindable var model: LibraryViewModel
    @State private var isImporting = false
    @State private var groupPrompt: GroupPrompt?

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(model: model, groupPrompt: $groupPrompt)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            RepositoryList(model: model, isImporting: $isImporting, groupPrompt: $groupPrompt)
                .navigationSplitViewColumnWidth(min: 420, ideal: 640)
                .searchable(text: $model.filter.searchText, placement: .toolbar, prompt: "Name, path, or branch")
        } detail: {
            RepositoryDetailView(model: model.detail, name: model.selectedRepository?.name)
                .navigationSplitViewColumnWidth(min: 280, ideal: 360)
        }
        .toolbar {
            ToolbarItem {
                QuickFilterMenu(filters: $model.filter.quickFilters)
            }
            ToolbarItemGroup {
                if let progress = model.actions.fetchAllProgress {
                    ProgressView(value: Double(progress.completed), total: Double(progress.total)) {
                        Text("Fetching \(progress.completed) of \(progress.total)")
                    }
                    .progressViewStyle(.linear)
                    .frame(width: 140)
                    .font(.caption)
                }
                Button("Fetch All", systemImage: "arrow.down.circle.dotted") {
                    Task { await model.fetchAll() }
                }
                .disabled(model.repositories.isEmpty || model.actions.fetchAllProgress != nil)
                if model.isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Scanning")
                }
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.rescanAll() }
                }
                .keyboardShortcut("r")
                .disabled(model.isScanning || model.folders.isEmpty)
                Button("Add Folder", systemImage: "plus") {
                    isImporting = true
                }
                .keyboardShortcut("o")
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task { await model.addFolders(urls) }
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(item: Bindable(model.actions).branchCleanup) { cleanup in
            StaleBranchSheet(
                model: cleanup,
                repositoryName: URL(fileURLWithPath: cleanup.path).lastPathComponent
            ) {
                Task { await model.actions.branchCleanupFinished(cleanup.path) }
            }
        }
        .alert(
            "Some actions failed",
            isPresented: Binding(
                get: { !model.actions.failures.isEmpty },
                set: { if !$0 { model.actions.failures = [] } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actions.failures.map { "\($0.repository): \($0.message)" }.joined(separator: "\n"))
        }
        .modifier(GroupNameAlert(prompt: $groupPrompt, model: model))
        .frame(minWidth: 960, minHeight: 480)
    }
}

/// The repository dashboard, or an empty state.
private struct RepositoryList: View {
    let model: LibraryViewModel
    @Binding var isImporting: Bool
    @Binding var groupPrompt: GroupPrompt?

    var body: some View {
        let rows = model.visibleRows
        if model.folders.isEmpty {
            ContentUnavailableView {
                Label("No Folders", systemImage: "folder.badge.plus")
            } description: {
                Text("Add a folder and RepoHub will find the git repositories inside it.")
            } actions: {
                Button("Add Folder…") { isImporting = true }
            }
            .accessibilityIdentifier("emptyState")
        } else if model.repositories.isEmpty && !model.isScanning {
            ContentUnavailableView(
                "No Repositories Found",
                systemImage: "magnifyingglass",
                description: Text("None of your folders contain git repositories.")
            )
        } else if rows.isEmpty && model.filter.isActive {
            ContentUnavailableView {
                Label("No Matches", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("No repositories here match your search and filters.")
            } actions: {
                Button("Clear Search and Filters") { model.filter = RepositoryFilter() }
            }
            .accessibilityIdentifier("noMatches")
        } else if rows.isEmpty, case .group(let name) = model.scope {
            ContentUnavailableView(
                "\(name) Is Empty",
                systemImage: "tag",
                description: Text("Right-click a repository and choose Add to Group, or drag it here.")
            )
        } else {
            DashboardTable(
                rows: rows,
                refreshing: model.statuses.refreshing.union(model.actions.busy),
                actions: model.actions,
                selection: Binding(
                    get: { model.selectedPath },
                    set: { path in Task { await model.select(path) } }
                )
            ) { paths in
                GroupMenu(model: model, paths: paths, groupPrompt: $groupPrompt)
            }
        }
    }
}
