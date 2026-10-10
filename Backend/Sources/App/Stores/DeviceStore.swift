import Fluent
import Foundation

/// Reads and writes signed-in devices and their refresh tokens.
protocol DeviceStore: Sendable {
    func create(userID: UUID, name: String, refreshTokenHash: Data, expiresAt: Date) async throws -> Device
    /// The device with this refresh token hash, if it isn't revoked or expired.
    func findActive(refreshTokenHash: Data, now: Date) async throws -> Device?
    /// Replaces the refresh token (rotation) and records activity.
    func rotate(_ device: Device, refreshTokenHash: Data, expiresAt: Date, now: Date) async throws
    /// Signs the device out.
    func revoke(id: UUID, now: Date) async throws
    func devices(userID: UUID) async throws -> [Device]
}

struct FluentDeviceStore: DeviceStore {
    let database: any Database

    func create(userID: UUID, name: String, refreshTokenHash: Data, expiresAt: Date) async throws -> Device {
        let device = Device(userID: userID, name: name, refreshTokenHash: refreshTokenHash, refreshExpiresAt: expiresAt)
        try await device.create(on: database)
        return device
    }

    func findActive(refreshTokenHash: Data, now: Date) async throws -> Device? {
        try await Device.query(on: database)
            .filter(\.$refreshTokenHash == refreshTokenHash)
            .filter(\.$revokedAt == nil)
            .filter(\.$refreshExpiresAt > now)
            .first()
    }

    func rotate(_ device: Device, refreshTokenHash: Data, expiresAt: Date, now: Date) async throws {
        device.refreshTokenHash = refreshTokenHash
        device.refreshExpiresAt = expiresAt
        device.lastSeenAt = now
        try await device.update(on: database)
    }

    func revoke(id: UUID, now: Date) async throws {
        try await Device.query(on: database).filter(\.$id == id).set(\.$revokedAt, to: now).update()
    }

    func devices(userID: UUID) async throws -> [Device] {
        try await Device.query(on: database).filter(\.$user.$id == userID).sort(\.$createdAt).all()
    }
}
