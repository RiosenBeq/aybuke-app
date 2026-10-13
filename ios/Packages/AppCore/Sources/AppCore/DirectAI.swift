import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Developer mode: the app calls an AI provider directly with an API key from
// the git-ignored `ios/Config/Secrets.xcconfig` (DEBUG builds only). It exists
// so a key can be tried in the simulator before the backend is deployed —
// shipping builds always go through the backend, which keeps keys off devices.
// This file builds the provider requests and decodes their responses; the
// iOS layer (DirectAIImageService) does the networking and image encoding.

// MARK: - Configuration

public enum DirectAIProvider: String, CaseIterable, Sendable {
    case fal
    case openai
    case gemini

    public var displayName: String {
        switch self {
        case .fal: return "fal.ai"
        case .openai: return "OpenAI"
        case .gemini: return "Google Gemini"
        }
    }

    /// Named on the AI consent screen as the party that processes photos.
    public var processorName: String {
        switch self {
        case .fal: return "fal.ai and the model providers it runs, such as Google"
        case .openai: return "OpenAI"
        case .gemini: return "Google (Gemini API)"
        }
    }

    public var defaultImageModel: String {
        switch self {
        case .fal: return FalDirectAPI.defaultEndpoints[.textToImage] ?? ""
        case .openai: return "gpt-image-1"
        case .gemini: return "gemini-2.5-flash-image"
        }
    }

    public var defaultEditModel: String {
        switch self {
        case .fal: return FalDirectAPI.defaultEndpoints[.magicEdit] ?? ""
        case .openai: return "gpt-image-1"
        case .gemini: return "gemini-2.5-flash-image"
        }
    }

    /// How the erase mask must be encoded for this provider.
    public var maskFormat: MaskFormat {
        self == .openai ? .transparentAreasEdit : .whiteAreasEdit
    }

    public enum MaskFormat: Sendable {
        /// Opaque PNG: white = remove, black = keep (fal, Gemini).
        case whiteAreasEdit
        /// RGBA PNG: fully transparent = edit (OpenAI Images API).
        case transparentAreasEdit
    }
}

public struct DirectAIConfiguration: Equatable, Sendable {
    public var provider: DirectAIProvider
    public var apiKey: String
    public var imageModel: String
    public var editModel: String

    /// `nil` unless both the provider and a plausible key are set (empty or
    /// unexpanded `$(…)` build variables mean "not configured").
    public init?(provider: String, apiKey: String, imageModel: String? = nil, editModel: String? = nil) {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let kind = DirectAIProvider(rawValue: provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()),
              !key.isEmpty, !key.contains("$(") else { return nil }
        self.provider = kind
        self.apiKey = key
        self.imageModel = Self.nonEmpty(imageModel) ?? kind.defaultImageModel
        self.editModel = Self.nonEmpty(editModel) ?? kind.defaultEditModel
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty, !value.contains("$(") else {
            return nil
        }
        return value
    }
}

/// One provider-neutral request. `prompt` is final (styles, identity clauses
/// and tool instructions already applied, see `DirectAIPrompts`).
public struct DirectAIInput: Equatable, Sendable {
    public var operation: AIOperation
    public var prompt: String
    public var aspectRatio: AspectRatio?
    public var numOutputs: Int
    /// Source photo as JPEG.
    public var image: Data?
    /// Erase mask as PNG, already in the provider's `maskFormat`.
    public var mask: Data?
    public var isPro: Bool

    public init(
        operation: AIOperation, prompt: String, aspectRatio: AspectRatio? = nil, numOutputs: Int = 1,
        image: Data? = nil, mask: Data? = nil, isPro: Bool = false
    ) {
        self.operation = operation
        self.prompt = prompt
        self.aspectRatio = aspectRatio
        self.numOutputs = numOutputs
        self.image = image
        self.mask = mask
        self.isPro = isPro
    }
}

