import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Wire models (shared contract with backend/supabase/functions/ai-image)

public struct GenerationRequest: Codable, Equatable, Sendable {
    public var operation: AIOperation
    public var prompt: String?
    public var styleID: String?
    public var templateID: String?
    public var aspectRatio: AspectRatio?
    public var numOutputs: Int
    /// Source photo as a `data:` URI (JPEG).
    public var image: String?
    /// Erase mask as a `data:` URI (PNG, white = remove).
    public var mask: String?
    /// `request_id` of a previous result the user is re-rolling for free
    /// ("Doesn't look like you? Retry free"). The backend allows one free
    /// retry per result within a short window.
    public var retryOf: String?

    enum CodingKeys: String, CodingKey {
        case operation, prompt, image, mask
        case styleID = "style_id"
        case templateID = "template_id"
        case aspectRatio = "aspect_ratio"
        case numOutputs = "num_outputs"
        case retryOf = "retry_of"
    }

    public init(
        operation: AIOperation, prompt: String? = nil, styleID: String? = nil, templateID: String? = nil,
        aspectRatio: AspectRatio? = nil, numOutputs: Int = 1, image: String? = nil, mask: String? = nil,
        retryOf: String? = nil
    ) {
        self.operation = operation
        self.prompt = prompt
        self.styleID = styleID
        self.templateID = templateID
        self.aspectRatio = aspectRatio
        self.numOutputs = numOutputs
        self.image = image
        self.mask = mask
        self.retryOf = retryOf
    }

    public static let maxOutputs = 4

    /// Mirrors the backend's validation so obviously bad requests fail fast.
    public func validate() throws {
        if operation.requiresSourceImage && (image ?? "").isEmpty {
            throw AIServiceError.invalidRequest("Pick a photo first.")
        }
        if operation.requiresPrompt && (prompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AIServiceError.invalidRequest("Describe what you want to see.")
        }
        if operation.requiresMask && (mask ?? "").isEmpty {
            throw AIServiceError.invalidRequest("Brush over the area you want to erase.")
        }
        if operation == .restyle && (templateID ?? "").isEmpty && (prompt ?? "").isEmpty {
            throw AIServiceError.invalidRequest("Choose a style.")
        }
        if !(1...Self.maxOutputs).contains(numOutputs) {
            throw AIServiceError.invalidRequest("You can create 1–\(Self.maxOutputs) images at a time.")
        }
    }

    public static func dataURI(_ data: Data, mimeType: String) -> String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }
}

/// Jobs are asynchronous: `POST` enqueues and returns `queued`; the app polls
/// `GET ?job_id=` until the job is `completed` or `failed`. (Edge functions
/// must not hold a request open for a 5–40 s generation.)
public struct GenerationResponse: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case queued, processing, completed, failed, cancelled
    }

    public struct Output: Codable, Equatable, Sendable {
        public var url: URL?
        /// Inline base64 payload (used by small results such as masks).
        public var base64: String?
        public var width: Int?
        public var height: Int?
        public var contentType: String?

        enum CodingKeys: String, CodingKey {
            case url, base64, width, height
            case contentType = "content_type"
        }

        public init(url: URL? = nil, base64: String? = nil, width: Int? = nil, height: Int? = nil, contentType: String? = nil) {
            self.url = url
            self.base64 = base64
            self.width = width
            self.height = height
            self.contentType = contentType
        }
    }

    public var jobID: String?
    public var status: Status
    public var outputs: [Output]
    public var creditsRemaining: Int?
    public var error: APIErrorBody?

    enum CodingKeys: String, CodingKey {
        case status, outputs, error
        case jobID = "job_id"
        case creditsRemaining = "credits_remaining"
    }

    public init(jobID: String? = nil, status: Status = .completed, outputs: [Output] = [], creditsRemaining: Int? = nil, error: APIErrorBody? = nil) {
        self.jobID = jobID
        self.status = status
        self.outputs = outputs
        self.creditsRemaining = creditsRemaining
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobID = try container.decodeIfPresent(String.self, forKey: .jobID)
        outputs = try container.decodeIfPresent([Output].self, forKey: .outputs) ?? []
        // A response without a status but with outputs is a finished job.
        status = try container.decodeIfPresent(Status.self, forKey: .status) ?? (outputs.isEmpty ? .queued : .completed)
        creditsRemaining = try container.decodeIfPresent(Int.self, forKey: .creditsRemaining)
        error = try container.decodeIfPresent(APIErrorBody.self, forKey: .error)
    }

    public var isFinished: Bool {
        status == .completed || status == .failed || status == .cancelled
    }
}

