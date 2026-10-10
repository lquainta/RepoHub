import Foundation

/// Maps changed file paths to the tracked repositories they belong to.
///
/// A path belongs to the repository with the longest matching path prefix, so
/// a change in a nested repository only refreshes that repository. Changes
/// that can't affect `git status` (object storage, reflogs, git's own lock
/// files) are ignored, which also stops RepoHub's own git commands from
/// triggering refresh loops.
///
/// FSEvents reports canonical paths (`/private/var/...`), while tracked paths
/// may go through symbolic links (`/var/...`, or a linked folder), so each
/// repository is matched by both its tracked and its canonical path.
struct ChangeRouter {
    /// A path to match against, and the tracked repository path it stands for.
    private let prefixes: [(match: String, repository: String)]

    /// Creates a router.
    ///
    /// - Parameters:
    ///   - paths: Tracked repositories' working tree roots.
    ///   - canonicalize: Resolves symbolic links; defaults to `realpath(3)`.
    init(
        repositories paths: some Sequence<String>,
        canonicalize: (String) -> String? = ChangeRouter.realPath
    ) {
        var prefixes: [(String, String)] = []
        for path in paths {
            let repository = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
            prefixes.append((repository, repository))
            if let canonical = canonicalize(repository), canonical != repository {
                prefixes.append((canonical, repository))
            }
        }
        // Longest first so nested repositories win.
        self.prefixes = prefixes.sorted { $0.0.count > $1.0.count }
    }

    /// The tracked repositories affected by changes at `changedPaths`.
    func repositories(affectedBy changedPaths: some Sequence<String>) -> Set<String> {
        var affected: Set<String> = []
        for path in changedPaths {
            guard let prefix = prefixes.first(where: { path == $0.match || path.hasPrefix($0.match + "/") }) else {
                continue
            }
            let relative = path.dropFirst(prefix.match.count)
            if !Self.isIgnored(relative) {
                affected.insert(prefix.repository)
            }
        }
        return affected
    }

    /// The canonical path with symbolic links resolved, or `nil` if it doesn't exist.
    static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else {
            return nil
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Paths inside `.git` that change without affecting status.
    private static func isIgnored(_ relative: Substring) -> Bool {
        guard relative.hasPrefix("/.git/") else {
            return false
        }
        let inGit = relative.dropFirst("/.git/".count)
        return inGit.hasPrefix("objects/") || inGit.hasPrefix("logs/") || inGit.hasSuffix(".lock")
            || inGit == "FETCH_HEAD" || inGit.hasPrefix("fsmonitor")
    }
}
