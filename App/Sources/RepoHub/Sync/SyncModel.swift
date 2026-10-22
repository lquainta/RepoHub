import Foundation
import OSLog
import Observation

/// Syncs groups and settings with the user's other Macs through the backend
/// (#80): on launch, after sign-in, and shortly after every change.
///
/// Conflicts are last-write-wins per group and for the settings, by the time
/// of the change. Repositories are matched by remote identity, because paths
/// differ between Macs; members not cloned on this Mac are kept in
/// `RepoGroup.remoteOnlyMembers` so they aren't lost.
@MainActor
@Observable
final class SyncModel {
    /// When the last sync finished.
    private(set) var lastSynced: Date?
    private(set) var isSyncing = false
    /// A user-facing description of the last failure, if any.
    private(set) var errorMessage: String?
    /// Called after a sync changed local groups or settings.
    var onApplied: (@MainActor () -> Void)?

    /// How long to wait after a change before syncing, so a burst of edits syncs once.
    static let debounce: Duration = .seconds(2)

    private let account: AccountModel
    private let api: any APIClienting
    private let store: LibraryStore
    private let defaults: UserDefaults
    private let identity: @MainActor (TrackedRepository) -> String?
    private let sleep: @Sendable (Duration) async throws -> Void
    private let logger = Logger(subsystem: "com.lquainta.RepoHub", category: "Sync")
    private var scheduled: Task<Void, Never>?

    /// - Parameters:
    ///   - account: Supplies the access token; nothing syncs while signed out.
    ///   - api: The backend.
    ///   - store: The local groups.
    ///   - defaults: Where the stale branch setting and the sync state are kept.
    ///   - identity: A tracked repository's remote identity, if known.
    ///   - sleep: Waits for the debounce; tests skip it.
    init(
        account: AccountModel,
        api: any APIClienting,
        store: LibraryStore,
        defaults: UserDefaults = .standard,
        identity: @escaping @MainActor (TrackedRepository) -> String?,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.account = account
        self.api = api
        self.store = store
        self.defaults = defaults
        self.identity = identity
        self.sleep = sleep
    }

    // MARK: - Recording local changes

    /// Remembers that a synced group was deleted, so other Macs delete it too.
    func recordDeletion(of syncID: UUID, at date: Date = .now) {
        var tombstones = pendingDeletions
        tombstones[syncID] = date
        pendingDeletions = tombstones
        scheduleSync()
    }

    /// Syncs after ``debounce``, replacing a sync already scheduled.
    func scheduleSync() {
        scheduled?.cancel()
        scheduled = Task { [weak self, sleep] in
            try? await sleep(Self.debounce)
            guard !Task.isCancelled else {
                return
            }
            await self?.sync()
        }
    }

    // MARK: - Syncing

    /// Pulls changes from other Macs, applies the newer ones, then pushes this
    /// Mac's newer changes. Does nothing while signed out.
    func sync() async {
        guard account.user != nil, !isSyncing else {
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let token = try await account.accessToken()
            let startedAt = Date.now
            let since = defaults.object(forKey: Keys.serverTime) as? Date
            let remote = try await api.workspace(since: since, accessToken: token)

            var applied = false
            for group in remote.groups {
                try store.applySynced(group, identity: identity)
                applied = true
            }
            applied = try await syncSettings(remote.settings, token: token) || applied
            try await pushDeletions(token: token)
            try await pushGroups(changedAfter: lastPush, token: token)

            defaults.set(remote.serverTime, forKey: Keys.serverTime)
            defaults.set(startedAt, forKey: Keys.lastPush)
            lastSynced = .now
            errorMessage = nil
            if applied {
                onApplied?()
            }
        } catch APIError.unauthorized {
            // Signed out; the account model already said so.
        } catch {
            logger.error("Sync failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// Applies newer remote settings, or pushes newer local ones. Returns
    /// whether local settings changed.
    private func syncSettings(_ remote: SyncedSettings, token: String) async throws -> Bool {
        let localChange = defaults.object(forKey: AppPreferences.staleBranchDaysModifiedAtKey) as? Date
        if let localChange, localChange > remote.updatedAt {
            let days = AppPreferences.staleBranchDays(defaults) ?? 0
            let settings = SyncedSettings(staleBranchDays: days, updatedAt: localChange)
            _ = try await api.updateSettings(settings, accessToken: token)
            return false
        }
        guard remote.updatedAt > localChange ?? .distantPast, let days = remote.staleBranchDays else {
            return false
        }
        let changed = AppPreferences.staleBranchDays(defaults) ?? 0 != days
        defaults.set(days, forKey: AppPreferences.staleBranchDaysKey)
        defaults.set(remote.updatedAt, forKey: AppPreferences.staleBranchDaysModifiedAtKey)
        return changed
    }

    private func pushDeletions(token: String) async throws {
        for (id, deletedAt) in pendingDeletions {
            try await api.deleteGroup(id: id, deletedAt: deletedAt, accessToken: token)
            var tombstones = pendingDeletions
            tombstones[id] = nil
            pendingDeletions = tombstones
        }
    }

    /// Pushes groups changed after `date` (all if `nil`), and any never synced.
    private func pushGroups(changedAfter date: Date?, token: String) async throws {
        for (index, group) in try store.groups().enumerated() {
            guard group.syncID == nil || date.map({ group.lastChange > $0 }) ?? true else {
                continue
            }
            let members = Set(group.repositories.compactMap(identity)).union(group.remoteOnlyMembers)
            let stored = try await api.putGroup(
                SyncedGroup(
                    id: group.syncID ?? UUID(),
                    name: group.name,
                    sortOrder: index,
                    members: members.sorted(),
                    updatedAt: group.lastChange
                ),
                accessToken: token
            )
            if group.syncID != stored.id {
                try store.adoptSyncID(stored.id, for: group)
            }
        }
    }

    // MARK: - Persisted state

    private enum Keys {
        /// The server time of the last pull, sent as `since`.
        static let serverTime = "syncServerTime"
        /// When the last push started; groups changed after it are pushed next time.
        static let lastPush = "syncLastPush"
        /// Deleted groups not yet pushed, as `[syncID: deletedAt]`.
        static let pendingDeletions = "syncPendingDeletions"
    }

    private var lastPush: Date? {
        defaults.object(forKey: Keys.lastPush) as? Date
    }

    private var pendingDeletions: [UUID: Date] {
        get {
            let stored = defaults.dictionary(forKey: Keys.pendingDeletions) as? [String: Date] ?? [:]
            return Dictionary(
                uniqueKeysWithValues: stored.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } }
            )
        }
        set {
            defaults.set(
                Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.uuidString, $0.value) }),
                forKey: Keys.pendingDeletions
            )
        }
    }
}
