import RepoHubCore
import SwiftUI

/// Placeholder root view until the repository dashboard (#68) lands.
struct ContentView: View {
    var body: some View {
        ContentUnavailableView {
            Label("RepoHub", systemImage: "folder.badge.gearshape")
        } description: {
            Text("Version \(RepoHubCore.version)")
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

#Preview {
    ContentView()
}
