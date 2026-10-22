import SwiftUI

/// The Account tab of the Settings window: GitHub sign-in and sign-out, and
/// notifications about GitHub activity.
struct AccountSettings: View {
    let account: AccountModel
    @Bindable var settings: SettingsModel
    /// Group and settings sync, if available.
    var sync: SyncModel?

    var body: some View {
        Form {
            switch account.state {
            case .signedOut:
                Section {
                    Text("Sign in with GitHub to see pull requests and CI status for your repositories.")
                    Button("Sign In with GitHub…") { account.signIn() }
                        .accessibilityIdentifier("signIn")
                }
            case .awaitingApproval(let userCode, let verificationURL):
                Section {
                    Text("Enter this code on GitHub to finish signing in. It's been copied to the clipboard.")
                    Text(userCode)
                        .font(.title.monospaced())
                        .textSelection(.enabled)
                        .accessibilityLabel(Text("Code \(userCode)"))
                        .accessibilityIdentifier("userCode")
                    HStack {
                        Link("Open \(verificationURL.host() ?? "GitHub")", destination: verificationURL)
                        Spacer()
                        ProgressView().controlSize(.small)
                        Text("Waiting for approval…").foregroundStyle(.secondaryText)
                        Button("Cancel") { account.cancelSignIn() }
                    }
                }
            case .signedIn(let user):
                Section {
                    LabeledContent("Signed in as") {
                        VStack(alignment: .trailing) {
                            Text(user.login).bold()
                            if let name = user.name {
                                Text(name).foregroundStyle(.secondaryText)
                            }
                        }
                    }
                    .accessibilityIdentifier("signedInUser")
                    Button("Sign Out") { Task { await account.signOut() } }
                }
                if let sync {
                    SyncSection(sync: sync)
                }
            }
            Section {
                Toggle("CI fails on a branch you have checked out", isOn: $settings.notifyCIFailures)
                Toggle("Someone requests your review", isOn: $settings.notifyReviewRequests)
            } header: {
                Text("Notify Me When")
            } footer: {
                Text("Needs GitHub sign-in. Clicking a notification opens the pull request or CI run.")
                    .font(.caption)
                    .foregroundStyle(.secondaryText)
            }
            if let message = account.errorMessage {
                Section {
                    StatusLabel(Text(message), systemImage: "exclamationmark.triangle", tint: .red)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Sync status: when groups and settings last synced, and Sync Now.
private struct SyncSection: View {
    let sync: SyncModel

    var body: some View {
        Section {
            LabeledContent("Last synced") {
                if sync.isSyncing {
                    ProgressView().controlSize(.small)
                } else if let date = sync.lastSynced {
                    Text(date, format: .relative(presentation: .named))
                } else {
                    Text("Not yet")
                }
            }
            if let message = sync.errorMessage {
                StatusLabel(Text(message), systemImage: "exclamationmark.triangle", tint: .red)
            }
            Button("Sync Now") { Task { await sync.sync() } }
                .disabled(sync.isSyncing)
        } header: {
            Text("Sync")
        } footer: {
            Text(
                "Groups and the stale branch setting sync to your other Macs. Repositories are matched by their remote."
            )
            .font(.caption)
            .foregroundStyle(.secondaryText)
        }
    }
}
