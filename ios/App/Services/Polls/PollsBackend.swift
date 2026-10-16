import Foundation
import AppCore

/// The server side of "Which vibe?" polls (`functions/v1/polls`; the
/// contract is in AppCore's `Polls.swift` and backend/README.md, "Polls").
///
/// Making a poll needs her session, made like the one for her first
/// consented cloud job (`ensureSession`, only after AI consent); reading her
/// list or deleting a poll only uses a session she already has. StoreKit's
/// AppTransaction goes along when the device has one within two seconds,
/// since the daily limit belongs to the App Store download too; without it
/// the server shares a small allowance among unverified installs.
final class PollsBackend: Sendable {
    private let config: BackendConfiguration
    private let auth: AuthSessionManager
    private let session: URLSession
    private let appTransactions: AppTransactionProvider

    init(config: BackendConfiguration, auth: AuthSessionManager, appTransactions: AppTransactionProvider, session: URLSession = .shared) {
        self.config = config
        self.auth = auth
        self.session = session
        self.appTransactions = appTransactions
    }

    /// Makes her (anonymous) session if there's none yet. Polls ask for it
    /// only after the consent sheet, like a cloud job.
    func ensureSession() async throws {
        _ = try await auth.validAccessToken()
    }

    func hasSession() async -> Bool {
        await auth.userID != nil
    }

    /// A new poll. A session the server no longer accepts is renewed once.
    func create(_ body: PollCreateRequest) async throws -> PollCreated {
        let appTransaction = await appTransactions.jws(waitingAtMost: .seconds(2))
        do {
            return try await submit(body, appTransaction: appTransaction)
        } catch PollError.unauthorized {
            await auth.invalidate()
            return try await submit(body, appTransaction: appTransaction)
        }
    }

    /// Her polls that haven't ended. Never makes a session: without one
    /// there's nothing to read.
    func mine() async throws -> PollList {
        let token: String?
        do {
            token = try await auth.existingAccessToken()
        } catch AIServiceError.unauthorized {
            throw PollError.noSession
        }
        guard let token else { throw PollError.noSession }
        let request = try RequestFactory.myPolls(config: config, accessToken: token,
                                                 appTransactionJWS: await appTransactions.jws(waitingAtMost: .seconds(2)))
        let (data, response) = try await session.mappedData(for: request)
        let http = response as? HTTPURLResponse
        return try ResponseDecoder.decodePollList(data: data, statusCode: http?.statusCode ?? 0,
                                                  retryAfter: http?.value(forHTTPHeaderField: "Retry-After"))
    }

    /// Deletes one of her polls now. One that's gone already counts as deleted.
    func delete(_ id: String) async throws {
        guard let token = try await auth.existingAccessToken() else { throw PollError.noSession }
        let request = try RequestFactory.deletePoll(id: id, config: config, accessToken: token)
        let (data, response) = try await session.mappedData(for: request)
        let http = response as? HTTPURLResponse
        do {
            try ResponseDecoder.decodePollDeleted(data: data, statusCode: http?.statusCode ?? 0,
                                                  retryAfter: http?.value(forHTTPHeaderField: "Retry-After"))
        } catch PollError.notFound {
            return
        }
    }

    private func submit(_ body: PollCreateRequest, appTransaction: String?) async throws -> PollCreated {
        let token = try await auth.validAccessToken()
        let request = try RequestFactory.createPoll(body, config: config, accessToken: token, appTransactionJWS: appTransaction)
        let (data, response) = try await session.mappedData(for: request)
        let http = response as? HTTPURLResponse
        return try ResponseDecoder.decodePollCreated(data: data, statusCode: http?.statusCode ?? 0,
                                                     retryAfter: http?.value(forHTTPHeaderField: "Retry-After"))
    }
}
