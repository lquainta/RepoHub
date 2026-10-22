import SwiftUI

/// The Account tab of the Settings window: GitHub sign-in and sign-out.
struct AccountSettings: View {
    let account: AccountModel

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
                        Text("Waiting for approval…").foregroundStyle(.secondary)
                        Button("Cancel") { account.cancelSignIn() }
                    }
                }
            case .signedIn(let user):
                Section {
                    LabeledContent("Signed in as") {
                        VStack(alignment: .trailing) {
                            Text(user.login).bold()
                            if let name = user.name {
                                Text(name).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("signedInUser")
                    Button("Sign Out") { Task { await account.signOut() } }
                }
            }
            if let message = account.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }
}
