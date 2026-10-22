import Foundation
import Security

/// What the app keeps between launches to stay signed in.
struct StoredCredentials: Equatable, Sendable, Codable {
    /// Single-use; replaced every time the session is refreshed.
    var refreshToken: String
    /// Shown while the session is being restored.
    var user: UserProfile
}

/// Keeps the signed-in device's credentials. The real store is the Keychain;
/// tests use an in-memory fake.
protocol CredentialStoring: Sendable {
    func load() throws -> StoredCredentials?
    func save(_ credentials: StoredCredentials) throws
    func delete() throws
}

/// A Keychain error, with the `OSStatus` that caused it.
struct KeychainError: Error, LocalizedError, Equatable {
    var status: OSStatus

    var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return String(localized: "Keychain error: \(message)")
    }
}

/// Stores credentials as one generic password item in the login Keychain,
/// readable only while the Mac is unlocked.
struct KeychainCredentialStore: CredentialStoring {
    var service = "com.lquainta.RepoHub"
    var account = "session"

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() throws -> StoredCredentials? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                return nil
            }
            return try JSONDecoder().decode(StoredCredentials.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    func save(_ credentials: StoredCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess {
            return
        }
        guard update == errSecItemNotFound else {
            throw KeychainError(status: update)
        }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        item[kSecAttrLabel as String] = "RepoHub session"
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}

/// Keeps credentials in memory only: for UI tests, which must never touch the
/// user's Keychain, and for unit tests.
final class InMemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: StoredCredentials?

    init(_ credentials: StoredCredentials? = nil) {
        self.credentials = credentials
    }

    func load() throws -> StoredCredentials? {
        lock.withLock { credentials }
    }

    func save(_ credentials: StoredCredentials) throws {
        lock.withLock { self.credentials = credentials }
    }

    func delete() throws {
        lock.withLock { credentials = nil }
    }
}
