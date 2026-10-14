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
    /// Makeup Studio's look, sent as a Magic Edit whose prompt the app wrote.
    var makeup: MakeupRecipe?

    /// Short human-readable title used in the library.
    var title: String {
        if let template { return template.title }
        // The look's name, never the long instruction behind it.
        if let makeup {
            return MakeupStudio.preset(matching: makeup).map { L10n.core($0.name) } ?? String(localized: "Makeup Studio")
        }
        if let prompt, operation == .textToImage || operation == .magicEdit {
            return PromptBuilder.sanitize(prompt)
        }
        return operation.displayName
    }

    /// Catalog text for the Lock Screen and the Dynamic Island, never a prompt.
    var activityTitle: String {
        makeup != nil ? title : L10n.core(template?.title ?? operation.displayName)
    }

    var activitySymbol: String {
        makeup != nil ? EditorTool.makeup.symbolName : template?.symbolName ?? operation.symbolName
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
