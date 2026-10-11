import UIKit
import AppCore

/// One unit of AI work requested by a screen.
struct AIJob {
    var operation: AIOperation
    var prompt: String?
    var style: ImageStyle?
    var template: PhotoTemplate?
    var aspectRatio: AspectRatio = .portrait
    var numOutputs = 1
    var sourceImage: UIImage?
    var mask: UIImage?
    /// Set when re-rolling a result for free (Likeness Lock).
    var retryOf: String?

    /// Short human-readable title used in the library.
    var title: String {
        if let template { return template.title }
        if let prompt, operation == .textToImage || operation == .magicEdit {
            return PromptBuilder.sanitize(prompt)
        }
        return operation.displayName
    }

    var isProOnly: Bool {
        (template?.isPro ?? false) || (style?.isPro ?? false) || numOutputs > 1
    }
}

struct AIJobResult {
    var images: [UIImage]
    /// Balance reported by the server, if any (source of truth for credits).
    var creditsRemaining: Int?
    /// Server request id, used for free retries and support.
    var requestID: String?
}

protocol AIImageService: AnyObject {
    func perform(_ job: AIJob) async throws -> AIJobResult
}

/// Sends cloud jobs to the backend (or the demo engine) and keeps
/// background removal on device.
final class AIServiceRouter: AIImageService {
    private let cloud: AIImageService
    private let onDevice: AIImageService

    init(cloud: AIImageService, onDevice: AIImageService) {
        self.cloud = cloud
        self.onDevice = onDevice
    }

    func perform(_ job: AIJob) async throws -> AIJobResult {
        if job.operation.runsOnDevice {
            return try await onDevice.perform(job)
        }
        return try await cloud.perform(job)
    }
}
