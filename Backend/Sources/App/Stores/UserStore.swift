import Fluent
import Foundation

/// Reads and writes users.
protocol UserStore: Sendable {
    /// Creates the user with this GitHub id, or updates their profile and token.
    func upsert(_ profile: GitHubProfile, tokenCiphertext: Data, scopes: String) async throws -> User
    func find(id: UUID) async throws -> User?
    func find(githubID: Int64) async throws -> User?
    /// Deletes the user and, through cascades, everything they own.
    func delete(id: UUID) async throws
}

/// The GitHub profile fields RepoHub keeps.
struct GitHubProfile: Equatable, Sendable {
    var id: Int64
    var login: String
    var name: String?
    var avatarURL: String?
}

struct FluentUserStore: UserStore {
    let database: any Database

    func upsert(_ profile: GitHubProfile, tokenCiphertext: Data, scopes: String) async throws -> User {
        let user =
            try await find(githubID: profile.id)
            ?? User(
                githubID: profile.id,
                login: profile.login,
                githubTokenCiphertext: tokenCiphertext,
                githubTokenScopes: scopes
            )
        user.login = profile.login
        user.name = profile.name
        user.avatarURL = profile.avatarURL
        user.githubTokenCiphertext = tokenCiphertext
        user.githubTokenScopes = scopes
        try await user.save(on: database)
        return user
    }

    func find(id: UUID) async throws -> User? {
        try await User.find(id, on: database)
    }

    func find(githubID: Int64) async throws -> User? {
        try await User.query(on: database).filter(\.$githubID == githubID).first()
    }

    func delete(id: UUID) async throws {
        try await User.query(on: database).filter(\.$id == id).delete()
    }
}
