import Redis
import Vapor

private struct CacheStoreKey: StorageKey {
    typealias Value = any CacheStore
}

extension Application {
    /// The cache, configured by ``configureCache(redisURL:)``.
    var cacheStore: any CacheStore {
        get {
            guard let store = storage[CacheStoreKey.self] else {
                preconditionFailure("cacheStore accessed before configureCache(redisURL:)")
            }
            return store
        }
        set { storage[CacheStoreKey.self] = newValue }
    }

    /// Uses Redis at `redisURL`, or a process-local cache when it's `nil` (development and tests).
    func configureCache(redisURL: String?) throws {
        if let redisURL {
            redis.configuration = try RedisConfiguration(url: redisURL)
            cacheStore = RedisCacheStore(redis: redis)
        } else {
            logger.warning("REDIS_URL is not set; using an in-memory GitHub cache")
            cacheStore = InMemoryCacheStore()
        }
    }

    /// The GitHub API through the cache.
    var githubCache: GitHubCache {
        GitHubCache(store: cacheStore, api: VaporGitHubAPI(client: client), logger: logger)
    }
}
