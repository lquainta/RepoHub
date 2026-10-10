import SwiftUI

/// Menu items for repository actions, shared by the context menu and the Repository menu.
struct RepositoryMenu: View {
    let actions: RepositoryActions
    /// Paths the actions apply to. Open actions use the first.
    let paths: [String]

    var body: some View {
        let first = paths.first
        Button("Fetch", systemImage: "arrow.down.circle") {
            Task { await actions.fetch(paths) }
        }
        .keyboardShortcut("f", modifiers: [.command, .option])
        Button("Pull (Fast-Forward Only)", systemImage: "arrow.down.to.line") {
            Task { await actions.pull(paths) }
        }
        .keyboardShortcut("p", modifiers: [.command, .option])

        Divider()

        Button("Open in Editor", systemImage: "chevron.left.forwardslash.chevron.right") {
            if let first { Task { await actions.openInEditor(first) } }
        }
        .keyboardShortcut("e", modifiers: [.command, .option])
        Button("Open in Terminal", systemImage: "terminal") {
            if let first { Task { await actions.openInTerminal(first) } }
        }
        .keyboardShortcut("t", modifiers: [.command, .option])
        Button("Show in Finder", systemImage: "folder") {
            if let first { actions.revealInFinder(first) }
        }
        .keyboardShortcut("r", modifiers: [.command, .option])

        Divider()

        Button("Copy Remote URL", systemImage: "doc.on.doc") {
            if let first { Task { await actions.copyRemoteURL(first) } }
        }
        .keyboardShortcut("c", modifiers: [.command, .option])
        Button("Open on GitHub", systemImage: "safari") {
            if let first { Task { await actions.openOnGitHub(first) } }
        }
        .keyboardShortcut("g", modifiers: [.command, .option])
    }
}

/// The app's Repository menu, acting on the selected repository.
struct RepositoryCommands: Commands {
    let model: LibraryViewModel

    var body: some Commands {
        CommandMenu("Repository") {
            Button("Fetch All", systemImage: "arrow.down.circle.dotted") {
                Task { await model.fetchAll() }
            }
            .keyboardShortcut("f", modifiers: [.command, .option, .shift])
            .disabled(model.repositories.isEmpty || model.actions.fetchAllProgress != nil)

            Divider()

            RepositoryMenu(actions: model.actions, paths: model.selectedPath.map { [$0] } ?? [])
                .disabled(model.selectedPath == nil)
        }
    }
}
