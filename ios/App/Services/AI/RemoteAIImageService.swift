import UIKit
import AppCore

/// Talks to the backend (`backend/supabase/functions`). The app never holds
/// AI-provider keys; the backend authenticates the user, meters credits,
/// moderates and forwards the job to the model provider.
///
/// Jobs are asynchronous: submit → poll until finished → download results →
/// confirm. Every balance the server reports on the way (the charge in the
/// 202, a finished job, a cancel's refund) goes to `balanceObserver`.
///
/// Free credits belong to the verified App Store install, so jobs and
/// balance reads carry StoreKit's AppTransaction (`appTransactions`).
final class RemoteAIImageService: AIImageService {
    private let config: BackendConfiguration
    private let auth: AuthSessionManager
    private let session: URLSession
    private let schedule: PollingSchedule
    private let entitlementProvider: () async -> String?
    private let appTransactions: AppTransactionProvider
    /// The server's balance and when the request that reported it was sent,
    /// so an older answer never overwrites a newer one.
    private let balanceObserver: @MainActor (Int, Date) -> Void

    /// Uploads are capped so requests stay small and fast.
    static let uploadLongEdge = 1536

    init(
        config: BackendConfiguration,
        auth: AuthSessionManager,
        session: URLSession = .shared,
        schedule: PollingSchedule = .standard,
        entitlementProvider: @escaping () async -> String?,
        appTransactions: AppTransactionProvider,
        balanceObserver: @escaping @MainActor (Int, Date) -> Void = { _, _ in }
    ) {
        self.config = config
        self.auth = auth
        self.session = session
        self.schedule = schedule
        self.entitlementProvider = entitlementProvider
        self.appTransactions = appTransactions
        self.balanceObserver = balanceObserver
    }

    // MARK: Jobs

    func perform(_ job: AIJob) async throws -> AIJobResult {
        let body = try Self.makeRequestBody(for: job)
        try body.validate()

        var appTransaction = await appTransactions.jws()
        let submitted: GenerationResponse
        do {
            submitted = try await submit(body, appTransaction: appTransaction)
        } catch AIServiceError.unauthorized {
            // Token may have been revoked server-side; retry once with a fresh session.
            await auth.invalidate()
            submitted = try await submit(body, appTransaction: appTransaction)
        } catch AIServiceError.appStoreCheckFailed {
            // The server couldn't verify this install: one more try with a
            // better AppTransaction. One StoreKit was still fetching first
            // (no prompt), else a fresh one from the App Store (she just
            // tapped, so Apple may ask her to sign in). Still nothing: the
            // error's own message, never a cryptic one.
            let before = appTransaction
            if before == nil { appTransaction = await appTransactions.jws(waitingAtMost: .seconds(15)) }
            if appTransaction == nil || appTransaction == before { appTransaction = await appTransactions.refresh() }
            guard let appTransaction, appTransaction != before else { throw AIServiceError.appStoreCheckFailed }
            submitted = try await submit(body, appTransaction: appTransaction)
        }
        let finished = try await waitUntilFinished(submitted)

        var images: [UIImage] = []
        for output in finished.outputs {
            if let image = try await loadImage(output) {
                images.append(image)
            }
        }
        // Not confirmed: the server refunds results that never reached the app.
        guard !images.isEmpty else { throw AIServiceError.invalidResponse }
        // "Got it": the server clears the results right away.
        if let jobID = finished.jobID { release(jobID: jobID, cancel: false) }
        return AIJobResult(images: images, creditsRemaining: finished.creditsRemaining, requestID: finished.jobID)
    }

    private func submit(_ body: GenerationRequest, appTransaction: String?) async throws -> GenerationResponse {
        let token = try await auth.validAccessToken()
        let jws = await entitlementProvider()
        let request = try RequestFactory.generation(body, config: config, accessToken: token, entitlementJWS: jws,
                                                    appTransactionJWS: appTransaction)
        return try await decodeJob(request)
    }

