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

    /// Adjust's sliders, after Soft skin when an adult turned it up (`softSkin`:
    /// the photo's skin mask, any size, and the slider's value).
    static func adjust(_ image: UIImage, with settings: AdjustmentSettings, softSkin: (mask: CIImage, amount: Double)? = nil) -> UIImage {
        guard let input = ImageFilters.ciImage(image) else { return image }
        let extent = input.extent
        func softened(_ photo: CIImage) -> CIImage {
            guard let softSkin, let plan = SoftSkin.plan(amount: softSkin.amount, longEdge: Double(max(extent.width, extent.height))) else {
                return photo
            }
            return ImageFilters.softSkin(photo, mask: softSkin.mask, plan: plan)
        }
        guard ImageUtilities.hasAlpha(image) else {
            // A photo stays opaque (a JPEG when saved).
            let adjusted = ImageFilters.adjust(softened(input), with: settings).settingAlphaOne(in: extent)
            return ImageFilters.render(adjusted, extent: extent) ?? image
        }
        // A cut-out is adjusted as if it were opaque, then gets its own edges
        // back, so glow, grain and the vignette never spill into the
        // see-through parts.
        let opaque = input.unpremultiplyingAlpha().settingAlphaOne(in: extent)
        let adjusted = ImageFilters.adjust(softened(opaque), with: settings)
            .settingAlphaOne(in: extent)
            .applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: input,
            ])
        return ImageFilters.render(adjusted, extent: extent) ?? image
    }

    /// Enhance's Quick fix at this image's size. A photo stays opaque; a
    /// cut-out keeps its own edges (and grows with them when upscaled).
    static func quickFix(_ image: UIImage, plan: QuickFixPlan) -> UIImage {
        guard let input = ImageFilters.ciImage(image) else { return image }
        let extent = input.extent
        let target = CGRect(x: 0, y: 0, width: (extent.width * plan.scale).rounded(), height: (extent.height * plan.scale).rounded())
        guard ImageUtilities.hasAlpha(image) else {
            let fixed = ImageFilters.quickFix(input, plan: plan).settingAlphaOne(in: target)
            return ImageFilters.render(fixed, extent: target) ?? image
        }
        let opaque = input.unpremultiplyingAlpha().settingAlphaOne(in: extent)
        let alpha = plan.scale > 1.001 ? ImageFilters.upscale(input, factor: Float(plan.scale)).cropped(to: target) : input
        let fixed = ImageFilters.quickFix(opaque, plan: plan)
            .settingAlphaOne(in: target)
            .applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: alpha,
            ])
        return ImageFilters.render(fixed, extent: target) ?? image
    }
}
