import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import AppCore

/// Vision's subject lifting for one photo: which subjects there are, where,
/// and their soft masks. Whole subjects only, never body parts. Vision's
/// handler isn't safe to share between threads, so mask requests go through
/// a lock; the editor throws the analysis away after any edit.
final class CutoutAnalysis: @unchecked Sendable {
    struct Subject: Identifiable, Sendable {
        /// Vision's instance label (0 is the background).
        let id: Int
        /// Normalized, top-left origin.
        let bounds: CGRect
    }

    /// The photo that was analysed (at most 2048 px, orientation baked in).
    let source: CGImage
    /// Left to right, so labels and VoiceOver read in order.
    let subjects: [Subject]
    let allIDs: IndexSet
    /// The photo was already a cut-out: there's nothing behind it to blur.
    let hasTransparency: Bool

    private let labels: [UInt8]
    private let labelWidth: Int
    private let labelHeight: Int
    private let lock = NSLock()
    /// Soft mask (white = keep) at the source's size for a set of labels.
    private let makeMask: (IndexSet) throws -> CIImage
    /// Each mask is a full-size float buffer (16 MB at 2048 px): keep a few.
    private var masks: [(ids: IndexSet, mask: CIImage)] = []

    init(source: CGImage, labels: [UInt8], labelWidth: Int, labelHeight: Int, makeMask: @escaping (IndexSet) throws -> CIImage) {
        self.source = source
        self.labels = labels
        self.labelWidth = labelWidth
        self.labelHeight = labelHeight
        self.makeMask = makeMask
        subjects = Self.subjects(in: labels, width: labelWidth, height: labelHeight)
        allIDs = IndexSet(subjects.map(\.id))
        hasTransparency = Self.hasTransparentPixels(source)
    }

    /// Core Image output always has an alpha channel, so look at the pixels.
    private static func hasTransparentPixels(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        let side = 64
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] < 250 }
    }

    /// Runs Vision (iOS 17+). Throws `noSubjectFound` when nothing stands out.
    static func analyze(_ image: UIImage) throws -> CutoutAnalysis {
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
        // The label map is small (a few hundred pixels), row 0 at the top.
        let buffer = observation.instanceMask
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else {
            throw AIServiceError.invalidResponse
        }
        var labels = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                labels[row * width + column] = base[row * rowBytes + column]
            }
        }
        return CutoutAnalysis(source: cgImage, labels: labels, labelWidth: width, labelHeight: height) { ids in
            let mask = try observation.generateScaledMaskForImage(forInstances: ids, from: handler)
            return CIImage(cvPixelBuffer: mask)
        }
    }

    func mask(for ids: IndexSet) throws -> CIImage {
        lock.lock()
        defer { lock.unlock() }
        if let cached = masks.first(where: { $0.ids == ids }) { return cached.mask }
        let mask = try makeMask(ids)
        masks.append((ids, mask))
        if masks.count > 3 { masks.removeFirst() }
        return mask
    }

    /// The subject under a normalized point (top-left origin), or nil on the
    /// background. Looks at a 5×5 patch so taps on hair and edges still count.
    func subject(atNormalized point: CGPoint) -> Int? {
        let x = Int((min(max(point.x, 0), 1) * CGFloat(labelWidth - 1)).rounded())
        let y = Int((min(max(point.y, 0), 1) * CGFloat(labelHeight - 1)).rounded())
        var counts: [UInt8: Int] = [:]
        for dy in -2...2 {
            for dx in -2...2 {
                let px = x + dx, py = y + dy
                guard px >= 0, py >= 0, px < labelWidth, py < labelHeight else { continue }
                let label = labels[py * labelWidth + px]
                if label != 0 { counts[label, default: 0] += 1 }
            }
        }
        guard let best = counts.max(by: { $0.value < $1.value }) else { return nil }
        return Int(best.key)
    }

    /// Normalized bounds of the chosen subjects together.
    func bounds(of ids: IndexSet) -> CGRect {
        subjects.filter { ids.contains($0.id) }.map(\.bounds).reduce(CGRect.null) { $0.union($1) }
    }

    /// Thin outlines around each subject at the label map's size: white for
    /// the kept ones, blush for the others.
    func outlines(kept ids: IndexSet) -> CGImage? {
        let width = labelWidth, height = labelHeight
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let label = labels[y * width + x]
                guard label != 0 else { continue }
                var isEdge = false
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1), (-2, 0), (2, 0), (0, -2), (0, 2)] {
                    let nx = x + dx, ny = y + dy
                    if nx < 0 || ny < 0 || nx >= width || ny >= height || labels[ny * width + nx] != label {
                        isEdge = true
                        break
                    }
                }
                guard isEdge else { continue }
                let offset = (y * width + x) * 4
                // Premultiplied RGBA: white, or blush (#F7C1D9).
                let color: (UInt8, UInt8, UInt8) = ids.contains(Int(label)) ? (255, 255, 255) : (247, 193, 217)
                pixels[offset] = color.0
                pixels[offset + 1] = color.1
                pixels[offset + 2] = color.2
                pixels[offset + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    private static func subjects(in labels: [UInt8], width: Int, height: Int) -> [Subject] {
        var boxes: [UInt8: (minX: Int, minY: Int, maxX: Int, maxY: Int, sumX: Int, count: Int)] = [:]
        for y in 0..<height {
            for x in 0..<width {
                let label = labels[y * width + x]
                guard label != 0 else { continue }
                var box = boxes[label] ?? (x, y, x, y, 0, 0)
                box.minX = min(box.minX, x); box.maxX = max(box.maxX, x)
                box.minY = min(box.minY, y); box.maxY = max(box.maxY, y)
                box.sumX += x; box.count += 1
                boxes[label] = box
            }
        }
        let w = CGFloat(max(width, 1)), h = CGFloat(max(height, 1))
        return boxes
            // Specks of a few pixels aren't something she could tap.
            .filter { $0.value.count > 12 }
            .sorted { Double($0.value.sumX) / Double($0.value.count) < Double($1.value.sumX) / Double($1.value.count) }
            .map { label, box in
                Subject(id: Int(label), bounds: CGRect(
                    x: CGFloat(box.minX) / w, y: CGFloat(box.minY) / h,
                    width: CGFloat(box.maxX - box.minX + 1) / w, height: CGFloat(box.maxY - box.minY + 1) / h
                ))
            }
    }
}

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

/// Puts the cut-out on its new background, and makes stickers. Every
/// function is pure and safe off the main thread, and works at any scale, so
/// the preview matches the final image.
enum CutoutRenderer {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// The kept subjects (`mask`) over `backdrop`, at `source`'s extent.
    static func composite(source: CIImage, mask: CIImage, backdrop: CutoutBackdrop, color: UIColor?, photo: UIImage?) -> CIImage {
        let extent = source.extent
        let background: CIImage
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
        let blend = CIFilter.blendWithMask()
        blend.inputImage = source
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

    /// Renders a composite; opaque when the background is, so it saves as
    /// JPEG like any photo.
    static func render(_ image: CIImage, opaque: Bool) -> UIImage? {
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
        guard opaque else { return UIImage(cgImage: cgImage) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
        }
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
        cut.inputImage = source
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
