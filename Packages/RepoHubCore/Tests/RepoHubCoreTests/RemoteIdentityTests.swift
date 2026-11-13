import RepoHubCore
import Testing

@Suite("RemoteIdentity")
struct RemoteIdentityTests {
    @Test(
        "HTTPS, SSH, scp-like, and git URLs of one repository have the same identity",
        arguments: [
            "https://github.com/Owner/Repo.git",
            "https://github.com/owner/repo",
            "http://user@github.com/owner/repo/",
            "git@github.com:Owner/Repo.git",
            "ssh://git@github.com:22/owner/repo.git",
            "git://github.com/owner/repo",
            "  github.com:owner/repo  ",
        ]
    )
    func sameRepository(url: String) {
        #expect(RemoteIdentity.normalize(url) == "github.com/owner/repo")
    }

    @Test("Other hosts and nested paths keep their host and full path")
    func otherHosts() {
        #expect(RemoteIdentity.normalize("git@gitlab.com:group/sub/project.git") == "gitlab.com/group/sub/project")
        #expect(RemoteIdentity.normalize("https://git.example.edu/cs471/hw.git") == "git.example.edu/cs471/hw")
    }

    @Test("Local paths and malformed URLs have no identity", arguments: ["/srv/git/repo.git", "", "https://", "host:"])
    func noIdentity(url: String) {
        #expect(RemoteIdentity.normalize(url) == nil)
    }
}
