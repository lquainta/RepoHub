import Testing

@testable import RepoHubCore

@Suite("RepoHubCore")
struct RepoHubCoreTests {
    @Test("Version is a semantic version")
    func versionIsSemantic() {
        let parts = RepoHubCore.version.split(separator: ".")
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { Int($0) != nil })
    }
}
