import Charts
import SwiftUI

/// The Activity window: commits per day for the last 30 days, by repository,
/// for all repositories or one group, and how many had uncommitted changes.
struct ActivityView: View {
    let model: ActivityModel
    let library: LibraryViewModel
    /// The group to show, or `nil` for every repository.
    @State private var groupName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Picker("Show", selection: $groupName) {
                    Text("All Repositories").tag(String?.none)
                    if !library.groups.isEmpty {
                        Divider()
                    }
                    ForEach(library.groups, id: \.name) { group in
                        Text(group.name).tag(Optional(group.name))
                    }
                }
                .fixedSize()
                Spacer()
                if model.isLoading {
                    ProgressView().controlSize(.small)
                }
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.load() } }
                    .disabled(!model.isSignedIn || model.isLoading)
            }
            content
        }
        .padding()
        .frame(minWidth: 560, minHeight: 420)
        .task { await model.load() }
    }

    @ViewBuilder private var content: some View {
        let scope = self.scope
        if !model.isSignedIn {
            ContentUnavailableView(
                "Sign In to See Activity",
                systemImage: "chart.bar.xaxis",
                description: Text(
                    "Activity history is stored with your GitHub account. Sign in from Settings → Account."
                )
            )
        } else if let message = model.errorMessage, !model.hasLoaded {
            ContentUnavailableView(
                "Couldn't Load Activity",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        } else if model.hasLoaded && model.isEmpty(in: scope) {
            ContentUnavailableView(
                "No Activity Yet",
                systemImage: "chart.bar.xaxis",
                description: Text(
                    "Commits from the last 30 days appear here after RepoHub has scanned your repositories."
                )
            )
        } else {
            CommitsChart(points: model.points(in: scope), days: model.chartDays)
            DirtyChart(counts: model.dirtyCounts(in: scope))
        }
    }

    /// Remote identities in the selected group, or `nil` for all.
    private var scope: Set<String>? {
        guard let groupName, let group = library.groups.first(where: { $0.name == groupName }) else {
            return nil
        }
        return Set(group.repositories.compactMap(library.remoteIdentity(of:))).union(group.remoteOnlyMembers)
    }
}

/// Stacked bars: commits per day, one color per repository.
private struct CommitsChart: View {
    let points: [ActivityPoint]
    let days: [Date]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Commits per Day").font(.headline)
            Chart(points) { point in
                BarMark(
                    x: .value("Day", point.day, unit: .day),
                    y: .value("Commits", point.commits)
                )
                .foregroundStyle(by: .value("Repository", point.series))
            }
            .chartXScale(domain: (days.first ?? .now)...(days.last ?? .now).addingTimeInterval(86_400))
            .chartLegend(position: .bottom, alignment: .leading)
            .accessibilityLabel(Text("Commits per day for the last 30 days"))
            .frame(minHeight: 220)
        }
    }
}

/// A line: how many repositories had uncommitted changes each day.
private struct DirtyChart: View {
    let counts: [(day: Date, repositories: Int)]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Repositories with Uncommitted Changes").font(.headline)
            Chart(counts, id: \.day) { entry in
                LineMark(x: .value("Day", entry.day, unit: .day), y: .value("Repositories", entry.repositories))
                    .interpolationMethod(.stepCenter)
                PointMark(x: .value("Day", entry.day, unit: .day), y: .value("Repositories", entry.repositories))
                    .symbolSize(entry.repositories > 0 ? 20 : 0)
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3))
            }
            .accessibilityLabel(Text("Repositories with uncommitted changes per day"))
            .frame(height: 110)
        }
    }
}
