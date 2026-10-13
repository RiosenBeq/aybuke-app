import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import AppCore

// MARK: - Subject analysis

/// Where the person is in a photo: face-aware crops for the cover and the
/// photo strip, and a cut-out so the cover's masthead can sit behind her
/// head like a real magazine. Vision, on the device; nothing is uploaded.
struct SubjectAnalysis {
    /// The largest face, normalized, with a top-left origin.
    var face: CGRect?
    /// The photo with everything but people transparent.
    var cutout: UIImage?
    /// Person mask (white = person), with the photo's extent.
    private var mask: CIImage?

    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func analyze(_ image: UIImage, includingCutout: Bool) -> SubjectAnalysis {
        guard let cgImage = image.cgImage else { return SubjectAnalysis() }
        var result = SubjectAnalysis()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let faces = VNDetectFaceRectanglesRequest()
        try? handler.perform([faces])
        if let face = faces.results?.max(by: { area($0.boundingBox) < area($1.boundingBox) }) {
            let box = face.boundingBox
            result.face = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        }
        guard includingCutout, result.face != nil else { return result }

        let segmentation = VNGeneratePersonSegmentationRequest()
        segmentation.qualityLevel = .balanced
        segmentation.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try? handler.perform([segmentation])
        guard let buffer = segmentation.results?.first?.pixelBuffer else { return result }
        let source = CIImage(cgImage: cgImage)
        let raw = CIImage(cvPixelBuffer: buffer)
        let mask = raw.transformed(by: CGAffineTransform(
            scaleX: source.extent.width / raw.extent.width,
            y: source.extent.height / raw.extent.height
        ))
        let blend = CIFilter.blendWithMask()
        blend.inputImage = source
        blend.backgroundImage = CIImage(color: .clear).cropped(to: source.extent)
        blend.maskImage = mask
        if let output = blend.outputImage, let cutout = context.createCGImage(output, from: source.extent) {
            result.cutout = UIImage(cgImage: cutout)
            result.mask = mask
        }
        return result
    }

    /// Share of `rect` (normalized, top-left origin) covered by people, 0…1.
    func personCoverage(in rect: CGRect) -> CGFloat {
        guard let mask else { return 0 }
        return Self.average(of: mask, in: rect)?.red ?? 0
    }

    /// Relative luminance of `rect` (normalized, top-left origin), 0…1.
    static func luminance(of image: UIImage, in rect: CGRect) -> CGFloat? {
        guard let cgImage = image.cgImage, let color = average(of: CIImage(cgImage: cgImage), in: rect) else { return nil }
        return 0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
    }

    private static func average(of image: CIImage, in rect: CGRect) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        let extent = image.extent
        let clamped = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clamped.isNull, clamped.width > 0, clamped.height > 0 else { return nil }
        let region = CGRect(
            x: extent.minX + clamped.minX * extent.width,
            y: extent.minY + (1 - clamped.maxY) * extent.height,
            width: clamped.width * extent.width,
            height: clamped.height * extent.height
        )
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = region
        guard let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }
}

// MARK: - Cover star & photo strip

extension ShareRenderer {
    static let coverSize = CGSize(width: 1080, height: 1350)

