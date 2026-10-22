import Testing

@testable import RepoHub

@Suite("Crash reporting")
struct CrashReportingTests {
    @Test("Off unless the user opted in and the build has a DSN")
    func optIn() {
        let dsn = "https://key@o1.ingest.sentry.io/1"
        #expect(CrashReporting.configuration(dsn: dsn, enabled: false, version: "1", build: "2", isDebug: false) == nil)
        #expect(CrashReporting.configuration(dsn: "", enabled: true, version: "1", build: "2", isDebug: false) == nil)
        #expect(CrashReporting.configuration(dsn: nil, enabled: true, version: "1", build: "2", isDebug: false) == nil)
        // An unexpanded build setting, as in a build without SENTRY_DSN.
        #expect(
            CrashReporting.configuration(dsn: "$(SENTRY_DSN)", enabled: true, version: nil, build: nil, isDebug: true)
                == nil
        )
    }

    @Test("Releases are named by version and build; debug builds report as development")
    func configuration() {
        let configuration = CrashReporting.configuration(
            dsn: "https://key@o1.ingest.sentry.io/1",
            enabled: true,
            version: "0.2.0",
            build: "143",
            isDebug: true
        )
        #expect(configuration?.release == "RepoHub@0.2.0+143")
        #expect(configuration?.environment == "development")
    }
}
