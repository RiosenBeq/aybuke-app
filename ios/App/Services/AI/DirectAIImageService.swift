import UIKit
import AppCore

/// DEBUG-only developer mode: calls xAI, fal.ai, OpenAI or Google Gemini directly
/// with the key from `ios/Config/Secrets.xcconfig`, so a key can be tried in
/// the simulator before the backend is deployed. Credits stay local. Release
/// builds never use this — the backend holds provider keys in production.
final class DirectAIImageService: AIImageService {
    private let config: DirectAIConfiguration
    private let session: URLSession
    private let schedule: PollingSchedule
    private let isPro: () async -> Bool

    init(
        config: DirectAIConfiguration,
        session: URLSession = .shared,
        schedule: PollingSchedule = .standard,
        isPro: @escaping () async -> Bool
    ) {
        self.config = config
        self.session = session
        self.schedule = schedule
        self.isPro = isPro
    }

    func perform(_ job: AIJob) async throws -> AIJobResult {
        let input = try await makeInput(for: job)
        let images: [UIImage]
        switch config.provider {
        case .xai:
            let (data, response) = try await load(XAIImagesAPI.request(input, config: config))
            images = try XAIImagesAPI.decode(data: data, statusCode: response.statusCode).compactMap { ImageUtilities.decodedImage(from: $0, maxPixel: 4096) }
        case .fal:
            images = try await runFal(input)
        case .openai:
            let (data, response) = try await load(OpenAIImagesAPI.request(input, config: config))
            images = try OpenAIImagesAPI.decode(data: data, statusCode: response.statusCode).compactMap { ImageUtilities.decodedImage(from: $0, maxPixel: 4096) }
        case .gemini:
            images = try await withThrowingTaskGroup(of: [Data].self) { group in
                for _ in 0..<max(1, input.numOutputs) {
                    group.addTask {
                        let (data, response) = try await self.load(GeminiImageAPI.request(input, config: self.config))
                        return try GeminiImageAPI.decode(data: data, statusCode: response.statusCode)
                    }
                }
                var all: [UIImage] = []
                for try await batch in group {
                    all += batch.compactMap { ImageUtilities.decodedImage(from: $0, maxPixel: 4096) }
                }
                return all
            }
        }
        guard !images.isEmpty else { throw AIServiceError.invalidResponse }
        return AIJobResult(images: images, creditsRemaining: nil, requestID: "direct-\(UUID().uuidString)")
    }

    // MARK: Input

    private func makeInput(for job: AIJob) async throws -> DirectAIInput {
        var input = DirectAIInput(
            operation: job.operation,
            prompt: prompt(for: job),
            aspectRatio: job.operation == .textToImage ? job.aspectRatio : nil,
            numOutputs: job.numOutputs,
            isPro: await isPro()
        )
        if let source = job.sourceImage {
            guard let jpeg = ImageUtilities.jpegData(source, maxLongEdge: RemoteAIImageService.uploadLongEdge, quality: 0.9) else {
                throw AIServiceError.invalidRequest(String(localized: "This photo couldn't be read."))
            }
            input.image = jpeg
        }
        if let mask = job.mask, let source = job.sourceImage {
            input.mask = Self.maskData(mask, matching: source, format: config.provider.maskFormat)
        }
        // Same checks as the backend contract (photo, prompt, mask, output count).
        try GenerationRequest(
            operation: job.operation, prompt: input.prompt, templateID: job.template?.id,
            numOutputs: job.numOutputs, image: input.image == nil ? nil : "jpeg", mask: input.mask == nil ? nil : "png"
        ).validate()
        return input
    }

