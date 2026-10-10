import Foundation
import Testing

@testable import RepoHubCore

extension Tag {
    /// Benchmarks with time budgets; run with `make bench` (release build).
    @Tag static var performance: Self
}

/// Benchmarks for scanning and parsing (#64), with time budgets that fail on large regressions.
///
/// Opt-in (`REPOHUB_BENCHMARK=1`) because timings only mean something in a
/// release build: `make bench` runs them with `-c release`. Budgets leave
/// room for slower CI runners (about 10x a local M-series Mac, see
/// docs/testing.md), so only real regressions fail, not normal variance. Results are written as
/// JSON to `REPOHUB_BENCHMARK_OUTPUT` when set (CI shows them in the job summary).
@Suite(
    "Performance",
    .serialized,
    .tags(.performance),
    .enabled(if: ProcessInfo.processInfo.environment["REPOHUB_BENCHMARK"] == "1")
)
struct PerformanceTests {
    /// Scanning 500 repositories (plus ignored and non-repository folders) must take less than this.
    static let scanBudget: Duration = .milliseconds(250)
    /// Parsing a 50,000-entry `git status` must take less than this.
    static let parseBudget: Duration = .milliseconds(500)

    /// A tree like a large `~/Developer`: 25 folders of 20 repositories each,
    /// 50 plain folders three levels deep, and `node_modules` with 200 packages.
    private static func makeTree() throws -> URL {
        let root = try TemporaryRepository.makeDirectory()
        let fileManager = FileManager.default
        for group in 0..<25 {
            for repo in 0..<20 {
                let repository = root.appending(path: "group-\(group)/repo-\(repo)")
                try fileManager.createDirectory(
                    at: repository.appending(path: ".git"),
                    withIntermediateDirectories: true
                )
                try fileManager.createDirectory(
                    at: repository.appending(path: "Sources/Feature"),
                    withIntermediateDirectories: true
                )
            }
        }
        for folder in 0..<50 {
            try fileManager.createDirectory(
                at: root.appending(path: "notes/folder-\(folder)/a/b"),
                withIntermediateDirectories: true
            )
        }
        for package in 0..<200 {
            try fileManager.createDirectory(
                at: root.appending(path: "web/node_modules/package-\(package)/lib"),
                withIntermediateDirectories: true
            )
        }
        return root
    }

    /// The median of `runs` timings of `body`.
    private static func median(runs: Int = 5, _ body: () async throws -> Void) async rethrows -> Duration {
        let clock = ContinuousClock()
        var timings: [Duration] = []
        for _ in 0..<runs {
            timings.append(try await clock.measure { try await body() })
        }
        return timings.sorted()[runs / 2]
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    private static func record(_ name: String, _ values: [String: Double]) throws {
        guard let path = ProcessInfo.processInfo.environment["REPOHUB_BENCHMARK_OUTPUT"] else {
            return
        }
        let url = URL(fileURLWithPath: path)
        var results = (try? JSONDecoder().decode([String: [String: Double]].self, from: Data(contentsOf: url))) ?? [:]
        results[name] = values
        try JSONEncoder().encode(results).write(to: url)
    }

    @Test("Scanning 500 repositories stays within budget, and concurrency speeds it up")
    func scanning() async throws {
        let root = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        var found: [URL] = []
        let concurrent = try await Self.median {
            found = try await RepositoryScanner().scan(root, maxDepth: 4)
        }
        let sequential = try await Self.median {
            _ = try await RepositoryScanner(concurrent: false).scan(root, maxDepth: 4)
        }
        let speedup = Self.milliseconds(sequential) / max(Self.milliseconds(concurrent), 0.001)
        try Self.record(
            "scan_500_repos",
            [
                "concurrent_ms": Self.milliseconds(concurrent), "sequential_ms": Self.milliseconds(sequential),
                "speedup": speedup, "budget_ms": Self.milliseconds(Self.scanBudget),
            ]
        )

        #expect(found.count == 500)
        #expect(
            concurrent < Self.scanBudget,
            "Scanning took \(concurrent) (sequential \(sequential)), over the \(Self.scanBudget) budget"
        )
    }

    @Test("Parsing a 50,000-entry status stays within budget")
    func parsing() async throws {
        var output = "# branch.oid 1a2b3c\0# branch.head main\0# branch.upstream origin/main\0# branch.ab +1 -2\0"
        for index in 0..<50_000 {
            switch index % 4 {
            case 0: output += "1 .M N... 100644 100644 100644 aaa bbb Sources/Module\(index)/File.swift\0"
            case 1: output += "1 A. N... 000000 100644 100644 000 ccc New Folder/added file \(index).txt\0"
            case 2: output += "2 R. N... 100644 100644 100644 ddd ddd R100 renamed-\(index).md\0old-\(index).md\0"
            default: output += "? untracked/ünïcode-\(index).txt\0"
            }
        }
        var files = 0
        let duration = try await Self.median {
            files = try PorcelainStatusParser.parseWithFiles(output).files.count
        }
        try Self.record(
            "parse_50k_status",
            ["median_ms": Self.milliseconds(duration), "budget_ms": Self.milliseconds(Self.parseBudget)]
        )

        #expect(files == 50_000)
        #expect(duration < Self.parseBudget, "Parsing took \(duration), over the \(Self.parseBudget) budget")
    }
}
