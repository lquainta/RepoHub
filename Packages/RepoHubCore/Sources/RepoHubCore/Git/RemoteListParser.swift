/// Parses `git remote -v` output.
public enum RemoteListParser {
    /// Parses lines such as `origin\thttps://github.com/o/r.git (fetch)`.
    ///
    /// - Returns: Remotes sorted by name.
    /// - Throws: ``GitError/unexpectedOutput(_:)`` if a line is malformed.
    public static func parse(_ output: String) throws -> [Remote] {
        var fetch: [String: String] = [:]
        var push: [String: String] = [:]
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else {
                throw GitError.unexpectedOutput("Malformed remote line: \(line)")
            }
            let name = String(parts[0])
            let rest = parts[1]
            if rest.hasSuffix(" (fetch)") {
                fetch[name] = String(rest.dropLast(" (fetch)".count))
            } else if rest.hasSuffix(" (push)") {
                push[name] = String(rest.dropLast(" (push)".count))
            } else {
                throw GitError.unexpectedOutput("Malformed remote line: \(line)")
            }
        }
        return fetch.keys.sorted().compactMap { name in
            guard let url = fetch[name] else {
                return nil
            }
            let pushURL = push[name].flatMap { $0 == url ? nil : $0 }
            return Remote(name: name, fetchURL: url, pushURL: pushURL)
        }
    }
}