    /// Aspect-fills `imageSize` into `frame`, with the face's centre at
    /// `faceAnchor` (fractions of the frame) when there is one. Never leaves
    /// an empty edge.
    static func fillRect(for imageSize: CGSize, in frame: CGRect, face: CGRect?, faceAnchor: CGPoint = CGPoint(x: 0.5, y: 0.42)) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return frame }
        let scale = max(frame.width / imageSize.width, frame.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        var origin = CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
        if let face {
            origin.x = frame.minX + frame.width * faceAnchor.x - face.midX * size.width
            origin.y = frame.minY + frame.height * faceAnchor.y - face.midY * size.height
        }
        origin.x = min(frame.minX, max(frame.maxX - size.width, origin.x))
        origin.y = min(frame.minY, max(frame.maxY - size.height, origin.y))
        return CGRect(origin: origin, size: size)
    }

    /// "Cover star": a 4:5 magazine cover. When Vision finds a person, the
    /// masthead tucks behind her head like a real cover. Cover lines, a
    /// "100% you" sticker and a barcode finish it. Feed-ready.
    static func magazineCover(_ image: UIImage, branded: Bool, date: Date = Date()) -> UIImage {
        let canvas = coverSize
        let subject = SubjectAnalysis.analyze(image, includingCutout: true)
        let photo = fillRect(for: image.size, in: CGRect(origin: .zero, size: canvas), face: subject.face, faceAnchor: CGPoint(x: 0.5, y: 0.46))

        let band = CGRect(x: 36, y: 30, width: canvas.width - 72, height: 280)
        let bandInPhoto = CGRect(
            x: (band.minX - photo.minX) / photo.width,
            y: (band.minY - photo.minY) / photo.height,
            width: band.width / photo.width,
            height: band.height / photo.height
        )
        let topIsLight = (SubjectAnalysis.luminance(of: image, in: bandInPhoto) ?? 0) > 0.62
        let coverage = subject.personCoverage(in: bandInPhoto)
        // Behind her head only when that still leaves most of the word readable.
        let tucksBehind = subject.cutout != nil && coverage > 0.02 && coverage < 0.36
        let ink: UIColor = topIsLight ? .brandInk : .white

        return renderer(canvas, opaque: true).image { context in
            let cg = context.cgContext
            image.draw(in: photo)
            shade(cg, from: canvas.height - 640, to: canvas.height, width: canvas.width, alpha: 0.6)

            drawMasthead(String(localized: "GLOW", comment: "Magazine cover masthead"), in: band, color: ink, context: cg)
            if tucksBehind, let cutout = subject.cutout {
                cg.saveGState()
                cg.clip(to: CGRect(x: 0, y: 0, width: canvas.width, height: band.maxY))
                cutout.draw(in: photo)
                cg.restoreGState()
            }

            let month = date.formatted(.dateTime.month(.wide).year()).uppercased()
            let issue = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
            drawLeft(String(localized: "THE GLOW-UP ISSUE  ·  \(month)  ·  Nº \(issue)"),
                     font: brandFont(22, weight: .heavy), color: ink, at: CGPoint(x: 48, y: band.maxY - 4), kern: 3, shadow: !topIsLight)

            // Cover lines, bottom left.
            let left: CGFloat = 52
            drawPill(String(localized: "THE GLOW ISSUE"), font: brandFont(24, weight: .heavy), fill: .brandBlush, color: .brandInk,
                     at: CGPoint(x: left, y: 806), kern: 2)
            drawLeft(String(localized: "Main character\nenergy", comment: "Magazine cover headline, two short lines"),
                     font: accentFont(84), color: .white, at: CGPoint(x: left, y: 862), maxWidth: 700, shadow: true, lineHeight: 0.98)
            drawLeft(String(localized: "10 looks that are so you"), font: brandFont(34, weight: .bold), color: .white,
                     at: CGPoint(x: left, y: 1080), maxWidth: 640, shadow: true)
            drawLeft(String(localized: "Glow-up secrets, unlocked"), font: brandFont(30, weight: .semibold), color: .white,
                     at: CGPoint(x: left, y: 1128), maxWidth: 640, shadow: true)
            if branded {
                drawLeft(String(localized: "Made with \(Brand.name) ✦"), font: brandFont(24, weight: .semibold), color: UIColor.white.withAlphaComponent(0.92),
                         at: CGPoint(x: left, y: canvas.height - 82), shadow: true)
            }

            drawSticker(String(localized: "100%\nYOU", comment: "Round sticker on the magazine cover"),
                        center: CGPoint(x: canvas.width - 170, y: 720), radius: 104, fill: .auraButter, context: cg)
            drawBarcode(in: CGRect(x: canvas.width - 48 - 176, y: canvas.height - 48 - 92, width: 176, height: 92), seed: issue, context: cg)
        }
    }

    /// "Photo strip": two to four frames in a black booth strip on a pink
    /// story background, date-stamped like a real photo booth.
    static func photoStrip(_ images: [UIImage], branded: Bool, date: Date = Date()) -> UIImage {
        let canvas = storySize
        let frames = Array(images.prefix(4))
        let count = CGFloat(max(frames.count, 1))
        let gap: CGFloat = 26
        let footer: CGFloat = 116
        let height: CGFloat = 1430
        let frameHeight = ((height - footer - gap * (count + 1)) / count).rounded(.down)
        let frameWidth = (frameHeight * 0.8).rounded()
        let strip = CGRect(x: ((canvas.width - frameWidth - gap * 2) / 2).rounded(), y: 245, width: frameWidth + gap * 2, height: height)

        return renderer(canvas, opaque: true).image { context in
            let cg = context.cgContext
            let colors = [UIColor.brandBlush.cgColor, UIColor.brandPetal.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: canvas.height), options: [])
            }
            radialGlow(cg, center: CGPoint(x: 150, y: 360), radius: 640, color: .white, alpha: 0.7)
            radialGlow(cg, center: CGPoint(x: 960, y: 1620), radius: 640, color: .auraLilac, alpha: 0.3)
            scatterDoodles(in: canvas, avoiding: strip.insetBy(dx: -40, dy: -20))

            cg.saveGState()
            cg.translateBy(x: strip.midX, y: strip.midY)
            cg.rotate(by: -3 * .pi / 180)
            cg.translateBy(x: -strip.midX, y: -strip.midY)
            cg.setShadow(offset: CGSize(width: 0, height: 24), blur: 48, color: UIColor.brandInk.withAlphaComponent(0.28).cgColor)
            UIColor.brandInk.setFill()
            cg.fill(strip)
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            for (index, image) in frames.enumerated() {
                let frame = CGRect(x: strip.minX + gap, y: strip.minY + gap + CGFloat(index) * (frameHeight + gap), width: frameWidth, height: frameHeight)
                let face = SubjectAnalysis.analyze(image, includingCutout: false).face
                cg.saveGState()
                cg.clip(to: frame)
                image.draw(in: fillRect(for: image.size, in: frame, face: face, faceAnchor: CGPoint(x: 0.5, y: 0.45)))
                cg.restoreGState()
            }
            let stamp = date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits))
            let label = branded ? "\(Brand.name.uppercased()) ✦ \(stamp)" : "✦ \(stamp) ✦"
            let typewriter = UIFont(name: "Courier-Bold", size: 34) ?? .monospacedSystemFont(ofSize: 34, weight: .bold)
            drawText(label, font: typewriter, color: .white,
                     centeredIn: CGRect(x: strip.minX, y: strip.maxY - footer, width: strip.width, height: footer - gap / 2))
            cg.restoreGState()

            drawSymbol("heart.fill", in: CGRect(x: strip.maxX - 54, y: strip.minY - 58, width: 118, height: 118), color: .auraPink, outline: .white, angle: 14)
            drawSymbol("sparkle", in: CGRect(x: strip.minX - 70, y: strip.maxY - 150, width: 128, height: 128), color: .auraButter, outline: .white, angle: -10)
        }
    }

    // MARK: Cover parts

    /// The masthead, fitted to the band's width.
    private static func drawMasthead(_ text: String, in band: CGRect, color: UIColor, context: CGContext) {
        let probe = brandFont(100, weight: .heavy)
        let probeWidth = (text as NSString).size(withAttributes: [.font: probe, .kern: -4]).width
        let size = min(300, 100 * band.width / max(probeWidth, 1))
        let font = brandFont(size, weight: .heavy)
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(color == .white ? 0.22 : 0)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = CGSize(width: 0, height: 6)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: -size * 0.04, .shadow: shadow]
        let measured = (text as NSString).size(withAttributes: attributes)
        // Poppins' line box is tall: lift it so the caps sit at the band's top.
        let origin = CGPoint(x: band.midX - measured.width / 2, y: band.minY - font.ascender + font.capHeight - size * 0.02)
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    private static func drawSticker(_ text: String, center: CGPoint, radius: CGFloat, fill: UIColor, context cg: CGContext) {
        cg.saveGState()
        cg.translateBy(x: center.x, y: center.y)
        cg.rotate(by: 12 * .pi / 180)
        let circle = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
        cg.setShadow(offset: CGSize(width: 0, height: 12), blur: 24, color: UIColor.black.withAlphaComponent(0.25).cgColor)
        UIColor.white.setFill()
        cg.fillEllipse(in: circle.insetBy(dx: -7, dy: -7))
        cg.setShadow(offset: .zero, blur: 0, color: nil)
        fill.setFill()
        cg.fillEllipse(in: circle)
        drawText(text, font: brandFont(radius * 0.42, weight: .heavy), color: .brandInk, centeredIn: circle.insetBy(dx: 10, dy: 22), lines: 2)
        cg.restoreGState()
    }

    private static func drawBarcode(in rect: CGRect, seed: Int, context cg: CGContext) {
        UIColor.white.setFill()
        cg.fill(rect)
        var generator = SplitMix64(seed: UInt64(seed) &* 2_654_435_761)
        var x = rect.minX + 10
        let barTop = rect.minY + 10
        let barHeight = rect.height - 34
        UIColor.brandInk.setFill()
        while x < rect.maxX - 12 {
            let width = CGFloat(1 + generator.next() % 4)
            cg.fill(CGRect(x: x, y: barTop, width: width, height: barHeight))
            x += width + CGFloat(1 + generator.next() % 3)
        }
        drawText("GLOW · Nº \(seed)", font: brandFont(15, weight: .bold), color: .brandInk,
                 centeredIn: CGRect(x: rect.minX, y: rect.maxY - 24, width: rect.width, height: 20))
    }

    // MARK: Shared drawing

    /// Black fading in from `top` to `bottom`, for legible white type.
    static func shade(_ cg: CGContext, from top: CGFloat, to bottom: CGFloat, width: CGFloat, alpha: CGFloat) {
        let colors = [UIColor.black.withAlphaComponent(0).cgColor, UIColor.black.withAlphaComponent(alpha).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        cg.saveGState()
        cg.clip(to: CGRect(x: 0, y: top, width: width, height: bottom - top))
        cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: [])
        cg.restoreGState()
    }

    static func drawLeft(
        _ text: String, font: UIFont, color: UIColor, at origin: CGPoint, maxWidth: CGFloat = 980,
        kern: CGFloat = 0, shadow: Bool = false, lineHeight: CGFloat = 1
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = lineHeight
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern, .paragraphStyle: paragraph]
        if shadow {
            let textShadow = NSShadow()
            textShadow.shadowColor = UIColor.black.withAlphaComponent(0.35)
            textShadow.shadowBlurRadius = font.pointSize * 0.3
            textShadow.shadowOffset = CGSize(width: 0, height: 2)
            attributes[.shadow] = textShadow
        }
        let string = NSAttributedString(string: text, attributes: attributes)
        let bounds = string.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        string.draw(with: CGRect(origin: origin, size: CGSize(width: maxWidth, height: ceil(bounds.height))), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    static func drawPill(_ text: String, font: UIFont, fill: UIColor, color: UIColor, at origin: CGPoint, kern: CGFloat = 0) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding = CGSize(width: font.pointSize * 0.75, height: font.pointSize * 0.35)
        let pill = CGRect(x: origin.x, y: origin.y, width: size.width + padding.width * 2, height: size.height + padding.height * 2)
        fill.setFill()
        UIBezierPath(roundedRect: pill, cornerRadius: pill.height / 2).fill()
        (text as NSString).draw(at: CGPoint(x: pill.minX + padding.width, y: pill.minY + padding.height), withAttributes: attributes)
    }

    /// An SF Symbol drawn like a sticker: a white outline, then the colour.
    static func drawSymbol(_ name: String, in rect: CGRect, color: UIColor, outline: UIColor? = nil, angle: CGFloat = 0) {
        guard let cg = UIGraphicsGetCurrentContext(),
              let symbol = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: rect.height, weight: .bold)) else { return }
        cg.saveGState()
        cg.translateBy(x: rect.midX, y: rect.midY)
        cg.rotate(by: angle * .pi / 180)
        let fitted = scaled(symbol.size, toFit: rect.size)
        let frame = CGRect(x: -fitted.width / 2, y: -fitted.height / 2, width: fitted.width, height: fitted.height)
        if let outline {
            let border = rect.height * 0.06
            let tinted = symbol.withTintColor(outline, renderingMode: .alwaysOriginal)
            for dx in [-border, 0, border] {
                for dy in [-border, 0, border] where dx != 0 || dy != 0 {
                    tinted.draw(in: frame.offsetBy(dx: dx, dy: dy))
                }
            }
        }
        symbol.withTintColor(color, renderingMode: .alwaysOriginal).draw(in: frame)
        cg.restoreGState()
    }

    /// Small hearts and sparkles around the edges of a story background.
    static func scatterDoodles(in canvas: CGSize, avoiding keepOut: CGRect) {
        let doodles: [(String, CGPoint, CGFloat, UIColor, CGFloat)] = [
            ("sparkle", CGPoint(x: 120, y: 420), 70, .white, 0),
            ("heart.fill", CGPoint(x: 950, y: 520), 54, UIColor.auraPink.withAlphaComponent(0.85), 12),
            ("sparkle", CGPoint(x: 980, y: 860), 46, .white, 0),
            ("heart.fill", CGPoint(x: 110, y: 980), 44, UIColor.white.withAlphaComponent(0.9), -10),
            ("sparkle", CGPoint(x: 160, y: 1400), 56, UIColor.auraButter, 0),
            ("heart.fill", CGPoint(x: 960, y: 1330), 60, UIColor.auraPink.withAlphaComponent(0.85), -8),
            ("sparkle", CGPoint(x: 900, y: 300), 40, .white, 0),
        ]
        for (name, center, size, color, angle) in doodles {
            let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
            guard !rect.intersects(keepOut) else { continue }
            drawSymbol(name, in: rect, color: color, angle: angle)
        }
    }
}

