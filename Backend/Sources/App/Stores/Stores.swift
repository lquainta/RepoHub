import Fluent
import Vapor

/// The data-access layer: one store per area, backed by Fluent.
///
/// Called "stores" rather than "repositories" because a repository means a
/// git repository everywhere else in RepoHub. Route handlers depend on the
/// protocols so tests can replace them.
struct Stores: Sendable {
    var users: any UserStore
    var devices: any DeviceStore
    var sync: any SyncStore
    var snapshots: any SnapshotStore
    var webhookEvents: any WebhookEventStore

    /// Fluent-backed stores on `database`.
    init(database: any Database) {
        users = FluentUserStore(database: database)
        devices = FluentDeviceStore(database: database)
        sync = FluentSyncStore(database: database)
        snapshots = FluentSnapshotStore(database: database)
        webhookEvents = FluentWebhookEventStore(database: database)
    }
}

extension Request {
    /// Stores bound to this request's database connection.
    var stores: Stores { Stores(database: db) }
}
