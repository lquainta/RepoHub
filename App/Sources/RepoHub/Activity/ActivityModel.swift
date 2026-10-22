import Foundation
import OSLog
import Observation
import RepoHubCore

/// A repository to snapshot: where it is, who it is on other Macs, and its status.
struct ActivitySource: Equatable, Sendable {
    var path: String
    /// Remote identity; repositories without a remote aren't uploaded.
    var identity: String
    var name: String
    var status: RepoStatus?
}

/// One bar segment of the chart: a repository's commits on a day.
struct ActivityPoint: Equatable, Identifiable {
    var day: Date
    /// The repository's name, or "Other" for the long tail.
    var series: String
    var commits: Int

    var id: String { "\(series)@\(day.timeIntervalSince1970)" }
}

/// The activity history (#81): uploads a snapshot of each repository's
/// commits per day, and loads the history for the chart.
@MainActor
@Observable
final class ActivityModel {
    /// How many days the chart shows and snapshots cover.
    static let days = 30
    /// Repositories shown by name; the rest are combined as "Other".
    static let namedSeries = 8

    private(set) var history: [RepositoryActivity] = []
    private(set) var isLoading = false
    /// A user-facing description of the last failure, if any.
    private(set) var errorMessage: String?
    /// Whether the history has been loaded since launch or sign-in.
    private(set) var hasLoaded = false

    private let account: AccountModel
    private let api: any APIClienting
    private let git: any GitServicing
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: "com.lquainta.RepoHub", category: "Activity")

    init(
        account: AccountModel,
        api: any APIClienting,
        git: any GitServicing = GitService(),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.account = account
        self.api = api
        self.git = git
        self.calendar = calendar
        self.now = now
    }

    var isSignedIn: Bool {
        account.user != nil
    }

    /// The days the chart covers, oldest first, as the start of each day.
    var chartDays: [Date] {
        let today = calendar.startOfDay(for: now())
        return (0..<Self.days).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    // MARK: - Uploading

    /// Counts each repository's commits per day for the last ``days`` days and
    /// uploads them, with today's uncommitted changes and sync state. Days
    /// without commits are skipped, except today.
    func upload(_ sources: [ActivitySource]) async {
        guard isSignedIn, !sources.isEmpty, let start = chartDays.first else {
            return
        }
        let today = dayString(calendar.startOfDay(for: now()))
        var snapshots: [ActivitySnapshot] = []
        for source in sources {
            snapshots += await self.snapshots(of: source, since: start, today: today)
        }
        guard !snapshots.isEmpty else {
            return
        }
        do {
            let token = try await account.accessToken()
            for start in stride(from: 0, to: snapshots.count, by: 5_000) {
                try await api.uploadSnapshots(
                    Array(snapshots[start..<min(start + 5_000, snapshots.count)]),
                    accessToken: token
                )
            }
        } catch {
            logger.error("Snapshot upload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// One snapshot per day with commits since `start`, plus `today` with
    /// the repository's current state; none if git can't read it.
    private func snapshots(of source: ActivitySource, since start: Date, today: String) async -> [ActivitySnapshot] {
        let dates: [Date]
        do {
            dates = try await git.commitDates(of: URL(fileURLWithPath: source.path, isDirectory: true), since: start)
        } catch {
            logger.info(
                "No activity for \(source.name, privacy: .private): \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
        var perDay = Dictionary(grouping: dates) { dayString(calendar.startOfDay(for: $0)) }.mapValues(\.count)
        // Today is always sent, to record its uncommitted changes.
        if perDay[today] == nil {
            perDay[today] = 0
        }
        return perDay.map { day, commits in
            ActivitySnapshot(
                repository: source.identity,
                day: day,
                commits: commits,
                capture: day == today
                    ? source.status.map { SnapshotCapture(dirty: !$0.isClean, ahead: $0.ahead, behind: $0.behind) }
                    : nil
            )
        }
    }

    // MARK: - Loading

    /// Loads the last ``days`` days of activity from the backend.
    func load() async {
        guard isSignedIn else {
            history = []
            hasLoaded = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            history = try await api.activity(days: Self.days, accessToken: try await account.accessToken())
            errorMessage = nil
            hasLoaded = true
        } catch {
            logger.error("Activity failed to load: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Chart data

    /// Commits per day per repository for the repositories in `scope` (all if
    /// `nil`). The ``namedSeries`` most active repositories are named; the
    /// rest are combined as "Other". Days without commits have no points.
    func points(in scope: Set<String>? = nil) -> [ActivityPoint] {
        let included = history.filter { scope?.contains($0.repository) ?? true }
        let totals = included.map { ($0, $0.days.reduce(0) { $0 + $1.commits }) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name < $1.0.name }
        let named = Set(totals.prefix(Self.namedSeries).map(\.0.repository))
        let other = String(localized: "Other")
        var sums: [String: [Date: Int]] = [:]
        for (repository, _) in totals {
            let series = named.contains(repository.repository) ? repository.name : other
            for day in repository.days where day.commits > 0 {
                guard let date = date(from: day.day) else {
                    continue
                }
                sums[series, default: [:]][date, default: 0] += day.commits
            }
        }
        return sums.flatMap { series, days in
            days.map { ActivityPoint(day: $0.key, series: series, commits: $0.value) }
        }
        .sorted { ($0.day, $0.series) < ($1.day, $1.series) }
    }

    /// How many repositories in `scope` had uncommitted changes, per day.
    func dirtyCounts(in scope: Set<String>? = nil) -> [(day: Date, repositories: Int)] {
        var counts: [Date: Int] = [:]
        for repository in history where scope?.contains(repository.repository) ?? true {
            for day in repository.days where day.dirty {
                if let date = date(from: day.day) {
                    counts[date, default: 0] += 1
                }
            }
        }
        return chartDays.map { ($0, counts[$0] ?? 0) }
    }

    /// Whether `scope` has any commits or uncommitted changes in the history.
    func isEmpty(in scope: Set<String>? = nil) -> Bool {
        points(in: scope).isEmpty && dirtyCounts(in: scope).allSatisfy { $0.repositories == 0 }
    }

    // MARK: - Days

    private func dayString(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func date(from day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            return nil
        }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
