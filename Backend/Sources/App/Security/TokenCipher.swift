import Crypto
import Foundation

/// Encrypts GitHub tokens at rest with AES-256-GCM.
///
/// Ciphertext is `version (1 byte) ‖ nonce ‖ ciphertext ‖ tag`. The version
/// byte lets the key be rotated later without guessing how old rows were sealed.
struct TokenCipher: Sendable {
    /// Why a ciphertext couldn't be opened.
    enum CipherError: Error, Equatable {
        case unsupportedVersion(UInt8)
        case malformed
    }

    private static let version: UInt8 = 1
    private let key: SymmetricKey

    /// - Parameter key: Exactly 32 bytes.
    init(key: Data) {
        self.key = SymmetricKey(data: key)
    }

    func seal(_ plaintext: String) throws -> Data {
        let box = try AES.GCM.seal(Data(plaintext.utf8), using: key)
        guard let combined = box.combined else {
            throw CipherError.malformed
        }
        return Data([Self.version]) + combined
    }

    /// - Throws: ``CipherError`` or `CryptoKitError` if the data was altered or sealed with another key.
    func open(_ ciphertext: Data) throws -> String {
        guard let version = ciphertext.first else {
            throw CipherError.malformed
        }
        guard version == Self.version else {
            throw CipherError.unsupportedVersion(version)
        }
        let box = try AES.GCM.SealedBox(combined: ciphertext.dropFirst())
        guard let plaintext = String(data: try AES.GCM.open(box, using: key), encoding: .utf8) else {
            throw CipherError.malformed
        }
        return plaintext
    }
}