public struct APIErrorBody: Codable, Equatable, Sendable {
    public var code: String
    public var message: String
    public var creditsRemaining: Int?
    /// Seconds until trying again makes sense (cool-downs, breakers, limits).
    public var retryAfter: Int?

    enum CodingKeys: String, CodingKey {
        case code, message
        case creditsRemaining = "credits_remaining"
        case retryAfter = "retry_after"
    }

    public init(code: String, message: String, creditsRemaining: Int? = nil, retryAfter: Int? = nil) {
        self.code = code
        self.message = message
        self.creditsRemaining = creditsRemaining
        self.retryAfter = retryAfter
    }
}

/// The numbers the server enforces (`credit_policy()`), sent with every
/// balance so the app's copy can say them. Any of them may be missing.
public struct ServerCreditPolicy: Decodable, Equatable, Sendable {
    public var freeDaily: Int?
    public var proMonthly: Int?
    public var rolloverCap: Int?
    public var trialCredits: Int?
    public var freeRetriesDaily: Int?

    enum CodingKeys: String, CodingKey {
        case freeDaily = "free_daily"
        case proMonthly = "pro_monthly"
        case rolloverCap = "rollover_cap"
        case trialCredits = "trial_credits"
        case freeRetriesDaily = "free_retries_daily"
    }

    public init(freeDaily: Int? = nil, proMonthly: Int? = nil, rolloverCap: Int? = nil, trialCredits: Int? = nil,
                freeRetriesDaily: Int? = nil) {
        self.freeDaily = freeDaily
        self.proMonthly = proMonthly
        self.rolloverCap = rolloverCap
        self.trialCredits = trialCredits
        self.freeRetriesDaily = freeRetriesDaily
    }
}

/// `GET /ai-image` without a job id: the balance and what's behind it.
public struct BalanceState: Decodable, Equatable, Sendable {
    /// Whether the free part of the balance is known.
    public enum FreeCredits: String, Decodable, Sendable {
        /// Today's free credits on her verified App Store install are in the balance.
        case ok
        /// Pro: no free daily credits.
        case pro
        /// No App Store install could be verified (no AppTransaction yet, or
        /// StoreKit couldn't supply one): the free part is unknown, so the
        /// app lets the server decide instead of showing the paywall.
        case unverified
    }

    /// Cloud AI for her account and install.
    public enum AIStatus: String, Decodable, Sendable {
        case ok
        /// Resting after repeated safety blocks, until `cooldownSeconds` pass.
        case cooldown
        /// Off until the team lifts it.
        case blocked
    }

    public var creditsRemaining: Int
    public var isPro: Bool?
    public var freeCredits: FreeCredits?
    public var aiStatus: AIStatus?
    public var cooldownSeconds: Int?
    public var policy: ServerCreditPolicy?

    enum CodingKeys: String, CodingKey {
        case policy
        case creditsRemaining = "credits_remaining"
        case isPro = "is_pro"
        case freeCredits = "free_credits"
        case aiStatus = "ai_status"
        case cooldownSeconds = "cooldown_seconds"
    }

    public init(creditsRemaining: Int, isPro: Bool? = nil, freeCredits: FreeCredits? = nil, aiStatus: AIStatus? = nil,
                cooldownSeconds: Int? = nil, policy: ServerCreditPolicy? = nil) {
        self.creditsRemaining = creditsRemaining
        self.isPro = isPro
        self.freeCredits = freeCredits
        self.aiStatus = aiStatus
        self.cooldownSeconds = cooldownSeconds
        self.policy = policy
    }

    /// Values this version doesn't know read as unknown, never as an error.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        creditsRemaining = try container.decode(Int.self, forKey: .creditsRemaining)
        isPro = try? container.decodeIfPresent(Bool.self, forKey: .isPro)
        freeCredits = (try? container.decodeIfPresent(String.self, forKey: .freeCredits)).flatMap { FreeCredits(rawValue: $0) }
        aiStatus = (try? container.decodeIfPresent(String.self, forKey: .aiStatus)).flatMap { AIStatus(rawValue: $0) }
        cooldownSeconds = try? container.decodeIfPresent(Int.self, forKey: .cooldownSeconds)
        policy = try? container.decodeIfPresent(ServerCreditPolicy.self, forKey: .policy)
    }
}

