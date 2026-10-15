import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import AppCore

/// What goes behind the cut-out. All of them are free and drawn on the device.
enum CutoutBackdrop: Hashable, Sendable {
    case transparent
    case color(UInt32)
    case custom
    case blurOriginal
    case gradient(CutoutGradient)
    case photo

    /// Blush and Aura swatches for the colour row.
    static let swatches: [UInt32] = [0xFFFFFF, 0xF8E0EA, 0xF7C1D9, 0xFF5CA1, 0xA78BFA, 0x78E1CD, 0xFFDE6E, 0x121212]
}

enum CutoutGradient: String, CaseIterable, Identifiable, Sendable {
    case pastel
    case cottonCandy
    case pinkSunset
    case auraGlow
    case lilacHaze
    case mint
    /// A pattern rather than a gradient: a pale pink sky with a lilac grid.
    case y2kGrid

    var id: String { rawValue }

    /// Top and bottom colours (the grid uses them for sky and lines).
    var colors: [UIColor] {
        switch self {
        case .pastel: return [.brandPetal, .auraLilac.withAlphaComponent(0.55), .auraMint.withAlphaComponent(0.6)]
        case .cottonCandy: return [.brandBlush, .auraLilac]
        case .pinkSunset: return [.auraPeach, .auraPink, .plum]
        case .auraGlow: return [.auraButter, .auraPink, .auraLilac]
        case .lilacHaze: return [.brandPetal, .auraLilac]
        case .mint: return [.brandPaper, .auraMint]
        case .y2kGrid: return [.brandPetal, .auraLilac]
        }
    }
}

/// One stroke of Cut out's refine brush: paints the photo back in
/// (`keeps`) or takes it away.
struct CutoutRefineStroke: Sendable, Equatable {
    let stroke: MaskStroke
    let keeps: Bool
}

/// Puts the cut-out on its new background, and makes stickers. Every
/// function is pure and safe off the main thread, and works at any scale, so
/// the preview matches the final image.
enum CutoutRenderer {
    private static let context = ImageFilters.context

