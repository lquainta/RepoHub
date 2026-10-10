import Foundation

/// A repository on github.com, identified by owner and name.
public struct GitHubRepository: Sendable, Equatable, Hashable, Codable {
    /// The user or organization, such as `lquainta`.
    public var owner: String
    /// The repository name, such as `RepoHub`.
    public var name: String

    /// Creates a GitHub repository reference.
    public init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    /// `owner/name`.
    public var fullName: String { "\(owner)/\(name)" }

    /// The repository's page, `https://github.com/owner/name`.
    public var webURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(owner)/\(name)"
        // Owner and name are validated to URL-safe characters in `init?(remoteURL:)`.
        return components.url ?? URL(fileURLWithPath: "/")
    }

    /// Parses a git remote URL that points at github.com.
    ///
    /// Accepts HTTPS (`https://github.com/o/r.git`), SSH (`git@github.com:o/r.git`,
    /// `ssh://git@github.com/o/r`), and `git://` forms, with or without `.git`.
    /// Returns `nil` for other hosts (including GitHub Enterprise) and malformed URLs.
    public init?(remoteURL: String) {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespaces)
        let path: Substring
        if let url = URLComponents(string: trimmed), let scheme = url.scheme, url.host != nil {
            guard ["https", "http", "ssh", "git"].contains(scheme.lowercased()),
                url.host?.lowercased() == "github.com"
            else {
                return nil
            }
            path = Substring(url.path)
        } else if let colon = trimmed.firstIndex(of: ":"), !trimmed.contains("://") {
            // scp-like syntax: [user@]github.com:owner/name
            let host = trimmed[..<colon].split(separator: "@").last.map { $0.lowercased() }
            guard host == "github.com" else {
                return nil
            }
            path = trimmed[trimmed.index(after: colon)...]
        } else {
            return nil
        }

        var parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 2 else {
            return nil
        }
        if parts[1].hasSuffix(".git") {
            parts[1].removeLast(4)
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }) else {
            return nil
        }
        self.init(owner: parts[0], name: parts[1])
    }
}
