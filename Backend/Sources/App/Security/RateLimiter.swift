import Foundation
import Logging

/// Fixed-window rate limiting over the shared cache, so limits hold across instances.
struct RateLimiter: Sendable {
    /// The decision for one request.
    enum Decision: Equatable {
        case allowed(remaining: Int)
        /// Over the limit; retry after this many seconds.
        case limited(retryAfter: Int)
    }

    let store: any CacheStore
    var logger = Logger(label: "com.lquainta.RepoHub.RateLimiter")
    var now: @Sendable () -> Date = { .now }

    /// Counts a request for `key` against `limit` per `window` seconds.
    ///
    /// If the cache is unavailable, requests are allowed: an outage of the
    /// cache shouldn't take the API down with it.
    func check(_ key: String, limit: Int, window: Int = 60) async -> Decision {
        let epoch = Int(now().timeIntervalSince1970)
        let windowStart = epoch - epoch % window
        do {
            let count = try await store.increment("ratelimit:\(key):\(windowStart)", expiresIn: window + 1)
            if count > limit {
                return .limited(retryAfter: max(1, windowStart + window - epoch))
            }
            return .allowed(remaining: limit - count)
        } catch {
            logger.warning("Rate limiter unavailable, allowing request: \(error)")
            return .allowed(remaining: limit)
        }
    }
}