// MARK: - Invite card

/// "Share Glowlit": a 9:16 story card with the app icon, what the app does
/// and a QR code. Made from brand art only — never the user's photos.
enum InviteCard {
    static func render(link: URL?) -> UIImage {
        let canvas = ShareRenderer.storySize
        return ShareRenderer.renderer(canvas, opaque: true).image { context in
            let cg = context.cgContext
            let aura = [UIColor.auraMint, .auraLilac, .auraPink, .auraPeach].map(\.cgColor) as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: aura, locations: [0, 0.4, 0.75, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: canvas.width, y: canvas.height), options: [])
            }
            // Pastel it down so ink type reads everywhere.
            UIColor.white.withAlphaComponent(0.38).setFill()
            cg.fill(CGRect(origin: .zero, size: canvas))
            ShareRenderer.radialGlow(cg, center: CGPoint(x: 160, y: 260), radius: 700, color: .white, alpha: 0.7)
            ShareRenderer.radialGlow(cg, center: CGPoint(x: 1000, y: 1700), radius: 620, color: .auraButter, alpha: 0.5)
            ShareRenderer.scatterDoodles(in: canvas, avoiding: CGRect(x: 180, y: 240, width: 720, height: 1440))

            // App icon
            let icon = CGRect(x: (canvas.width - 236) / 2, y: 250, width: 236, height: 236)
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: UIColor.plum.withAlphaComponent(0.35).cgColor)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: icon, cornerRadius: icon.width * 0.225).fill()
            cg.restoreGState()
            cg.saveGState()
            UIBezierPath(roundedRect: icon, cornerRadius: icon.width * 0.225).addClip()
            UIImage(named: "BrandIcon")?.draw(in: icon)
            cg.restoreGState()

            ShareRenderer.drawText(Brand.name, font: ShareRenderer.brandFont(112, weight: .heavy), color: .brandInk,
                                   centeredIn: CGRect(x: 0, y: 506, width: canvas.width, height: 140))
            ShareRenderer.drawText(String(localized: "Make it glow."), font: ShareRenderer.accentFont(62), color: .brandInk,
                                   centeredIn: CGRect(x: 0, y: 638, width: canvas.width, height: 84))

            let features = [
                String(localized: "✨ AI glow-ups"),
                String(localized: "📼 80s & 90s effects"),
                String(localized: "🎬 Easy video edits"),
                String(localized: "🔒 Private by default"),
            ]
            drawPillRow(Array(features.prefix(2)), centerY: 790, width: canvas.width)
            drawPillRow(Array(features.suffix(2)), centerY: 884, width: canvas.width)

            drawPrints(cg, top: 966, width: canvas.width)
            drawLinkCard(cg, link: link, frame: CGRect(x: 120, y: 1420, width: canvas.width - 240, height: 236))
        }
    }

    /// Message that travels with the card in Messages, WhatsApp and friends.
    static func message(link: URL?) -> String {
        let pitch = String(localized: "I edit my photos with Glowlit ✨ AI glow-ups, 80s & 90s effects and easy video edits. Free to start.")
        guard let link else { return pitch + " " + String(localized: "Find “Glowlit” on the App Store.") }
        return pitch + "\n" + link.absoluteString
    }

    private static func drawPillRow(_ titles: [String], centerY: CGFloat, width: CGFloat) {
        let font = ShareRenderer.brandFont(32, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.brandInk]
        let sizes = titles.map { ($0 as NSString).size(withAttributes: attributes) }
        let padding: CGFloat = 26
        let spacing: CGFloat = 16
        let height: CGFloat = 70
        let total = sizes.reduce(0) { $0 + $1.width + padding * 2 } + spacing * CGFloat(max(0, titles.count - 1))
        var x = (width - total) / 2
        for (title, size) in zip(titles, sizes) {
            let pill = CGRect(x: x, y: centerY - height / 2, width: size.width + padding * 2, height: height)
            UIColor.white.withAlphaComponent(0.88).setFill()
            UIBezierPath(roundedRect: pill, cornerRadius: height / 2).fill()
            (title as NSString).draw(at: CGPoint(x: pill.minX + padding, y: pill.midY - size.height / 2), withAttributes: attributes)
            x = pill.maxX + spacing
        }
    }

    /// A fan of three prints made from the demo art (never real photos).
    private static func drawPrints(_ cg: CGContext, top: CGFloat, width: CGFloat) {
        let styles = ["pastel", "kawaii", "fantasy"].map { StyleCatalog.style(id: $0) }
        let size = CGSize(width: 238, height: 300)
        let placements: [(dx: CGFloat, dy: CGFloat, angle: CGFloat, style: Int)] = [(-236, 34, -10, 0), (236, 34, 10, 2), (0, 0, 0, 1)]
        for placement in placements {
            let art = DemoArt.render(prompt: "Glowlit invite", style: styles[placement.style], size: AspectRatio.portrait.pixelSize(longEdge: 600), variant: placement.style)
            let frame = CGRect(x: width / 2 + placement.dx - size.width / 2, y: top + placement.dy, width: size.width, height: size.height)
            cg.saveGState()
            cg.translateBy(x: frame.midX, y: frame.midY)
            cg.rotate(by: placement.angle * .pi / 180)
            cg.translateBy(x: -frame.midX, y: -frame.midY)
            cg.setShadow(offset: CGSize(width: 0, height: 16), blur: 32, color: UIColor.plum.withAlphaComponent(0.3).cgColor)
            UIColor.white.setFill()
            cg.fill(CGRect(x: frame.minX - 14, y: frame.minY - 14, width: frame.width + 28, height: frame.height + 48))
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            cg.saveGState()
            cg.clip(to: frame)
            art.draw(in: ShareRenderer.fillRect(for: art.size, in: frame, face: nil))
            cg.restoreGState()
            cg.restoreGState()
        }
    }

    private static func drawLinkCard(_ cg: CGContext, link: URL?, frame: CGRect) {
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 14), blur: 32, color: UIColor.plum.withAlphaComponent(0.2).cgColor)
        UIColor.white.setFill()
        UIBezierPath(roundedRect: frame, cornerRadius: 44).fill()
        cg.restoreGState()

        guard let link, let code = QRCode.image(for: link.absoluteString, side: 184) else {
            ShareRenderer.drawText(String(localized: "Find “Glowlit” on the App Store"), font: ShareRenderer.brandFont(40, weight: .bold),
                                   color: .brandInk, centeredIn: frame.insetBy(dx: 30, dy: 30), lines: 2)
            return
        }
        let qr = CGRect(x: frame.minX + 26, y: frame.midY - 92, width: 184, height: 184)
        cg.interpolationQuality = .none
        code.draw(in: qr)
        cg.interpolationQuality = .default
        let textX = qr.maxX + 30
        let textWidth = frame.maxX - 30 - textX
        ShareRenderer.drawLeft(String(localized: "Scan to get Glowlit"), font: ShareRenderer.brandFont(40, weight: .heavy), color: .brandInk,
                               at: CGPoint(x: textX, y: frame.minY + 42), maxWidth: textWidth)
        ShareRenderer.drawLeft(String(localized: "Free on the App Store"), font: ShareRenderer.brandFont(30, weight: .semibold),
                               color: UIColor(hex: 0x5C5457), at: CGPoint(x: textX, y: frame.minY + 104), maxWidth: textWidth)
        let host = (link.host() ?? link.absoluteString).replacingOccurrences(of: "www.", with: "")
        ShareRenderer.drawLeft(host, font: ShareRenderer.brandFont(24, weight: .semibold), color: UIColor(hex: 0x6E6468),
                               at: CGPoint(x: textX, y: frame.minY + 152), maxWidth: textWidth)
    }
}

// MARK: - QR code

enum QRCode {
    /// A crisp QR code (ink on white), `side` points square.
    static func image(for text: String, side: CGFloat) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let colored = output.applyingFilter("CIFalseColor", parameters: [
            "inputColor0": CIColor(red: 0.07, green: 0.07, blue: 0.07),
            "inputColor1": CIColor(red: 1, green: 1, blue: 1),
        ])
        let scale = max(1, floor(side / output.extent.width))
        let scaled = colored.samplingNearest().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
