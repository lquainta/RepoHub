import Foundation
import RepoHubCore
import Testing

@testable import RepoHub

/// One Mac: its own store, defaults, and account, sharing a server (`FakeAPI`).
@MainActor
struct TestMac {
    let store: LibraryStore
    let defaults: UserDefaults
    let sync: SyncModel
    /// Remote identity by path; repositories not listed have no remote.
    let identities: [String: String]

    init(api: FakeAPI, repositories: [String: String]) async throws {
        store = LibraryStore(container: try Persistence.makeInMemoryContainer())
        defaults = try #require(UserDefaults(suiteName: "SyncModelTests-\(UUID().uuidString)"))
        identities = repositories
        let folder = try #require(try store.addScanFolder(at: URL(fileURLWithPath: "/dev")))
        try store.replaceRepositories(in: folder, with: repositories.keys.sorted().map { URL(fileURLWithPath: $0) })
        await api.setPolls([.success(.signedIn(.fixture()))])
        let account = AccountModel(
            api: api,
            credentials: InMemoryCredentialStore(),
            workspace: FakeWorkspace(),
            sleep: { _ in }
        )
        account.signIn()
        await account.waitForSignIn()
        let identities = repositories
        sync = SyncModel(
            account: account,
            api: api,
            store: store,
            defaults: defaults,
            identity: { identities[$0.path] },
            sleep: { _ in }
        )
    }

    func group(_ name: String) throws -> RepoGroup? {
        try store.groups().first { $0.name == name }
    }

    func memberPaths(_ name: String) throws -> [String] {
        try group(name)?.repositories.map(\.path).sorted() ?? []
    }
}

@MainActor
@Suite("Sync", .serialized)
struct SyncModelTests {
    let api = FakeAPI()

    @Test("A group created on one Mac shows up on another, matched by remote, not path")
    func groupReachesOtherMac() async throws {
        let macA = try await TestMac(
            api: api,
            repositories: ["/dev/api": "github.com/o/api", "/dev/web": "github.com/o/web"]
        )
        let macB = try await TestMac(api: api, repositories: ["/dev/code/api": "github.com/o/api"])
        let school = try macA.store.createGroup(named: "School")
        try macA.store.add(["/dev/api", "/dev/web"], to: school)

        await macA.sync.sync()
        await macB.sync.sync()

        #expect(try macB.memberPaths("School") == ["/dev/code/api"])
        // `web` isn't cloned on Mac B; it's kept so Mac B's edits don't drop it.
        #expect(try macB.group("School")?.remoteOnlyMembers == ["github.com/o/web"])
        #expect(try macA.group("School")?.syncID == macB.group("School")?.syncID)
    }

    @Test("Edits on one Mac reach the other without dropping members it doesn't have")
    func editsKeepRemoteOnlyMembers() async throws {
        let macA = try await TestMac(
            api: api,
            repositories: ["/a/api": "github.com/o/api", "/a/web": "github.com/o/web"]
        )
        let macB = try await TestMac(
            api: api,
            repositories: ["/b/api": "github.com/o/api", "/b/cli": "github.com/o/cli"]
        )
        try macA.store.add(["/a/api", "/a/web"], to: macA.store.createGroup(named: "Work"))
        await macA.sync.sync()
        await macB.sync.sync()

        let work = try #require(try macB.group("Work"))
        try macB.store.rename(work, to: "Job")
        try macB.store.add(["/b/cli"], to: work)
        await macB.sync.sync()
        await macA.sync.sync()

        #expect(try macA.group("Work") == nil)
        #expect(try macA.memberPaths("Job") == ["/a/api", "/a/web"])
        #expect(try macA.group("Job")?.remoteOnlyMembers == ["github.com/o/cli"])
    }

    @Test("Deleting a group deletes it on the other Mac")
    func deletion() async throws {
        let macA = try await TestMac(api: api, repositories: [:])
        let macB = try await TestMac(api: api, repositories: [:])
        try macA.store.createGroup(named: "Temp")
        await macA.sync.sync()
        await macB.sync.sync()
        let temp = try #require(try macA.group("Temp"))

        let syncID = try #require(try macA.store.deleteGroup(temp))
        macA.sync.recordDeletion(of: syncID)
        await macA.sync.sync()
        await macB.sync.sync()

        #expect(try macB.store.groups().isEmpty)
    }

    @Test("Concurrent edits: the later one wins")
    func lastWriteWins() async throws {
        let macA = try await TestMac(api: api, repositories: ["/a/x": "github.com/o/x"])
        let macB = try await TestMac(api: api, repositories: ["/b/x": "github.com/o/x"])
        try macA.store.createGroup(named: "G")
        await macA.sync.sync()
        await macB.sync.sync()

        // Mac B edits after Mac A; Mac A syncs first.
        try macA.store.add(["/a/x"], to: try #require(try macA.group("G")))
        try await Task.sleep(for: .milliseconds(5))
        try macB.store.rename(try #require(try macB.group("G")), to: "Renamed")
        await macA.sync.sync()
        await macB.sync.sync()
        await macA.sync.sync()

        #expect(try macA.group("Renamed") != nil)
        #expect(try macB.group("Renamed") != nil)
    }

    @Test("Groups with the same name created on two Macs merge into one")
    func sameNameMerges() async throws {
        let macA = try await TestMac(api: api, repositories: [:])
        let macB = try await TestMac(api: api, repositories: [:])
        try macA.store.createGroup(named: "School")
        try macB.store.createGroup(named: "school")

        await macA.sync.sync()
        await macB.sync.sync()

        #expect(await api.serverGroups.count == 1)
        #expect(try macB.store.groups().count == 1)
        #expect(try macA.group("School")?.syncID == macB.store.groups().first?.syncID)
    }

    @Test("The stale branch setting syncs; the newer change wins")
    func settings() async throws {
        let macA = try await TestMac(api: api, repositories: [:])
        let macB = try await TestMac(api: api, repositories: [:])
        macA.defaults.set(30, forKey: AppPreferences.staleBranchDaysKey)
        macA.defaults.set(Date.now, forKey: AppPreferences.staleBranchDaysModifiedAtKey)

        await macA.sync.sync()
        await macB.sync.sync()

        #expect(AppPreferences.staleBranchDays(macB.defaults) == 30)
        #expect(await api.serverSettings.staleBranchDays == 30)
    }

    @Test("Removing a scan folder keeps its repositories in synced groups")
    func folderRemovalKeepsMembers() async throws {
        let macA = try await TestMac(api: api, repositories: ["/dev/api": "github.com/o/api"])
        try macA.store.add(["/dev/api"], to: macA.store.createGroup(named: "G"))

        try macA.store.preserveMemberships(of: ["/dev/api"], identity: { macA.identities[$0.path] })
        try macA.store.removeScanFolder(try #require(try macA.store.scanFolders().first))
        await macA.sync.sync()

        #expect(await api.serverGroups.values.first?.group.members == ["github.com/o/api"])
    }

    @Test("Signed out, nothing syncs")
    func signedOut() async throws {
        let store = LibraryStore(container: try Persistence.makeInMemoryContainer())
        let account = AccountModel(api: api, credentials: InMemoryCredentialStore(), workspace: FakeWorkspace())
        let sync = SyncModel(account: account, api: api, store: store, identity: { _ in nil })

        await sync.sync()

        #expect(await api.syncLog.isEmpty)
        #expect(sync.lastSynced == nil)
    }
}
