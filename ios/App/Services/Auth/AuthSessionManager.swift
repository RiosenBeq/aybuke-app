import Foundation
import AppCore

/// Keeps a Supabase session alive so the backend can meter credits per user
/// without asking anyone to sign up: anonymous by default, or an account after
/// Sign in with Apple. Tokens live in the Keychain.
actor AuthSessionManager {
    private let config: BackendConfiguration
    private let session: URLSession
    private var current: AuthSession?
    /// The anonymous session from before Sign in with Apple, kept until its
    /// credits have been merged into the account (so a failed merge can retry).
    private var pendingMerge: AuthSession?
    private var inFlight: Task<AuthSession, Error>?
    private static let keychainKey = "auth.session"
    private static let pendingMergeKey = "auth.pendingMerge"

    init(config: BackendConfiguration, session: URLSession = .shared) {
        self.config = config
        self.session = session
        self.current = Keychain.load(AuthSession.self, key: Self.keychainKey)
        self.pendingMerge = Keychain.load(AuthSession.self, key: Self.pendingMergeKey)
    }

    var userID: String? { current?.userID }

    /// The signed-in account, or nil while anonymous.
    var account: AuthSession? { current?.isAccount == true ? current : nil }

    /// Swaps the anonymous session for the Apple account. The anonymous session
    /// is kept aside until `pendingAnonymousToken()` has been merged.
    func signInWithApple(idToken: String, nonce: String) async throws {
        if current != nil, current?.isAccount != true {
            _ = try? await validAccessToken() // refreshes the anonymous session if needed
            if let anonymous = current, !anonymous.isAccount {
                pendingMerge = anonymous
                Keychain.save(anonymous, key: Self.pendingMergeKey)
            }
        }
        let request = try RequestFactory.signInWithApple(idToken: idToken, nonce: nonce, config: config)
        let (data, response) = try await session.data(for: request)
        let account = try ResponseDecoder.decodeSession(data: data, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        current = account
        Keychain.save(account, key: Self.keychainKey)
    }

    /// A valid access token for the anonymous user waiting to be merged, if any.
    func pendingAnonymousToken() async -> String? {
        guard let pending = pendingMerge else { return nil }
        if !pending.isExpired() { return pending.accessToken }
        if let refreshed = try? await Self.refresh(pending.refreshToken, config: config, session: session) {
            pendingMerge = refreshed
            Keychain.save(refreshed, key: Self.pendingMergeKey)
            return refreshed.accessToken
        }
        clearPendingMerge() // expired for good: nothing left to recover
        return nil
    }

    func clearPendingMerge() {
        pendingMerge = nil
        Keychain.delete(key: Self.pendingMergeKey)
    }

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
        clearPendingMerge()
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