/// Why cloud AI is off for now. The free on-device tools always work.
public enum CloudPause: Equatable, Sendable {
    /// A short rest after repeated safety blocks, until the date.
    case cooldown(until: Date)
    /// Off for this install until the team lifts it.
    case blocked

    public func isActive(at date: Date = Date()) -> Bool {
        switch self {
        case .cooldown(let until): return until > date
        case .blocked: return true
        }
    }

    /// From a balance: nil when cloud AI is on.
    public static func from(_ state: BalanceState, now: Date = Date()) -> CloudPause? {
        switch state.aiStatus {
        case .cooldown:
            return .cooldown(until: now.addingTimeInterval(TimeInterval(max(60, state.cooldownSeconds ?? 24 * 3600))))
        case .blocked:
            return .blocked
        case .ok, nil:
            return nil
        }
    }
}

/// `GET /credits-redeem`: cloud AI rests for everyone, not just her (that's
/// `CloudPause`): the owner's pause, the day's limits or the image
/// provider's balance (backend `credits-redeem/pause.ts`). Jobs get
/// `ai_paused` meanwhile, so the app offers no ad for a credit and says so
/// where credits are sold. The free on-device tools always work.
public struct AIServicePause: Equatable, Sendable {
    /// Only free daily credits rest (ad credits land there too); Pro
    /// credits and packs still work.
    public var freeOnly: Bool
    /// When it ends at the latest; the owner can end it sooner.
    public var until: Date

    public init(freeOnly: Bool, until: Date) {
        self.freeOnly = freeOnly
        self.until = until
    }

    public func isActive(at date: Date = Date()) -> Bool {
        until > date
    }

    /// Whether it stops what she'd pay with: every pause stops free credits,
    /// a free one leaves Pro's credits alone.
    public func touches(isPro: Bool) -> Bool {
        !(freeOnly && isPro)
    }
}

/// When the app reads the balance on its own (at launch, back in the
/// foreground): each read is a server request, so at most once every
/// `interval` after the last read that answered. A purchase, a sign-in, the
/// credits sheet and every job still read or report it at once.
public struct BalanceRefreshPolicy: Equatable, Sendable {
    public var interval: TimeInterval

    public init(interval: TimeInterval = 15 * 60) {
        self.interval = interval
    }

    public static let standard = BalanceRefreshPolicy()

    /// Due without a read yet, once `interval` has passed, or when the clock went back.
    public func isDue(lastRead: Date?, now: Date = Date()) -> Bool {
        guard let lastRead else { return true }
        let age = now.timeIntervalSince(lastRead)
        return age >= interval || age < 0
    }
}

struct APIErrorEnvelope: Decodable {
    let error: APIErrorBody
}

/// How often to poll a job. The server holds each poll while the job runs, up
/// to 20 s (backend `ai-image/long-poll.ts`), and answers the moment it ends,
/// so a short gap between polls is enough: most edits (5–15 s) take one or two
/// polls, each one Edge Function invocation. There is an overall deadline. A
/// poll that can't reach the server (a lift, a tunnel, a busy gateway) doesn't
/// end the wait: the job and its credit are still on the server, so the app
/// retries with growing gaps and stops only after `offlineGrace` without an
/// answer. The server refunds a result that never reached the app (backend
/// `sweep_jobs()`).
public struct PollingSchedule: Equatable, Sendable {
    public var delays: [TimeInterval]
    public var maxDelay: TimeInterval
    /// A job the server still runs after this is cancelled (and refunded).
    public var timeout: TimeInterval
    /// Waits after polls in a row that couldn't reach the server.
    public var retryDelays: [TimeInterval]
    /// How long the server may stay out of reach before the app stops waiting.
    public var offlineGrace: TimeInterval

