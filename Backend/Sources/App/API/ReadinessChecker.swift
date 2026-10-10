import Foundation

/// Checks whether the server's dependencies are reachable, for `GET /ready`.
struct ReadinessChecker: Sendable {
    /// One dependency's result.
    struct Result: Equatable, Sendable {
        var isUp: Bool
        var latency: Duration
        /// Why it's down; never contains credentials.
        var error: String?

        /// The latency in whole milliseconds.
        var latencyMilliseconds: Int {
            let (seconds, attoseconds) = latency.components
            return Int(seconds) * 1_000 + Int(attoseconds / 1_000_000_000_000_000)
        }
    }

    /// The default time a check may take before it counts as down.
    static let defaultTimeout: Duration = .seconds(2)

    let database: @Sendable () async throws -> Void
    let cache: @Sendable () async throws -> Void
    var timeout: Duration = defaultTimeout

    /// Runs both checks concurrently.
    func check() async -> (database: Result, cache: Result) {
        async let database = run(database)
        async let cache = run(cache)
        return await (database, cache)
    }

    private func run(_ probe: @escaping @Sendable () async throws -> Void) async -> Result {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask {
                    try await probe()
                    return true
                }
                group.addTask { [timeout] in
                    try await Task.sleep(for: timeout)
                    return false
                }
                defer { group.cancelAll() }
                guard try await group.next() == true else {
                    throw ReadinessError.timedOut
                }
            }
            return Result(isUp: true, latency: clock.now - start)
        } catch ReadinessError.timedOut {
            return Result(isUp: false, latency: clock.now - start, error: "Timed out after \(timeout)")
        } catch {
            // Type name only: driver errors can include connection strings.
            return Result(isUp: false, latency: clock.now - start, error: "Unreachable (\(type(of: error)))")
        }
    }
}

private enum ReadinessError: Error {
    case timedOut
}
