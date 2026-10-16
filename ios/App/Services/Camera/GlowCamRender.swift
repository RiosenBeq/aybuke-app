import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import AppCore

/// Glow Cam's look in Core Image, the same for the live preview and the
/// full-size still: the makeup tint first (under the light, like real
/// makeup), then her light and the vibe through the editor's own Adjust maths
/// (`ImageFilters.adjust`), then sparkle on top. Colour and light only:
/// nothing blurs skin or moves a feature (AGENTS.md §5).
enum GlowCamRender {
    /// A face to tint, in the pixels of the image being drawn.
    struct TintFace {
        var landmarks: FaceLandmarks
        /// 0…1, as it fades in and out.
        var opacity: Double
    }

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// `seconds` (the frames' clock) places the sparkle.
    static func apply(_ input: CIImage, settings: GlowCamSettings, faces: [TintFace], seconds: Double) -> CIImage {
        let extent = input.extent
        var image = input
        if settings.hasTint, !faces.isEmpty {
            image = tint(image, faces: faces, settings: settings)
        }
        image = ImageFilters.adjust(image, with: settings.adjustment)
        if settings.sparkle {
            image = sparkle(over: image.cropped(to: extent), seconds: seconds)
        }
        return image.cropped(to: extent)
    }

    /// The full-size still. Faces are found again on the photo itself, so the
    /// tint sits exactly on her lips and cheeks. Call it off the main actor.
    static func develop(_ photo: UIImage, settings: GlowCamSettings, seconds: Double) -> UIImage {
        guard let input = ImageFilters.ciImage(photo) else { return photo }
        let extent = input.extent
        var faces: [TintFace] = []
        if settings.hasTint {
            faces = GlowFaceTracker.landmarks(in: input, maxPixel: 1600).map { face in
                TintFace(landmarks: face.mapped {
                    FacePoint(x: Double(extent.minX) + $0.x * Double(extent.width), y: Double(extent.minY) + $0.y * Double(extent.height))
                }, opacity: 1)
            }
        }
        // A photo comes out opaque (a JPEG when saved).
        let output = apply(input, settings: settings, faces: faces, seconds: seconds).settingAlphaOne(in: extent)
        return ImageFilters.render(output, extent: extent) ?? photo
    }

    // MARK: Makeup tint

    private static func tint(_ image: CIImage, faces: [TintFace], settings: GlowCamSettings) -> CIImage {
        var result = image
        if let blend = GlowCam.cheekTint(settings.cheeks),
           let mask = combined(faces.flatMap { face in FaceTintGeometry.cheeks(of: face.landmarks).map { blushMask($0, opacity: face.opacity) } }) {
            result = wash(result, blend, mask: mask)
        }
        if let blend = GlowCam.lipTint(settings.lips),
           let mask = combined(faces.compactMap { face in FaceTintGeometry.lips(of: face.landmarks).flatMap { lipMask($0, opacity: face.opacity) } }) {
            result = wash(result, blend, mask: mask)
        }
        return result
    }

