import Foundation
import Redis
import Vapor

/// A key-value cache with expiry. ``RedisCacheStore`` is used whenever
/// `REDIS_URL` is set; ``InMemoryCacheStore`` is for tests and for local
/// development without Redis.
protocol CacheStore: Sendable {
    func get<Value: Decodable & Sendable>(_ key: String, as type: Value.Type) async throws -> Value?
    /// Stores `value`, replacing any existing value, for `seconds`.
    func set<Value: Encodable & Sendable>(_ key: String, to value: Value, expiresIn seconds: Int) async throws
    func delete(_ keys: [String]) async throws
    /// Adds `member` to the set at `key` and (re)sets the set's expiry.
    func addToSet(_ key: String, member: String, expiresIn seconds: Int) async throws
    func members(ofSet key: String) async throws -> [String]
}

/// A cache in Redis. Values are stored as JSON.
struct RedisCacheStore: CacheStore {
    /// Vapor's Redis wrapper, which is `Sendable` (RediStack's `RedisClient` protocol isn't).
    let redis: Application.Redis

    func get<Value: Decodable & Sendable>(_ key: String, as type: Value.Type) async throws -> Value? {
        try await redis.get(RedisKey(key), asJSON: type)
    }

    func set<Value: Encodable & Sendable>(_ key: String, to value: Value, expiresIn seconds: Int) async throws {
        try await redis.setex(RedisKey(key), toJSON: value, expirationInSeconds: max(1, seconds))
    }

    func delete(_ keys: [String]) async throws {
        guard !keys.isEmpty else {
            return
        }
        _ = try await redis.delete(keys.map { RedisKey($0) }).get()
    }

    func addToSet(_ key: String, member: String, expiresIn seconds: Int) async throws {
        _ = try await redis.sadd(member, to: RedisKey(key)).get()
        _ = try await redis.expire(RedisKey(key), after: .seconds(Int64(max(1, seconds)))).get()
    }

    func members(ofSet key: String) async throws -> [String] {
        try await redis.smembers(of: RedisKey(key), as: String.self).get().compactMap { $0 }
    }
}

/// A process-local cache with the same semantics as ``RedisCacheStore``.
actor InMemoryCacheStore: CacheStore {
    private struct Entry {
        var data: Data
        var expiresAt: Date
    }

    private var values: [String: Entry] = [:]
    private var sets: [String: (members: Set<String>, expiresAt: Date)] = [:]
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { .now }) {
        self.now = now
    }

    func get<Value: Decodable & Sendable>(_ key: String, as type: Value.Type) async throws -> Value? {
        guard let entry = values[key], entry.expiresAt > now() else {
            values[key] = nil
            return nil
        }
        return try JSONDecoder().decode(type, from: entry.data)
    }

    func set<Value: Encodable & Sendable>(_ key: String, to value: Value, expiresIn seconds: Int) async throws {
        values[key] = Entry(data: try JSONEncoder().encode(value), expiresAt: now().addingTimeInterval(Double(seconds)))
    }

    func delete(_ keys: [String]) async throws {
        for key in keys {
            values[key] = nil
            sets[key] = nil
        }
    }

    func addToSet(_ key: String, member: String, expiresIn seconds: Int) async throws {
        var members = (sets[key]?.expiresAt ?? .distantPast) > now() ? sets[key]?.members ?? [] : []
        members.insert(member)
        sets[key] = (members, now().addingTimeInterval(Double(seconds)))
    }

    func members(ofSet key: String) async throws -> [String] {
        guard let set = sets[key], set.expiresAt > now() else {
            return []
        }
        return set.members.sorted()
    }
}
