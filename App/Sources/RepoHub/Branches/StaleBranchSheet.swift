import RepoHubCore
import SwiftUI

/// Lists stale branches with the reason for each and deletes the ones the user selects.
struct StaleBranchSheet: View {
    @Bindable var model: StaleBranchModel
    let repositoryName: String
    /// Called after branches were deleted so statuses and details refresh.
    let onFinish: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clean Up Branches in \(repositoryName)").font(.title3.bold())
            content
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 560, height: 440)
        .task { await model.load() }
        .confirmationDialog(
            "Delete unmerged branches?",
            isPresented: Binding(
                get: { if case .confirmingForce = model.phase { true } else { false } },
                set: { if !$0 { model.cancelForceDelete() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Unmerged Work", role: .destructive) {
                Task { await model.confirmForceDelete() }
            }
            Button("Cancel", role: .cancel) { model.cancelForceDelete() }
        } message: {
            Text(
                "These branches have commits that aren't in \(model.report?.defaultBranch ?? "the default branch"): "
                    + "\(model.selectedUnmerged.joined(separator: ", ")). Their work will be lost."
            )
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading, .deleting:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView(
                "Couldn't Read Branches",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .finished:
            FinishedView(deleted: model.deleted, failures: model.failures)
        case .reviewing, .confirmingForce:
            if model.candidates.isEmpty {
                ContentUnavailableView(
                    "No Stale Branches",
                    systemImage: "checkmark.circle",
                    description: Text("Every branch is either active or not yet merged.")
                )
            } else {
                Text(
                    "Compared with \(model.report?.defaultBranch ?? "") · "
                        + "The current branch and \(model.report?.defaultBranch ?? "") are never deleted."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                List(model.candidates, id: \.branch.name) { candidate in
                    Toggle(isOn: binding(for: candidate.branch.name)) {
                        CandidateRow(candidate: candidate)
                    }
                    .toggleStyle(.checkbox)
                }
                .accessibilityIdentifier("staleBranchList")
                Toggle("Also delete the branches on their remote", isOn: $model.deleteRemote)
            }
        }
    }

    @ViewBuilder private var footer: some View {
        HStack {
            if model.phase == .reviewing, !model.selectedUnmerged.isEmpty {
                Label(
                    "\(model.selectedUnmerged.count) selected branches aren't merged",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
                .font(.callout)
            }
            Spacer()
            if model.phase == .finished {
                Button("Done") {
                    onFinish()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Delete \(model.selection.count) Branches", role: .destructive) {
                    Task { await model.deleteSelected() }
                }
                .disabled(model.selection.isEmpty || model.phase != .reviewing)
            }
        }
    }

    private func binding(for name: String) -> Binding<Bool> {
        Binding(
            get: { model.selection.contains(name) },
            set: { isOn in
                if isOn { model.selection.insert(name) } else { model.selection.remove(name) }
            }
        )
    }
}

private struct CandidateRow: View {
    let candidate: StaleBranch

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.branch.name).fontWeight(.medium)
                Text(candidate.reasons.map(StatusText.description(of:)).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !candidate.isMerged {
                Text("Unmerged")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
            Text(candidate.branch.lastCommitDate, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct FinishedView: View {
    let deleted: [String]
    let failures: [String: String]

    var body: some View {
        List {
            if !deleted.isEmpty {
                Section("Deleted (\(deleted.count))") {
                    ForEach(deleted, id: \.self) { Label($0, systemImage: "checkmark.circle") }
                }
            }
            if !failures.isEmpty {
                Section("Not Deleted (\(failures.count))") {
                    ForEach(failures.keys.sorted(), id: \.self) { name in
                        VStack(alignment: .leading) {
                            Label(name, systemImage: "xmark.circle")
                            Text(failures[name] ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
