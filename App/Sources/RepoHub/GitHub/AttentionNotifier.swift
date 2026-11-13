import AppKit
import Foundation
import OSLog
import UserNotifications

/// A notification to post: what happened and where clicking it goes.
struct AttentionNotification: Equatable, Sendable {
    enum Kind: String, Sendable {
        case ciFailure, reviewRequest
    }

    /// Stable per event, so the same event is never posted twice.
    var id: String
    var kind: Kind
    var title: String
    var body: String
    /// The CI run or pull request.
    var url: URL
}

/// Posts user notifications. The real one uses `UNUserNotificationCenter`;
/// tests record what would have been posted.
@MainActor
protocol UserNotifying: AnyObject {
    /// Asks for permission the first time it's needed; returns whether notifications are allowed.
    func requestAuthorization() async -> Bool
    func post(_ notification: AttentionNotification) async
}

/// Decides which GitHub changes deserve a notification: CI that starts
/// failing on a checked-out branch, and new review requests. Each event is
/// posted once. The first update after launch or sign-in only records what's
/// already there, so existing failures don't all notify at once.
@MainActor
final class AttentionNotifier {
    private let notifier: any UserNotifying
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.lquainta.RepoHub", category: "Notifications")
    /// IDs of events already seen (posted or part of the baseline).
    private var seen: Set<String> = []
    private var hasBaseline = false

    init(notifier: any UserNotifying, defaults: UserDefaults = .standard) {
        self.notifier = notifier
        self.defaults = defaults
    }

    /// Call with every GitHub status update.
    func update(_ statuses: GitHubStatusModel.Statuses) async {
        let events = Self.events(in: statuses)
        guard hasBaseline else {
            seen = Set(events.map(\.id))
            hasBaseline = true
            return
        }
        let new = events.filter { !seen.contains($0.id) && isEnabled($0.kind) }
        seen.formUnion(events.map(\.id))
        guard !new.isEmpty else {
            return
        }
        guard await notifier.requestAuthorization() else {
            logger.info("Notifications not allowed; \(new.count) skipped")
            return
        }
        for notification in new {
            await notifier.post(notification)
        }
    }

    private func isEnabled(_ kind: AttentionNotification.Kind) -> Bool {
        switch kind {
        case .ciFailure: AppPreferences.notifyCIFailures(defaults)
        case .reviewRequest: AppPreferences.notifyReviewRequests(defaults)
        }
    }

    /// Every notifiable event in `statuses`, in a stable order.
    static func events(in statuses: GitHubStatusModel.Statuses) -> [AttentionNotification] {
        var events: [AttentionNotification] = []
        var reviewIDs: Set<String> = []
        for (request, status) in statuses.sorted(by: { $0.key.repository.fullName < $1.key.repository.fullName }) {
            let repository = status.repository.fullName
            if let checks = status.checks, checks.state == .failure, let branch = request.branch {
                // The failing run's URL changes with every new run, so a fix
                // followed by a new failure notifies again.
                events.append(
                    AttentionNotification(
                        id: "ci:\(repository.lowercased()):\(branch):\(checks.url.absoluteString)",
                        kind: .ciFailure,
                        title: String(localized: "CI failed on \(branch)"),
                        body: String(localized: "\(repository): \(checks.failed) of \(checks.total) checks failed"),
                        url: checks.url
                    )
                )
            }
            for pull in status.reviewRequests {
                // Two worktrees of one repository share its review requests.
                let id = "review:\(repository.lowercased())#\(pull.number)"
                guard reviewIDs.insert(id).inserted else {
                    continue
                }
                events.append(
                    AttentionNotification(
                        id: id,
                        kind: .reviewRequest,
                        title: String(localized: "Review requested by \(pull.author)"),
                        body: String(localized: "\(repository) #\(pull.number): \(pull.title)"),
                        url: pull.url
                    )
                )
            }
        }
        return events
    }
}

/// Posts nothing: for UI tests, which must not ask for notification permission.
@MainActor
final class SilentNotifier: UserNotifying {
    func requestAuthorization() async -> Bool { false }
    func post(_ notification: AttentionNotification) async {}
}

/// ``UserNotifying`` with the system notification center. Clicking a
/// notification opens its URL in the browser.
@MainActor
final class SystemNotifier: NSObject, UserNotifying, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "com.lquainta.RepoHub", category: "Notifications")

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func post(_ notification: AttentionNotification) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.threadIdentifier = notification.kind.rawValue
        content.userInfo = ["url": notification.url.absoluteString]
        do {
            try await center.add(UNNotificationRequest(identifier: notification.id, content: content, trigger: nil))
        } catch {
            logger.error("Could not post notification: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let string = response.notification.request.content.userInfo["url"] as? String,
            let url = URL(string: string)
        {
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
        }
        completionHandler()
    }

    /// Shows notifications even while RepoHub is the active app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
