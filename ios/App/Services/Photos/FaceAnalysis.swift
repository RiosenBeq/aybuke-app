import UIKit
import Vision
import CoreImage

/// What the likeness check found after a people edit.
enum LikenessResult: Equatable {
    /// Face shape and skin tone look like the original.
    case stillYou
    case skinLighter
    case skinDarker
    case faceShapeChanged

    var needsAttention: Bool { self != .stillYou }

    var message: String {
        switch self {
        case .stillYou: return String(localized: "Still you")
        case .skinLighter: return String(localized: "Your skin tone looks lighter than in your photo.")
        case .skinDarker: return String(localized: "Your skin tone looks darker than in your photo.")
        case .faceShapeChanged: return String(localized: "Your face shape looks different from your photo.")
        }
    }
}

/// On-device face checks with Apple's Vision framework. Nothing leaves the
/// iPhone, and nothing here rates anyone's looks: only how many people are in
/// a photo, how sharp and well lit a face is, and whether an AI edit changed
/// someone's skin tone or face shape.
enum FaceAnalysis {
    // MARK: Kindness check

    /// How many faces are in the photo.
    static func faceCount(in image: UIImage) async -> Int {
        await Task.detached(priority: .utility) {
            guard let cgImage = prepared(image, maxLongEdge: 1024) else { return 0 }
            let request = VNDetectFaceRectanglesRequest()
            try? VNImageRequestHandler(cgImage: cgImage).perform([request])
            // Ignore tiny background faces (a poster, a crowd far away).
            return (request.results ?? []).filter { $0.boundingBox.width * $0.boundingBox.height > 0.004 }.count
        }.value
    }

    // MARK: Hide faces

    /// Every face Vision finds, normalized with a top-left origin, left to
    /// right. Small background faces are kept on purpose: bystanders are who
    /// "Hide faces" protects. Rectangles only; no landmarks.
    static func faceRects(in image: UIImage) async -> [CGRect] {
        await Task.detached(priority: .userInitiated) {
            guard let cgImage = prepared(image, maxLongEdge: 2048) else { return [] }
            let request = VNDetectFaceRectanglesRequest()
            try? VNImageRequestHandler(cgImage: cgImage).perform([request])
            return (request.results ?? [])
                .map { face in
                    let box = face.boundingBox
                    return CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
                }
                .filter { $0.width * $0.height > 0.0001 }
                .sorted { $0.midX < $1.midX }
        }.value
    }

    // MARK: Best shot

    /// Apple's face capture quality (0…1: light, focus, pose, eyes open) for
    /// the largest face, or nil when there's no face.
    static func captureQuality(of image: UIImage) async -> Float? {
        await Task.detached(priority: .userInitiated) {
            guard let cgImage = prepared(image, maxLongEdge: 1280) else { return nil }
            let request = VNDetectFaceCaptureQualityRequest()
            try? VNImageRequestHandler(cgImage: cgImage).perform([request])
            let largest = (request.results ?? []).max { area($0) < area($1) }
            return largest?.faceCaptureQuality
        }.value
    }

    // MARK: Likeness check

    /// Where skin tone is read: the cheeks, or the chin for a makeup look,
    /// whose blush, freckles and lip color would read as a skin change.
    enum SkinSample: Sendable {
        case cheeks, chin
    }

    /// Compares the main face before and after an AI edit. Nil when it can't
    /// tell (no face, or a different number of people).
    static func likeness(original: UIImage, edited: UIImage, skinSample: SkinSample = .cheeks) async -> LikenessResult? {
        await Task.detached(priority: .utility) {
            guard let before = faceSignature(original, skinSample: skinSample),
                  let after = faceSignature(edited, skinSample: skinSample),
                  before.faces == after.faces else { return nil }

            // Skin lightness relative to the whole photo, so a lighting change
            // ("golden hour") doesn't count as a skin tone change.
            let lightness = after.relativeSkinLightness - before.relativeSkinLightness
            if lightness > 9 { return .skinLighter }
            if lightness < -9 { return .skinDarker }

            let mouth = abs(after.eyesToMouth - before.eyesToMouth) / max(before.eyesToMouth, 0.01)
            let width = abs(after.faceWidth - before.faceWidth) / max(before.faceWidth, 0.01)
            if mouth > 0.16 || width > 0.18 { return .faceShapeChanged }
            return .stillYou
        }.value
    }

