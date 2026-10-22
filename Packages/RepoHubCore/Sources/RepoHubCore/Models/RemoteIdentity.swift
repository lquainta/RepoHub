import Foundation

/// Identifies a repository across Macs by its remote, because local paths differ.
///
/// The same repository cloned over HTTPS on one Mac and SSH on another has the
/// same identity: `host/path`, lowercased, without a scheme, user, port, or
/// `.git` suffix. For example, `git@github.com:Owner/Repo.git` and
/// `https://github.com/owner/repo` are both `github.com/owner/repo`.
public enum RemoteIdentity {
    /// The identity of `remoteURL`, or `nil` for local paths and malformed URLs.
    public static func normalize(_ remoteURL: String) -> String? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespaces)
        let host: Substring
        let path: Substring
        if let url = URLComponents(string: trimmed), let scheme = url.scheme?.lowercased(),
            ["https", "http", "ssh", "git"].contains(scheme), let urlHost = url.host, !urlHost.isEmpty
        {
            host = Substring(urlHost)
            path = Substring(url.path)
        } else if !trimmed.contains("://"), !trimmed.hasPrefix("/"), let colon = trimmed.firstIndex(of: ":") {
            // scp-like syntax: [user@]host:path
            guard let scpHost = trimmed[..<colon].split(separator: "@").last, !scpHost.isEmpty else {
                return nil
            }
            host = scpHost
            path = trimmed[trimmed.index(after: colon)...]
        } else {
            return nil
        }
        var parts = path.split(separator: "/", omittingEmptySubsequences: true).map { $0.lowercased() }
        guard !parts.isEmpty else {
            return nil
        }
        if let last = parts.last, last.hasSuffix(".git") {
            parts[parts.count - 1] = String(last.dropLast(4))
        }
        guard parts.allSatisfy({ !$0.isEmpty }) else {
            return nil
        }
        return ([host.lowercased()] + parts).joined(separator: "/")
    }
}
