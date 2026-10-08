/// Shared models and git logic used by the RepoHub macOS app and backend.
///
/// This package must build on both macOS and Linux, so it may only depend on
/// Foundation APIs that are available in swift-corelibs-foundation.
public enum RepoHubCore {
    /// Semantic version of the core package.
    public static let version = "0.1.0"
}
