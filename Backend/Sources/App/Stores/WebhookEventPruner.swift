import Foundation
import Vapor

/// Deletes webhook events older than ``retention``, at most once per
/// ``interval`` (#187).
///
/// Run after a delivery is stored, so the table is trimmed whenever it grows,
/// without a timer that would keep an idle machine awake.
actor WebhookEventPruner {
    /// How long deliveries are kept, for idempotency and debugging.
    static let retention: TimeInterval = 30 * 86_400
    /// The shortest time between two prunes by this process.
    static let interval: TimeInterval = 3600

    private let now: @Sendable () -> Date
    private var lastPruned: Date?

    init(now: @escaping @Sendable () -> Date = { .now }) {
        self.now = now
    }

    /// Prunes `store` if this process hasn't in the last ``interval``.
    ///
    /// Returns how many events were deleted, or `nil` if it wasn't time or the
    /// delete failed. A failure is logged, never thrown (the delivery that
    /// triggered it has already been stored), and retried after ``interval``.
    @discardableResult
    func pruneIfDue(_ store: any WebhookEventStore, logger: Logger) async -> Int? {
        let now = now()
        if let lastPruned, now.timeIntervalSince(lastPruned) < Self.interval {
            return nil
        }
        lastPruned = now
        do {
            let deleted = try await store.prune(receivedBefore: now.addingTimeInterval(-Self.retention))
            if deleted > 0 {
                logger.info("Pruned old webhook events", metadata: ["deleted": "\(deleted)"])
            }
            return deleted
        } catch {
            logger.warning("Couldn't prune webhook events: \(String(reflecting: error))")
            return nil
        }
    }
}

private struct WebhookEventPrunerKey: StorageKey {
    typealias Value = WebhookEventPruner
}

extension Application {
    /// The process's webhook event pruner, created by ``configure(_:reader:)``.
    var webhookEventPruner: WebhookEventPruner {
        get {
            guard let pruner = storage[WebhookEventPrunerKey.self] else {
                preconditionFailure("webhookEventPruner accessed before configure")
            }
            return pruner
        }
        set { storage[WebhookEventPrunerKey.self] = newValue }
    }
}
