import UIKit
import Vision
import CoreImage
import AppCore

/// Features that run entirely on the iPhone: free, instant and private.
final class OnDeviceImageService: AIImageService {
    func perform(_ job: AIJob) async throws -> AIJobResult {
        guard let source = job.sourceImage else {
            throw AIServiceError.invalidRequest("Pick a photo first.")
        }
        switch job.operation {
        case .removeBackground:
            let cutout = try await Task.detached(priority: .userInitiated) {
                try Self.removeBackground(from: source)
            }.value
            return AIJobResult(images: [cutout], creditsRemaining: nil)
        default:
            throw AIServiceError.invalidRequest("\(job.operation.displayName) needs the cloud.")
        }
    }

    /// Subject lifting with Vision (iOS 17+). Returns a PNG-friendly image with
    /// a transparent background, same size as the input.
    static func removeBackground(from image: UIImage) throws -> UIImage {
        let normalized = ImageUtilities.normalized(image, maxLongEdge: 2048)
        guard let cgImage = normalized.cgImage else {
            throw AIServiceError.invalidRequest("This photo couldn't be read.")
        }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw AIServiceError.server(code: "vision_failed", message: "Background removal isn't available on this device.")
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

    /// Classic auto-enhance (exposure, color, sharpening) used for previews and
    /// as an offline fallback.
    static func autoEnhance(_ image: UIImage) -> UIImage {
        guard let input = ImageFilters.ciImage(image) else { return image }
        return ImageFilters.render(ImageFilters.autoEnhance(input), extent: input.extent) ?? image
    }

    /// Auto-enhance plus a gentle warm grade — the onboarding "aha" moment.
    static func quickGlow(_ image: UIImage) -> UIImage {
        guard let input = ImageFilters.ciImage(image) else { return image }
        let enhanced = ImageFilters.autoEnhance(input)
        let graded = ImageFilters.adjust(enhanced, with: AdjustmentSettings(
            brightness: 0.02, contrast: 1.06, saturation: 1.1, warmth: 0.18, sharpness: 0.25, vignette: 0.12
        ))
        return ImageFilters.render(graded, extent: input.extent) ?? image
    }

    static func adjust(_ image: UIImage, with settings: AdjustmentSettings) -> UIImage {
        guard let input = ImageFilters.ciImage(image) else { return image }
        return ImageFilters.render(ImageFilters.adjust(input, with: settings), extent: input.extent) ?? image
    }
}
