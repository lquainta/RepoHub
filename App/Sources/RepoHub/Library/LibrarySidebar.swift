import SwiftUI

/// What the group-name prompt is for.
enum GroupPrompt: Identifiable, Equatable {
    /// Create a group, then add these repositories to it.
    case create(adding: [String])
    /// Rename the group with this name.
    case rename(String)

    var id: String {
        switch self {
        case .create(let paths): "create:\(paths.joined(separator: ","))"
        case .rename(let name): "rename:\(name)"
        }
    }
}

/// Sidebar: all repositories, user-defined groups, and scan folders.
struct LibrarySidebar: View {
    @Bindable var model: LibraryViewModel
    @Binding var groupPrompt: GroupPrompt?

    var body: some View {
        List(selection: $model.scope) {
            Section("Library") {
                Label("All Repositories", systemImage: "square.stack.3d.up")
                    .badge(model.repositories.count)
                    .tag(SidebarScope.all)
            }
            Section {
                ForEach(model.groups) { group in
                    Label(group.name, systemImage: "tag")
                        .badge(group.repositories.count)
                        .tag(SidebarScope.group(group.name))
                        .dropDestination(for: String.self) { paths, _ in
                            model.add(paths, toGroup: group.name)
                            return true
                        }
                        .contextMenu {
                            Button("Rename Group…") { groupPrompt = .rename(group.name) }
                            Button("Delete Group", role: .destructive) { model.deleteGroup(group.name) }
                        }
                }
            } header: {
                HStack {
                    Text("Groups")
                    Spacer()
                    Button("New Group", systemImage: "plus") { groupPrompt = .create(adding: []) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("New Group")
                }
            }
            Section("Folders") {
                ForEach(model.folders) { folder in
                    Label(URL(fileURLWithPath: folder.path).lastPathComponent, systemImage: "folder")
                        .help(folder.path)
                        .tag(SidebarScope.folder(folder.path))
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

/// Asks for a group name to create or rename a group.
struct GroupNameAlert: ViewModifier {
    @Binding var prompt: GroupPrompt?
    let model: LibraryViewModel
    @State private var name = ""

    func body(content: Content) -> some View {
        content.alert(
            title,
            isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })
        ) {
            TextField("Name", text: $name)
            Button(isRenaming ? "Rename" : "Create") {
                switch prompt {
                case .create(let paths): model.createGroup(named: name, adding: paths)
                case .rename(let old): model.renameGroup(old, to: name)
                case nil: break
                }
                prompt = nil
            }
            Button("Cancel", role: .cancel) { prompt = nil }
        }
        .onChange(of: prompt) { _, newValue in
            if case .rename(let old) = newValue {
                name = old
            } else {
                name = ""
            }
        }
    }

    private var isRenaming: Bool {
        if case .rename = prompt { true } else { false }
    }

    private var title: String {
        isRenaming ? String(localized: "Rename Group") : String(localized: "New Group")
    }
}

/// The Filter toolbar menu: quick filters that combine with search.
struct QuickFilterMenu: View {
    @Binding var filters: Set<QuickFilter>

    var body: some View {
        Menu {
            ForEach(QuickFilter.allCases) { filter in
                Toggle(
                    isOn: Binding(
                        get: { filters.contains(filter) },
                        set: { isOn in
                            if isOn { filters.insert(filter) } else { filters.remove(filter) }
                        }
                    )
                ) {
                    Label(filter.title, systemImage: filter.systemImage)
                }
            }
            Divider()
            Button("Clear Filters") { filters = [] }
                .disabled(filters.isEmpty)
        } label: {
            Label(
                filters.isEmpty ? "Filter" : "Filter (\(filters.count))",
                systemImage: filters.isEmpty
                    ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
            )
        }
        .help("Show only repositories that match every selected filter")
        .accessibilityIdentifier("quickFilterMenu")
    }
}

/// "Add to Group" and "Remove from Group" context menu items.
struct GroupMenu: View {
    let model: LibraryViewModel
    let paths: [String]
    @Binding var groupPrompt: GroupPrompt?

    var body: some View {
        Menu("Add to Group", systemImage: "tag") {
            ForEach(model.groups) { group in
                Button(group.name) { model.add(paths, toGroup: group.name) }
            }
            if !model.groups.isEmpty {
                Divider()
            }
            Button("New Group…") { groupPrompt = .create(adding: paths) }
        }
        if case .group(let name) = model.scope {
            Button("Remove from \(name)", systemImage: "tag.slash") {
                model.remove(paths, fromGroup: name)
            }
        }
    }
}
