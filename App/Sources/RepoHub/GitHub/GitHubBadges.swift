import RepoHubCore
import SwiftUI

/// Pull request and CI badges for a dashboard row. Each badge opens GitHub.
/// Status is shown by icon shape and text, not only color.
struct GitHubBadges: View {
    let status: GitHubRepositoryStatus
    /// The branch checked out locally, whose pull request is linked first.
    let branch: String?

    var body: some View {
        HStack(spacing: 6) {
            if let checks = status.checks {
                ChecksBadge(checks: checks)
            }
            if !status.pullRequests.isEmpty {
                let reviews = status.reviewRequests.count
                Link(destination: pullRequestsURL) {
                    Label("\(status.pullRequests.count)", systemImage: "arrow.triangle.pull")
                        .labelStyle(.titleAndIcon)
                        .monospacedDigit()
                }
                .help(pullRequestsHelp(reviews: reviews))
                .accessibilityLabel(Text(pullRequestsHelp(reviews: reviews)))
                if reviews > 0 {
                    StatusLabel("\(reviews)", systemImage: "eye", tint: .orange)
                        .labelStyle(.titleAndIcon)
                        .help("\(reviews) waiting for your review")
                        .accessibilityLabel(Text("\(reviews) waiting for your review"))
                }
            }
        }
        .buttonStyle(.borderless)
    }

    /// The pull request for the current branch, or the repository's list of pull requests.
    private var pullRequestsURL: URL {
        status.pullRequest(for: branch)?.url ?? status.repository.webURL.appending(path: "pulls")
    }

    private func pullRequestsHelp(reviews: Int) -> String {
        if let pull = status.pullRequest(for: branch) {
            return String(localized: "#\(pull.number) \(pull.title) (\(status.pullRequests.count) open)")
        }
        return String(localized: "\(status.pullRequests.count) open pull requests")
    }
}

/// The combined CI result for the checked-out branch.
struct ChecksBadge: View {
    let checks: GitHubRepositoryStatus.Checks

    var body: some View {
        Link(destination: checks.url) {
            Image(systemName: symbol)
                .foregroundStyle(color)
        }
        .help(description)
        .accessibilityLabel(Text(description))
    }

    private var symbol: String {
        switch checks.state {
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.octagon.fill"
        case .pending: "clock.fill"
        }
    }

    private var color: Color {
        switch checks.state {
        case .success: .green
        case .failure: .red
        case .pending: .yellow
        }
    }

    var description: String {
        switch checks.state {
        case .success: String(localized: "CI passed (\(checks.total) checks)")
        case .failure: String(localized: "CI failed (\(checks.failed) of \(checks.total) checks)")
        case .pending: String(localized: "CI running (\(checks.pending) of \(checks.total) checks)")
        }
    }
}

/// Pull requests and CI in the detail pane.
struct GitHubSection: View {
    let status: GitHubRepositoryStatus
    let branch: String?

    var body: some View {
        Section("GitHub") {
            if let checks = status.checks {
                LabeledContent("CI") {
                    HStack {
                        ChecksBadge(checks: checks)
                        Text(ChecksBadge(checks: checks).description)
                    }
                }
            }
            if status.pullRequests.isEmpty {
                Text("No open pull requests").foregroundStyle(.secondaryText)
            }
            ForEach(status.pullRequests) { pull in
                Link(destination: pull.url) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("#\(pull.number)").monospacedDigit().foregroundStyle(.secondaryText)
                            Text(pull.title).lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            Text(pull.author)
                            Text(pull.headBranch).font(.caption.monospaced())
                            if pull.isDraft {
                                Text("Draft")
                            }
                            if pull.reviewRequested {
                                StatusLabel("Review requested", systemImage: "eye", tint: .orange)
                            }
                            if pull.headBranch == branch {
                                Text("Current branch")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondaryText)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
