import Fluent
import Vapor

/// Long-lived security services, created once in `configure(_:)`.
struct SecurityServices: Sendable {
    let config: SecurityConfig
    let tokens: SessionTokens
    let cipher: TokenCipher
    let limiter: RateLimiter
}

private struct SecurityServicesKey: StorageKey {
    typealias Value = SecurityServices
}

private struct GitHubOAuthKey: StorageKey {
    typealias Value = any GitHubOAuth
}

extension Application {
    var security: SecurityServices {
        get {
            guard let services = storage[SecurityServicesKey.self] else {
                preconditionFailure("security accessed before configureSecurity(_:)")
            }
            return services
        }
        set { storage[SecurityServicesKey.self] = newValue }
    }

    /// GitHub's device flow, or `nil` when `GITHUB_CLIENT_ID` isn't configured. Tests replace it with a fake.
    var githubOAuth: (any GitHubOAuth)? {
        get { storage[GitHubOAuthKey.self] }
        set { storage[GitHubOAuthKey.self] = newValue }
    }

    /// Creates the services and installs the rate-limit, body-limit, and webhook-signature middleware.
    func configureSecurity(_ config: SecurityConfig) async {
        let limiter = RateLimiter(store: cacheStore, logger: logger)
        security = SecurityServices(
            config: config,
            tokens: await SessionTokens(signingKey: config.jwtSigningKey),
            cipher: TokenCipher(key: config.tokenEncryptionKey),
            limiter: limiter
        )
        githubOAuth = config.githubClientID.map { VaporGitHubOAuth(client: client, clientID: $0) }
        middleware.use(
            RateLimitMiddleware(
                limiter: limiter,
                limitPerMinute: config.rateLimitPerMinute,
                authLimitPerMinute: config.authRateLimitPerMinute,
                trustsProxyHeader: environment == .production
            )
        )
        middleware.use(BodyLimitMiddleware())
        middleware.use(WebhookSignatureMiddleware(secret: config.githubWebhookSecret))
    }

    /// The auth service using `database` and, if configured, GitHub's device flow.
    func authService(on database: any Database) -> AuthService {
        let stores = Stores(database: database)
        return AuthService(
            users: stores.users,
            devices: stores.devices,
            oauth: githubOAuth,
            tokens: security.tokens,
            cipher: security.cipher,
            logger: contextLogger
        )
    }
}
