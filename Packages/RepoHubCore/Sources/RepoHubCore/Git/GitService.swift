import Foundation

/// Reads and changes repository state. ``GitService`` is the real
/// implementation; the app's view models depend on this protocol so tests can
/// inject fakes.
public protocol GitServicing: Sendable {
    /// Returns the current status of the repository at `repository`.
    func status(of repository: URL) async throws -> RepoStatus
    /// Returns the status plus changed files, branches, recent commits, remotes, and stashes.
    func details(of repository: URL, commitLimit: Int) async throws -> RepositoryDetails
    /// Downloads objects and refs from every remote and prunes deleted remote branches.
    func fetch(_ repository: URL) async throws
    /// Fast-forwards the current branch to its upstream. Never creates a merge commit.
    func pull(_ repository: URL) async throws
    /// Returns the configured remotes, sorted by name.
    func remotes(of repository: URL) async throws -> [Remote]
    /// Finds local branches that are merged, whose upstream is gone, or that are inactive.
    func staleBranches(of repository: URL, inactiveAfterDays: Int?) async throws -> StaleBranchReport
    /// Deletes local branches (and optionally their upstreams), never the current or default branch.
    func deleteBranches(
        _ branches: [Branch],
        in repository: URL,
        force: Bool,
        deleteRemote: Bool
    ) async throws -> [BranchDeletionResult]
}

extension GitServicing {
    /// Returns details with the 20 most recent commits.
    public func details(of repository: URL) async throws -> RepositoryDetails {
        try await details(of: repository, commitLimit: 20)
    }
}

/// Reads repository state by running git.
public struct GitService: GitServicing {
    private let runner: any GitCommandRunning

    /// Creates a service that runs commands with `runner`.
    public init(runner: any GitCommandRunning = ProcessGitRunner()) {
        self.runner = runner
    }

    /// Returns the current status of the repository at `repository`.
    ///
    /// - Throws: ``GitError`` if git fails or its output can't be parsed.
    public func status(of repository: URL) async throws -> RepoStatus {
        var status = try PorcelainStatusParser.parse(try await runStatus(in: repository))

        // A repository with no commits has nothing to log.
        if case .unborn = status.head {
            return status
        }
        let log = try await runner.run(
            ["--no-optional-locks", "log", "-1", "--format=\(CommitSummaryParser.format)"],
            in: repository
        )
        status.lastCommit = try CommitSummaryParser.parse(log)
        return status
    }

    /// Returns the status plus changed files, branches, the `commitLimit` most
    /// recent commits, remotes, and stashes of the repository at `repository`.
    ///
    /// The underlying git commands run concurrently.
    ///
    /// - Throws: ``GitError`` if any git command fails or its output can't be parsed.
    public func details(of repository: URL, commitLimit: Int = 20) async throws -> RepositoryDetails {
        async let statusOutput = runStatus(in: repository)
        async let branchOutput = runner.run(
            ["--no-optional-locks", "for-each-ref", "--format=\(BranchListParser.format)"]
                + BranchListParser.refPatterns,
            in: repository
        )
        async let remotes = remotes(of: repository)
        async let stashOutput = runner.run(
            ["--no-optional-locks", "stash", "list", "--format=\(StashListParser.format)"],
            in: repository
        )

        let (status, files) = try PorcelainStatusParser.parseWithFiles(try await statusOutput)
        var details = RepositoryDetails(
            status: status,
            files: files,
            branches: try BranchListParser.parse(try await branchOutput),
            remotes: try await remotes,
            stashes: try StashListParser.parse(try await stashOutput)
        )
        // A repository with no commits has nothing to log.
        if case .unborn = status.head {
            return details
        }
        let log = try await runner.run(
            ["--no-optional-locks", "log", "-\(max(1, commitLimit))", "--format=\(CommitSummaryParser.format)"],
            in: repository
        )
        details.recentCommits = try CommitSummaryParser.parseList(log)
        details.status.lastCommit = details.recentCommits.first
        return details
    }

    /// Runs `git fetch --all --prune`.
    ///
    /// - Throws: ``GitError`` if a remote can't be reached or authentication fails.
    public func fetch(_ repository: URL) async throws {
        _ = try await runner.run(["fetch", "--all", "--prune", "--quiet"], in: repository)
    }

    /// Runs `git pull --ff-only`, so local commits are never merged or rebased.
    ///
    /// - Throws: ``GitError/commandFailed(command:exitCode:stderr:)`` if the
    ///   branch has diverged from its upstream, has no upstream, or local
    ///   changes would be overwritten.
    public func pull(_ repository: URL) async throws {
        _ = try await runner.run(["pull", "--ff-only", "--quiet"], in: repository)
    }

