import SwiftUI
import UniformTypeIdentifiers

/// Main window: scan folders in the sidebar, discovered repositories in the detail.
struct LibraryView: View {
    @Bindable var model: LibraryViewModel
    @State private var isImporting = false

    var body: some View {
        NavigationSplitView {
            FolderSidebar(model: model, isImporting: $isImporting)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            RepositoryList(model: model, isImporting: $isImporting)
        }
        .toolbar {
            ToolbarItemGroup {
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
        .frame(minWidth: 700, minHeight: 420)
    }
}

/// Sidebar listing scan folders.
private struct FolderSidebar: View {
    let model: LibraryViewModel
    @Binding var isImporting: Bool

    var body: some View {
        List {
            Section("Folders") {
                ForEach(model.folders) { folder in
                    Label(URL(fileURLWithPath: folder.path).lastPathComponent, systemImage: "folder")
                        .help(folder.path)
                        .contextMenu {
                            Button("Remove Folder", role: .destructive) {
                                model.remove(folder)
                            }
                        }
                }
            }
        }
        .accessibilityIdentifier("folderList")
    }
}

/// The repository dashboard, or an empty state.
private struct RepositoryList: View {
    let model: LibraryViewModel
    @Binding var isImporting: Bool

    var body: some View {
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
        } else {
            DashboardTable(rows: model.rows, refreshing: model.statuses.refreshing)
        }
    }
}