    private struct FaceSignature {
        let faces: Int
        /// Eye-line-to-mouth distance and face width, both in eye distances.
        let eyesToMouth: CGFloat
        let faceWidth: CGFloat
        /// Skin L* (CIELAB) minus the photo's average L*.
        let relativeSkinLightness: CGFloat
    }

    private static func faceSignature(_ image: UIImage, skinSample: SkinSample) -> FaceSignature? {
        guard let cgImage = prepared(image, maxLongEdge: 1024) else { return nil }
        let request = VNDetectFaceLandmarksRequest()
        try? VNImageRequestHandler(cgImage: cgImage).perform([request])
        let faces = (request.results ?? []).filter { $0.boundingBox.width * $0.boundingBox.height > 0.004 }
        guard let face = faces.max(by: { area($0) < area($1) }),
              let landmarks = face.landmarks,
              let leftEye = landmarks.leftEye, let rightEye = landmarks.rightEye, let lips = landmarks.outerLips else { return nil }

        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let left = center(leftEye.pointsInImage(imageSize: size))
        let right = center(rightEye.pointsInImage(imageSize: size))
        let mouth = center(lips.pointsInImage(imageSize: size))
        let eyeDistance = hypot(right.x - left.x, right.y - left.y)
        guard eyeDistance > 4 else { return nil }
        let eyeLine = CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
        let faceBox = VNImageRectForNormalizedRect(face.boundingBox, cgImage.width, cgImage.height)

        // Cheeks: between the eye line and the mouth, as wide as the eyes.
        // Vision's coordinates start at the bottom left; Core Image's do too.
        let cheeks = CGRect(
            x: min(left.x, right.x),
            y: min(mouth.y, eyeLine.y),
            width: abs(right.x - left.x),
            height: abs(eyeLine.y - mouth.y)
        )
        var skinArea = cheeks
        if skinSample == .chin {
            // Under the lower lip, as wide as the mouth, leaving out the rows
            // nearest the lip so lip color never counts. Too small (a photo cut
            // off at the chin): the cheeks after all.
            let lipPoints = lips.pointsInImage(imageSize: size)
            if let lipsBottom = lipPoints.map(\.y).min(), let lipsLeft = lipPoints.map(\.x).min(),
               let lipsRight = lipPoints.map(\.x).max() {
                let chin = CGRect(x: lipsLeft, y: faceBox.minY, width: lipsRight - lipsLeft, height: (lipsBottom - faceBox.minY) * 0.8)
                if chin.width > 2, chin.height > 2 { skinArea = chin }
            }
        }
        let ciImage = CIImage(cgImage: cgImage)
        guard skinArea.width > 2, skinArea.height > 2,
              let skin = averageLightness(of: ciImage, in: skinArea),
              let scene = averageLightness(of: ciImage, in: ciImage.extent) else { return nil }

        return FaceSignature(
            faces: faces.count,
            eyesToMouth: hypot(mouth.x - eyeLine.x, mouth.y - eyeLine.y) / eyeDistance,
            faceWidth: faceBox.width / eyeDistance,
            relativeSkinLightness: skin - scene
        )
    }

    // MARK: Helpers

    private static let context = ImageFilters.measuringContext

    /// Average CIELAB lightness (0…100) of a region.
    private static func averageLightness(of image: CIImage, in rect: CGRect) -> CGFloat? {
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: CIVector(cgRect: rect),
        ]), let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        func linear(_ value: UInt8) -> CGFloat {
            let c = CGFloat(value) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(pixel[0]) + 0.7152 * linear(pixel[1]) + 0.0722 * linear(pixel[2])
        return luminance > 0.008856 ? 116 * pow(luminance, 1 / 3) - 16 : 903.3 * luminance
    }

    private static func prepared(_ image: UIImage, maxLongEdge: Int) -> CGImage? {
        ImageUtilities.normalized(image, maxLongEdge: maxLongEdge).cgImage
    }

    private static func area(_ face: VNFaceObservation) -> CGFloat {
        face.boundingBox.width * face.boundingBox.height
    }

    private static func center(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }
}