    /// Polls until the job is finished. A poll that can't reach the server
    /// doesn't end the wait (the job and its credit are still there); the
    /// schedule backs off and gives up only after `offlineGrace` without an
    /// answer.
    private func waitUntilFinished(_ initial: GenerationResponse) async throws -> GenerationResponse {
        var response = initial
        let started = Date()
        var attempt = 0
        var failures = 0
        var outageStarted: Date?
        while !response.isFinished {
            guard let jobID = response.jobID else { throw AIServiceError.invalidResponse }
            let outage = outageStarted.map { Date().timeIntervalSince($0) } ?? 0
            switch schedule.next(elapsed: Date().timeIntervalSince(started), attempt: attempt, failures: failures, outage: outage) {
            case .poll(let delay):
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    // The user cancelled: stop the job so its credit is released.
                    release(jobID: jobID, cancel: true)
                    throw CancellationError()
                }
            case .cancel:
                throw await cancelOverdue(jobID: jobID)
            case .giveUp:
                // No cancel either: if the results were handed over in an
                // answer that never arrived, a DELETE would read as "got it".
                throw Self.resultNotReceived
            }
            attempt += 1
            do {
                // Never a new account mid-job: the job belongs to this session.
                guard let token = try await auth.existingAccessToken() else { throw AIServiceError.unauthorized }
                response = try await decodeJob(RequestFactory.jobStatus(jobID: jobID, config: config, accessToken: token))
                failures = 0
                outageStarted = nil
            } catch where PollingSchedule.isWorthRetrying(error) {
                failures += 1
                if outageStarted == nil { outageStarted = Date() }
            } catch is CancellationError {
                release(jobID: jobID, cancel: true)
                throw CancellationError()
            }
        }
        return response
    }

    /// Still running at the deadline: cancel it and say what really happened.
    private func cancelOverdue(jobID: String) async -> Error {
        let sent = Date()
        guard let token = try? await auth.existingAccessToken(),
              var request = try? RequestFactory.cancelJob(jobID: jobID, config: config, accessToken: token) else {
            return Self.resultNotReceived
        }
        request.timeoutInterval = 15
        guard let (data, response) = try? await load(request),
              (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0) else {
            return Self.resultNotReceived
        }
        await report(ResponseDecoder.reportedBalance(in: data), sent: sent)
        switch ResponseDecoder.reportedStatus(in: data) {
        case .cancelled, .failed:
            // Cancelled or failed jobs are refunded (or were never charged).
            return AIServiceError.server(code: "timeout", message: String(localized: "This is taking longer than usual. Your credit was refunded — please try again."))
        default:
            return Self.resultNotReceived
        }
    }

    /// The connection dropped and never came back in time. The server
    /// refunds a result that never reached the app, so no refund is claimed
    /// beyond that.
    static let resultNotReceived = AIServiceError.server(
        code: "result_not_received",
        message: String(localized: "The connection dropped before your result arrived. If it never reaches you, your credit comes back automatically within about an hour.")
    )

    private func decodeJob(_ request: URLRequest) async throws -> GenerationResponse {
        let sent = Date()
        let (data, response) = try await load(request)
        let http = response as? HTTPURLResponse
        await report(ResponseDecoder.reportedBalance(in: data), sent: sent)
        return try ResponseDecoder.decodeGeneration(
            data: data,
            statusCode: http?.statusCode ?? 0,
            retryAfter: http?.value(forHTTPHeaderField: "Retry-After")
        )
    }

    private func report(_ balance: Int?, sent: Date) async {
        guard let balance else { return }
        await balanceObserver(balance, sent)
    }

    /// Fire-and-forget so it still runs when the calling task was cancelled.
    /// `cancel`: she stopped it, so the server cancels and refunds it (unless
    /// its results already reached the app). Otherwise it's the "got it" after
    /// the download, and the server deletes the results; retried a few times,
    /// since a lost confirmation keeps them on the server for up to an hour.
    private func release(jobID: String, cancel: Bool) {
        let config = config
        let auth = auth
        let session = session
        let observer = balanceObserver
        let makeRequest: (String, BackendConfiguration, String?) throws -> URLRequest = cancel
            ? RequestFactory.cancelJob(jobID:config:accessToken:)
            : RequestFactory.confirmJob(jobID:config:accessToken:)
        Task.detached(priority: .utility) {
            for retryDelay in [0, 2, 5] as [Double] {
                if retryDelay > 0 { try? await Task.sleep(for: .seconds(retryDelay)) }
                let sent = Date()
                guard let token = try? await auth.existingAccessToken(),
                      let request = try? makeRequest(jobID, config, token),
                      let (data, response) = try? await session.data(for: request) else { continue }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if cancel, (200..<300).contains(status), let balance = ResponseDecoder.reportedBalance(in: data) {
                    await observer(balance, sent)
                }
                if status < 500 { return }
            }
        }
    }

    // MARK: Account & credits

    /// The server-side balance with its policy numbers and status, or nil
    /// without a session. Never signs up: reading a balance must not create
    /// an account. Never asks the App Store for anything either.
    func fetchBalance() async throws -> BalanceState? {
        guard let token = try await auth.existingAccessToken() else { return nil }
        let jws = await entitlementProvider()
        let appTransaction = await appTransactions.jws()
        let request = try RequestFactory.balance(config: config, accessToken: token, entitlementJWS: jws,
                                                 appTransactionJWS: appTransaction)
        let (data, response) = try await load(request)
        return try ResponseDecoder.decodeBalanceState(data: data, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Whether cloud AI rests for everyone right now (nil: it takes jobs).
    /// Sent without her session or install: the answer is the same for all.
    func fetchAIPause() async throws -> AIServicePause? {
        let (data, response) = try await load(RequestFactory.aiPause(config: config))
        return try ResponseDecoder.decodeAIPause(data: data, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Sends a consumable's signed transaction; returns the new balance.
    func redeemCreditPack(signedTransaction: String) async throws -> Int {
        let token = try await auth.validAccessToken()
        let request = try RequestFactory.redeemCreditPack(signedTransaction: signedTransaction, config: config, accessToken: token,
                                                          appTransactionJWS: await appTransactions.jws())
        let (data, response) = try await load(request)
        return try ResponseDecoder.decodeBalance(data: data, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Deletes the server account, if this device has one. Never signs up:
    /// a new anonymous user would be the one deleted, while the real account
    /// stayed. `previouslyRequested` means an earlier attempt was sent, so a
    /// rejected session means that attempt worked and only its reply was lost.
    /// `authorizationCode` is a fresh Sign in with Apple code, sent after the
    /// server answered `appleConfirmationNeeded`; `skipAppleRevoke` deletes
    /// without one when Apple couldn't give a code.
    func deleteAccount(previouslyRequested: Bool, authorizationCode: String? = nil, skipAppleRevoke: Bool = false) async throws {
        let token: String?
        do {
            token = try await auth.existingAccessToken()
        } catch AIServiceError.unauthorized {
            guard previouslyRequested else { throw AccountDeletionError.sessionRejected }
            await auth.signOut()
            return
        } catch {
            throw AIServiceError.network(String(localized: "Check your internet connection and try again."))
        }
        guard let token else { return }
        // An anonymous user whose merge failed after Sign in with Apple goes too.
        let anonymous = await auth.pendingAnonymousToken()
        let request = try RequestFactory.deleteAccount(
            config: config, accessToken: token, anonymousToken: anonymous,
            authorizationCode: authorizationCode, skipAppleRevoke: skipAppleRevoke
        )
        let (data, response) = try await load(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, previouslyRequested {
            await auth.signOut()
            return
        }
        guard (200..<300).contains(status) else {
            let error = ResponseDecoder.error(from: data, statusCode: status)
            // Nothing was deleted: the server holds no Apple token to revoke.
            if case .server(code: "apple_reauth_required", _) = error { throw AccountDeletionError.appleConfirmationNeeded }
            throw error
        }
        await auth.signOut()
    }

    /// Sends a "Report this image" to the backend for review.
    func report(_ reason: ReportReason, jobID: String?) async throws {
        let token = try await auth.validAccessToken()
        let request = try RequestFactory.report(reason, jobID: jobID, config: config, accessToken: token)
        let (data, response) = try await load(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ResponseDecoder.error(from: data, statusCode: status)
        }
    }

    // MARK: Sign in with Apple

    /// Signs in with Apple. Throws only when that sign-in failed: from here on
    /// requests use the account, and `linkAccount()` moves her credits and
    /// hands Apple's code over (kept in the Keychain until it did).
    func signInWithApple(idToken: String, nonce: String, authorizationCode: String?) async throws {
        try await auth.signInWithApple(idToken: idToken, nonce: nonce, authorizationCode: authorizationCode)
    }

    /// Hands Apple's code to the server and merges a leftover anonymous user
    /// into the account. Safe to retry: both wait until the server took them.
    func linkAccount() async throws {
        let anonymous = await auth.pendingAnonymousToken()
        let code = await auth.appleCode
        guard anonymous != nil || code != nil else { return }
        let token = try await auth.validAccessToken()
        let request = try RequestFactory.linkAccount(
            anonymousToken: anonymous, authorizationCode: code, config: config, accessToken: token
        )
        let (data, response) = try await load(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ResponseDecoder.error(from: data, statusCode: status)
        }
        // Taken even when Apple refused it (the code lasts five minutes): with
        // no token stored, deleting the account asks Apple for a fresh one.
        await auth.clearAppleCode()
        await auth.clearPendingMerge()
    }

    /// Credits from before Sign in with Apple still wait to move into the account.
    func creditsWaitingToMove() async -> Bool {
        await auth.hasPendingMerge
    }

    /// The signed-in account (nil while anonymous).
    func account() async -> AuthSession? {
        await auth.account
    }

    /// Back to a fresh anonymous session on this iPhone.
    func signOut() async {
        await auth.signOut()
    }

    /// The stored user id, if any. No network and no sign-up.
    func existingUserID() async -> UUID? {
        await auth.userID.flatMap(UUID.init(uuidString:))
    }

    /// Supabase user id, used as the StoreKit `appAccountToken`. Signs up an
    /// anonymous user when there is none yet, so call it only when she acts.
    func currentUserID() async -> UUID? {
        _ = try? await auth.validAccessToken()
        return await auth.userID.flatMap(UUID.init(uuidString:))
    }

    // MARK: Request body

    static func makeRequestBody(for job: AIJob) throws -> GenerationRequest {
        var request = GenerationRequest(operation: job.operation, numOutputs: job.numOutputs, retryOf: job.retryOf)
        switch job.operation {
        case .textToImage:
            request.prompt = PromptBuilder.textToImagePrompt(job.prompt ?? "", style: job.style ?? StyleCatalog.auto)
            request.styleID = job.style?.id
            request.aspectRatio = job.aspectRatio
        case .magicEdit:
            request.prompt = PromptBuilder.editInstruction(job.prompt ?? "")
        case .restyle:
            // The server expands the template id into its own, up-to-date recipe.
            request.templateID = job.template?.id
            request.prompt = job.template == nil ? job.prompt : nil
        case .enhance, .removeBackground, .eraseObject:
            break
        }

        if let source = job.sourceImage {
            guard let jpeg = ImageUtilities.jpegData(source, maxLongEdge: uploadLongEdge, quality: 0.9) else {
                throw AIServiceError.invalidRequest(String(localized: "This photo couldn't be read."))
            }
            request.image = GenerationRequest.dataURI(jpeg, mimeType: "image/jpeg")
        }
        if let mask = job.mask, let png = ImageUtilities.pngData(mask, maxLongEdge: uploadLongEdge) {
            request.mask = GenerationRequest.dataURI(png, mimeType: "image/png")
        }
        return request
    }

    // MARK: Networking

    private func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.mappedData(for: request)
    }

    /// Decoded once into a plain bitmap here, off the main actor: the editor,
    /// My Works and the encoders read a result many times.
    private func loadImage(_ output: GenerationResponse.Output) async throws -> UIImage? {
        if let base64 = output.base64, let data = Data(base64Encoded: base64) {
            return ImageUtilities.decodedImage(from: data, maxPixel: 4096)
        }
        guard let url = output.url else { return nil }
        let (data, _) = try await load(URLRequest(url: url))
        return ImageUtilities.decodedImage(from: data, maxPixel: 4096)
    }
}

enum AccountDeletionError: LocalizedError {
    /// The server no longer accepts the session.
    case sessionRejected
    /// A Sign in with Apple account the server holds no Apple token for:
    /// nothing was deleted, and Apple has to confirm first (a fresh code).
    case appleConfirmationNeeded

    var errorDescription: String? {
        switch self {
        case .sessionRejected:
            String(localized: "We couldn't confirm your account, so nothing was deleted. Please contact support and we'll delete it for you.")
        case .appleConfirmationNeeded:
            String(localized: "Confirm with Apple to finish deleting your account.")
        }
    }
}
