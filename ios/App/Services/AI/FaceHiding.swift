import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// How "Hide faces" covers a face.
enum FaceCover: String, CaseIterable, Identifiable, Sendable {
    case blur
    case pixelate
    case heart
    case star
    case smiley

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .blur: return "drop.fill"
        case .pixelate: return "square.grid.3x3.fill"
        case .heart: return "heart.fill"
        case .star: return "sparkle"
        case .smiley: return "face.smiling.inverse"
        }
    }
}

/// Hides faces on the device. Strength is fixed on purpose: a light blur or
/// fine pixels can be undone, and a soft face blur would double as skin
/// smoothing. Covers are drawn as shapes, never emoji or SF Symbols baked
/// into exports, and are fully opaque.
enum FaceHiding {
    /// Vision's face box stops at the brows: grow it to take in the hairline,
    /// ears and chin. Normalized, top-left origin.
    static func coverRect(for face: CGRect) -> CGRect {
        CGRect(
            x: face.minX - face.width * 0.15,
            y: face.minY - face.height * 0.35,
            width: face.width * 1.3,
            height: face.height * 1.45
        )
    }

    /// The face box for a hand-placed spot centred on `point`, as big as
    /// `side` pixels (normalized, top-left origin).
    static func spot(at point: CGPoint, side: CGFloat, imageSize: CGSize) -> CGRect {
        let width = side / max(imageSize.width, 1)
        let height = side / max(imageSize.height, 1)
        // coverRect grows more upward than downward; centre the cover on the tap.
        let midY = point.y + height * 0.125
        return CGRect(x: point.x - width / 2, y: midY - height / 2, width: width, height: height)
    }