/// Instructions for tools that general image-edit models don't have as a
/// dedicated endpoint.
public enum DirectAIPrompts {
    public static let enhance = "Enhance this photo: make it sharper and more detailed, reduce blur and noise, restore faces naturally and gently improve the lighting. Keep the composition, colors, every person and their identity exactly the same."

    /// OpenAI applies the edit only inside the transparent mask area.
    public static let eraseWithMask = "Remove the object in the masked area and fill it naturally so it blends with the surroundings. Keep everything else unchanged."

    /// Gemini receives the mask as a second image.
    public static let eraseWithMaskImage = "The second image is a mask. Remove everything covered by its white area from the first image and fill that area naturally so it matches the surroundings. Keep everything else in the first image unchanged and return only the edited first image."
}

// MARK: - Errors

public enum DirectAIErrors {
    static let blockedPattern = ["safety", "nsfw", "content policy", "content_policy", "moderation", "flagged", "prohibited"]

    static func looksBlocked(_ text: String) -> Bool {
        let lower = text.lowercased()
        return blockedPattern.contains { lower.contains($0) }
    }

    /// Maps a provider HTTP error to a user-facing error.
    static func map(status: Int, message: String?, code: String?, provider: DirectAIProvider) -> AIServiceError {
        let detail = [code, message].compactMap { $0 }.joined(separator: " ")
        if looksBlocked(detail) {
            return .contentBlocked("This request was blocked by the AI provider's safety filters. Try a different idea.")
        }
        switch status {
        case 401, 403:
            return .server(code: "provider_auth", message: "\(provider.displayName) rejected the API key. Check ios/Config/Secrets.xcconfig.")
        case 402:
            return .server(code: "provider_billing", message: "Your \(provider.displayName) account needs billing or credit to run this.")
        case 429:
            if detail.lowercased().contains("quota") {
                return .server(code: "provider_quota", message: "Your \(provider.displayName) quota is used up. Check your plan or billing.")
            }
            return .rateLimited(retryAfter: nil)
        case 500...:
            return .server(code: "provider_unavailable", message: "\(provider.displayName) is busy. Please try again.")
        default:
            let text = message.map { "\(provider.displayName): \($0)" } ?? "\(provider.displayName) couldn't process this request."
            return .server(code: code ?? "provider_\(status)", message: text)
        }
    }
}

// MARK: - fal.ai (queue API; same models and inputs as the backend)

public struct FalQueuedRequest: Decodable, Equatable, Sendable {
    public var requestID: String
    public var statusURL: URL
    public var responseURL: URL
    public var cancelURL: URL?

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case statusURL = "status_url"
        case responseURL = "response_url"
        case cancelURL = "cancel_url"
    }
}

public enum FalDirectAPI {
    /// Mirrors `ENDPOINTS` in backend/supabase/functions/_shared/fal.ts.
    public static let defaultEndpoints: [AIOperation: String] = [
        .textToImage: "fal-ai/nano-banana-2",
        .magicEdit: "fal-ai/nano-banana-2/edit",
        .restyle: "fal-ai/nano-banana-2/edit",
        .enhance: "fal-ai/seedvr/upscale/image",
        .removeBackground: "fal-ai/birefnet/v2",
        .eraseObject: "fal-ai/object-removal/mask",
    ]

    public static func endpoint(for operation: AIOperation, config: DirectAIConfiguration) -> String {
        switch operation {
        case .textToImage: return config.imageModel
        case .magicEdit, .restyle: return config.editModel
        default: return defaultEndpoints[operation] ?? config.editModel
        }
    }

