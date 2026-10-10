import Crypto
import Foundation
import JWTKit

/// The claims in a RepoHub access token.
struct AccessTokenPayload: JWTPayload, Equatable {
    /// The user's id.
    var sub: SubjectClaim
    /// The device (session) id, so a signed-out device's tokens stop working.
    var sid: String
    var iat: IssuedAtClaim
    var exp: ExpirationClaim
    var iss: IssuerClaim

    static let issuer = "repohub"

    func verify(using algorithm: some JWTAlgorithm) async throws {
        try exp.verifyNotExpired()
        guard iss.value == Self.issuer else {
            throw JWTError.claimVerificationFailure(failedClaim: iss, reason: "unexpected issuer")
        }
    }
}

/// Issues and verifies access tokens, and creates refresh tokens.
///
/// - Access tokens are HS256 JWTs valid for ``accessTokenLifetime``.
/// - Refresh tokens are 256 random bits, base64url-encoded. Only their
///   SHA-256 hash is stored, so a database leak doesn't leak sessions.
struct SessionTokens: Sendable {
    static let accessTokenLifetime: TimeInterval = 15 * 60
    static let refreshTokenLifetime: TimeInterval = 30 * 24 * 3_600

    private let keys: JWTKeyCollection

    init(signingKey: Data) async {
        keys = JWTKeyCollection()
        await keys.add(hmac: HMACKey(key: SymmetricKey(data: signingKey)), digestAlgorithm: .sha256)
    }

    func accessToken(userID: UUID, deviceID: UUID, now: Date = .now) async throws -> String {
        try await keys.sign(
            AccessTokenPayload(
                sub: SubjectClaim(value: userID.uuidString),
                sid: deviceID.uuidString,
                iat: IssuedAtClaim(value: now),
                exp: ExpirationClaim(value: now.addingTimeInterval(Self.accessTokenLifetime)),
                iss: IssuerClaim(value: AccessTokenPayload.issuer)
            )
        )
    }

    /// The verified claims, or `nil` if the token is malformed, forged, or expired.
    func verify(_ token: String) async -> (userID: UUID, deviceID: UUID)? {
        guard let payload = try? await keys.verify(token, as: AccessTokenPayload.self),
            let userID = UUID(uuidString: payload.sub.value),
            let deviceID = UUID(uuidString: payload.sid)
        else {
            return nil
        }
        return (userID, deviceID)
    }

    /// A new random refresh token and the hash to store.
    static func makeRefreshToken() -> (token: String, hash: Data) {
        let bytes = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        let token = bytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return (token, hash(token))
    }

    /// The SHA-256 hash of a refresh token, as stored in `devices.refresh_token_hash`.
    static func hash(_ refreshToken: String) -> Data {
        Data(SHA256.hash(data: Data(refreshToken.utf8)))
    }
}
