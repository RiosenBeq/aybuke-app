import UIKit
import Vision
import CoreImage
import AppCore

/// Features that run entirely on the iPhone: free, instant and private.
final class OnDeviceImageService: AIImageService {
    func perform(_ job: AIJob) async throws -> AIJobResult {
        guard let source = job.sourceImage else {
            throw AIServiceError.invalidRequest(String(localized: "Pick a photo first."))
        }
        switch job.operation {
        case .removeBackground:
            let cutout = try await Task.detached(priority: .userInitiated) {
                try Self.removeBackground(from: source)
            }.value
            return AIJobResult(images: [cutout], creditsRemaining: nil)
        default:
            throw AIServiceError.invalidRequest(String(localized: "\(L10n.core(job.operation.displayName)) needs the cloud."))
        }
    }

    /// Subject lifting with Vision (iOS 17+). Returns a PNG-friendly image with
    /// a transparent background, same size as the input.
    static func removeBackground(from image: UIImage) throws -> UIImage {
        let normalized = ImageUtilities.normalized(image, maxLongEdge: 2048)
        guard let cgImage = normalized.cgImage else {
            throw AIServiceError.invalidRequest(String(localized: "This photo couldn't be read."))
        }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw AIServiceError.server(code: "vision_failed", message: String(localized: "Background removal isn't available on this device."))
        }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw AIServiceError.noSubjectFound
        }
        let buffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: false
        )
        guard let output = ImageFilters.render(CIImage(cvPixelBuffer: buffer)) else {
            throw AIServiceError.invalidResponse
        }
        return output
    }

    static func adjust(_ image: UIImage, with settings: AdjustmentSettings) -> UIImage {
        guard let input = ImageFilters.ciImage(image) else { return image }
        return ImageFilters.render(ImageFilters.adjust(input, with: settings), extent: input.extent) ?? image
    }
}
