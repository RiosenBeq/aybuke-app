import XCTest
@testable import AppCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class DirectAITests: XCTestCase {
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
    private let png = Data([0x89, 0x50, 0x4E, 0x47])

    private func config(_ provider: String, image: String? = nil, edit: String? = nil) throws -> DirectAIConfiguration {
        try XCTUnwrap(DirectAIConfiguration(provider: provider, apiKey: "test-key", imageModel: image, editModel: edit))
    }

    private func json(_ request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    // MARK: Configuration

    func testConfigurationNeedsProviderAndKey() {
        XCTAssertNil(DirectAIConfiguration(provider: "", apiKey: "key"))
        XCTAssertNil(DirectAIConfiguration(provider: "openai", apiKey: "  "))
        XCTAssertNil(DirectAIConfiguration(provider: "openai", apiKey: "$(GL_AI_API_KEY)"))
        XCTAssertNil(DirectAIConfiguration(provider: "midjourney", apiKey: "key"))
        let config = DirectAIConfiguration(provider: " OpenAI ", apiKey: " sk-test ", imageModel: "", editModel: "$(GL_AI_EDIT_MODEL)")
        XCTAssertEqual(config?.provider, .openai)
        XCTAssertEqual(config?.apiKey, "sk-test")
        XCTAssertEqual(config?.imageModel, "gpt-image-1")
        XCTAssertEqual(config?.editModel, "gpt-image-1")
    }

    func testModelOverrides() throws {
        let config = try config("gemini", image: "gemini-3-pro-image", edit: "gemini-3-pro-image")
        XCTAssertEqual(config.imageModel, "gemini-3-pro-image")
        XCTAssertEqual(config.editModel, "gemini-3-pro-image")
    }

    // MARK: fal.ai

    func testFalUsesTheBackendModels() throws {
        let config = try config("fal")
        XCTAssertEqual(FalDirectAPI.endpoint(for: .textToImage, config: config), "fal-ai/nano-banana-2")
        XCTAssertEqual(FalDirectAPI.endpoint(for: .restyle, config: config), "fal-ai/nano-banana-2/edit")
        XCTAssertEqual(FalDirectAPI.endpoint(for: .enhance, config: config), "fal-ai/seedvr/upscale/image")
        XCTAssertEqual(FalDirectAPI.endpoint(for: .eraseObject, config: config), "fal-ai/object-removal/mask")
    }

    func testFalSubmitRequest() throws {
        let input = DirectAIInput(operation: .magicEdit, prompt: "Golden hour light.", image: jpeg, isPro: true)
        let request = try FalDirectAPI.submitRequest(input, config: config("fal"))
        XCTAssertEqual(request.url?.absoluteString, "https://queue.fal.run/fal-ai/nano-banana-2/edit")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Key test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Fal-Store-IO"), "0")
        let body = try json(request)
        XCTAssertEqual(body["prompt"] as? String, "Golden hour light.")
        XCTAssertEqual(body["resolution"] as? String, "2K")
        XCTAssertEqual((body["image_urls"] as? [String])?.first, "data:image/jpeg;base64,/9j/4A==")
    }

    func testFalTextToImageInput() {
        let input = DirectAIInput(operation: .textToImage, prompt: "A fox", aspectRatio: .story, numOutputs: 3)
        let body = FalDirectAPI.input(for: input)
        XCTAssertEqual(body["aspect_ratio"] as? String, "9:16")
        XCTAssertEqual(body["num_images"] as? Int, 3)
        XCTAssertEqual(body["resolution"] as? String, "1K")
    }

    func testFalDecodesQueueAndResults() throws {
        let queued = try FalDirectAPI.decodeQueued(data: Data("""
        {"request_id":"r1","status_url":"https://queue.fal.run/x/requests/r1/status","response_url":"https://queue.fal.run/x/requests/r1","cancel_url":"https://queue.fal.run/x/requests/r1/cancel"}
        """.utf8), statusCode: 200)
        XCTAssertEqual(queued.requestID, "r1")
        XCTAssertEqual(FalDirectAPI.decodeStatus(data: Data(#"{"status":"IN_PROGRESS"}"#.utf8)), "IN_PROGRESS")

        let many = try FalDirectAPI.decodeResult(data: Data(#"{"images":[{"url":"https://cdn/a.jpg"},{"url":"https://cdn/b.jpg"}]}"#.utf8), statusCode: 200)
        XCTAssertEqual(many.map(\.absoluteString), ["https://cdn/a.jpg", "https://cdn/b.jpg"])
        let single = try FalDirectAPI.decodeResult(data: Data(#"{"image":{"url":"https://cdn/c.png"}}"#.utf8), statusCode: 200)
        XCTAssertEqual(single.map(\.absoluteString), ["https://cdn/c.png"])
    }

    func testFalErrors() {
        XCTAssertThrowsError(try FalDirectAPI.decodeResult(data: Data(#"{"detail":"Content flagged as NSFW"}"#.utf8), statusCode: 422)) { error in
            guard case AIServiceError.contentBlocked = error else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try FalDirectAPI.decodeQueued(data: Data(#"{"detail":"Invalid key"}"#.utf8), statusCode: 401)) { error in
            XCTAssertEqual(error as? AIServiceError, .server(code: "provider_auth", message: "fal.ai rejected the API key. Check ios/Config/Secrets.xcconfig."))
        }
    }

    // MARK: OpenAI

    func testOpenAIGenerationRequest() throws {
        let input = DirectAIInput(operation: .textToImage, prompt: "A fox", aspectRatio: .portrait, numOutputs: 2)
        let request = try OpenAIImagesAPI.request(input, config: config("openai"))
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/images/generations")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        let body = try json(request)
        XCTAssertEqual(body["model"] as? String, "gpt-image-1")
        XCTAssertEqual(body["size"] as? String, "1024x1536")
        XCTAssertEqual(body["n"] as? Int, 2)
        XCTAssertEqual(body["quality"] as? String, "medium")
    }

    func testOpenAIEditIsMultipartWithMask() throws {
        let input = DirectAIInput(operation: .eraseObject, prompt: DirectAIPrompts.eraseWithMask, image: jpeg, mask: png)
        let request = try OpenAIImagesAPI.request(input, config: config("openai"), boundary: "B")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/images/edits")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "multipart/form-data; boundary=B")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"model\"\r\n\r\ngpt-image-1\r\n"))
        XCTAssertTrue(body.contains("name=\"image\"; filename=\"photo.jpg\""))
        XCTAssertTrue(body.contains("name=\"mask\"; filename=\"mask.png\""))
        XCTAssertFalse(body.contains("input_fidelity"), "Only identity-sensitive edits ask for high fidelity")
        XCTAssertTrue(body.hasSuffix("--B--\r\n"))
    }

    func testOpenAIRestyleAsksForHighInputFidelity() throws {
        let input = DirectAIInput(operation: .restyle, prompt: "Pro headshot", image: jpeg)
        let body = String(decoding: try XCTUnwrap(OpenAIImagesAPI.request(input, config: config("openai"), boundary: "B").httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"input_fidelity\"\r\n\r\nhigh\r\n"))
    }

    func testOpenAIDecoding() throws {
        let images = try OpenAIImagesAPI.decode(data: Data(#"{"data":[{"b64_json":"/9j/4A=="}]}"#.utf8), statusCode: 200)
        XCTAssertEqual(images, [jpeg])

        let blocked = Data(#"{"error":{"message":"Your request was rejected by the safety system.","type":"image_generation_user_error","code":"moderation_blocked"}}"#.utf8)
        XCTAssertThrowsError(try OpenAIImagesAPI.decode(data: blocked, statusCode: 400)) { error in
            guard case AIServiceError.contentBlocked = error else { return XCTFail("\(error)") }
        }
        let quota = Data(#"{"error":{"message":"You exceeded your current quota","type":"insufficient_quota","code":"insufficient_quota"}}"#.utf8)
        XCTAssertThrowsError(try OpenAIImagesAPI.decode(data: quota, statusCode: 429)) { error in
            guard case AIServiceError.server(let code, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(code, "provider_quota")
        }
    }

    // MARK: Gemini

    func testGeminiEditRequest() throws {
        let input = DirectAIInput(operation: .eraseObject, prompt: DirectAIPrompts.eraseWithMaskImage, image: jpeg, mask: png)
        let request = try GeminiImageAPI.request(input, config: config("gemini"))
        XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "test-key")
        let body = try json(request)
        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 3, "prompt, photo, mask")
        XCTAssertEqual((parts[1]["inline_data"] as? [String: String])?["mime_type"], "image/jpeg")
        XCTAssertEqual((parts[2]["inline_data"] as? [String: String])?["mime_type"], "image/png")
        let generation = try XCTUnwrap(body["generationConfig"] as? [String: Any])
        XCTAssertNil(generation["imageConfig"], "Edits keep the photo's own aspect ratio")
    }

    func testGeminiTextToImageSetsAspectRatio() throws {
        let input = DirectAIInput(operation: .textToImage, prompt: "A fox", aspectRatio: .wide)
        let body = try json(GeminiImageAPI.request(input, config: config("gemini")))
        let generation = try XCTUnwrap(body["generationConfig"] as? [String: Any])
        XCTAssertEqual((generation["imageConfig"] as? [String: String])?["aspectRatio"], "16:9")
        XCTAssertEqual(generation["responseModalities"] as? [String], ["IMAGE"])
    }

    func testGeminiDecoding() throws {
        let ok = Data(#"{"candidates":[{"content":{"parts":[{"text":"Here you go"},{"inlineData":{"mimeType":"image/png","data":"iVBORw=="}}]},"finishReason":"STOP"}]}"#.utf8)
        XCTAssertEqual(try GeminiImageAPI.decode(data: ok, statusCode: 200), [png])

        let blocked = Data(#"{"candidates":[{"finishReason":"IMAGE_SAFETY"}]}"#.utf8)
        XCTAssertThrowsError(try GeminiImageAPI.decode(data: blocked, statusCode: 200)) { error in
            guard case AIServiceError.contentBlocked = error else { return XCTFail("\(error)") }
        }
        let badKey = Data(#"{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT"}}"#.utf8)
        XCTAssertThrowsError(try GeminiImageAPI.decode(data: badKey, statusCode: 400)) { error in
            guard case AIServiceError.server(let code, let message) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(code, "INVALID_ARGUMENT")
            XCTAssertTrue(message.contains("API key not valid"))
        }
    }

    // MARK: Reports

    func testReportRequest() throws {
        let config = BackendConfiguration(baseURL: URL(string: "https://example.supabase.co")!, anonKey: "anon")
        let request = try RequestFactory.report(.mismatch, jobID: "job-1", config: config, accessToken: "jwt")
        XCTAssertEqual(request.url?.absoluteString, "https://example.supabase.co/functions/v1/report")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer jwt")
        let body = try json(request)
        XCTAssertEqual(body["reason"] as? String, "mismatch")
        XCTAssertEqual(body["job_id"] as? String, "job-1")
    }
}
