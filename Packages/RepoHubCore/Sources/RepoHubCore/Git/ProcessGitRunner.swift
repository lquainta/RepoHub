import Foundation

#if canImport(Glibc)
    import Glibc
#endif

/// Runs the `git` executable as a child process.
public struct ProcessGitRunner: GitCommandRunning {
    /// Path to the git executable.
    public let executableURL: URL
    /// Maximum time a command may run before it is terminated.
    public let timeout: Duration
    /// Variables added to (or overriding) the inherited environment.
    public let environmentOverrides: [String: String]

    /// Creates a runner.
    ///
    /// - Parameters:
    ///   - executableURL: The git binary. Defaults to `/usr/bin/git`.
    ///   - timeout: Per-command time limit. Defaults to 30 seconds.
    ///   - environmentOverrides: Extra environment variables for every command.
    public init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/git"),
        timeout: Duration = .seconds(30),
        environmentOverrides: [String: String] = [:]
    ) {
        self.executableURL = executableURL
        self.timeout = timeout
        self.environmentOverrides = environmentOverrides
    }

    /// Runs git and returns its standard output.
    public func run(_ arguments: [String], in directory: URL) async throws -> String {
        let command = ([executableURL.lastPathComponent] + arguments).joined(separator: " ")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw GitError.gitNotFound(path: executableURL.path)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue
        else {
            throw GitError.directoryNotFound(path: directory.path)
        }

        let process = ChildProcess(
            executableURL: executableURL,
            arguments: arguments,
            directory: directory,
            environment: environment()
        )
        let result = try await withThrowingTaskGroup(of: ChildProcess.Result?.self) { group in
            group.addTask { try await process.run() }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let result = first else {
                throw GitError.timedOut(command: command)
            }
            return result
        }

        // Decoding is deliberately lossy: on Linux, file names need not be valid
        // UTF-8, and one odd path must not make the whole repository unreadable.
        guard result.exitCode == 0 else {
            // swiftlint:disable:next optional_data_string_conversion
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            if stderr.contains("not a git repository") {
                throw GitError.notARepository(path: directory.path)
            }
            throw GitError.commandFailed(
                command: command,
                exitCode: result.exitCode,
                stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: result.stdout, as: UTF8.self)
    }

    private func environment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        // Never block on credential prompts, and keep messages in English so
        // errors can be recognized.
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["LC_ALL"] = "C"
        environment.merge(environmentOverrides) { _, override in override }
        return environment
    }
}

/// A single child process run, with output captured and cancellation support.
///
/// `Process` and `FileHandle` are not `Sendable`; all mutable state is guarded
/// by `lock`, which makes the `@unchecked Sendable` conformance safe.
private final class ChildProcess: @unchecked Sendable {
    struct Result: Sendable {
        let exitCode: Int32
        let stdout: Data
        let stderr: Data
    }

    private let process = Process()
    private let lock = NSLock()
    private var isCancelled = false

    init(executableURL: URL, arguments: [String], directory: URL, environment: [String: String]) {
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
    }

    func run() async throws -> Result {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Swift.Result { try self.runBlocking() })
                }
            }
        } onCancel: {
            terminate()
        }
    }

    private func terminate() {
        lock.withLock {
            isCancelled = true
            if process.isRunning {
                process.terminate()
            }
        }
    }

    /// Starts the process and blocks until it exits. Must not run on the
    /// cooperative thread pool.
    private func runBlocking() throws -> Result {
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        try lock.withLock {
            guard !isCancelled else { throw CancellationError() }
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            try withTerminationSignalsUnblocked { try process.run() }
        }

        // Drain stderr concurrently so a full pipe buffer can't deadlock the child.
        let stderrReader = PipeReader(handle: stderrPipe.fileHandleForReading)
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stderrReader.readToEnd()
            readers.leave()
        }
        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        readers.wait()
        process.waitUntilExit()

        if lock.withLock({ isCancelled }) {
            throw CancellationError()
        }
        return Result(exitCode: process.terminationStatus, stdout: stdout, stderr: stderrReader.data)
    }
}

/// Runs `body` with SIGTERM and SIGINT unblocked on the current thread.
///
/// A child process inherits its launching thread's signal mask. On Linux,
/// libdispatch worker threads block most signals, so without this a child
/// launched from a dispatch queue ignores `terminate()` and timeouts or
/// cancellation would wait for it to finish on its own.
private func withTerminationSignalsUnblocked<T>(_ body: () throws -> T) rethrows -> T {
    #if canImport(Glibc)
        var signals = sigset_t()
        var previous = sigset_t()
        sigemptyset(&signals)
        sigaddset(&signals, SIGTERM)
        sigaddset(&signals, SIGINT)
        pthread_sigmask(SIG_UNBLOCK, &signals, &previous)
        defer { pthread_sigmask(SIG_SETMASK, &previous, nil) }
    #endif
    return try body()
}

/// Reads a pipe to end-of-file on a background thread.
private final class PipeReader: @unchecked Sendable {
    private let handle: FileHandle
    private(set) var data = Data()

    init(handle: FileHandle) {
        self.handle = handle
    }

    func readToEnd() {
        data = handle.readDataToEndOfFile()
    }
}
