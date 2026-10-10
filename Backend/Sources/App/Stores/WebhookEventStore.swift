import Fluent
import Foundation
import PostgresNIO

/// GitHub webhook deliveries (#77).
protocol WebhookEventStore: Sendable {
    /// Stores the event unless its delivery id was seen before.
    ///
    /// - Returns: `false` for a duplicate delivery, which should be ignored.
    func insertIfNew(_ event: WebhookEvent) async throws -> Bool
    func markProcessed(id: UUID, at date: Date) async throws
    /// Deletes events received before `date`; returns how many were deleted.
    @discardableResult
    func prune(receivedBefore date: Date) async throws -> Int
}

struct FluentWebhookEventStore: WebhookEventStore {
    let database: any Database

    func insertIfNew(_ event: WebhookEvent) async throws -> Bool {
        do {
            try await event.create(on: database)
            return true
        } catch let error as PSQLError where error.serverInfo?[.sqlState] == PostgresError.Code.uniqueViolation.raw {
            // Only a duplicate delivery id is expected; any other failure is a real error.
            return false
        }
    }

    func markProcessed(id: UUID, at date: Date) async throws {
        try await WebhookEvent.query(on: database).filter(\.$id == id).set(\.$processedAt, to: date).update()
    }

    func prune(receivedBefore date: Date) async throws -> Int {
        let count = try await WebhookEvent.query(on: database).filter(\.$receivedAt < date).count()
        try await WebhookEvent.query(on: database).filter(\.$receivedAt < date).delete()
        return count
    }
}