    public init(
        delays: [TimeInterval] = [2, 2, 3], maxDelay: TimeInterval = 3, timeout: TimeInterval = 180,
        retryDelays: [TimeInterval] = [2, 3, 5, 8, 13], offlineGrace: TimeInterval = 120
    ) {
        self.delays = delays
        self.maxDelay = maxDelay
        self.timeout = timeout
        self.retryDelays = retryDelays
        self.offlineGrace = offlineGrace
    }

    public static let standard = PollingSchedule()

    public func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt >= 0 else { return delays.first ?? maxDelay }
        return attempt < delays.count ? delays[attempt] : maxDelay
    }

    /// The wait after `failures` polls in a row couldn't reach the server.
    public func retryDelay(afterFailures failures: Int) -> TimeInterval {
        guard let last = retryDelays.last else { return maxDelay }
        return failures >= 1 && failures <= retryDelays.count ? retryDelays[failures - 1] : last
    }

    public enum Step: Equatable, Sendable {
        /// Ask again after this many seconds.
        case poll(after: TimeInterval)
        /// The server's last answer says the job still runs past the deadline: cancel it.
        case cancel
        /// The server has been out of reach too long: stop, without claiming a refund.
        case giveUp
    }

    /// What to do after a poll: `elapsed` seconds since the job started,
    /// `attempt` polls so far, and the last `failures` polls in a row not
    /// reaching the server, the first of them `outage` seconds ago. The outage
    /// is measured while the app runs, so a poll cut off by a trip to the
    /// background is simply asked again.
    public func next(elapsed: TimeInterval, attempt: Int, failures: Int, outage: TimeInterval = 0) -> Step {
        if failures > 0 {
            return outage >= offlineGrace ? .giveUp : .poll(after: retryDelay(afterFailures: failures))
        }
        return elapsed >= timeout ? .cancel : .poll(after: delay(forAttempt: attempt))
    }

    /// Failures worth polling through: no connection, a timeout, a rate limit,
    /// or a server or gateway error. A job the server doesn't know, or a
    /// session it rejects, isn't.
    public static func isWorthRetrying(_ error: Error) -> Bool {
        switch error as? AIServiceError {
        case .offline, .timedOut, .network, .rateLimited:
            return true
        case .server(let code, _):
            return code.hasPrefix("http_5") || code == "internal"
        default:
            return false
        }
    }
}

// MARK: - Reports

/// Why a user reported a result. Raw values are the wire format of the
/// backend `report` function.
public enum ReportReason: String, CaseIterable, Codable, Sendable, Identifiable {
    case offensive
    case sexual
    case mismatch
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .offensive: return "Offensive or harmful"
        case .sexual: return "Sexual content"
        case .mismatch: return "Doesn't match my request"
        case .other: return "Something else"
        }
    }
}

struct ReportBody: Encodable {
    let reason: ReportReason
    let jobID: String?
    let details: String?

    enum CodingKeys: String, CodingKey {
        case reason, details
        case jobID = "job_id"
    }
}

// MARK: - Errors

public enum AIServiceError: Error, Equatable, Sendable {
    case notConfigured
    case consentRequired
    case invalidRequest(String)
    case insufficientCredits(remaining: Int?)
    case contentBlocked(String)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case server(code: String, message: String)
    case network(String)
    /// No connection at all; the free on-device tools still work.
    case offline
    /// The connection was too slow to answer in time.
    case timedOut
    /// The server's certificate or the TLS handshake failed.
    case insecureConnection
    case invalidResponse
    case noSubjectFound
    /// The server couldn't verify this install with the App Store (its
    /// AppTransaction was missing or invalid), so no free credits.
    case appStoreCheckFailed
    /// Cloud AI rests for a while after repeated safety blocks.
    case cooldown(retryAfter: TimeInterval?)
    /// Cloud AI is off for this install until the team lifts it.
    case cloudBlocked
    /// The day's AI budget is used up (a circuit breaker), or the team paused AI.
    case aiPaused(retryAfter: TimeInterval?)
    /// Too many jobs this hour or today.
    case usageLimit(retryAfter: TimeInterval?)
    /// Today's free Likeness Lock retries are used.
    case retryLimit
}

