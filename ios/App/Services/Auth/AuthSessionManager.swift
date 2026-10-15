import Foundation
import AppCore

/// Keeps a Supabase session alive so the backend can meter credits per user
/// without asking anyone to sign up: anonymous by default, or an account after
/// Sign in with Apple. Tokens live in the Keychain.
actor AuthSessionManager {
    private let config: BackendConfiguration
    private let session: URLSession
    private var current: AuthSession? {
        didSet {
            if (oldValue == nil) != (current == nil) { sessionContinuation.yield(current != nil) }
        }
    }
    /// Whether a session exists, each time that changes: her first consented
    /// cloud job or purchase makes one, signing out or deleting her data ends
    /// it. Writing help waits for one and never makes it (`AppModel.hasSession`).
    nonisolated let sessionChanges: AsyncStream<Bool>
    private let sessionContinuation: AsyncStream<Bool>.Continuation
    /// A session was in the Keychain at launch.
    nonisolated let hadSessionAtLaunch: Bool
    /// The anonymous session from before Sign in with Apple, kept until its
    /// credits have been merged into the account (so a failed merge can retry).
    private var pendingMerge: AuthSession?
    /// Apple's one-time authorization code, kept until /account/link took it,
    /// so a failed link can hand it over on the next try.
    private var pendingAppleCode: String?
    private var inFlight: Task<AuthSession, Error>?
    /// A refresh that never falls back to signing up (`existingAccessToken`).
    private var refreshInFlight: Task<AuthSession, Error>?
    private static let keychainKey = "auth.session"
    private static let pendingMergeKey = "auth.pendingMerge"
    private static let pendingAppleCodeKey = "auth.pendingAppleCode"

    init(config: BackendConfiguration, session: URLSession = .shared) {
        self.config = config
        self.session = session
        let stored = Keychain.load(AuthSession.self, key: Self.keychainKey)
        self.current = stored
        self.hadSessionAtLaunch = stored != nil
        (sessionChanges, sessionContinuation) = AsyncStream.makeStream(of: Bool.self, bufferingPolicy: .bufferingNewest(1))
        self.pendingMerge = Keychain.load(AuthSession.self, key: Self.pendingMergeKey)
        self.pendingAppleCode = Keychain.load(String.self, key: Self.pendingAppleCodeKey)
    }

    var userID: String? { current?.userID }

    /// The signed-in account, or nil while anonymous.
    var account: AuthSession? { current?.isAccount == true ? current : nil }

    /// Swaps the anonymous session for the Apple account. The anonymous session
    /// is kept aside until `pendingAnonymousToken()` has been merged, and
    /// Apple's code until `appleCode` has been handed over.
    func signInWithApple(idToken: String, nonce: String, authorizationCode: String?) async throws {
        var setAside: AuthSession?
        if current != nil, current?.isAccount != true {
            _ = try? await validAccessToken() // refreshes the anonymous session if needed
            if let anonymous = current, !anonymous.isAccount {
                setAside = anonymous
                pendingMerge = anonymous
                Keychain.save(anonymous, key: Self.pendingMergeKey)
            }
        }
        do {
            let request = try RequestFactory.signInWithApple(idToken: idToken, nonce: nonce, config: config)
            let (data, response) = try await session.mappedData(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // Supabase turning Apple's token down isn't an expired session.
            if (400..<500).contains(status), status != 429 { throw AccountSignInError.rejected }
            let account = try ResponseDecoder.decodeSession(data: data, statusCode: status)
            current = account
            Keychain.save(account, key: Self.keychainKey)
        } catch {
            // Still anonymous: nothing waits to be merged.
            if let setAside, pendingMerge == setAside { clearPendingMerge() }
            throw error
        }
        if let authorizationCode {
            pendingAppleCode = authorizationCode
            Keychain.save(authorizationCode, key: Self.pendingAppleCodeKey)
        }
    }

    /// Apple's authorization code from the last sign-in, until /account/link took it.
    var appleCode: String? { pendingAppleCode }

    /// The anonymous user's credits haven't been merged into the account yet.
    var hasPendingMerge: Bool { pendingMerge != nil }

    func clearAppleCode() {
        pendingAppleCode = nil
        Keychain.delete(key: Self.pendingAppleCodeKey)
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

    /// A valid token for the stored session, refreshed if needed, or nil when
    /// there is no session. Never signs up: deleting an account (or polling a
    /// job, or reading the balance) must not create a new one. Throws
    /// `unauthorized` when the refresh token was rejected (the user was
    /// deleted, or the session revoked). Concurrent callers share one refresh.
    func existingAccessToken() async throws -> String? {
        guard let current else { return nil }
        if !current.isExpired() { return current.accessToken }
        if let refreshInFlight {
            return try await refreshInFlight.value.accessToken
        }
        let task = Task<AuthSession, Error> { [config, session] in
            try await Self.refresh(current.refreshToken, config: config, session: session)
        }
        refreshInFlight = task
        defer { refreshInFlight = nil }
        let refreshed = try await task.value
        self.current = refreshed
        Keychain.save(refreshed, key: Self.keychainKey)
        return refreshed.accessToken
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
        clearAppleCode()
    }

    private static func refresh(_ refreshToken: String, config: BackendConfiguration, session: URLSession) async throws -> AuthSession {
        let request = try RequestFactory.refreshSession(refreshToken: refreshToken, config: config)
        let (data, response) = try await session.mappedData(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try ResponseDecoder.decodeSession(data: data, statusCode: status)
    }

    private static func signUpAnonymously(config: BackendConfiguration, session: URLSession) async throws -> AuthSession {
        let request = RequestFactory.anonymousSignUp(config: config)
        let (data, response) = try await session.mappedData(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try ResponseDecoder.decodeSession(data: data, statusCode: status)
    }
}

/// Supabase didn't accept Apple's sign-in (the token, its nonce or the
/// provider's setup), so she stays anonymous and nothing changed.
enum AccountSignInError: LocalizedError {
    case rejected

    var errorDescription: String? {
        String(localized: "Your Apple sign-in wasn't accepted, so nothing changed. Please try again.")
    }
}
