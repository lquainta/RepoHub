import Foundation
import Sentry

/// Opt-in crash and error reporting with Sentry (#51).
///
/// Off unless the user turned on Settings → General → Send crash reports and
/// the build has a DSN (`SENTRY_DSN`; empty in development builds). Reports
/// carry no personal data: no paths, user names, or repository contents.
enum CrashReporting {
    /// Forces a crash at launch, to check reporting end to end. Only while
    /// reporting is enabled.
    static let forceCrashKey = "REPOHUB_FORCE_CRASH"

    /// What to start Sentry with, or `nil` to leave it off.
    struct Configuration: Equatable {
        var dsn: String
        var release: String
        var environment: String
    }

    /// Decides whether to report and with which settings.
    static func configuration(
        dsn: String?,
        enabled: Bool,
        version: String?,
        build: String?,
        isDebug: Bool
    ) -> Configuration? {
        guard enabled, let dsn, dsn.hasPrefix("https://") else {
            return nil
        }
        return Configuration(
            dsn: dsn,
            release: "RepoHub@\(version ?? "0")+\(build ?? "0")",
            environment: isDebug ? "development" : "production"
        )
    }

    /// Starts Sentry if the user opted in and the build has a DSN.
    static func start(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        #if DEBUG
            let isDebug = true
        #else
            let isDebug = false
        #endif
        guard
            let configuration = configuration(
                dsn: bundle.object(forInfoDictionaryKey: "SentryDSN") as? String,
                enabled: defaults.bool(forKey: AppPreferences.sendCrashReportsKey),
                version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                isDebug: isDebug
            )
        else {
            return
        }
        SentrySDK.start { options in
            options.dsn = configuration.dsn
            options.releaseName = configuration.release
            options.environment = configuration.environment
            options.sendDefaultPii = false
            options.tracesSampleRate = 0
            options.enableAutoBreadcrumbTracking = false
            // Paths can name the user's projects; drop them from breadcrumbs.
            options.beforeBreadcrumb = { _ in nil }
        }
        if environment[forceCrashKey] == "1" {
            SentrySDK.crash()
        }
    }

    /// Reports an error that didn't crash the app, if reporting is on.
    static func capture(_ error: any Error) {
        guard SentrySDK.isEnabled else {
            return
        }
        SentrySDK.capture(error: error)
    }
}