    /// Mirrors `buildFalInput` in the backend.
    public static func input(for input: DirectAIInput) -> [String: Any] {
        let resolution = input.isPro ? "2K" : "1K"
        let image = input.image.map { GenerationRequest.dataURI($0, mimeType: "image/jpeg") }
        switch input.operation {
        case .textToImage:
            return [
                "prompt": input.prompt,
                "aspect_ratio": (input.aspectRatio ?? .square).rawValue,
                "resolution": resolution,
                "num_images": input.numOutputs,
                "output_format": "jpeg",
                "safety_tolerance": "2",
                "limit_generations": true,
            ]
        case .magicEdit, .restyle:
            return [
                "prompt": input.prompt,
                "image_urls": [image ?? ""],
                "aspect_ratio": "auto",
                "resolution": resolution,
                "num_images": 1,
                "output_format": "jpeg",
                "safety_tolerance": "2",
            ]
        case .enhance:
            return ["image_url": image ?? "", "upscale_mode": "factor", "upscale_factor": 2]
        case .removeBackground:
            return [
                "image_url": image ?? "",
                "model": "General Use (Heavy)",
                "operating_resolution": "2048x2048",
                "output_format": "png",
                "refine_foreground": true,
            ]
        case .eraseObject:
            return [
                "image_url": image ?? "",
                "mask_url": input.mask.map { GenerationRequest.dataURI($0, mimeType: "image/png") } ?? "",
                "model": "best_quality",
                "mask_expansion": 15,
            ]
        }
    }

