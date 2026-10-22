import Foundation
import Vapor

/// A change to a repository that connected apps should refresh.
struct RepositoryChange: Sendable, Equatable, Codable {
    var owner: String
    var name: String
    /// The GitHub event (`check_run`, `pull_request`, ...).
    var event: String
}

/// Delivers ``RepositoryChange``s to the event streams (`GET /events`) of
/// the users they concern.
///
/// Subscribers live in this process. Production runs one machine (ADR 0007);
/// running more would need Redis pub/sub between them.
actor EventHub {
    private var subscribers: [UUID: (user: UUID, continuation: AsyncStream<RepositoryChange>.Continuation)] = [:]

    /// A stream of changes for `user`, until the caller stops iterating.
    func subscribe(user: UUID) -> AsyncStream<RepositoryChange> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: RepositoryChange.self,
            bufferingPolicy: .bufferingNewest(100)
        )
        subscribers[id] = (user, continuation)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id) }
        }
        return stream
    }

    /// Sends `change` to every stream of the given users.
    func publish(_ change: RepositoryChange, to users: Set<UUID>) {
        for subscriber in subscribers.values where users.contains(subscriber.user) {
            subscriber.continuation.yield(change)
        }
    }

    /// The number of open streams, for tests and logging.
    var subscriberCount: Int {
        subscribers.count
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }
}

private struct EventHubKey: StorageKey {
    typealias Value = EventHub
}

extension Application {
    /// The process's event hub, created by ``configure(_:reader:)``.
    var eventHub: EventHub {
        get {
            guard let hub = storage[EventHubKey.self] else {
                preconditionFailure("eventHub accessed before configure")
            }
            return hub
        }
        set { storage[EventHubKey.self] = newValue }
    }
}