    /// Runs `git remote -v`.
    public func remotes(of repository: URL) async throws -> [Remote] {
        try RemoteListParser.parse(try await runner.run(["remote", "-v"], in: repository))
    }

    /// Finds stale local branches.
    ///
    /// The default branch is `origin/HEAD` if it is set, otherwise `main` or
    /// `master` if one exists, otherwise the current branch. Merged means
    /// reachable from the default branch (its remote-tracking ref when there is
    /// no local copy).
    public func staleBranches(of repository: URL, inactiveAfterDays: Int?) async throws -> StaleBranchReport {
        let branches = try BranchListParser.parse(
            try await runner.run(
                ["--no-optional-locks", "for-each-ref", "--format=\(BranchListParser.format)"]
                    + BranchListParser.refPatterns,
                in: repository
            )
        )
        let current = branches.first { $0.isCurrent }?.name
        let (defaultName, defaultRef) = try await defaultBranch(in: repository, branches: branches, current: current)
        var merged: Set<String> = []
        if let defaultRef {
            let output = try await runner.run(
                ["for-each-ref", "--merged=\(defaultRef)", "--format=%(refname:short)", "refs/heads"],
                in: repository
            )
            merged = Set(output.split(separator: "\n").map(String.init))
        }
        return StaleBranchReport(
            defaultBranch: defaultName,
            currentBranch: current,
            candidates: StaleBranchDetector.candidates(
                in: branches,
                mergedNames: merged,
                defaultBranch: defaultName,
                inactiveAfterDays: inactiveAfterDays
            )
        )
    }

    /// Deletes local branches one at a time and reports each outcome.
    ///
    /// - Without `force`, uses `git branch -d`, which refuses to delete
    ///   unmerged work. With `force`, uses `-D`.
    /// - The current and default branches are refused regardless of `force`.
    /// - With `deleteRemote`, also deletes each branch's upstream on its remote
    ///   (`git push <remote> --delete <branch>`) after the local delete succeeds,
    ///   unless the upstream is already gone.
    public func deleteBranches(
        _ branches: [Branch],
        in repository: URL,
        force: Bool,
        deleteRemote: Bool
    ) async throws -> [BranchDeletionResult] {
        let report = try await staleBranches(of: repository, inactiveAfterDays: nil)
        let protected = Set([report.defaultBranch] + (report.currentBranch.map { [$0] } ?? []))
        let remotes = deleteRemote ? try await remotes(of: repository).map(\.name) : []

        var results: [BranchDeletionResult] = []
        for branch in branches {
            guard !branch.isRemote, !protected.contains(branch.name) else {
                results.append(
                    BranchDeletionResult(
                        name: branch.name,
                        error: .commandFailed(
                            command: "git branch -d \(branch.name)",
                            exitCode: 1,
                            stderr: "Refusing to delete the current or default branch."
                        )
                    )
                )
                continue
            }
            do {
                _ = try await runner.run(["branch", force ? "-D" : "-d", "--", branch.name], in: repository)
            } catch let error as GitError {
                results.append(BranchDeletionResult(name: branch.name, error: error))
                continue
            }
            var result = BranchDeletionResult(name: branch.name)
            if deleteRemote, !branch.isUpstreamGone, let upstream = branch.upstream,
                let remote = remotes.filter({ upstream.hasPrefix($0 + "/") }).max(by: { $0.count < $1.count })
            {
                let remoteBranch = String(upstream.dropFirst(remote.count + 1))
                do {
                    _ = try await runner.run(["push", "--quiet", remote, "--delete", remoteBranch], in: repository)
                    result.deletedRemote = true
                } catch let error as GitError {
                    result.error = error
                }
            }
            results.append(result)
        }
        return results
    }

    /// Returns the default branch's name and the ref to compare against, if any.
    private func defaultBranch(
        in repository: URL,
        branches: [Branch],
        current: String?
    ) async throws -> (name: String, ref: String?) {
        let local = Set(branches.filter { !$0.isRemote }.map(\.name))
        let remoteHead = try? await runner.run(
            ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"],
            in: repository
        )
        if let remoteHead = remoteHead?.trimmingCharacters(in: .whitespacesAndNewlines),
            remoteHead.hasPrefix("origin/")
        {
            let name = String(remoteHead.dropFirst("origin/".count))
            return (name, local.contains(name) ? name : remoteHead)
        }
        for candidate in ["main", "master"] where local.contains(candidate) {
            return (candidate, candidate)
        }
        return (current ?? "main", current)
    }

    private func runStatus(in repository: URL) async throws -> String {
        try await runner.run(
            [
                // Don't take index.lock for a read; avoids conflicts with the user's own git commands.
                "--no-optional-locks",
                "status", "--porcelain=v2", "--branch", "--show-stash", "-z", "--untracked-files=normal",
            ],
            in: repository
        )
    }
}