    /// A sheer wash of colour where `mask` is light: the colour's hue and
    /// saturation over her own lightness, so the light and texture underneath
    /// stay, with some multiply mixed in for depth.
    private static func wash(_ image: CIImage, _ blend: TintBlend, mask: CIImage) -> CIImage {
        let extent = image.extent
        let colour = CIColor(red: CGFloat(blend.color.red), green: CGFloat(blend.color.green), blue: CGFloat(blend.color.blue),
                             alpha: 1, colorSpace: sRGB) ?? CIColor(red: CGFloat(blend.color.red), green: CGFloat(blend.color.green), blue: CGFloat(blend.color.blue))
        let paint = CIImage(color: colour).cropped(to: extent)
        var layer = paint.applyingFilter("CIColorBlendMode", parameters: [kCIInputBackgroundImageKey: image])
        if blend.depth > 0 {
            let deep = paint.applyingFilter("CIMultiplyBlendMode", parameters: [kCIInputBackgroundImageKey: image])
            layer = layer.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: deep, kCIInputTimeKey: blend.depth])
        }
        let strength = CGFloat(blend.opacity)
        let weight = mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: strength, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: strength, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: strength, w: 0),
        ])
        return layer.applyingFilter("CIBlendWithRedMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: weight])
            .cropped(to: extent)
    }

    /// Inside the lip line, the mouth's opening left out, with a soft edge.
    /// Drawn small (the edge is soft anyway) and scaled up: a few thousand
    /// pixels on the CPU, not a copy of the frame.
    private static func lipMask(_ plan: FaceTintGeometry.LipPlan, opacity: Double) -> CIImage? {
        let xs = plan.outline.map(\.x), ys = plan.outline.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(), plan.feather > 0 else { return nil }
        let pad = 3 * plan.feather
        let bounds = CGRect(x: minX - pad, y: minY - pad, width: maxX - minX + 2 * pad, height: maxY - minY + 2 * pad)
        let scale = min(1, 160 / bounds.width)
        let width = Int((bounds.width * scale).rounded(.up)), height = Int((bounds.height * scale).rounded(.up))
        guard width > 2, height > 2,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // A bitmap's y runs up, like Core Image's.
        func local(_ point: FacePoint) -> CGPoint {
            CGPoint(x: (point.x - bounds.minX) * scale, y: (point.y - bounds.minY) * scale)
        }
        let path = CGMutablePath()
        path.addLines(between: plan.outline.map(local))
        path.closeSubpath()
        if plan.opening.count >= 3 {
            path.addLines(between: plan.opening.map(local))
            path.closeSubpath()
        }
        context.addPath(path)
        context.setFillColor(gray: CGFloat(min(max(opacity, 0), 1)), alpha: 1)
        context.fillPath(using: .evenOdd)
        guard let cgImage = context.makeImage() else { return nil }
        return CIImage(cgImage: cgImage, options: [.colorSpace: NSNull()])
            .transformed(by: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale).concatenating(CGAffineTransform(translationX: bounds.minX, y: bounds.minY)))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: plan.feather)
            .cropped(to: bounds)
    }

    /// A soft flush of blush: the most colour in the middle, fading out
    /// slowly over the cheek, so it never reads as a spot.
    private static func blushMask(_ cheek: FaceTintGeometry.Ellipse, opacity: Double) -> CIImage {
        let spot = CIFilter.gaussianGradient()
        spot.center = .zero
        spot.radius = Float(1.5 * cheek.radiusX)
        spot.color0 = CIColor(red: 1, green: 1, blue: 1)
        spot.color1 = CIColor(red: 0, green: 0, blue: 0)
        let level = CGFloat(min(max(opacity, 0), 1))
        let reach = 2 * max(cheek.radiusX, cheek.radiusY)
        return (spot.outputImage ?? CIImage.empty())
            .transformed(by: CGAffineTransform(scaleX: 1, y: cheek.radiusY / max(cheek.radiusX, 1e-6))
                .concatenating(CGAffineTransform(rotationAngle: cheek.angle))
                .concatenating(CGAffineTransform(translationX: cheek.center.x, y: cheek.center.y)))
            .cropped(to: CGRect(x: cheek.center.x - reach, y: cheek.center.y - reach, width: 2 * reach, height: 2 * reach))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: level, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: level, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: level, w: 0),
            ])
    }

    /// Several faces' masks as one (the stronger where they overlap).
    private static func combined(_ masks: [CIImage]) -> CIImage? {
        guard var mask = masks.first else { return nil }
        for next in masks.dropFirst() {
            mask = next.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: mask])
        }
        return mask
    }

    // MARK: Sparkle

    /// `SparkleField`'s glints as light screened over the picture: soft discs
    /// for bokeh, a bright point with four fine rays for a star. Generated on
    /// the GPU every frame; nothing is drawn on the CPU.
    private static func sparkle(over image: CIImage, seconds: Double) -> CIImage {
        let extent = image.extent
        let longEdge = Double(max(extent.width, extent.height))
        var light: CIImage?
        for glint in SparkleField.glints(at: seconds) where glint.opacity > 0.01 {
            let center = CGPoint(x: Double(extent.minX) + glint.x * Double(extent.width), y: Double(extent.minY) + glint.y * Double(extent.height))
            let spark = self.glint(glint, radius: glint.radius * longEdge)
                .transformed(by: CGAffineTransform(translationX: center.x, y: center.y))
            light = light.map { spark.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: $0]) } ?? spark
        }
        guard let light else { return image }
        return light.cropped(to: extent).applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image])
    }

    /// One glint around the origin.
    private static func glint(_ glint: SparkleField.Glint, radius: Double) -> CIImage {
        let color = glint.color
        func spot(inner: Double, outer: Double, alpha: Double) -> CIImage {
            let gradient = CIFilter.radialGradient()
            gradient.center = .zero
            gradient.radius0 = Float(inner)
            gradient.radius1 = Float(outer)
            gradient.color0 = CIColor(red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: CGFloat(alpha))
            gradient.color1 = CIColor(red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 0)
            return (gradient.outputImage ?? CIImage.empty()).cropped(to: CGRect(x: -outer, y: -outer, width: 2 * outer, height: 2 * outer))
        }
        switch glint.kind {
        case .bokeh:
            // A soft orb, like an out-of-focus light.
            return spot(inner: 0.2 * radius, outer: radius, alpha: glint.opacity)
        case .star:
            var star = spot(inner: 0, outer: 0.45 * radius, alpha: glint.opacity)
            let ray = spot(inner: 0, outer: 2.4 * radius, alpha: 0.8 * glint.opacity)
            for squash in [CGAffineTransform(scaleX: 1, y: 0.06), CGAffineTransform(scaleX: 0.06, y: 1)] {
                star = ray.transformed(by: squash).applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: star])
            }
            return star
        }
    }
}
