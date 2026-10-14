import UIKit
import Vision
import CoreImage
import AppCore

/// Looks at a photo on device with Apple's Vision framework, for the editor's
/// "Ideas for this photo". Nothing leaves the device and nothing here judges
/// anyone: only what's in the picture (labels, how many faces, a pet) and how
/// bright it is.
@MainActor
enum PhotoInsightsService {
    /// Keyed by the image object; the editor asks again after each step.
    private static let cache: NSCache<UIImage, Box> = {
        let cache = NSCache<UIImage, Box>()
        cache.countLimit = 4
        return cache
    }()

    private final class Box {
        let insight: PhotoInsight
        init(_ insight: PhotoInsight) { self.insight = insight }
    }

    static func insight(for image: UIImage) async -> PhotoInsight {
        if let cached = cache.object(forKey: image) { return cached.insight }
        let insight = await Task.detached(priority: .userInitiated) { analyze(image) }.value
        cache.setObject(Box(insight), forKey: image)
        return insight
    }

    nonisolated private static func analyze(_ image: UIImage) -> PhotoInsight {
        // A small copy is plenty for labels and faces, and keeps this quick.
        guard let cgImage = ImageUtilities.normalized(image, maxLongEdge: 1024).cgImage else { return PhotoInsight() }

        let classify = VNClassifyImageRequest()
        let faces = VNDetectFaceRectanglesRequest()
        let animals = VNRecognizeAnimalsRequest()
        // Each request may fail on its own (the simulator has no Neural
        // Engine for classification), so they run separately.
        let handler = VNImageRequestHandler(cgImage: cgImage)
        for request in [classify, faces, animals] as [VNRequest] {
            try? handler.perform([request])
        }

        let labels = (classify.results ?? [])
            .filter { $0.confidence >= 0.3 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(12)
            .map { $0.identifier.lowercased() }
        // Same rule as the kindness check: ignore tiny background faces.
        let faceCount = (faces.results ?? []).filter { $0.boundingBox.width * $0.boundingBox.height > 0.004 }.count
        let animal = (animals.results ?? [])
            .filter { $0.confidence >= 0.5 }
            .max { $0.confidence < $1.confidence }?
            .labels.first?.identifier.lowercased()

        return PhotoInsight(
            faceCount: faceCount,
            labels: Array(labels),
            hasAnimal: animal != nil,
            animalKind: animal,
            isDark: averageLuminance(of: cgImage).map { $0 < 0.22 } ?? false,
            isPortraitOrientation: cgImage.height > cgImage.width
        )
    }

    /// Average luminance (0…1) of the whole photo.
    nonisolated private static func averageLuminance(of cgImage: CGImage) -> Double? {
        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input,
            kCIInputExtentKey: CIVector(cgRect: input.extent),
        ]), let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        ImageFilters.measuringContext
            .render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return (0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])) / 255
    }
}
