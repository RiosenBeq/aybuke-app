import UIKit
import AppCore

/// Talks to the backend (`backend/supabase/functions`). The app never holds
/// AI-provider keys; the backend authenticates the user, meters credits,
/// moderates and forwards the job to the model provider.
///
/// Jobs are asynchronous: submit → poll until finished → download results.
final class RemoteAIImageService: AIImageService {
    private let config: BackendConfiguration
    private let auth: AuthSessionManager
    private let session: URLSession
    private let schedule: PollingSchedule
    private let entitlementProvider: () async -> String?

    /// Uploads are capped so requests stay small and fast.
    static let uploadLongEdge = 1536

    init(
        config: BackendConfiguration,
        auth: AuthSessionManager,
        session: URLSession = .shared,
        schedule: PollingSchedule = .standard,
        entitlementProvider: @escaping () async -> String?
    ) {
        self.config = config
        self.auth = auth
        self.session = session
        self.schedule = schedule
        self.entitlementProvider = entitlementProvider
    }

    // MARK: Jobs

    func perform(_ job: AIJob) async throws -> AIJobResult {
        let body = try Self.makeRequestBody(for: job)
        try body.validate()

        let submitted: GenerationResponse
        do {
            submitted = try await submit(body)
        } catch AIServiceError.unauthorized {
            // Token may have been revoked server-side; retry once with a fresh session.
            await auth.invalidate()
            submitted = try await submit(body)
        }
        let finished = try await waitUntilFinished(submitted)

        var images: [UIImage] = []
        for output in finished.outputs {
            if let image = try await loadImage(output) {
                images.append(image)
            }
        }
        guard !images.isEmpty else { throw AIServiceError.invalidResponse }
        return AIJobResult(images: images, creditsRemaining: finished.creditsRemaining, requestID: finished.jobID)
    }

    private func submit(_ body: GenerationRequest) async throws -> GenerationResponse {
        let token = try await auth.validAccessToken()
        let jws = await entitlementProvider()
        let request = try RequestFactory.generation(body, config: config, accessToken: token, entitlementJWS: jws)
        return try await decodeJob(request)
    }

    private func waitUntilFinished(_ initial: GenerationResponse) async throws -> GenerationResponse {
        var response = initial
        let started = Date()
        var attempt = 0
        while !response.isFinished {
            guard let jobID = response.jobID else { throw AIServiceError.invalidResponse }
            guard Date().timeIntervalSince(started) < schedule.timeout else {
                cancelInBackground(jobID: jobID)
                throw AIServiceError.server(code: "timeout", message: "This is taking longer than usual. Your credit was refunded — please try again.")
            }
            do {
                try await Task.sleep(for: .seconds(schedule.delay(forAttempt: attempt)))
            } catch {
                // The user cancelled: stop the job so its credit is released.
                cancelInBackground(jobID: jobID)
                throw CancellationError()
            }
            attempt += 1
            let token = try await auth.validAccessToken()
            response = try await decodeJob(RequestFactory.jobStatus(jobID: jobID, config: config, accessToken: token))
        }
        return response
    }

    private func decodeJob(_ request: URLRequest) async throws -> GenerationResponse {
        let (data, response) = try await load(request)
        let http = response as? HTTPURLResponse
        return try ResponseDecoder.decodeGeneration(
            data: data,
            statusCode: http?.statusCode ?? 0,
            retryAfter: http?.value(forHTTPHeaderField: "Retry-After")
        )
    }

    /// Fire-and-forget so it still runs when the calling task was cancelled.
    private func cancelInBackground(jobID: String) {
        let config = config
        let auth = auth
        let session = session
        Task.detached(priority: .utility) {
            guard let token = try? await auth.validAccessToken(),
                  let request = try? RequestFactory.cancelJob(jobID: jobID, config: config, accessToken: token) else { return }
            _ = try? await session.data(for: request)
        }
    }

    // MARK: Account & credits

    /// Current server-side balance.
    func fetchBalance() async throws -> Int {
        let token = try await auth.validAccessToken()
        let jws = await entitlementProvider()
        let (data, response) = try await load(RequestFactory.balance(config: config, accessToken: token, entitlementJWS: jws))
        return try ResponseDecoder.decodeBalance(data: data, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Sends a consumable's signed transaction; returns the new balance.
    func redeemCreditPack(signedTransaction: String) async throws -> Int {
        let token = try await auth.validAccessToken()
        let request = try RequestFactory.redeemCreditPack(signedTransaction: signedTransaction, config: config, accessToken: token)
        let (data, response) = try await load(request)
        return try ResponseDecoder.decodeBalance(data: data, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    func deleteAccount() async throws {
        let token = try await auth.validAccessToken()
        let (data, response) = try await load(RequestFactory.deleteAccount(config: config, accessToken: token))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ResponseDecoder.error(from: data, statusCode: status)
        }
        await auth.signOut()
    }

    /// Supabase user id, used as the StoreKit `appAccountToken`.
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
                throw AIServiceError.invalidRequest("This photo couldn't be read.")
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
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AIServiceError.network("Check your internet connection and try again.")
        }
    }

    private func loadImage(_ output: GenerationResponse.Output) async throws -> UIImage? {
        if let base64 = output.base64, let data = Data(base64Encoded: base64) {
            return UIImage(data: data)
        }
        guard let url = output.url else { return nil }
        let (data, _) = try await load(URLRequest(url: url))
        return UIImage(data: data)
    }
}
