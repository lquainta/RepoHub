import SwiftUI
import UniformTypeIdentifiers

/// The app's Settings window (⌘,).
struct SettingsView: View {
    @Bindable var settings: SettingsModel
    let library: LibraryViewModel

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings(settings: settings, library: library)
            }
            Tab("Folders", systemImage: "folder") {
                FolderSettings(settings: settings, library: library)
            }
            Tab("Apps", systemImage: "app.badge") {
                AppSettings(settings: settings)
            }
        }
        .frame(width: 520, height: 400)
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { settings.errorMessage != nil }, set: { if !$0 { settings.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(settings.errorMessage ?? "")
        }
    }
}

private struct GeneralSettings: View {
    @Bindable var settings: SettingsModel
    let library: LibraryViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Open RepoHub at login", isOn: $settings.launchAtLogin)
                Toggle("Show summary in the menu bar", isOn: $settings.showMenuBarExtra)
                Toggle("Run in the menu bar only (no Dock icon)", isOn: $settings.menuBarOnly)
                    .disabled(!settings.showMenuBarExtra)
            }
            Section {
                Picker("Fetch all repositories", selection: $settings.backgroundFetchMinutes) {
                    Text("Never").tag(0)
                    Text("Every 5 minutes").tag(5)
                    Text("Every 15 minutes").tag(15)
                    Text("Every 30 minutes").tag(30)
                    Text("Every hour").tag(60)
                }
                Text("Statuses refresh automatically when files change. Fetching also checks remotes for new commits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Stepper(value: $settings.staleBranchDays, in: 0...3_650, step: 15) {
                    LabeledContent("Stale after") {
                        Text(settings.staleBranchDays == 0 ? "Off" : "\(settings.staleBranchDays) days")
                            .monospacedDigit()
                    }
                }
                .onChange(of: settings.staleBranchDays) {
                    Task { await library.refreshStatuses() }
                }
                Text("Inactive branches are suggested in Clean Up Branches. Merged branches always are.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct FolderSettings: View {
    let settings: SettingsModel
    let library: LibraryViewModel
    @State private var isImporting = false
    @State private var newIgnoredName = ""

    var body: some View {
        Form {
            Section("Scan Folders") {
                if library.folders.isEmpty {
                    Text("No folders yet").foregroundStyle(.secondary)
                }
                ForEach(library.folders) { folder in
                    HStack {
                        Label(folder.path, systemImage: "folder").lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") { library.remove(folder) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Stop tracking this folder")
                    }
                }
                Button("Add Folder…") { isImporting = true }
            }
            Section {
                ForEach(settings.ignoredFolderNames, id: \.self) { name in
                    HStack {
                        Text(name).font(.body.monospaced())
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") { settings.removeIgnoredFolderName(name) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Folder name", text: $newIgnoredName)
                        .onSubmit(addIgnoredName)
                    Button("Add", action: addIgnoredName)
                        .disabled(newIgnoredName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Skip Folders Named")
            } footer: {
                HStack {
                    Text("Hidden folders are always skipped. Changes apply on the next refresh (⌘R).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Defaults") { settings.resetIgnoredFolderNames() }
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task { await library.addFolders(urls) }
            }
        }
    }

    private func addIgnoredName() {
        if settings.addIgnoredFolderName(newIgnoredName) {
            newIgnoredName = ""
        }
    }
}

private struct AppSettings: View {
    @Bindable var settings: SettingsModel

    var body: some View {
        Form {
            AppPicker(title: "Editor", apps: KnownApps.editors, selection: $settings.editorBundleID)
            AppPicker(title: "Terminal", apps: KnownApps.terminals, selection: $settings.terminalBundleID)
        }
        .formStyle(.grouped)
    }
}

/// Picks one of the installed apps, or any other app.
private struct AppPicker: View {
    let title: LocalizedStringKey
    let apps: [KnownApps.App]
    @Binding var selection: String

    var body: some View {
        let installed = KnownApps.installed(apps, including: selection)
        Picker(title, selection: $selection) {
            ForEach(installed) { Text($0.name).tag($0.bundleID) }
            if !installed.contains(where: { $0.bundleID == selection }) {
                Text("Not installed (\(selection))").tag(selection)
            }
            Divider()
            Text("Other…").tag("")
        }
        .onChange(of: selection) { old, new in
            if new.isEmpty {
                selection = KnownApps.chooseOtherApp() ?? old
            }
        }
    }
}
