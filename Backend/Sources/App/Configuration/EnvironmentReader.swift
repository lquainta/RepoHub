import Vapor

/// An error raised while loading configuration from environment variables.
enum ConfigurationError: Error, Equatable, CustomStringConvertible {
    /// A required variable is unset or empty.
    case missing(key: String)
    /// A variable is set but cannot be parsed as the expected type.
    case invalid(key: String, expected: String)

    var description: String {
        switch self {
        case .missing(let key):
            "Missing required environment variable \(key). See .env.sample."
        case .invalid(let key, let expected):
            "Environment variable \(key) must be \(expected)."
        }
    }
}

/// Reads typed values from environment variables.
///
/// All configuration comes from the environment; nothing is hard-coded. Every
/// key read here must be listed in `.env.sample` (enforced in CI).
struct EnvironmentReader: Sendable {
    private let lookup: @Sendable (String) -> String?

    /// Creates a reader. Tests inject a dictionary-backed lookup.
    init(lookup: @escaping @Sendable (String) -> String? = { Environment.get($0) }) {
        self.lookup = lookup
    }

    /// Returns the value for `key`, or throws if it is unset or empty.
    func required(_ key: String) throws -> String {
        guard let value = optional(key) else {
            throw ConfigurationError.missing(key: key)
        }
        return value
    }

    /// Returns the value for `key`, treating an empty string as unset.
    func optional(_ key: String) -> String? {
        guard let value = lookup(key)?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Returns `key` parsed as an integer, `defaultValue` if unset, or throws if malformed.
    func integer(_ key: String, default defaultValue: Int) throws -> Int {
        guard let raw = optional(key) else {
            return defaultValue
        }
        guard let value = Int(raw) else {
            throw ConfigurationError.invalid(key: key, expected: "an integer")
        }
        return value
    }
}
