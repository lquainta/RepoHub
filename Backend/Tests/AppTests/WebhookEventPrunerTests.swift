import Foundation
import Logging
import Testing

@testable import App

/// Records prune requests and fails on demand.
private actor RecordingEventStore: WebhookEventStore {
    private(set) var cutoffs: [Date] = []
    private var failure: (any Error)?

    func failNext(with error: any Error) {
        failure = error
    }

    func insertIfNew(_ event: WebhookEvent) async throws -> Bool { true }
    func markProcessed(id: UUID, at date: Date) async throws {}

    func prune(receivedBefore date: Date) async throws -> Int {
        cutoffs.append(date)
        if let failure {
            self.failure = nil
            throw failure
        }
        return 3
    }
}

/// A clock the test moves by hand.
private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date { lock.withLock { date } }

    func advance(by seconds: TimeInterval) {
        lock.withLock { date += seconds }
    }
}

@Suite("WebhookEventPruner")
struct WebhookEventPrunerTests {
    private let logger = Logger(label: "test")

    @Test("Deletes events older than 30 days, at most once an hour")
    func throttled() async {
        let clock = ManualClock()
        let store = RecordingEventStore()
        let pruner = WebhookEventPruner(now: { clock.now })
        let start = clock.now

        let first = await pruner.pruneIfDue(store, logger: logger)
        clock.advance(by: 3599)
        let tooSoon = await pruner.pruneIfDue(store, logger: logger)
        clock.advance(by: 1)
        let later = await pruner.pruneIfDue(store, logger: logger)

        #expect(first == 3)
        #expect(tooSoon == nil)
        #expect(later == 3)
        let cutoffs = await store.cutoffs
        #expect(cutoffs == [start.addingTimeInterval(-30 * 86_400), start.addingTimeInterval(3600 - 30 * 86_400)])
    }

    @Test("A failed prune doesn't throw and is retried after the interval")
    func failure() async {
        let clock = ManualClock()
        let store = RecordingEventStore()
        let pruner = WebhookEventPruner(now: { clock.now })
        await store.failNext(with: CancellationError())

        let failed = await pruner.pruneIfDue(store, logger: logger)
        clock.advance(by: WebhookEventPruner.interval)
        let retried = await pruner.pruneIfDue(store, logger: logger)

        #expect(failed == nil)
        #expect(retried == 3)
    }
}
