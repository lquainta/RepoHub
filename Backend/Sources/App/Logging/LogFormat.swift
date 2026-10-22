import Logging
import Vapor

/// How logs are written: `LOG_FORMAT` is `json` or `text`. JSON is the
/// default in production, text (Vapor's console format) elsewhere.
enum LogFormat: String {
    case json, text

    static func detect(environment: Environment, value: String? = Environment.get("LOG_FORMAT")) throws -> LogFormat {
        guard let raw = value?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else {
            return environment == .production ? .json : .text
        }
        guard let format = LogFormat(rawValue: raw) else {
            throw ConfigurationError.invalid(key: "LOG_FORMAT", expected: "json or text")
        }
        return format
    }

    /// Sets up the logging system. The level comes from `--log` or `LOG_LEVEL`
    /// (default `notice` in production, `info` elsewhere), so it changes without a code change.
    static func bootstrap(_ environment: inout Environment) throws {
        switch try detect(environment: environment) {
        case .text:
            try LoggingSystem.bootstrap(from: &environment)
        case .json:
            try LoggingSystem.bootstrap(from: &environment) { level in
                { label in JSONLogHandler(label: label, level: level) }
            }
        }
    }
}
