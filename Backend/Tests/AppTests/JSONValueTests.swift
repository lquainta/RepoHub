import Foundation
import Logging
import Testing

@testable import App

@Suite("JSONValue")
struct JSONValueTests {
    @Test("Every kind of JSON value decodes and encodes back to the same JSON")
    func roundTrip() throws {
        let json = #"{"array":[1,"two",null],"bool":true,"null":null,"number":1.5,"object":{"k":"v"},"string":"s"}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))

        #expect(value["array"] == .array([.number(1), .string("two"), .null]))
        #expect(value["bool"] == .bool(true))
        #expect(value["null"] == .null)
        #expect(value["number"] == .number(1.5))
        #expect(value["object"]?["k"] == .string("v"))
        #expect(value["string"] == .string("s"))

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(String(bytes: try encoder.encode(value), encoding: .utf8) == json)
    }

    @Test("Only objects have members")
    func subscriptOnNonObject() {
        #expect(JSONValue.string("s")["key"] == nil)
        #expect(JSONValue.array([.null])["key"] == nil)
        #expect(JSONValue.object([:])["missing"] == nil)
    }
}

@Suite("JSON log handler")
struct JSONLogHandlerTests {
    @Test("Handler metadata can be read back, and the default writer is standard output")
    func metadataAndDefaultWriter() {
        var handler = JSONLogHandler(label: "test", level: .info)
        handler[metadataKey: "component"] = "cache"
        #expect(handler[metadataKey: "component"] == "cache")
        #expect(handler[metadataKey: "missing"] == nil)
        // Writes one line to the test's standard output.
        Logger(label: "test") { _ in handler }.info("JSON log handler default writer")
    }
}