extension AIServiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI features aren't configured yet."
        case .consentRequired:
            return "Allow AI processing to use this feature."
        case .invalidRequest(let message):
            return message
        case .insufficientCredits:
            return "You're out of credits for today."
        case .contentBlocked(let message):
            return message
        case .unauthorized:
            return "Your session expired. Please try again."
        case .rateLimited:
            return "Too many requests. Please wait a moment."
        case .server(_, let message):
            return message
        case .network(let message):
            return message
        case .offline:
            return "You're offline. Effects, Adjust, Cut out and Video still work."
        case .timedOut:
            return "This is taking too long. Check your connection and try again."
        case .insecureConnection:
            return "Secure connection failed."
        case .invalidResponse:
            return "Something went wrong. Please try again."
        case .noSubjectFound:
            return "We couldn't find a clear subject in this photo."
        case .appStoreCheckFailed:
            return "We couldn't confirm your download with the App Store, so free credits aren't available right now. Check that you're signed in to the App Store, then try again."
        case .cooldown:
            return "Cloud AI is taking a little break for now. Your free tools still work in the meantime."
        case .cloudBlocked:
            return "Cloud AI is turned off here for now. Your free tools still work. If you think this is a mistake, contact us."
        case .aiPaused:
            return "AI is taking a short break. Please try again later. Your free tools still work."
        case .usageLimit:
            return "You've made a lot in a short time. Take a little break and try again later."
        case .retryLimit:
            return "You've used today's free retries."
        }
    }
}

// MARK: - Request building

public struct BackendConfiguration: Equatable, Sendable {
    public var baseURL: URL
    /// Supabase publishable (anon) key. Public by design; access is enforced
    /// server-side with row-level security and the function's own checks.
    public var anonKey: String
    public var functionPath: String

    public init(baseURL: URL, anonKey: String, functionPath: String = "functions/v1/ai-image") {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.functionPath = functionPath
    }
}

public enum RequestFactory {
    public static let entitlementHeader = "X-Entitlement-JWS"
    /// StoreKit's signed AppTransaction: free credits belong to a verified
    /// App Store install (backend `_shared/apple.ts`).
    public static let appTransactionHeader = "X-App-Transaction"

    public static func generation(
        _ body: GenerationRequest,
        config: BackendConfiguration,
        accessToken: String?,
        entitlementJWS: String? = nil,
        appTransactionJWS: String? = nil,
        timeout: TimeInterval = 120
    ) throws -> URLRequest {
        var request = URLRequest(url: config.baseURL.appendingPathComponent(config.functionPath))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken ?? config.anonKey)", forHTTPHeaderField: "Authorization")
        attach(entitlementJWS: entitlementJWS, appTransactionJWS: appTransactionJWS, to: &request)
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    static func attach(entitlementJWS: String?, appTransactionJWS: String?, to request: inout URLRequest) {
        if let entitlementJWS, !entitlementJWS.isEmpty {
            request.setValue(entitlementJWS, forHTTPHeaderField: entitlementHeader)
        }
        if let appTransactionJWS, !appTransactionJWS.isEmpty {
            request.setValue(appTransactionJWS, forHTTPHeaderField: appTransactionHeader)
        }
    }

    /// How long a poll may take: the server holds it up to 20 s while the job
    /// runs (backend `ai-image/long-poll.ts`), so well over that.
    public static let pollTimeout: TimeInterval = 45

    public static func jobStatus(jobID: String, config: BackendConfiguration, accessToken: String?) throws -> URLRequest {
        var request = try authorized(config: config, path: config.functionPath, method: "GET",
                                     query: [URLQueryItem(name: "job_id", value: jobID)], accessToken: accessToken)
        request.timeoutInterval = pollTimeout
        return request
    }

    /// Stops a job she cancelled or stopped waiting for. The server refunds
    /// it unless its results already reached the app.
    public static func cancelJob(jobID: String, config: BackendConfiguration, accessToken: String?) throws -> URLRequest {
        try authorized(config: config, path: config.functionPath, method: "DELETE",
                       query: [URLQueryItem(name: "job_id", value: jobID), URLQueryItem(name: "intent", value: "cancel")],
                       accessToken: accessToken)
    }

    /// "Got it": the app has the results, so the server deletes them right away.
    public static func confirmJob(jobID: String, config: BackendConfiguration, accessToken: String?) throws -> URLRequest {
        try authorized(config: config, path: config.functionPath, method: "DELETE",
                       query: [URLQueryItem(name: "job_id", value: jobID)], accessToken: accessToken)
    }

