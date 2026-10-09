import Foundation
import Testing

@testable import RepoHubCore

@Suite("RepositoryScanner", .tags(.integration))
struct RepositoryScannerTests {
    /// Builds a directory tree under a temporary root. Paths ending in
    /// `/.git/` become repository directories; `.git` without a trailing
    /// slash becomes a `.git` file (linked worktree / submodule).
    private final class Tree {
        let root: URL

        init(_ paths: [String]) throws {
            root = try TemporaryRepository.makeDirectory()
            for path in paths {
                let url = root.appendingPathComponent(path)
                if path.hasSuffix("/") {
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                } else {
                    try FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try Data("gitdir: elsewhere\n".utf8).write(to: url)
                }
            }
        }

        func relative(_ urls: [URL]) -> [String] {
            let prefix = root.standardizedFileURL.path + "/"
            return urls.map { String($0.path.dropFirst(prefix.count)) }
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private let scanner = RepositoryScanner()

    @Test("Finds repositories at any depth up to the limit, sorted by path")
    func findsRepositories() async throws {
        let tree = try Tree([
            "zeta/.git/",
            "alpha/.git/",
            "group/beta/.git/",
            "worktree/.git",
            "not-a-repo/src/",
        ])
        let found = try await scanner.scan(tree.root, maxDepth: 4)
        #expect(tree.relative(found) == ["alpha", "group/beta", "worktree", "zeta"])
    }

    @Test("Does not descend into repositories, so submodules aren't double-counted")
    func nestedRepositories() async throws {
        let tree = try Tree(["app/.git/", "app/Vendor/library/.git"])
        #expect(tree.relative(try await scanner.scan(tree.root, maxDepth: 4)) == ["app"])
    }

    @Test("Skips ignored, hidden, and too-deep directories")
    func skipsDirectories() async throws {
        let tree = try Tree([
            "web/node_modules/package/.git/",
            ".config/tool/.git/",
            "a/b/c/d/e/deep/.git/",
            "a/shallow/.git/",
        ])
        #expect(tree.relative(try await scanner.scan(tree.root, maxDepth: 4)) == ["a/shallow"])
        #expect(
            tree.relative(try await scanner.scan(tree.root, maxDepth: 6)).contains("a/b/c/d/e/deep")
        )
    }

    @Test("Custom ignore list replaces the defaults")
    func customIgnoreList() async throws {
        let tree = try Tree(["node_modules/pkg/.git/", "archive/old/.git/"])
        let found = try await RepositoryScanner(ignoredNames: ["archive"]).scan(tree.root, maxDepth: 4)
        #expect(tree.relative(found) == ["node_modules/pkg"])
    }

    @Test("Symbolic link cycles don't hang or duplicate results")
    func symlinkCycle() async throws {
        let tree = try Tree(["projects/api/.git/"])
        try FileManager.default.createSymbolicLink(
            at: tree.root.appendingPathComponent("projects/loop"),
            withDestinationURL: tree.root
        )
        #expect(tree.relative(try await scanner.scan(tree.root, maxDepth: 10)) == ["projects/api"])
    }

    @Test("A root that is itself a repository is returned alone")
    func rootIsRepository() async throws {
        let tree = try Tree([".git/", "packages/inner/.git/"])
        let found = try await scanner.scan(tree.root, maxDepth: 4)
        #expect(found == [tree.root.standardizedFileURL])
    }

    @Test("Missing folder throws folderNotFound")
    func missingFolder() async {
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")
        await #expect(throws: ScanError.folderNotFound(path: missing.path)) {
            try await scanner.scan(missing, maxDepth: 4)
        }
    }
}
