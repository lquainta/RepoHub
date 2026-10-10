import Foundation
import Logging

/// Writes one JSON object per line: what log aggregators (Fly.io, Sentry
/// breadcrumbs, `jq`) can parse without guessing.
///
/// ```json
/// {"timestamp":"2026-10-10T06:00:00.000Z","level":"info","message":"Signed in",
///  "label":"codes.vapor.application","request_id":"4C9…","metadata":{"user":"octocat"}}
/// ```
///
/// `request-id` (added by Vapor to each request's logger) is promoted to the
/// top-level `request_id` field so every request can be traced across lines.
struct JSONLogHandler: LogHandler {
    let label: String
    var logLevel: Logger.Level
    var metadata: Logger.Metadata = [:]
    var metadataProvider: Logger.MetadataProvider?
    private let write: @Sendable (String) -> Void

    /// Creates a handler.
    ///
    /// - Parameters:
    ///   - label: The logger's label, written to each line.
    ///   - level: The minimum level that's written.
    ///   - metadataProvider: Adds metadata (such as trace IDs) to every line.
    ///   - write: Receives each finished line (stdout by default; tests capture it).
    init(
        label: String,
        level: Logger.Level,
        metadataProvider: Logger.MetadataProvider? = nil,
        write: @escaping @Sendable (String) -> Void = JSONLogHandler.standardOutput
    ) {
        self.label = label
        self.logLevel = level
        self.metadataProvider = metadataProvider
        self.write = write
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    // swiftlint:disable:next function_parameter_count
    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata explicit: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        // Precedence, lowest to highest: provider, handler, call site.
        var merged = metadataProvider?.get() ?? [:]
        merged.merge(metadata) { _, new in new }
        merged.merge(explicit ?? [:]) { _, new in new }

        var object: [String: JSONLogValue] = [
            "timestamp": .string(Self.timestamp(Date())),
            "level": .string(level.rawValue),
            "message": .string(message.description),
            "label": .string(label),
            "source": .string(source),
        ]
        if let requestID = merged.removeValue(forKey: "request-id") {
            object["request_id"] = .string(requestID.description)
        }
        if level >= .warning {
            object["file"] = .string("\(file):\(line)")
        }
        if !merged.isEmpty {
            object["metadata"] = .init(merged)
        }
        guard let data = try? Self.encoder.encode(object), let json = String(data: data, encoding: .utf8) else {
            return
        }
        write(json)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static func timestamp(_ date: Date) -> String {
        date.formatted(
            .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted)
        )
    }

    /// Writes a line to standard output atomically.
    static let standardOutput: @Sendable (String) -> Void = { line in
        let data = Data((line + "\n").utf8)
        outputLock.withLock { FileHandle.standardOutput.write(data) }
    }

    private static let outputLock = NSLock()
}

/// Log metadata as JSON.
enum JSONLogValue: Encodable, Equatable {
    case string(String)
    case array([JSONLogValue])
    case object([String: JSONLogValue])

    init(_ metadata: Logger.Metadata) {
        self = .object(metadata.mapValues(Self.init))
    }

    init(_ value: Logger.Metadata.Value) {
        switch value {
        case .string(let string): self = .string(string)
        case .stringConvertible(let convertible): self = .string(convertible.description)
        case .array(let values): self = .array(values.map(Self.init))
        case .dictionary(let dictionary): self = .object(dictionary.mapValues(Self.init))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .array(let values): try container.encode(values)
        case .object(let object): try container.encode(object)
        }
    }
}