    /// `GET` without a job id returns the balance (`BalanceState`).
    public static func balance(
        config: BackendConfiguration, accessToken: String?, entitlementJWS: String? = nil, appTransactionJWS: String? = nil
    ) throws -> URLRequest {
        var request = try authorized(config: config, path: config.functionPath, method: "GET", query: [], accessToken: accessToken)
        attach(entitlementJWS: entitlementJWS, appTransactionJWS: appTransactionJWS, to: &request)
        return request
    }

    /// Grants a consumable credit pack after the server verifies Apple's signed transaction.
    public static func redeemCreditPack(
        signedTransaction: String, config: BackendConfiguration, accessToken: String?, appTransactionJWS: String? = nil
    ) throws -> URLRequest {
        var request = try authorized(config: config, path: "functions/v1/credits-redeem", method: "POST", query: [], accessToken: accessToken)
        attach(entitlementJWS: nil, appTransactionJWS: appTransactionJWS, to: &request)
        request.httpBody = try JSONEncoder().encode(["signed_transaction": signedTransaction])
        return request
    }

    /// Whether cloud AI takes jobs right now (`AIServicePause`). The answer is
    /// the same for everyone, so it goes without her session: the
    /// publishable key is enough, and no account is ever made to ask.
    public static func aiPause(config: BackendConfiguration) throws -> URLRequest {
        try authorized(config: config, path: "functions/v1/credits-redeem", method: "GET", query: [], accessToken: nil)
    }

    /// Deletes the account and all server-side data (Guideline 5.1.1(v)); the
    /// server also revokes the Sign in with Apple token. `anonymousToken` is an
    /// anonymous user that was never merged after Sign in with Apple, so the
    /// server deletes that user too. `authorizationCode` is a fresh Sign in with
    /// Apple code for an account the server holds no Apple token for (it answers
    /// `apple_reauth_required` otherwise); `skipAppleRevoke` deletes without one
    /// when Apple couldn't give a code.
    public static func deleteAccount(
        config: BackendConfiguration, accessToken: String?, anonymousToken: String? = nil,
        authorizationCode: String? = nil, skipAppleRevoke: Bool = false
    ) throws -> URLRequest {
        struct Body: Encodable {
            let anonymousToken: String?
            let authorizationCode: String?
            let skipAppleRevoke: Bool?

            enum CodingKeys: String, CodingKey {
                case anonymousToken = "anonymous_token"
                case authorizationCode = "authorization_code"
                case skipAppleRevoke = "skip_apple_revoke"
            }
        }
        var request = try authorized(config: config, path: "functions/v1/account", method: "DELETE", query: [], accessToken: accessToken)
        if anonymousToken != nil || authorizationCode != nil || skipAppleRevoke {
            request.httpBody = try JSONEncoder().encode(Body(
                anonymousToken: anonymousToken, authorizationCode: authorizationCode, skipAppleRevoke: skipAppleRevoke ? true : nil
            ))
        }
        return request
    }

