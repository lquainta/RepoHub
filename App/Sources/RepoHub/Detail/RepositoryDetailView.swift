import RepoHubCore
import SwiftUI

/// Details of the selected repository: changed files, branches, recent commits, remotes, and stashes.
struct RepositoryDetailView: View {
    let model: RepositoryDetailModel
    let name: String?

    var body: some View {
        switch model.state {
        case .empty:
            ContentUnavailableView(
                "No Repository Selected",
                systemImage: "sidebar.right",
                description: Text("Select a repository to see its changes, branches, and history.")
            )
        case .loading:
            ProgressView("Loading…")
        case .failed(let message):
            ContentUnavailableView(
                "Couldn't Read Repository",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .loaded(let details):
            DetailList(details: details, name: name ?? "", path: model.path ?? "")
        }
    }
}

private struct DetailList: View {
    let details: RepositoryDetails
    let name: String
    let path: String

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.title2.bold())
                    Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack(spacing: 12) {
                        Label(StatusText.branch(details.status.head), systemImage: "arrow.triangle.branch")
                        Text(StatusText.sync(details.status)).foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
                .accessibilityElement(children: .combine)
            }

            ChangesSection(files: details.files)

            Section("Branches") {
                let local = details.branches.filter { !$0.isRemote }
                let remote = details.branches.filter(\.isRemote)
                if local.isEmpty {
                    Text("No branches yet").foregroundStyle(.secondary)
                }
                ForEach(local, id: \.name) { BranchRow(branch: $0) }
                if !remote.isEmpty {
                    DisclosureGroup("Remote branches (\(remote.count))") {
                        ForEach(remote, id: \.name) { BranchRow(branch: $0) }
                    }
                }
            }

            Section("Recent Commits") {
                if details.recentCommits.isEmpty {
                    Text("No commits yet").foregroundStyle(.secondary)
                }
                ForEach(details.recentCommits, id: \.hash) { CommitRow(commit: $0) }
            }

            Section("Remotes") {
                if details.remotes.isEmpty {
                    Text("No remotes").foregroundStyle(.secondary)
                }
                ForEach(details.remotes, id: \.name) { remote in
                    LabeledContent(remote.name) {
                        VStack(alignment: .trailing) {
                            Text(remote.fetchURL).textSelection(.enabled)
                            if let push = remote.pushURL {
                                Text("Push: \(push)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Stashes") {
                if details.stashes.isEmpty {
                    Text("No stashes").foregroundStyle(.secondary)
                }
                ForEach(details.stashes, id: \.index) { stash in
                    LabeledContent {
                        Text(stash.date, format: .relative(presentation: .named)).foregroundStyle(.secondary)
                    } label: {
                        Text(stash.message)
                        Text(verbatim: "stash@{\(stash.index)}").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityIdentifier("repositoryDetail")
    }
}

/// Changed files grouped by staged, unstaged, untracked, and conflicted.
private struct ChangesSection: View {
    let files: [FileChange]

    var body: some View {
        if files.isEmpty {
            Section("Changes") {
                Label("Working tree clean", systemImage: "checkmark.circle")
            }
        }
        ForEach(FileChange.Area.displayOrder, id: \.self) { area in
            let inArea = files.filter { $0.area == area }
            if !inArea.isEmpty {
                Section {
                    ForEach(inArea, id: \.self) { FileRow(file: $0) }
                } header: {
                    Text("\(StatusText.title(for: area)) (\(inArea.count))")
                }
            }
        }
    }
}

private struct FileRow: View {
    let file: FileChange

    var body: some View {
        HStack {
            Image(systemName: StatusText.symbol(for: file.kind))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.path).lineLimit(1).truncationMode(.middle)
                if let original = file.originalPath {
                    Text("from \(original)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(StatusText.description(of: file.kind)).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BranchRow: View {
    let branch: Branch

    var body: some View {
        LabeledContent {
            Text(branch.lastCommitDate, format: .relative(presentation: .named)).foregroundStyle(.secondary)
        } label: {
            HStack(spacing: 6) {
                Text(branch.name).fontWeight(branch.isCurrent ? .semibold : .regular)
                if branch.isCurrent {
                    Text("Current")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.tint.opacity(0.2), in: Capsule())
                }
            }
            if let tracking = StatusText.tracking(of: branch) {
                Text(tracking).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CommitRow: View {
    let commit: CommitSummary

    var body: some View {
        LabeledContent {
            Text(commit.date, format: .relative(presentation: .named)).foregroundStyle(.secondary)
        } label: {
            Text(commit.subject).lineLimit(2)
            Text("\(String(commit.hash.prefix(7))) · \(commit.author)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

extension FileChange.Area {
    /// Conflicts first, since they block committing.
    static let displayOrder: [Self] = [.conflicted, .staged, .unstaged, .untracked]
}
