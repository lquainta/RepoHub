import Foundation

/// Runs git commands. ``ProcessGitRunner`` is the real implementation; tests
/// inject fakes.
public protocol GitCommandRunning: Sendable {
    /// Runs git with `arguments` in `directory` and returns its standard output.
    ///
    /// Arguments are passed directly to the process, never through a shell.
    ///
    /// - Throws: ``GitError`` if git cannot be started, exits with a non-zero
    ///   status, or times out; `CancellationError` if the task is cancelled.
    func run(_ arguments: [String], in directory: URL) async throws -> String
}
