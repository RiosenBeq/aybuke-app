import Foundation
import AppCore

/// Keeps a Supabase anonymous session alive so the backend can meter credits
/// per user without asking anyone to sign up. Tokens live in the Keychain.
actor AuthSessionManager {
    private let config: BackendConfiguration
    private let session: URLSession
    private var current: AuthSession?
    private var inFlight: Task<AuthSession, Error>?
    private static let keychainKey = "auth.session"

    init(config: BackendConfiguration, session: URLSession = .shared) {
        self.config = config
        self.session = session
        self.current = Keychain.load(AuthSession.self, key: Self.keychainKey)
    }

    var userID: String? { current?.userID }

    /// Returns a non-expired access token, refreshing or signing up as needed.
    /// Concurrent callers share a single network round-trip.
    func validAccessToken() async throws -> String {
        if let current, !current.isExpired() {
            return current.accessToken
        }
        if let inFlight {
            return try await inFlight.value.accessToken
        }

        let task = Task<AuthSession, Error> { [config, session, current] in
            if let current {
                do {
                    return try await Self.refresh(current.refreshToken, config: config, session: session)
                } catch AIServiceError.unauthorized {
                    // Refresh token revoked or expired: start a fresh anonymous session.
                }
            }
            return try await Self.signUpAnonymously(config: config, session: session)
        }
        inFlight = task
        defer { inFlight = nil }

        let newSession = try await task.value
        current = newSession
        Keychain.save(newSession, key: Self.keychainKey)
        return newSession.accessToken
    }

    /// Forces a refresh on the next call (e.g. after a 401).
    func invalidate() {
        current = current.map {
            AuthSession(accessToken: $0.accessToken, refreshToken: $0.refreshToken, expiresAt: .distantPast, userID: $0.userID)
        }
    }

    func signOut() {
        current = nil
        Keychain.delete(key: Self.keychainKey)
    }

    private static func refresh(_ refreshToken: String, config: BackendConfiguration, session: URLSession) async throws -> AuthSession {
        let request = try RequestFactory.refreshSession(refreshToken: refreshToken, config: config)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try ResponseDecoder.decodeSession(data: data, statusCode: status)
    }

    private static func signUpAnonymously(config: BackendConfiguration, session: URLSession) async throws -> AuthSession {
        let request = RequestFactory.anonymousSignUp(config: config)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try ResponseDecoder.decodeSession(data: data, statusCode: status)
    }
}
