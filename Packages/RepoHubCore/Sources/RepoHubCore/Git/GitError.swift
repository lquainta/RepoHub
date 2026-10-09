/// Errors raised while running git or interpreting its output.
public enum GitError: Error, Equatable, Sendable {
    /// No executable exists at the configured git path.
    case gitNotFound(path: String)
    /// The directory to run git in does not exist.
    case directoryNotFound(path: String)
    /// The directory exists but is not inside a git repository.
    case notARepository(path: String)
    /// git exited with a non-zero status.
    case commandFailed(command: String, exitCode: Int32, stderr: String)
    /// git did not finish within the allowed time and was terminated.
    case timedOut(command: String)
    /// git's output did not match the expected format.
    case unexpectedOutput(String)
}