    /// `mask` with her refine strokes painted over it in order (white keeps,
    /// black removes), with an edge as soft as Vision's own.
    static func refined(_ mask: CIImage, with strokes: [CutoutRefineStroke]) -> CIImage {
        let extent = mask.extent
        guard !strokes.isEmpty, extent.width >= 1, extent.height >= 1 else { return mask }
        // Strokes are soft anyway, so a smaller layer scaled up is enough.
        let scale = min(1, 1024 / max(extent.width, extent.height))
        let size = CGSize(width: (extent.width * scale).rounded(), height: (extent.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let layer = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for refine in strokes {
                cg.setStrokeColor((refine.keeps ? UIColor.white : UIColor.black).cgColor)
                cg.setLineWidth(refine.stroke.width * size.width)
                cg.addPath(refine.stroke.path(in: size).cgPath)
                cg.strokePath()
            }
        }
        guard let cgLayer = layer.cgImage else { return mask }
        let painted = CIImage(cgImage: cgLayer)
            .transformed(by: CGAffineTransform(scaleX: extent.width / size.width, y: extent.height / size.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(max(1, max(extent.width, extent.height) * 0.0015)))
            .cropped(to: extent)
        return painted.composited(over: mask).cropped(to: extent)
    }

    /// The kept subjects (`mask`) over `backdrop`, at `source`'s extent, with
    /// a soft shadow under each subject in `shadowUnder` (their bounds,
    /// normalized, top-left origin).
    static func composite(source: CIImage, mask: CIImage, backdrop: CutoutBackdrop, color: UIColor?, photo: UIImage?,
                          shadowUnder subjects: [CGRect] = []) -> CIImage {
        let extent = source.extent
        var background: CIImage
        switch backdrop {
        case .transparent:
            background = CIImage(color: .clear).cropped(to: extent)
        case .color(let hex):
            background = CIImage(color: CIColor(color: UIColor(hex: hex))).cropped(to: extent)
        case .custom:
            background = CIImage(color: CIColor(color: color ?? .brandBlush)).cropped(to: extent)
        case .blurOriginal:
            background = blurredBackground(source: source, mask: mask)
        case .gradient(let gradient):
            background = image(of: extent.size) { size in drawGradient(gradient, size: size) }
        case .photo:
            background = image(of: extent.size) { size in
                guard let photo else { return }
                photo.draw(in: ShareRenderer.fillRect(for: photo.size, in: CGRect(origin: .zero, size: size), face: nil))
            }
        }
        if !subjects.isEmpty {
            background = shadow(of: mask, under: subjects, extent: extent).composited(over: background).cropped(to: extent)
        }
        // Her own colours over the soft edge, so no old background rides along.
        let blend = CIFilter.blendWithMask()
        blend.inputImage = Matte.foreground(of: source, matte: mask)
        blend.backgroundImage = background
        blend.maskImage = mask
        return (blend.outputImage ?? source).cropped(to: extent)
    }

    /// The photo with its subjects taken out and the hole filled from around
    /// them, then blurred: blur(photo × (1 − m)) / blur(1 − m). The slightly
    /// grown mask keeps the subject's edge colours out, so there's no halo.
    static func blurredBackground(source: CIImage, mask: CIImage) -> CIImage {
        let extent = source.extent
        let longEdge = max(extent.width, extent.height)
        let grown = mask
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: max(1, longEdge * 0.006)])
            .cropped(to: extent)
        let keep = CIFilter.blendWithMask()
        keep.inputImage = source
        keep.backgroundImage = CIImage(color: .clear).cropped(to: extent)
        keep.maskImage = grown.applyingFilter("CIColorInvert")
        let background = (keep.outputImage ?? source)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(longEdge * 0.013))
            .cropped(to: extent)
        return background.unpremultiplyingAlpha().settingAlphaOne(in: extent)
    }

    /// So the subjects sit on the new background instead of floating: a
    /// close, soft drop shadow of their shape, and a contact shadow where
    /// each meets the ground (its own shape pressed flat at the bottom of
    /// its bounds, so a pet beside her gets its own). Black on transparency,
    /// to go between the background and the subjects.
    static func shadow(of mask: CIImage, under subjects: [CGRect], extent: CGRect) -> CIImage {
        let longEdge = max(extent.width, extent.height)
        func layer(_ shape: CIImage, opacity: CGFloat) -> CIImage {
            let tint = CIFilter.blendWithMask()
            tint.inputImage = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: opacity)).cropped(to: extent)
            tint.backgroundImage = CIImage(color: .clear).cropped(to: extent)
            tint.maskImage = shape
            return tint.outputImage ?? CIImage(color: .clear).cropped(to: extent)
        }
        let drop = mask
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(longEdge * 0.012))
            .transformed(by: CGAffineTransform(translationX: 0, y: -longEdge * 0.008))
            .cropped(to: extent)
        var pressed = CIImage(color: .black).cropped(to: extent)
        for subject in subjects where !subject.isNull && !subject.isEmpty {
            // Core Image's y runs up, so the subject's bottom edge is at minY.
            let region = CGRect(x: extent.minX + (subject.minX - 0.02) * extent.width, y: extent.minY + (1 - subject.maxY) * extent.height,
                                width: (subject.width + 0.04) * extent.width, height: subject.height * extent.height)
            let ground = region.minY
            let flat = mask.cropped(to: region)
                .transformed(by: CGAffineTransform(translationX: 0, y: -ground)
                    .concatenating(CGAffineTransform(scaleX: 1, y: 0.1))
                    .concatenating(CGAffineTransform(translationX: 0, y: ground)))
            pressed = flat.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: pressed])
        }
        let contact = pressed
            .cropped(to: extent)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(longEdge * 0.018))
            .cropped(to: extent)
        return layer(contact, opacity: 0.4).composited(over: layer(drop, opacity: 0.22)).cropped(to: extent)
    }

    /// Renders a composite; opaque when the background is, so it saves as
    /// JPEG like any photo.
    static func render(_ image: CIImage, opaque: Bool) -> UIImage? {
        // Known-opaque output renders without an alpha channel. (A UIKit
        // "opaque" redraw kept one, so these saved as large PNGs.)
        let output = opaque ? image.settingAlphaOne(in: image.extent) : image
        return context.createCGImage(output, from: image.extent).map { UIImage(cgImage: $0) }
    }

    /// A sticker of the kept subjects: cropped to them, with a white outline
    /// and a soft shadow on a transparent background, about 1024 px.
    static func sticker(source: CIImage, mask: CIImage, bounds: CGRect) -> UIImage? {
        let extent = source.extent
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }
        let subject = CGRect(
            x: bounds.minX * extent.width, y: (1 - bounds.maxY) * extent.height,
            width: bounds.width * extent.width, height: bounds.height * extent.height
        )
        let side = max(subject.width, subject.height)
        let region = subject.insetBy(dx: -side * 0.08, dy: -side * 0.08)
        let scale = 1024 / max(region.width, region.height)
        let move = CGAffineTransform(translationX: -region.minX, y: -region.minY).concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let canvas = CGRect(x: 0, y: 0, width: (region.width * scale).rounded(), height: (region.height * scale).rounded())

        let cut = CIFilter.blendWithMask()
        cut.inputImage = Matte.foreground(of: source, matte: mask)
        cut.backgroundImage = CIImage(color: .clear).cropped(to: extent)
        cut.maskImage = mask
        guard let cutout = cut.outputImage?.cropped(to: extent).transformed(by: move) else { return nil }
        // Outside the photo the mask is empty, which reads as "not kept".
        let alpha = mask.transformed(by: move)
        let outlineWidth = max(canvas.width, canvas.height) * 0.028
        let outline = alpha
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: outlineWidth])
            .applyingGaussianBlur(sigma: 1.2)
            .cropped(to: canvas)
        let white = CIFilter.blendWithMask()
        white.inputImage = CIImage(color: .white).cropped(to: canvas)
        white.backgroundImage = CIImage(color: .clear).cropped(to: canvas)
        white.maskImage = outline
        let shadow = CIFilter.blendWithMask()
        shadow.inputImage = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.28)).cropped(to: canvas)
        shadow.backgroundImage = CIImage(color: .clear).cropped(to: canvas)
        shadow.maskImage = outline.applyingGaussianBlur(sigma: 10).transformed(by: CGAffineTransform(translationX: 0, y: -8))
        guard let whiteLayer = white.outputImage, let shadowLayer = shadow.outputImage else { return nil }
        let sticker = cutout.composited(over: whiteLayer.composited(over: shadowLayer)).cropped(to: canvas)
        return render(sticker, opaque: false)
    }

    // MARK: Backdrops

    /// A small swatch of a gradient for the backdrop row, drawn like the real thing.
    static func thumbnail(of gradient: CutoutGradient, side: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in drawGradient(gradient, size: size) }
    }

    private static func image(of size: CGSize, draw: (CGSize) -> Void) -> CIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(size) }
        return rendered.cgImage.map { CIImage(cgImage: $0) } ?? CIImage(color: CIColor(color: .brandPetal)).cropped(to: CGRect(origin: .zero, size: size))
    }

    private static func drawGradient(_ gradient: CutoutGradient, size: CGSize) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        let colors = gradient.colors
        let space = CGColorSpaceCreateDeviceRGB()
        switch gradient {
        case .auraGlow:
            UIColor.brandPetal.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            let radius = max(size.width, size.height) * 0.75
            if let glow = CGGradient(colorsSpace: space, colors: colors.map(\.cgColor) as CFArray, locations: [0, 0.45, 1]) {
                cg.drawRadialGradient(glow, startCenter: CGPoint(x: size.width / 2, y: size.height * 0.4), startRadius: 0,
                                      endCenter: CGPoint(x: size.width / 2, y: size.height * 0.4), endRadius: radius,
                                      options: [.drawsAfterEndLocation])
            }
        case .y2kGrid:
            if let sky = CGGradient(colorsSpace: space, colors: [UIColor.brandPetal.cgColor, UIColor.brandBlush.cgColor] as CFArray, locations: [0, 1]) {
                cg.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            let step = max(size.width, size.height) / 14
            cg.setStrokeColor(UIColor.auraLilac.withAlphaComponent(0.55).cgColor)
            cg.setLineWidth(max(1, step * 0.04))
            var x: CGFloat = 0
            while x <= size.width { cg.move(to: CGPoint(x: x, y: 0)); cg.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y <= size.height { cg.move(to: CGPoint(x: 0, y: y)); cg.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            cg.strokePath()
        default:
            let locations: [CGFloat] = colors.count == 3 ? [0, 0.55, 1] : [0, 1]
            if let linear = CGGradient(colorsSpace: space, colors: colors.map(\.cgColor) as CFArray, locations: locations) {
                cg.drawLinearGradient(linear, start: .zero, end: CGPoint(x: size.width * 0.3, y: size.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
        }
    }
}