    public static func submitRequest(_ input: DirectAIInput, config: DirectAIConfiguration) throws -> URLRequest {
        let endpoint = endpoint(for: input.operation, config: config)
        guard let url = URL(string: "https://queue.fal.run/\(endpoint)") else { throw AIServiceError.notConfigured }
        var request = authorized(url, key: config.apiKey)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.input(for: input), options: [.sortedKeys])
        return request
    }

    /// Status, result and cancel calls on the URLs fal returned.
    public static func authorized(_ url: URL, key: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.setValue("Key \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Keep no request history at fal; outputs expire from its CDN after an hour.
        request.setValue("0", forHTTPHeaderField: "X-Fal-Store-IO")
        request.setValue(#"{"expiration_duration_seconds":3600}"#, forHTTPHeaderField: "X-Fal-Object-Lifecycle-Preference")
        return request
    }

    public static func decodeQueued(data: Data, statusCode: Int) throws -> FalQueuedRequest {
        guard (200..<300).contains(statusCode) else { throw error(data: data, statusCode: statusCode) }
        guard let queued = try? JSONDecoder().decode(FalQueuedRequest.self, from: data) else {
            throw AIServiceError.invalidResponse
        }
        return queued
    }

    /// "IN_QUEUE", "IN_PROGRESS" or "COMPLETED"; `nil` if unreadable.
    public static func decodeStatus(data: Data) -> String? {
        struct Status: Decodable { let status: String? }
        return (try? JSONDecoder().decode(Status.self, from: data))?.status
    }

    /// Output image URLs of a completed request (`images: [...]` or `image: {...}`).
    public static func decodeResult(data: Data, statusCode: Int) throws -> [URL] {
        guard (200..<300).contains(statusCode) else { throw error(data: data, statusCode: statusCode) }
        struct Image: Decodable { let url: String? }
        struct Payload: Decodable {
            let images: [Image]?
            let image: Image?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { throw AIServiceError.invalidResponse }
        let urls = (payload.images ?? payload.image.map { [$0] } ?? []).compactMap { $0.url.flatMap(URL.init(string:)) }
        guard !urls.isEmpty else { throw AIServiceError.invalidResponse }
        return urls
    }

    static func error(data: Data, statusCode: Int) -> AIServiceError {
        let text = String(data: data, encoding: .utf8) ?? ""
        struct Body: Decodable { let detail: DetailValue? }
        enum DetailValue: Decodable {
            case text(String)
            case items([Item])
            struct Item: Decodable { let msg: String? }
            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let text = try? container.decode(String.self) { self = .text(text) } else { self = .items(try container.decode([Item].self)) }
            }
        }
        var message: String?
        if let body = try? JSONDecoder().decode(Body.self, from: data) {
            switch body.detail {
            case .text(let value): message = value
            case .items(let items): message = items.compactMap(\.msg).first
            case nil: message = nil
            }
        }
        if DirectAIErrors.looksBlocked(text) {
            return .contentBlocked("This request was blocked by the AI provider's safety filters. Try a different idea.")
        }
        return DirectAIErrors.map(status: statusCode, message: message, code: nil, provider: .fal)
    }
}

// MARK: - OpenAI Images API

public enum OpenAIImagesAPI {
    public static let baseURL = URL(string: "https://api.openai.com/v1/images")!

    /// gpt-image sizes: square, portrait (2:3) or landscape (3:2).
    public static func size(for ratio: AspectRatio?) -> String {
        switch ratio {
        case .square?: return "1024x1024"
        case .portrait?, .story?: return "1024x1536"
        case .landscape?, .wide?: return "1536x1024"
        case nil: return "auto"
        }
    }

    public static func request(_ input: DirectAIInput, config: DirectAIConfiguration, boundary: String = "glowlit-\(UUID().uuidString)") throws -> URLRequest {
        let quality = input.isPro ? "high" : "medium"
        if input.operation == .textToImage {
            var request = URLRequest(url: baseURL.appendingPathComponent("generations"))
            request.httpMethod = "POST"
            request.timeoutInterval = 180
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "model": config.imageModel,
                "prompt": input.prompt,
                "n": input.numOutputs,
                "size": size(for: input.aspectRatio),
                "quality": quality,
                "output_format": "jpeg",
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
            return request
        }

        guard let image = input.image else { throw AIServiceError.invalidRequest("Pick a photo first.") }
        var form = MultipartForm(boundary: boundary)
        form.addField("model", config.editModel)
        form.addField("prompt", input.prompt)
        form.addField("n", "1")
        form.addField("size", "auto")
        form.addField("quality", quality)
        form.addField("output_format", "jpeg")
        if config.editModel == "gpt-image-1", input.operation == .magicEdit || input.operation == .restyle {
            // Keeps faces closer to the input (Likeness Lock).
            form.addField("input_fidelity", "high")
        }
        form.addFile("image", filename: "photo.jpg", mimeType: "image/jpeg", data: image)
        if input.operation == .eraseObject {
            guard let mask = input.mask else { throw AIServiceError.invalidRequest("Brush over the area you want to erase.") }
            form.addFile("mask", filename: "mask.png", mimeType: "image/png", data: mask)
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("edits"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finalized()
        return request
    }

    /// Base64 images from `data[].b64_json`.
    public static func decode(data: Data, statusCode: Int) throws -> [Data] {
        guard (200..<300).contains(statusCode) else {
            struct Envelope: Decodable {
                struct Body: Decodable { let message: String?; let code: String?; let type: String? }
                let error: Body
            }
            let body = try? JSONDecoder().decode(Envelope.self, from: data).error
            throw DirectAIErrors.map(status: statusCode, message: body?.message, code: body?.code ?? body?.type, provider: .openai)
        }
        struct Payload: Decodable {
            struct Item: Decodable { let b64_json: String? }
            let data: [Item]?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { throw AIServiceError.invalidResponse }
        let images = (payload.data ?? []).compactMap { $0.b64_json.flatMap { Data(base64Encoded: $0) } }
        guard !images.isEmpty else { throw AIServiceError.invalidResponse }
        return images
    }
}

// MARK: - Google Gemini API (generateContent with image output)

public enum GeminiImageAPI {
    public static let baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!

    /// One request per output image (Gemini returns one image per call).
    public static func request(_ input: DirectAIInput, config: DirectAIConfiguration) throws -> URLRequest {
        let model = input.operation == .textToImage ? config.imageModel : config.editModel
        var request = URLRequest(url: baseURL.appendingPathComponent("\(model):generateContent"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue(config.apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var parts: [[String: Any]] = [["text": input.prompt]]
        if input.operation != .textToImage {
            guard let image = input.image else { throw AIServiceError.invalidRequest("Pick a photo first.") }
            parts.append(["inline_data": ["mime_type": "image/jpeg", "data": image.base64EncodedString()]])
        }
        if input.operation == .eraseObject {
            guard let mask = input.mask else { throw AIServiceError.invalidRequest("Brush over the area you want to erase.") }
            parts.append(["inline_data": ["mime_type": "image/png", "data": mask.base64EncodedString()]])
        }

        var generationConfig: [String: Any] = ["responseModalities": ["IMAGE"]]
        if input.operation == .textToImage, let ratio = input.aspectRatio {
            generationConfig["imageConfig"] = ["aspectRatio": ratio.rawValue]
        }
        let strict = "BLOCK_LOW_AND_ABOVE"
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": generationConfig,
            "safetySettings": [
                ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": strict],
                ["category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"],
                ["category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_MEDIUM_AND_ABOVE"],
                ["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    static let blockedFinishReasons: Set<String> = [
        "SAFETY", "PROHIBITED_CONTENT", "IMAGE_SAFETY", "IMAGE_PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "RECITATION",
    ]

    /// Image bytes from `candidates[].content.parts[].inlineData`.
    public static func decode(data: Data, statusCode: Int) throws -> [Data] {
        guard (200..<300).contains(statusCode) else {
            struct Envelope: Decodable {
                struct Body: Decodable { let message: String?; let status: String? }
                let error: Body
            }
            let body = try? JSONDecoder().decode(Envelope.self, from: data).error
            throw DirectAIErrors.map(status: statusCode, message: body?.message, code: body?.status, provider: .gemini)
        }
        struct InlineData: Decodable {
            let mimeType: String?
            let data: String?
            enum CodingKeys: String, CodingKey { case mimeType, mime_type, data }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
                    ?? container.decodeIfPresent(String.self, forKey: .mime_type)
                data = try container.decodeIfPresent(String.self, forKey: .data)
            }
        }
        struct Part: Decodable {
            let inlineData: InlineData?
            enum CodingKeys: String, CodingKey { case inlineData, inline_data }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                inlineData = try container.decodeIfPresent(InlineData.self, forKey: .inlineData)
                    ?? container.decodeIfPresent(InlineData.self, forKey: .inline_data)
            }
        }
        struct Content: Decodable { let parts: [Part]? }
        struct Candidate: Decodable { let content: Content?; let finishReason: String? }
        struct Feedback: Decodable { let blockReason: String? }
        struct Payload: Decodable { let candidates: [Candidate]?; let promptFeedback: Feedback? }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { throw AIServiceError.invalidResponse }
        let images = (payload.candidates ?? [])
            .flatMap { $0.content?.parts ?? [] }
            .compactMap(\.inlineData)
            .filter { ($0.mimeType ?? "image/").hasPrefix("image/") }
            .compactMap { $0.data.flatMap { Data(base64Encoded: $0) } }
        if !images.isEmpty { return images }

        let reasons = (payload.candidates ?? []).compactMap(\.finishReason) + [payload.promptFeedback?.blockReason].compactMap { $0 }
        if payload.promptFeedback?.blockReason != nil || reasons.contains(where: blockedFinishReasons.contains) {
            throw AIServiceError.contentBlocked("This request was blocked by the AI provider's safety filters. Try a different idea.")
        }
        throw AIServiceError.server(code: "no_image", message: "Google Gemini didn't return an image. Try rephrasing your request.")
    }
}

// MARK: - Multipart

struct MultipartForm {
    let boundary: String
    private var body = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    mutating func addField(_ name: String, _ value: String) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
    }

    mutating func addFile(_ name: String, filename: String, mimeType: String, data: Data) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    func finalized() -> Data {
        body + Data("--\(boundary)--\r\n".utf8)
    }
}