    /// The same photo with `faces` (normalized face boxes) covered.
    static func render(_ image: UIImage, faces: [CGRect], cover: FaceCover) -> UIImage {
        guard !faces.isEmpty, let cgImage = image.cgImage else { return image }
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let source = CIImage(cgImage: cgImage)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = !ImageUtilities.hasAlpha(image)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
            for face in faces {
                let rect = pixelRect(coverRect(for: face), in: size)
                guard rect.width >= 2, rect.height >= 2 else { continue }
                switch cover {
                case .blur, .pixelate:
                    let feather = rect.insetBy(dx: -rect.width * 0.12, dy: -rect.width * 0.12)
                    if let patch = filteredPatch(source, cover: cover, rect: rect, feather: feather) {
                        UIImage(cgImage: patch).draw(in: feather)
                    }
                case .heart: drawHeart(over: rect, in: context.cgContext)
                case .star: drawStar(over: rect, in: context.cgContext)
                case .smiley: drawSmiley(over: rect, in: context.cgContext)
                }
            }
        }
    }

    /// True when two photos have the same shape, so the same normalized face
    /// boxes land on the same people in both.
    static func sameShape(_ lhs: UIImage, _ rhs: UIImage) -> Bool {
        let a = lhs.size.width / max(lhs.size.height, 1)
        let b = rhs.size.width / max(rhs.size.height, 1)
        return abs(a - b) < 0.01
    }

    // MARK: Blur and pixelate

    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// The blurred or pixelated face as a transparent patch the size of
    /// `feather` (UIKit coordinates), opaque inside `rect`'s ellipse and
    /// fading out only beyond it.
    private static func filteredPatch(_ source: CIImage, cover: FaceCover, rect: CGRect, feather: CGRect) -> CGImage? {
        let height = source.extent.height
        let ciRect = CGRect(x: feather.minX, y: height - feather.maxY, width: feather.width, height: feather.height)
        let effect: CIImage
        if cover == .pixelate {
            let pixels = CIFilter.pixellate()
            pixels.inputImage = source.clampedToExtent()
            pixels.center = CGPoint(x: rect.midX, y: height - rect.midY)
            pixels.scale = Float(max(rect.width / 6, 4))
            guard let output = pixels.outputImage else { return nil }
            effect = output
        } else {
            // Blurring a smaller copy gives the same strong blur with a small
            // kernel, which is faster and works on every GPU.
            let sigma = max(rect.width * 0.22, 6)
            let shrink = min(1, 8 / sigma)
            let padded = ciRect.insetBy(dx: -sigma * 3, dy: -sigma * 3)
            effect = source.clampedToExtent()
                .cropped(to: padded)
                .transformed(by: CGAffineTransform(scaleX: shrink, y: shrink))
                .clampedToExtent()
                .applyingGaussianBlur(sigma: Double(sigma * shrink))
                .transformed(by: CGAffineTransform(scaleX: 1 / shrink, y: 1 / shrink))
        }
        guard let mask = ellipseMask(rect: rect, feather: feather) else { return nil }
        let blend = CIFilter.blendWithMask()
        blend.inputImage = effect.cropped(to: ciRect)
        blend.backgroundImage = CIImage(color: .clear).cropped(to: ciRect)
        blend.maskImage = CIImage(cgImage: mask).transformed(by: CGAffineTransform(translationX: ciRect.minX, y: ciRect.minY))
        guard let output = blend.outputImage else { return nil }
        return context.createCGImage(output, from: ciRect)
    }

    /// White ellipse over `rect`, with a soft edge only outside it, on a
    /// black canvas the size of `feather`.
    private static func ellipseMask(rect: CGRect, feather: CGRect) -> CGImage? {
        let width = Int(feather.width.rounded(.up)), height = Int(feather.height.rounded(.up))
        guard width > 0, height > 0, let cg = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        // The ellipse is symmetric and centred, so the bitmap's flipped y doesn't matter.
        let core = CGRect(x: rect.minX - feather.minX, y: rect.minY - feather.minY, width: rect.width, height: rect.height)
        let margin = rect.width * 0.12
        let steps = 12
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            cg.setFillColor(gray: t * t * (3 - 2 * t), alpha: 1)
            cg.fillEllipse(in: core.insetBy(dx: -margin * (1 - t), dy: -margin * (1 - t)))
        }
        return cg.makeImage()
    }

    // MARK: Covers

    /// A circle that contains the whole cover ellipse.
    private static func coverCircle(over rect: CGRect) -> CGRect {
        let side = max(rect.width, rect.height) * 1.08
        return CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
    }

    private static func outline(_ path: UIBezierPath, side: CGFloat) {
        UIColor.white.setStroke()
        path.lineWidth = max(2, side * 0.035)
        path.lineJoinStyle = .round
        path.stroke()
    }

    private static func drawHeart(over rect: CGRect, in cg: CGContext) {
        // Big enough that the ellipse fits inside the heart's lobes and point.
        let side = max(rect.width, rect.height) * 1.55
        let box = CGRect(x: rect.midX - side / 2, y: rect.midY - side * 0.52, width: side, height: side)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: box.minX + x * side, y: box.minY + y * side) }
        let heart = UIBezierPath()
        heart.move(to: point(0.5, 0.97))
        heart.addCurve(to: point(0.0, 0.34), controlPoint1: point(0.2, 0.76), controlPoint2: point(0.0, 0.56))
        heart.addCurve(to: point(0.5, 0.17), controlPoint1: point(0.0, 0.04), controlPoint2: point(0.38, -0.02))
        heart.addCurve(to: point(1.0, 0.34), controlPoint1: point(0.62, -0.02), controlPoint2: point(1.0, 0.04))
        heart.addCurve(to: point(0.5, 0.97), controlPoint1: point(1.0, 0.56), controlPoint2: point(0.8, 0.76))
        heart.close()
        UIColor.auraPink.setFill()
        heart.fill()
        outline(heart, side: side)
        // A small gloss, like a sticker.
        UIColor.white.withAlphaComponent(0.45).setFill()
        UIBezierPath(ovalIn: CGRect(x: box.minX + side * 0.16, y: box.minY + side * 0.16, width: side * 0.16, height: side * 0.1)).fill()
    }

    /// The brand's four-point sparkle on a lilac disc (the disc does the hiding).
    private static func drawStar(over rect: CGRect, in cg: CGContext) {
        let circle = coverCircle(over: rect)
        let disc = UIBezierPath(ovalIn: circle)
        UIColor.auraLilac.setFill()
        disc.fill()
        outline(disc, side: circle.width)

        let center = CGPoint(x: circle.midX, y: circle.midY)
        let radius = circle.width * 0.38
        let waist = radius * 0.22
        let sparkle = UIBezierPath()
        for index in 0..<4 {
            let angle = CGFloat(index) * .pi / 2 - .pi / 2
            let tip = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            let next = angle + .pi / 2
            let nextTip = CGPoint(x: center.x + cos(next) * radius, y: center.y + sin(next) * radius)
            let control = CGPoint(x: center.x + cos(angle + .pi / 4) * waist, y: center.y + sin(angle + .pi / 4) * waist)
            if index == 0 { sparkle.move(to: tip) }
            sparkle.addQuadCurve(to: nextTip, controlPoint: control)
        }
        sparkle.close()
        UIColor.auraButter.setFill()
        sparkle.fill()
    }

    private static func drawSmiley(over rect: CGRect, in cg: CGContext) {
        let circle = coverCircle(over: rect)
        let face = UIBezierPath(ovalIn: circle)
        UIColor.auraButter.setFill()
        face.fill()
        outline(face, side: circle.width)

        let side = circle.width
        UIColor.plum.setFill()
        for x in [0.36, 0.64] {
            UIBezierPath(ovalIn: CGRect(x: circle.minX + side * x - side * 0.05, y: circle.minY + side * 0.3, width: side * 0.1, height: side * 0.16)).fill()
        }
        let smile = UIBezierPath(
            arcCenter: CGPoint(x: circle.midX, y: circle.minY + side * 0.52),
            radius: side * 0.24, startAngle: .pi * 0.18, endAngle: .pi * 0.82, clockwise: true
        )
        UIColor.plum.setStroke()
        smile.lineWidth = max(2, side * 0.06)
        smile.lineCapStyle = .round
        smile.stroke()
    }

    // MARK: Helpers

    private static func pixelRect(_ normalized: CGRect, in size: CGSize) -> CGRect {
        CGRect(x: normalized.minX * size.width, y: normalized.minY * size.height,
               width: normalized.width * size.width, height: normalized.height * size.height)
    }
}