    private func prompt(for job: AIJob) -> String {
        switch job.operation {
        case .textToImage:
            return PromptBuilder.textToImagePrompt(job.prompt ?? "", style: job.style ?? StyleCatalog.auto)
        case .magicEdit:
            return PromptBuilder.editInstruction(job.prompt ?? "")
        case .restyle:
            return job.template?.prompt ?? PromptBuilder.sanitize(job.prompt ?? "")
        case .enhance:
            return (job.enhanceMode ?? .unblur).prompt
        case .eraseObject:
            switch config.provider {
            case .xai: return DirectAIPrompts.eraseWithMaskImages
            case .gemini: return DirectAIPrompts.eraseWithMaskImage
            case .fal, .openai: return DirectAIPrompts.eraseWithMask
            }
        case .removeBackground:
            return ""
        }
    }

    /// Scales the brush mask (white = remove) to the uploaded photo's size and
    /// converts it to the provider's convention: OpenAI edits where the mask
    /// is fully transparent, fal and Gemini take white-on-black.
    static func maskData(_ mask: UIImage, matching source: UIImage, format: DirectAIProvider.MaskFormat) -> Data? {
        let target = ImageSizing.fit(ImageUtilities.pixelSize(of: source), maxLongEdge: RemoteAIImageService.uploadLongEdge)
        let width = target.width
        let height = target.height
        guard let cgMask = mask.cgImage,
              let gray = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else { return nil }
        gray.interpolationQuality = .high
        gray.draw(cgMask, in: CGRect(x: 0, y: 0, width: width, height: height))

        switch format {
        case .whiteAreasEdit:
            return gray.makeImage().flatMap { UIImage(cgImage: $0).pngData() }
        case .transparentAreasEdit:
            guard let source = gray.data?.assumingMemoryBound(to: UInt8.self),
                  let rgba = CGContext(
                      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ),
                  let output = rgba.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
            for y in 0..<height {
                for x in 0..<width {
                    let value = source[y * gray.bytesPerRow + x]
                    let pixel = y * rgba.bytesPerRow + x * 4
                    // Black, with alpha 0 where the user brushed.
                    output[pixel] = 0
                    output[pixel + 1] = 0
                    output[pixel + 2] = 0
                    output[pixel + 3] = 255 &- value
                }
            }
            return rgba.makeImage().flatMap { UIImage(cgImage: $0).pngData() }
        }
    }

    // MARK: fal.ai queue

    private func runFal(_ input: DirectAIInput) async throws -> [UIImage] {
        let (submitData, submitResponse) = try await load(FalDirectAPI.submitRequest(input, config: config))
        let queued = try FalDirectAPI.decodeQueued(data: submitData, statusCode: submitResponse.statusCode)
        let started = Date()
        var attempt = 0
        while true {
            do {
                try await Task.sleep(for: .seconds(schedule.delay(forAttempt: attempt)))
            } catch {
                cancelFal(queued)
                throw CancellationError()
            }
            attempt += 1
            let (statusData, _) = try await load(FalDirectAPI.authorized(queued.statusURL, key: config.apiKey))
            if FalDirectAPI.decodeStatus(data: statusData) == "COMPLETED" { break }
            guard Date().timeIntervalSince(started) < schedule.timeout else {
                cancelFal(queued)
                throw AIServiceError.server(code: "timeout", message: String(localized: "This is taking longer than usual. Please try again."))
            }
        }
        let (resultData, resultResponse) = try await load(FalDirectAPI.authorized(queued.responseURL, key: config.apiKey))
        var images: [UIImage] = []
        for url in try FalDirectAPI.decodeResult(data: resultData, statusCode: resultResponse.statusCode) {
            let (data, _) = try await load(URLRequest(url: url))
            if let image = ImageUtilities.decodedImage(from: data, maxPixel: 4096) { images.append(image) }
        }
        return images
    }

    private func cancelFal(_ queued: FalQueuedRequest) {
        guard let url = queued.cancelURL else { return }
        let request = FalDirectAPI.authorized(url, key: config.apiKey, method: "PUT")
        let session = session
        Task.detached(priority: .utility) { _ = try? await session.data(for: request) }
    }

    // MARK: Networking

    private func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }
            return (data, http)
        } catch {
            throw NetworkFailure.map(error)
        }
    }
}