    /// Supabase's native Sign in with Apple: exchanges Apple's identity token
    /// (requested with the SHA-256 of `nonce`) for a session. `nonce` is the raw value.
    public static func signInWithApple(idToken: String, nonce: String, config: BackendConfiguration) throws -> URLRequest {
        var components = URLComponents(url: config.baseURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]
        guard let url = components?.url else { throw AIServiceError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(["provider": "apple", "id_token": idToken, "nonce": nonce])
        return request
    }

    /// Right after Sign in with Apple: merges the previous anonymous user into
    /// the account and hands over Apple's one-time authorization code.
    public static func linkAccount(
        anonymousToken: String?, authorizationCode: String?,
        config: BackendConfiguration, accessToken: String?
    ) throws -> URLRequest {
        var request = try authorized(config: config, path: "functions/v1/account/link", method: "POST", query: [], accessToken: accessToken)
        var body: [String: String] = [:]
        body["anonymous_token"] = anonymousToken
        body["authorization_code"] = authorizationCode
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// Reports a result for review (Guideline 1.2). `jobID` links it to the job row when known.
    public static func report(
        _ reason: ReportReason, jobID: String?, details: String? = nil,
        config: BackendConfiguration, accessToken: String?
    ) throws -> URLRequest {
        var request = try authorized(config: config, path: "functions/v1/report", method: "POST", query: [], accessToken: accessToken)
        request.httpBody = try JSONEncoder().encode(ReportBody(reason: reason, jobID: jobID, details: details))
        return request
    }

    static func authorized(config: BackendConfiguration, path: String, method: String, query: [URLQueryItem], accessToken: String?) throws -> URLRequest {
        var components = URLComponents(url: config.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query
        }
        guard let url = components?.url else { throw AIServiceError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken ?? config.anonKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Supabase anonymous sign-in (`POST /auth/v1/signup` with an empty body).
    public static func anonymousSignUp(config: BackendConfiguration) -> URLRequest {
        var request = URLRequest(url: config.baseURL.appendingPathComponent("auth/v1/signup"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = Data("{}".utf8)
        return request
    }

    public static func refreshSession(refreshToken: String, config: BackendConfiguration) throws -> URLRequest {
        var components = URLComponents(url: config.baseURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        guard let url = components?.url else { throw AIServiceError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken])
        return request
    }
}

// MARK: - Response decoding

public enum ResponseDecoder {
    /// Decodes a job response. Returns queued/processing responses as-is (the
    /// caller keeps polling); throws for failed jobs and HTTP errors.
    public static func decodeGeneration(data: Data, statusCode: Int, retryAfter: String? = nil) throws -> GenerationResponse {
        guard (200..<300).contains(statusCode) else {
            throw error(from: data, statusCode: statusCode, retryAfter: retryAfter)
        }
        guard let response = try? JSONDecoder().decode(GenerationResponse.self, from: data) else {
            throw AIServiceError.invalidResponse
        }
        switch response.status {
        case .failed:
            throw mapped(response.error, statusCode: statusCode, retryAfter: nil)
                ?? AIServiceError.server(code: "job_failed", message: "This creation failed. Your credit was refunded.")
        case .cancelled:
            throw CancellationError()
        case .completed where response.outputs.isEmpty:
            throw AIServiceError.invalidResponse
        default:
            return response
        }
    }

    /// The balance a job response carries, if any: the 202 after the charge,
    /// a finished poll, a cancel's refund, or an error body (out of credits).
    public static func reportedBalance(in data: Data) -> Int? {
        struct Body: Decodable {
            struct ErrorBody: Decodable {
                let creditsRemaining: Int?
                enum CodingKeys: String, CodingKey { case creditsRemaining = "credits_remaining" }
            }
            let creditsRemaining: Int?
            let error: ErrorBody?
            enum CodingKeys: String, CodingKey {
                case error
                case creditsRemaining = "credits_remaining"
            }
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { return nil }
        return body.creditsRemaining ?? body.error?.creditsRemaining
    }

    /// The status in a job response, if any (e.g. a cancel's "cancelled").
    public static func reportedStatus(in data: Data) -> GenerationResponse.Status? {
        struct Body: Decodable { let status: GenerationResponse.Status? }
        return (try? JSONDecoder().decode(Body.self, from: data))?.status
    }

    public static func decodeBalance(data: Data, statusCode: Int) throws -> Int {
        try decodeBalanceState(data: data, statusCode: statusCode).creditsRemaining
    }

    /// The balance with its policy numbers and status (`GET /ai-image`).
    public static func decodeBalanceState(data: Data, statusCode: Int) throws -> BalanceState {
        guard (200..<300).contains(statusCode) else {
            throw error(from: data, statusCode: statusCode)
        }
        guard let state = try? JSONDecoder().decode(BalanceState.self, from: data) else {
            throw AIServiceError.invalidResponse
        }
        return state
    }

    /// `GET /credits-redeem`: nil while cloud AI takes jobs. A pause without
    /// an end lasts an hour here, until the next read says more; one that
    /// doesn't say it's free-only counts as all of AI.
    public static func decodeAIPause(data: Data, statusCode: Int, now: Date = Date()) throws -> AIServicePause? {
        struct Body: Decodable {
            let aiPaused: Bool
            let freeOnly: Bool?
            let retryAfter: Int?

            enum CodingKeys: String, CodingKey {
                case aiPaused = "ai_paused"
                case freeOnly = "free_only"
                case retryAfter = "retry_after"
            }
        }
        guard (200..<300).contains(statusCode) else {
            throw error(from: data, statusCode: statusCode)
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else {
            throw AIServiceError.invalidResponse
        }
        guard body.aiPaused else { return nil }
        let wait = TimeInterval(max(1, body.retryAfter ?? 3600))
        return AIServicePause(freeOnly: body.freeOnly ?? false, until: now.addingTimeInterval(wait))
    }

    public static func error(from data: Data, statusCode: Int, retryAfter: String? = nil) -> AIServiceError {
        let body = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error
        if let mapped = mapped(body, statusCode: statusCode, retryAfter: retryAfter) {
            return mapped
        }
        return .server(code: "http_\(statusCode)", message: "The AI service is busy. Please try again.")
    }

    static func mapped(_ body: APIErrorBody?, statusCode: Int, retryAfter: String?) -> AIServiceError? {
        // The body's number, else the header's.
        let wait = body?.retryAfter.map(TimeInterval.init) ?? retryAfter.flatMap(TimeInterval.init)
        // Codes first: some share a status with older meanings (403, 429).
        switch body?.code {
        case "app_transaction_required", "app_transaction_invalid":
            return .appStoreCheckFailed
        case "cooldown":
            return .cooldown(retryAfter: wait)
        case "install_blocked":
            return .cloudBlocked
        case "ai_paused":
            return .aiPaused(retryAfter: wait)
        case "usage_limit":
            return .usageLimit(retryAfter: wait)
        case "rate_limited":
            return .rateLimited(retryAfter: wait)
        case "retry_limit":
            return .retryLimit
        case "pro_required":
            // A Pro look or style without Pro or a live try of it (a 402, but
            // not a lack of credits): nothing was booked.
            return .server(code: "pro_required", message: body?.message ?? "")
        default:
            break
        }
        switch (statusCode, body?.code) {
        case (402, _), (_, "insufficient_credits"):
            return .insufficientCredits(remaining: body?.creditsRemaining)
        case (_, "content_blocked"), (451, _):
            return .contentBlocked(body?.message ?? "This request isn't allowed by our content policy.")
        case (401, _), (403, _):
            return .unauthorized
        case (429, _):
            return .rateLimited(retryAfter: wait)
        default:
            if let body {
                return .server(code: body.code, message: body.message)
            }
            return nil
        }
    }

    public static func decodeSession(data: Data, statusCode: Int, now: Date = Date()) throws -> AuthSession {
        guard (200..<300).contains(statusCode) else {
            throw statusCode == 401 || statusCode == 400 ? AIServiceError.unauthorized : error(from: data, statusCode: statusCode)
        }
        guard let dto = try? JSONDecoder().decode(SupabaseSessionDTO.self, from: data) else {
            throw AIServiceError.invalidResponse
        }
        let expiresAt = dto.expiresAt.map { Date(timeIntervalSince1970: $0) }
            ?? now.addingTimeInterval(dto.expiresIn ?? 3600)
        return AuthSession(
            accessToken: dto.accessToken, refreshToken: dto.refreshToken, expiresAt: expiresAt, userID: dto.user.id,
            isAnonymous: dto.user.isAnonymous, email: dto.user.email
        )
    }
}

// MARK: - Auth session

public struct AuthSession: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var userID: String
    /// False once signed in with Apple. Optional so sessions saved before
    /// accounts existed (all anonymous) still decode.
    public var isAnonymous: Bool?
    /// The Apple ID email or its private relay address, if shared.
    public var email: String?

    public init(
        accessToken: String, refreshToken: String, expiresAt: Date, userID: String,
        isAnonymous: Bool? = nil, email: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userID = userID
        self.isAnonymous = isAnonymous
        self.email = email
    }

    /// Signed in with Apple (a permanent account), rather than anonymous.
    public var isAccount: Bool { isAnonymous == false }

    /// Refresh a minute early to avoid racing the expiry.
    public func isExpired(at date: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        date.addingTimeInterval(leeway) >= expiresAt
    }
}

struct SupabaseSessionDTO: Decodable {
    struct User: Decodable {
        let id: String
        let isAnonymous: Bool?
        let email: String?

        enum CodingKeys: String, CodingKey {
            case id, email
            case isAnonymous = "is_anonymous"
        }
    }

    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval?
    let expiresAt: TimeInterval?
    let user: User

    enum CodingKeys: String, CodingKey {
        case user
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
    }
}
