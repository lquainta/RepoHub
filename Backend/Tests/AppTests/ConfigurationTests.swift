import Testing

@testable import App

@Suite("Configuration")
struct ConfigurationTests {
    private func reader(_ values: [String: String]) -> EnvironmentReader {
        EnvironmentReader { values[$0] }
    }

    @Test("Missing required variable throws an error naming it")
    func missingRequiredNamesKey() {
        #expect(throws: ConfigurationError.missing(key: "DATABASE_URL")) {
            try reader([:]).required("DATABASE_URL")
        }
        #expect(ConfigurationError.missing(key: "DATABASE_URL").description.contains("DATABASE_URL"))
    }

    @Test("Empty and whitespace-only values count as unset", arguments: ["", "   "])
    func emptyIsUnset(value: String) {
        #expect(reader(["KEY": value]).optional("KEY") == nil)
        #expect(throws: ConfigurationError.missing(key: "KEY")) {
            try reader(["KEY": value]).required("KEY")
        }
    }

    @Test("Integer values parse, fall back to the default, and reject garbage")
    func integerParsing() throws {
        #expect(try reader(["PORT": "9090"]).integer("PORT", default: 8080) == 9090)
        #expect(try reader([:]).integer("PORT", default: 8080) == 8080)
        #expect(throws: ConfigurationError.invalid(key: "PORT", expected: "an integer")) {
            try reader(["PORT": "eighty"]).integer("PORT", default: 8080)
        }
    }

    @Test("Build commit defaults to unknown")
    func buildCommitDefault() throws {
        #expect(try AppConfig(reader: reader([:])).buildCommit == "unknown")
        #expect(try AppConfig(reader: reader(["BUILD_COMMIT": "abc1234"])).buildCommit == "abc1234")
    }
}
