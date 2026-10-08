import RepoHubCore
import Testing

@testable import RepoHub

@Suite("RepoHub app")
struct RepoHubTests {
    @Test("App links the core package")
    func linksCorePackage() {
        #expect(!RepoHubCore.version.isEmpty)
    }
}
