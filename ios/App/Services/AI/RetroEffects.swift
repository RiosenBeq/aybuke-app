import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// On-device "special effects" with an era: VHS tapes, disposable cameras,
/// Y2K digicams, instant film, 90s glamour shots and glitter. Pure Core Image
/// plus a little UIKit drawing (date stamps, frames, sparkles), so they're
/// instant, free for everyone and never leave the iPhone.
enum RetroEffect: String, CaseIterable, Identifiable {
    case vhs
    case disposable
    case kira
    case digicam
    case instant
    case glamour
    case neon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vhs: return "VHS '86"
        case .disposable: return "Disposable '98"
        case .kira: return "Kira Kira"
        case .digicam: return "Digicam '04"
        case .instant: return "Instant '82"
        case .glamour: return "Glamour '92"
        case .neon: return "Neon '84"
        }
    }

    var era: String {
        switch self {
        case .vhs, .instant, .neon: return "80s"
        case .disposable, .glamour: return "90s"
        case .digicam: return "Y2K"
        case .kira: return String(localized: "Sparkle")
        }
    }

    /// Effects that print a date on the photo, like the real thing did.
    var hasDateStamp: Bool {
        switch self {
        case .vhs, .disposable, .digicam: return true
        default: return false
        }
    }

    // MARK: Rendering

    /// Renders the effect at the image's own size (the instant frame adds a border).
    func apply(to image: UIImage, dateStamp: Bool = true, date: Date = Date()) -> UIImage {
        let source = ImageUtilities.normalized(image, maxLongEdge: 4096)
        guard let input = ImageFilters.ciImage(source) else { return image }
        let graded = grade(input)
        guard var output = ImageFilters.render(graded, extent: input.extent) else { return image }
        switch self {
        case .kira:
            output = RetroEffect.sparkles(on: output)
        case .instant:
            output = RetroEffect.instantFrame(around: output)
        default:
            break
        }
        if dateStamp, hasDateStamp {
            output = RetroEffect.stamp(stampText(for: date), style: self, on: output)
        }
        return output
    }

    /// Effects that also work on video frames (no frames or per-frame sparkles).
    static let videoEffects: [RetroEffect] = [.vhs, .disposable, .digicam, .glamour, .neon]

    /// The colour, grain and light of the effect, for photos and video frames.
    func grade(_ input: CIImage) -> CIImage {
        let extent = input.extent
        let unit = max(extent.width, extent.height) / 1000
        switch self {
        case .vhs:
            var image = input
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.25, kCIInputContrastKey: 1.08])
                .clampedToExtent().applyingGaussianBlur(sigma: 0.9 * unit).cropped(to: extent)
            image = RetroEffect.chromaticShift(image, offset: 3.5 * unit)
            image = RetroEffect.scanlines(over: image, spacing: max(2, 3 * unit), strength: 0.18)
            image = RetroEffect.grain(over: image, amount: 0.12, scale: unit)
            return RetroEffect.tint(image, red: 1.02, green: 0.99, blue: 1.02)
        case .disposable:
            var image = input
                .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.28])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 8200, y: 12),
                ])
                .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.06, kCIInputSaturationKey: 1.12])
            image = RetroEffect.liftBlacks(image, amount: 0.06)
            image = RetroEffect.lightLeak(over: image, color: CIColor(red: 1, green: 0.45, blue: 0.2), at: CGPoint(x: extent.maxX, y: extent.maxY), radius: extent.width * 0.7)
            image = RetroEffect.grain(over: image, amount: 0.16, scale: unit * 1.4)
            return image.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 0.9, kCIInputRadiusKey: 1.4])
        case .kira:
            let bloom = input.applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: 8 * unit, kCIInputIntensityKey: 0.45])
            return bloom.cropped(to: extent).applyingFilter("CIVibrance", parameters: ["inputAmount": 0.35])
        case .digicam:
            var image = input
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 5200, y: -8),
                ])
                .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.18, kCIInputSaturationKey: 1.1, kCIInputBrightnessKey: 0.02])
            // On-camera flash: a hot centre that falls off fast.
            image = RetroEffect.lightLeak(over: image, color: CIColor(red: 1, green: 1, blue: 1), at: CGPoint(x: extent.midX, y: extent.midY), radius: extent.width * 0.55, alpha: 0.28)
            image = image.clampedToExtent().applyingGaussianBlur(sigma: 0.6 * unit).cropped(to: extent)
            return RetroEffect.grain(over: image, amount: 0.06, scale: unit)
                .applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 0.6, kCIInputRadiusKey: 1.8])
        case .instant:
            var image = input
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 7600, y: 18),
                ])
                .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 0.88, kCIInputSaturationKey: 0.82])
            image = RetroEffect.liftBlacks(image, amount: 0.12)
            image = RetroEffect.tint(image, red: 1.02, green: 0.99, blue: 0.93)
            return RetroEffect.grain(over: image, amount: 0.08, scale: unit)
        case .glamour:
            // Soft-focus 90s studio portrait: a dreamy glow and a blush cast.
            let soft = input.clampedToExtent().applyingGaussianBlur(sigma: 14 * unit).cropped(to: extent)
            var image = soft.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: input])
            image = image.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.06, kCIInputContrastKey: 1.04, kCIInputSaturationKey: 1.05])
            image = RetroEffect.tint(image, red: 1.04, green: 0.97, blue: 1.0)
            image = RetroEffect.liftBlacks(image, amount: 0.05)
            return image.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 0.5, kCIInputRadiusKey: 2])
        case .neon:
            let duotone = input.applyingFilter("CIFalseColor", parameters: [
                "inputColor0": CIColor(red: 0.12, green: 0.05, blue: 0.35),
                "inputColor1": CIColor(red: 1, green: 0.42, blue: 0.78),
            ])
            let mixed = duotone.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: input, kCIInputTimeKey: 0.42,
            ])
            return mixed
                .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.15, kCIInputSaturationKey: 1.3])
                .applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: 10 * unit, kCIInputIntensityKey: 0.5])
                .cropped(to: extent)
        }
    }

    // MARK: Building blocks

    private static func tint(_ image: CIImage, red: CGFloat, green: CGFloat, blue: CGFloat) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: red, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: green, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: blue, w: 0),
        ])
    }

    /// Faded shadows, as on old prints.
    private static func liftBlacks(_ image: CIImage, amount: CGFloat) -> CIImage {
        image.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0, y: amount),
            "inputPoint1": CIVector(x: 0.25, y: 0.25 + amount * 0.5),
            "inputPoint2": CIVector(x: 0.5, y: 0.5),
            "inputPoint3": CIVector(x: 0.75, y: 0.76),
            "inputPoint4": CIVector(x: 1, y: 0.98),
        ])
    }

    /// Red and blue channels drift apart, like a worn tape.
    private static func chromaticShift(_ image: CIImage, offset: CGFloat) -> CIImage {
        func channel(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CIImage {
            image.clampedToExtent().applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
            ])
        }
        let red = channel(1, 0, 0).transformed(by: CGAffineTransform(translationX: offset, y: 0))
        let green = channel(0, 1, 0)
        let blue = channel(0, 0, 1).transformed(by: CGAffineTransform(translationX: -offset, y: 0))
        // Adding three opaque layers sums their alpha too; reset it to 1.
        return red
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: green])
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: blue])
            .settingAlphaOne(in: image.extent)
            .cropped(to: image.extent)
    }

    private static func scanlines(over image: CIImage, spacing: CGFloat, strength: CGFloat) -> CIImage {
        let stripes = CIFilter.stripesGenerator()
        stripes.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: strength)
        stripes.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        stripes.width = Float(spacing)
        stripes.sharpness = 0.6
        guard let lines = stripes.outputImage?
            .transformed(by: CGAffineTransform(rotationAngle: .pi / 2))
            .cropped(to: image.extent) else { return image }
        return lines.composited(over: image)
    }

    /// Film grain: grey noise centred on 50% (neutral for soft light), so it
    /// adds texture without darkening. Scaled with the photo, so previews and
    /// full-size renders look alike.
    private static func grain(over image: CIImage, amount: CGFloat, scale: CGFloat) -> CIImage {
        guard let noise = CIFilter.randomGenerator().outputImage else { return image }
        let spread = amount * 2
        let offset = 0.5 - spread / 2
        // The generator's alpha is random too; fix it at 1 first, or the colour
        // matrix (which un-premultiplies) would blow the values up.
        let gray = noise
            .settingAlphaOne(in: CGRect(x: -1e6, y: -1e6, width: 2e6, height: 2e6))
            .transformed(by: CGAffineTransform(scaleX: max(scale, 1), y: max(scale, 1)))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: spread, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: spread, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: spread, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: offset, y: offset, z: offset, w: 1),
            ])
            .cropped(to: image.extent)
        return gray.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image])
    }

    private static func lightLeak(over image: CIImage, color: CIColor, at point: CGPoint, radius: CGFloat, alpha: CGFloat = 0.55) -> CIImage {
        let gradient = CIFilter.radialGradient()
        gradient.center = point
        gradient.radius0 = 0
        gradient.radius1 = Float(radius)
        gradient.color0 = CIColor(red: color.red, green: color.green, blue: color.blue, alpha: alpha)
        gradient.color1 = CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0)
        guard let leak = gradient.outputImage?.cropped(to: image.extent) else { return image }
        return leak.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image])
    }

    // MARK: UIKit overlays

    private func stampText(for date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents([.month, .day], from: date)
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        switch self {
        case .vhs:
            let names = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
            return "PLAY ▶\n\(names[month - 1]) \(String(format: "%02d", day)) 1986"
        case .disposable:
            return String(format: "'98 %02d %02d", month, day)
        default:
            return String(format: "2004/%02d/%02d", month, day)
        }
    }

    /// The date stamp on a transparent layer the size of a video frame.
    func videoStampOverlay(size: CGSize, date: Date = Date()) -> CIImage? {
        guard hasDateStamp else { return nil }
        let layer = RetroEffect.stampLayer(stampText(for: date), style: self, size: size)
        return CIImage(image: layer)
    }

    private static func stamp(_ text: String, style: RetroEffect, on image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(at: .zero)
            stampLayer(text, style: style, size: image.size).draw(at: .zero)
        }
    }

    private static func stampLayer(_ text: String, style: RetroEffect, size: CGSize) -> UIImage {
        let unit = max(size.width, size.height) / 1000
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let isVHS = style == .vhs
            let font = UIFont.monospacedSystemFont(ofSize: (isVHS ? 30 : 34) * unit, weight: isVHS ? .bold : .semibold)
            let color = isVHS ? UIColor.white : UIColor(red: 1, green: 0.55, blue: 0.18, alpha: 0.95)
            let shadow = NSShadow()
            shadow.shadowColor = isVHS ? UIColor(red: 0.3, green: 0.5, blue: 1, alpha: 0.9) : UIColor(red: 1, green: 0.3, blue: 0, alpha: 0.6)
            shadow.shadowBlurRadius = 6 * unit
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .shadow: shadow]
            let margin = 36 * unit
            if isVHS {
                let lines = text.components(separatedBy: "\n")
                (lines[0] as NSString).draw(at: CGPoint(x: margin, y: margin), withAttributes: attributes)
                let bottom = lines[1] as NSString
                let bottomSize = bottom.size(withAttributes: attributes)
                bottom.draw(at: CGPoint(x: margin, y: size.height - margin - bottomSize.height), withAttributes: attributes)
            } else {
                let label = text as NSString
                let textSize = label.size(withAttributes: attributes)
                label.draw(at: CGPoint(x: size.width - margin - textSize.width, y: size.height - margin - textSize.height), withAttributes: attributes)
            }
            _ = context
        }
    }

    /// White instant-film border with a deeper chin.
    private static func instantFrame(around image: UIImage) -> UIImage {
        let size = image.size
        let side = max(size.width, size.height) * 0.05
        let chin = max(size.width, size.height) * 0.17
        let canvas = CGSize(width: size.width + side * 2, height: size.height + side + chin)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            UIColor(red: 0.985, green: 0.98, blue: 0.965, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            image.draw(in: CGRect(x: side, y: side, width: size.width, height: size.height))
        }
    }

    /// Glitter: four-point stars on the brightest spots, like Kira Kira
    /// cameras. Positions come from the photo itself, so previews match.
    private static func sparkles(on image: UIImage) -> UIImage {
        let points = highlights(in: image, count: 14)
        let size = image.size
        let unit = max(size.width, size.height) / 1000
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            image.draw(at: .zero)
            let cg = context.cgContext
            for (index, point) in points.enumerated() {
                let radius = (index % 3 == 0 ? 34 : index % 3 == 1 ? 22 : 14) * unit * (0.6 + point.strength * 0.6)
                let center = CGPoint(x: point.location.x * size.width, y: point.location.y * size.height)
                cg.setShadow(offset: .zero, blur: radius * 0.9, color: UIColor.white.withAlphaComponent(0.95).cgColor)
                UIColor.white.setFill()
                sparklePath(center: center, radius: radius).fill()
                if index % 2 == 0 {
                    // A smaller star turned 45° makes the eight-point twinkle.
                    let small = sparklePath(center: center, radius: radius * 0.5)
                    small.apply(CGAffineTransform(translationX: -center.x, y: -center.y)
                        .concatenating(CGAffineTransform(rotationAngle: .pi / 4))
                        .concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
                    small.fill()
                }
            }
        }
    }

    private static func sparklePath(center: CGPoint, radius: CGFloat) -> UIBezierPath {
        let inner = radius * 0.22
        let path = UIBezierPath()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), controlPoint: CGPoint(x: center.x + inner, y: center.y - inner))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), controlPoint: CGPoint(x: center.x + inner, y: center.y + inner))
        path.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), controlPoint: CGPoint(x: center.x - inner, y: center.y + inner))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), controlPoint: CGPoint(x: center.x - inner, y: center.y - inner))
        path.close()
        return path
    }

    /// The brightest, well-spaced spots (normalised 0…1, top-left origin).
    private static func highlights(in image: UIImage, count: Int) -> [(location: CGPoint, strength: CGFloat)] {
        let grid = 48
        let thumb = ImageUtilities.normalized(image, maxLongEdge: grid)
        guard let cgImage = thumb.cgImage else { return [] }
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var candidates: [(x: Int, y: Int, luma: CGFloat)] = []
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let luma = (0.299 * CGFloat(pixels[i]) + 0.587 * CGFloat(pixels[i + 1]) + 0.114 * CGFloat(pixels[i + 2])) / 255
                if luma > 0.62 { candidates.append((x, y, luma)) }
            }
        }
        candidates.sort { $0.luma > $1.luma }
        var picked: [(location: CGPoint, strength: CGFloat)] = []
        let minDistance = CGFloat(max(width, height)) * 0.12
        for candidate in candidates where picked.count < count {
            let point = CGPoint(x: (CGFloat(candidate.x) + 0.5) / CGFloat(width), y: (CGFloat(candidate.y) + 0.5) / CGFloat(height))
            let tooClose = picked.contains { hypot(($0.location.x - point.x) * CGFloat(width), ($0.location.y - point.y) * CGFloat(height)) < minDistance }
            if !tooClose { picked.append((point, (candidate.luma - 0.62) / 0.38)) }
        }
        return picked
    }
}
