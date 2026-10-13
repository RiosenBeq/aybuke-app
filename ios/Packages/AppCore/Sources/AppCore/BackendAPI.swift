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

    enum CodingKeys: String, CodingKey {
        case code, message
        case creditsRemaining = "credits_remaining"
    }

    public init(code: String, message: String, creditsRemaining: Int? = nil) {
        self.code = code
        self.message = message
        self.creditsRemaining = creditsRemaining
    }
}

struct APIErrorEnvelope: Decodable {
    let error: APIErrorBody
}

/// How often to poll a job: quick at first (most edits finish in 5–15 s),
/// then backing off, with an overall deadline.
public struct PollingSchedule: Equatable, Sendable {
    public var delays: [TimeInterval]
    public var maxDelay: TimeInterval
    public var timeout: TimeInterval

    public init(delays: [TimeInterval] = [1, 1, 1.5, 1.5, 2, 2, 2.5], maxDelay: TimeInterval = 3, timeout: TimeInterval = 180) {
        self.delays = delays
        self.maxDelay = maxDelay
        self.timeout = timeout
    }

    public static let standard = PollingSchedule()

    public func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt >= 0 else { return delays.first ?? maxDelay }
        return attempt < delays.count ? delays[attempt] : maxDelay
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
    case invalidResponse
    case noSubjectFound
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
        case .invalidResponse:
            return "Something went wrong. Please try again."
        case .noSubjectFound:
            return "We couldn't find a clear subject in this photo."
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

    public static func generation(
        _ body: GenerationRequest,
        config: BackendConfiguration,
        accessToken: String?,
        entitlementJWS: String? = nil,
        timeout: TimeInterval = 120
    ) throws -> URLRequest {
        var request = URLRequest(url: config.baseURL.appendingPathComponent(config.functionPath))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken ?? config.anonKey)", forHTTPHeaderField: "Authorization")
        if let entitlementJWS, !entitlementJWS.isEmpty {
            request.setValue(entitlementJWS, forHTTPHeaderField: entitlementHeader)
        }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    public static func jobStatus(jobID: String, config: BackendConfiguration, accessToken: String?) throws -> URLRequest {
        try authorized(config: config, path: config.functionPath, method: "GET",
                       query: [URLQueryItem(name: "job_id", value: jobID)], accessToken: accessToken)
    }

    public static func cancelJob(jobID: String, config: BackendConfiguration, accessToken: String?) throws -> URLRequest {
        try authorized(config: config, path: config.functionPath, method: "DELETE",
                       query: [URLQueryItem(name: "job_id", value: jobID)], accessToken: accessToken)
    }

    /// `GET` without a job id returns `{ "credits_remaining": n }`.
    public static func balance(config: BackendConfiguration, accessToken: String?, entitlementJWS: String? = nil) throws -> URLRequest {
        var request = try authorized(config: config, path: config.functionPath, method: "GET", query: [], accessToken: accessToken)
        if let entitlementJWS, !entitlementJWS.isEmpty {
            request.setValue(entitlementJWS, forHTTPHeaderField: entitlementHeader)
        }
        return request
    }

    /// Grants a consumable credit pack after the server verifies Apple's signed transaction.
    public static func redeemCreditPack(signedTransaction: String, config: BackendConfiguration, accessToken: String?) throws -> URLRequest {
        var request = try authorized(config: config, path: "functions/v1/credits-redeem", method: "POST", query: [], accessToken: accessToken)
        request.httpBody = try JSONEncoder().encode(["signed_transaction": signedTransaction])
        return request
    }

    /// Deletes the anonymous account and all server-side data (Guideline 5.1.1(v)).
    public static func deleteAccount(config: BackendConfiguration, accessToken: String?) throws -> URLRequest {
        try authorized(config: config, path: "functions/v1/account", method: "DELETE", query: [], accessToken: accessToken)
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

    public static func decodeBalance(data: Data, statusCode: Int) throws -> Int {
        guard (200..<300).contains(statusCode) else {
            throw error(from: data, statusCode: statusCode)
        }
        struct Balance: Decodable {
            let creditsRemaining: Int
            enum CodingKeys: String, CodingKey { case creditsRemaining = "credits_remaining" }
        }
        guard let balance = try? JSONDecoder().decode(Balance.self, from: data) else {
            throw AIServiceError.invalidResponse
        }
        return balance.creditsRemaining
    }

    public static func error(from data: Data, statusCode: Int, retryAfter: String? = nil) -> AIServiceError {
        let body = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error
        if let mapped = mapped(body, statusCode: statusCode, retryAfter: retryAfter) {
            return mapped
        }
        return .server(code: "http_\(statusCode)", message: "The AI service is busy. Please try again.")
    }

    static func mapped(_ body: APIErrorBody?, statusCode: Int, retryAfter: String?) -> AIServiceError? {
        switch (statusCode, body?.code) {
        case (402, _), (_, "insufficient_credits"):
            return .insufficientCredits(remaining: body?.creditsRemaining)
        case (_, "content_blocked"), (451, _):
            return .contentBlocked(body?.message ?? "This request isn't allowed by our content policy.")
        case (401, _), (403, _):
            return .unauthorized
        case (429, _):
            return .rateLimited(retryAfter: retryAfter.flatMap(TimeInterval.init))
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
        return AuthSession(accessToken: dto.accessToken, refreshToken: dto.refreshToken, expiresAt: expiresAt, userID: dto.user.id)
    }
}

// MARK: - Auth session

public struct AuthSession: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var userID: String

    public init(accessToken: String, refreshToken: String, expiresAt: Date, userID: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userID = userID
    }

    /// Refresh a minute early to avoid racing the expiry.
    public func isExpired(at date: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        date.addingTimeInterval(leeway) >= expiresAt
    }
}

struct SupabaseSessionDTO: Decodable {
    struct User: Decodable { let id: String }

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
