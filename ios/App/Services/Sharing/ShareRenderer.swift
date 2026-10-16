import UIKit
import CoreImage
import AppCore

/// What the user is sharing. `original` enables the Before / After collage.
struct SharePayload: Identifiable {
    let id = UUID()
    var image: UIImage
    var original: UIImage?
    let operation: AIOperation?
    var prompt: String?
    /// A cut-out placed on another photo (IPTC "composite").
    var isComposite = false
    /// Other variations from the same creation, for "Which vibe?".
    var alternatives: [UIImage] = []
    /// The AI marking the source file already carried (see `Provenance`).
    var inheritedSourceType: DigitalSourceType? = nil
    /// Shared straight from My Works or Create, not from the editor (which
    /// has Hide faces): the composer offers "Hide other faces".
    var offersHidingFaces = false

    /// Decides the IPTC field, the free-tier branding, the AI hashtags and
    /// the AI label.
    var provenance: Provenance { Provenance(operation: operation, inheritedSourceType: inheritedSourceType, isComposite: isComposite) }

    /// Photo strip frames: the original first, then the glow-up and its
    /// variations (up to four).
    var stripImages: [UIImage] {
        Array(([original].compactMap { $0 } + [image] + alternatives).prefix(4))
    }

    /// "Which vibe?": two variations of one creation. Never her original
    /// photo against an edit: friends would be voting on her face.
    var pickPair: (a: UIImage, b: UIImage)? {
        alternatives.first.map { (image, $0) }
    }

    /// Prompts are only offered on the card for text-to-image creations;
    /// edit instructions can be personal.
    var shareablePrompt: String? {
        guard operation == .textToImage, let prompt = prompt.map({ PromptBuilder.sanitize($0) }), !prompt.isEmpty else { return nil }
        return prompt
    }
}

enum ShareFormat: String, CaseIterable, Identifiable {
    case photo
    case beforeAfter
    case story
    case cover
    case strip
    case pick

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: return String(localized: "Photo")
        case .beforeAfter: return String(localized: "Before / After")
        case .story: return String(localized: "Story card")
        case .cover: return String(localized: "Cover star")
        case .strip: return String(localized: "Photo strip")
        case .pick: return String(localized: "Which vibe?")
        }
    }

    var symbolName: String {
        switch self {
        case .photo: return "photo"
        case .beforeAfter: return "square.split.2x1"
        case .story: return "rectangle.portrait"
        case .cover: return "magazine"
        case .strip: return "film"
        case .pick: return "a.circle"
        }
    }

    /// The Photo and the Story card come in every size (`ShareSize`).
    var offersSizes: Bool { self == .photo || self == .story }

    /// Text she can change on this design.
    var textSlots: [ShareTextSlot] {
        switch self {
        case .story: return [.storyLine]
        case .cover: return [.coverHeadline, .coverMasthead]
        case .strip: return [.stripCaption]
        case .photo, .beforeAfter, .pick: return []
        }
    }
}

/// What she changed on a design: its size, its background and its text.
/// Empty, every design looks as it always has.
struct ShareDesign: Equatable, Sendable {
    /// For the Photo and the Story card; the others keep their own shape.
    var size: ShareSize = .original
    /// nil: the design's own (the blurred photo around a padded Photo, the
    /// brand glow on cards).
    var backdrop: ShareBackdrop?
    /// Her words, already through `ContentPolicy`; a missing slot shows the design's own.
    var texts: [ShareTextSlot: String] = [:]
    var font: OverlayFont?
    var color: OverlayColor?

    func text(_ slot: ShareTextSlot) -> String? {
        texts[slot].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The Story card's size: Stories unless she picked another.
    var cardSize: ShareSize { size == .original ? .story : size }
}

extension CanvasRect {
    init(_ rect: CGRect) {
        self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// Renders share formats. Free exports of Aybuke's cloud AI results carry
/// Aybuke branding (the corner watermark, or a "Made with Aybuke" line on
/// collages and cards); on-device edits and Pro never do. Pure functions,
/// safe off the main thread.
enum ShareRenderer {
    static func render(_ payload: SharePayload, format: ShareFormat, branded: Bool, showPrompt: Bool, aiLabel: Bool = false,
                       design: ShareDesign = ShareDesign()) -> UIImage {
        let rendered = render(payload, format: format, branded: branded, showPrompt: showPrompt, design: design)
        let provenance = payload.provenance
        guard aiLabel, provenance.carriesAIProvenance else { return rendered }
        let reservedBottom: CGFloat
        // Clear of TikTok's left edge too, where a design keeps clear of its buttons.
        var reservedLeft: CGFloat = 0
        switch format {
        case .story:
            reservedBottom = ShareLayout.labelReserve(size: design.cardSize, isCard: true)
            reservedLeft = design.cardSize.safeInsets.left
        case .strip, .pick: reservedBottom = 300
        case .cover: reservedBottom = 70
        case .photo:
            reservedBottom = ShareLayout.labelReserve(size: design.size, isCard: false)
            reservedLeft = ShareLayout.photoInsets(size: design.size).left
        case .beforeAfter: reservedBottom = 0
        }
        return addAILabel(to: rendered, text: provenance.isFullyGenerated ? String(localized: "Made with AI") : String(localized: "AI-edited"),
                          reservedBottom: reservedBottom, reservedLeft: reservedLeft)
    }

    private static func render(_ payload: SharePayload, format: ShareFormat, branded: Bool, showPrompt: Bool, design: ShareDesign) -> UIImage {
        let image = ImageUtilities.normalized(payload.image, maxLongEdge: 2048)
        switch format {
        case .photo:
            // Sized for where she posts: the whole photo, the room around it
            // filled; at TikTok's size the photo and the mark keep clear of its buttons.
            guard let pixels = design.size.pixelSize, let area = ShareLayout.photoArea(size: design.size) else {
                return branded ? Watermark.apply(to: image) : image
            }
            let padded = paddedPhoto(image, canvas: CGSize(width: pixels.width, height: pixels.height), area: area,
                                     backdrop: design.backdrop ?? .blur)
            let insets = ShareLayout.photoInsets(size: design.size)
            return branded ? Watermark.apply(to: padded, insets: UIEdgeInsets(top: insets.top, left: insets.left,
                                                                              bottom: insets.bottom, right: insets.right)) : padded
        case .beforeAfter:
            guard let original = payload.original else { return branded ? Watermark.apply(to: image) : image }
            return beforeAfter(before: ImageUtilities.normalized(original, maxLongEdge: 2048), after: image, branded: branded)
        case .story:
            return storyCard(image, prompt: showPrompt ? payload.shareablePrompt : nil, branded: branded, design: design)
        case .cover:
            return magazineCover(image, branded: branded, design: design)
        case .strip:
            let frames = payload.stripImages.map { ImageUtilities.normalized($0, maxLongEdge: 1400) }
            guard frames.count >= 2 else { return storyCard(image, prompt: nil, branded: branded) }
            return photoStrip(frames, branded: branded, design: design)
        case .pick:
            guard let pair = payload.pickPair else { return storyCard(image, prompt: nil, branded: branded) }
            return pickCard(
                a: ImageUtilities.normalized(pair.a, maxLongEdge: 1400),
                b: ImageUtilities.normalized(pair.b, maxLongEdge: 1400),
                branded: branded
            )
        }
    }

    // MARK: Visible AI label

    /// An honest, visible "✦ AI-edited" pill in the bottom-left corner, for
    /// people who want their followers to know (on top of the invisible
    /// IPTC label every export already carries).
    static func addAILabel(to image: UIImage, text: String, reservedBottom: CGFloat = 0, reservedLeft: CGFloat = 0) -> UIImage {
        let size = image.size
        let unit = min(size.width, size.height)
        return renderer(size, opaque: !ImageUtilities.hasAlpha(image)).image { _ in
            image.draw(at: .zero)
            let font = brandFont(max(unit * 0.03, 18), weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.brandInk]
            let label = "✦ \(text)" as NSString
            let textSize = label.size(withAttributes: attributes)
            let padding = CGSize(width: font.pointSize * 0.7, height: font.pointSize * 0.35)
            let margin = unit * 0.035
            let pill = CGRect(
                x: reservedLeft + margin,
                y: size.height - reservedBottom - margin - textSize.height - padding.height * 2,
                width: textSize.width + padding.width * 2,
                height: textSize.height + padding.height * 2
            )
            UIColor.white.withAlphaComponent(0.88).setFill()
            UIBezierPath(roundedRect: pill, cornerRadius: pill.height / 2).fill()
            label.draw(at: CGPoint(x: pill.minX + padding.width, y: pill.minY + padding.height), withAttributes: attributes)
        }
    }

    // MARK: Which vibe? (9:16)

    /// "A or B?" story card: two variations of one creation side by side
    /// for friends to vote on, in a Story (with a poll sticker) or a group chat.
    static func pickCard(a: UIImage, b: UIImage, branded: Bool) -> UIImage {
        let canvas = storySize
        return renderer(canvas, opaque: true).image { context in
            let cg = context.cgContext
            UIColor.brandPetal.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            radialGlow(cg, center: CGPoint(x: 180, y: 300), radius: 800, color: .white, alpha: 0.8)
            radialGlow(cg, center: CGPoint(x: 940, y: 1650), radius: 760, color: .brandBlush, alpha: 0.9)

            // Instagram keeps ~250 px at the top and bottom for its own UI.
            drawText(String(localized: "Which vibe?"), font: brandFont(96, weight: .heavy), color: .brandInk,
                     centeredIn: CGRect(x: 0, y: 300, width: canvas.width, height: 120))
            drawText(String(localized: "which one should I post?"), font: accentFont(54), color: .brandInk,
                     centeredIn: CGRect(x: 0, y: 420, width: canvas.width, height: 80))

            let slot = CGSize(width: 430, height: 760)
            let gap: CGFloat = 60
            let top: CGFloat = 590
            for (index, image) in [a, b].enumerated() {
                let size = scaled(image.size, toFit: slot)
                let slotX = (canvas.width - slot.width * 2 - gap) / 2 + CGFloat(index) * (slot.width + gap)
                let frame = CGRect(x: slotX + (slot.width - size.width) / 2, y: top + (slot.height - size.height) / 2,
                                   width: size.width, height: size.height)
                cg.saveGState()
                cg.translateBy(x: frame.midX, y: frame.midY)
                cg.rotate(by: (index == 0 ? -3 : 3) * .pi / 180)
                cg.translateBy(x: -frame.midX, y: -frame.midY)
                cg.setShadow(offset: CGSize(width: 0, height: 20), blur: 40, color: UIColor.brandInk.withAlphaComponent(0.2).cgColor)
                UIColor.white.setFill()
                cg.fill(frame.insetBy(dx: -16, dy: -16))
                cg.setShadow(offset: .zero, blur: 0, color: nil)
                image.draw(in: frame)
                cg.restoreGState()

                let badge = CGRect(x: frame.midX - 62, y: frame.maxY - 30, width: 124, height: 124)
                cg.setShadow(offset: CGSize(width: 0, height: 10), blur: 20, color: UIColor.brandInk.withAlphaComponent(0.25).cgColor)
                (index == 0 ? UIColor.brandInk : UIColor.brandBlush).setFill()
                cg.fillEllipse(in: badge)
                cg.setShadow(offset: .zero, blur: 0, color: nil)
                drawText(index == 0 ? "A" : "B", font: brandFont(68, weight: .heavy),
                         color: index == 0 ? .brandBlush : .brandInk, centeredIn: badge)
            }

            drawText(String(localized: "Reply A or B ♡"), font: brandFont(46, weight: .bold), color: .brandInk,
                     centeredIn: CGRect(x: 0, y: 1500, width: canvas.width, height: 70))
            if branded {
                drawText(String(localized: "Made with \(Brand.name) ✦"), font: brandFont(34, weight: .semibold), color: .brandInk,
                         centeredIn: CGRect(x: 0, y: canvas.height - 300, width: canvas.width, height: 60))
            }
        }
    }

    // MARK: Before / After

    static func beforeAfter(before: UIImage, after: UIImage, branded: Bool) -> UIImage {
        let landscape = after.size.width > after.size.height
        let unit: CGFloat = 1400
        let afterSize = scaled(after.size, toFit: landscape ? CGSize(width: unit, height: .greatestFiniteMagnitude) : CGSize(width: .greatestFiniteMagnitude, height: unit))
        let beforeSize = landscape
            ? scaled(before.size, toFit: CGSize(width: afterSize.width, height: .greatestFiniteMagnitude))
            : scaled(before.size, toFit: CGSize(width: .greatestFiniteMagnitude, height: afterSize.height))
        let padding = unit * 0.05
        let gap = unit * 0.025
        let footer = branded ? unit * 0.1 : 0
        let canvas = landscape
            ? CGSize(width: padding * 2 + afterSize.width, height: padding * 2 + beforeSize.height + gap + afterSize.height + footer)
            : CGSize(width: padding * 2 + beforeSize.width + gap + afterSize.width, height: padding * 2 + afterSize.height + footer)

        return renderer(canvas, opaque: true).image { context in
            UIColor.brandPetal.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            let beforeRect = CGRect(origin: CGPoint(x: padding, y: padding), size: beforeSize)
            let afterRect = landscape
                ? CGRect(origin: CGPoint(x: padding, y: beforeRect.maxY + gap), size: afterSize)
                : CGRect(origin: CGPoint(x: beforeRect.maxX + gap, y: padding), size: afterSize)
            let radius = unit * 0.035
            for (image, rect, label) in [(before, beforeRect, "BEFORE"), (after, afterRect, "AFTER")] {
                drawRounded(image, in: rect, radius: radius, context: context.cgContext)
                drawTag(label, at: CGPoint(x: rect.minX + unit * 0.02, y: rect.minY + unit * 0.02), size: unit * 0.026, highlighted: label == "AFTER")
            }
            if branded {
                drawText(String(localized: "Made with \(Brand.name) ✦"), font: brandFont(unit * 0.034), color: .brandInk,
                         centeredIn: CGRect(x: 0, y: canvas.height - padding - footer * 0.85, width: canvas.width, height: footer))
            }
        }
    }

    // MARK: Story card (9:16)

    static let storySize = CGSize(width: 1080, height: 1920)

    /// The Story card: her photo tilted on the brand glow, in any size
    /// (`StoryCardLayout` keeps it clear of the app's own buttons), with her
    /// words or the prompt under it.
    static func storyCard(_ image: UIImage, prompt: String?, branded: Bool, design: ShareDesign = ShareDesign()) -> UIImage {
        let words = design.text(.storyLine)
        let caption = words ?? prompt.map { "“\(String($0.prefix(110)))\($0.count > 110 ? "…" : "")”" }
        let layout = StoryCardLayout(size: design.cardSize, branded: branded, hasCaption: caption != nil)
        let canvas = CGSize(width: layout.canvas.width, height: layout.canvas.height)
        let unit = layout.unit
        let backdrop = design.backdrop ?? .glow
        // Light type on a dark background, the free mark included.
        let ink: UIColor = backdrop.isDark ? .white : .brandInk
        return renderer(canvas, opaque: true).image { context in
            let cg = context.cgContext
            drawBackdrop(backdrop, photo: image, canvas: canvas, context: cg) { brandGlow(cg, canvas: canvas) }

            let frame = layout.photoFrame(imageWidth: image.size.width, imageHeight: image.size.height).cgRect
            cg.saveGState()
            cg.translateBy(x: frame.midX, y: frame.midY)
            cg.rotate(by: -2 * .pi / 180)
            cg.translateBy(x: -frame.midX, y: -frame.midY)
            let border = frame.insetBy(dx: -18 * unit, dy: -18 * unit)
            cg.setShadow(offset: CGSize(width: 0, height: 24 * unit), blur: 48 * unit, color: UIColor.brandInk.withAlphaComponent(0.22).cgColor)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: border, cornerRadius: 52 * unit).fill()
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            drawRounded(image, in: frame, radius: 36 * unit, context: cg)
            cg.restoreGState()

            if let caption, let rect = layout.caption(under: CanvasRect(frame))?.cgRect {
                let font = words != nil ? (design.font?.uiFont(size: 46 * unit) ?? brandFont(44 * unit, weight: .bold))
                                        : brandFont(40 * unit, weight: .semibold)
                drawText(caption, font: font, color: words != nil ? (design.color?.uiColor ?? ink) : ink, centeredIn: rect, lines: 3)
            }
            if branded, let header = layout.header?.cgRect, let footer = layout.footer?.cgRect {
                drawText(Brand.name, font: brandFont(64 * unit, weight: .heavy), color: ink, centeredIn: header)
                drawText(String(localized: "Made with \(Brand.name) ✦  ·  \(Brand.tagline)"), font: brandFont(34 * unit, weight: .semibold), color: ink,
                         centeredIn: footer)
            }
        }
    }

    // MARK: Sizes and backgrounds

    /// The whole photo in a size for where she posts, fitted in `area`
    /// (`ShareLayout.photoArea`), the room around it filled.
    static func paddedPhoto(_ image: UIImage, canvas: CGSize, area: CanvasRect, backdrop: ShareBackdrop) -> UIImage {
        renderer(canvas, opaque: true).image { context in
            let cg = context.cgContext
            drawBackdrop(backdrop, photo: image, canvas: canvas, context: cg) { brandGlow(cg, canvas: canvas) }
            let frame = ShareLayout.fit(width: image.size.width, height: image.size.height, in: area)
            image.draw(in: frame.cgRect)
        }
    }

    /// The brand glow: blush with soft white and petal light, as on the Story card.
    static func brandGlow(_ cg: CGContext, canvas: CGSize) {
        let unit = min(canvas.width, canvas.height) / 1080
        UIColor.brandBlush.setFill()
        cg.fill(CGRect(origin: .zero, size: canvas))
        radialGlow(cg, center: CGPoint(x: 160 * unit, y: 260 * unit), radius: 760 * unit, color: .white, alpha: 0.75)
        radialGlow(cg, center: CGPoint(x: canvas.width - 100 * unit, y: canvas.height - 220 * unit), radius: 700 * unit, color: .brandPetal, alpha: 0.9)
    }

    /// Behind a design: its own glow (`glow`), her photo blurred, or a colour.
    static func drawBackdrop(_ backdrop: ShareBackdrop, photo: UIImage, canvas: CGSize, context cg: CGContext, glow: () -> Void) {
        let bounds = CGRect(origin: .zero, size: canvas)
        switch backdrop {
        case .glow:
            glow()
        case .blur:
            guard let blurred = blurredBackdrop(photo) else { return glow() }
            cg.saveGState()
            cg.interpolationQuality = .high
            blurred.draw(in: fillRect(for: blurred.size, in: bounds, face: nil))
            cg.restoreGState()
            // A light veil keeps it calm behind the photo and the type.
            UIColor.white.withAlphaComponent(0.14).setFill()
            cg.fill(bounds)
        case .color(let swatch):
            UIColor(hex: swatch.hex).setFill()
            cg.fill(bounds)
        }
    }

    /// Her photo, small and heavily blurred: soft colour, no detail.
    static func blurredBackdrop(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let source = CIImage(cgImage: cgImage)
        let scale = 240 / max(source.extent.width, source.extent.height, 1)
        let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = small.clampedToExtent().applyingGaussianBlur(sigma: 12).cropped(to: small.extent)
        guard let output = ImageFilters.context.createCGImage(blurred, from: small.extent.integral) else { return nil }
        return UIImage(cgImage: output)
    }

    /// The largest size of `make` (down to `minimum`) at which `text` fits
    /// `width` on one line, or `width` × `height` when it may wrap.
    static func fittedFont(_ text: String, width: CGFloat, height: CGFloat? = nil, from size: CGFloat, minimum: CGFloat,
                           lineHeight: CGFloat = 1, kern: CGFloat = 0, make: (CGFloat) -> UIFont) -> UIFont {
        var size = size
        while size > minimum {
            let font = make(size)
            if let height {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineHeightMultiple = lineHeight
                let bounds = (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                             options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                             attributes: [.font: font, .paragraphStyle: paragraph], context: nil)
                if bounds.height <= height { return font }
            } else if (text as NSString).size(withAttributes: [.font: font, .kern: kern]).width <= width {
                return font
            }
            size -= 2
        }
        return make(minimum)
    }

    // MARK: Drawing helpers

    /// Draws a design with UIKit. UIGraphicsImageRenderer keeps an alpha
    /// channel (and 16-bit floats for wide colour) even for an opaque
    /// picture, which made opaque designs PNGs several times the size of a
    /// JPEG, so opaque ones lose it once drawn.
    struct Renderer {
        let base: UIGraphicsImageRenderer
        let opaque: Bool

        func image(_ actions: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
            let image = base.image(actions: actions)
            return opaque ? ImageUtilities.opaque(image) : image
        }
    }

    static func renderer(_ size: CGSize, opaque: Bool) -> Renderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        return Renderer(base: UIGraphicsImageRenderer(size: size, format: format), opaque: opaque)
    }

    static func scaled(_ size: CGSize, toFit bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    static func drawRounded(_ image: UIImage, in rect: CGRect, radius: CGFloat, context: CGContext) {
        context.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: radius).addClip()
        image.draw(in: rect)
        context.restoreGState()
    }

    private static func drawTag(_ text: String, at origin: CGPoint, size: CGFloat, highlighted: Bool) {
        let font = UIFont.systemFont(ofSize: size, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: highlighted ? UIColor.brandInk : UIColor.white,
            .kern: size * 0.08,
        ]
        let label = text as NSString
        let textSize = label.size(withAttributes: attributes)
        let rect = CGRect(x: origin.x, y: origin.y, width: textSize.width + size * 1.2, height: textSize.height + size * 0.6)
        (highlighted ? UIColor.brandBlush : UIColor.brandInk.withAlphaComponent(0.75)).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).fill()
        label.draw(at: CGPoint(x: rect.minX + size * 0.6, y: rect.minY + size * 0.3), withAttributes: attributes)
    }

    static func drawText(_ text: String, font: UIFont, color: UIColor, centeredIn rect: CGRect, lines: Int = 1) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        let string = NSAttributedString(string: text, attributes: attributes)
        let bounds = string.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let height = min(rect.height, ceil(bounds.height))
        string.draw(with: CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine], context: nil)
    }

    static func radialGlow(_ context: CGContext, center: CGPoint, radius: CGFloat, color: UIColor, alpha: CGFloat) {
        let colors = [color.withAlphaComponent(alpha).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    /// The editorial italic accent (New York Italic), as in the app's headlines.
    static func accentFont(_ size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .medium)
        guard let descriptor = base.fontDescriptor.withDesign(.serif)?.withSymbolicTraits(.traitItalic) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    static func brandFont(_ size: CGFloat, weight: UIFont.Weight = .bold) -> UIFont {
        let name: String
        switch weight {
        case .heavy, .black: name = BrandFont.postScriptName(for: .heavy)
        case .bold: name = BrandFont.postScriptName(for: .bold)
        default: name = BrandFont.postScriptName(for: .semibold)
        }
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}

/// Default caption with hashtags and a link people can tap.
enum ShareCaption {
    /// `aiHashtags` (#MadeWithAI…) are added only when generative AI made or
    /// changed the picture, never for on-device edits.
    static func make(for payload: SharePayload, hashtags: [String], aiHashtags: [String], link: URL?) -> String {
        var lines: [String] = []
        if let prompt = payload.shareablePrompt {
            lines.append("“\(prompt)”")
        }
        lines.append(String(localized: "Made with \(Brand.name) ✦ \(Brand.tagline)"))
        if let link {
            lines.append(link.absoluteString)
        }
        let tags = hashtagLine(hashtags, aiHashtags: aiHashtags, madeWithAI: payload.provenance.carriesAIProvenance)
        if !tags.isEmpty {
            lines.append(tags)
        }
        return lines.joined(separator: "\n")
    }

    /// "#Aybuke #GlowUp", plus the AI tags when they apply.
    static func hashtagLine(_ hashtags: [String], aiHashtags: [String], madeWithAI: Bool) -> String {
        (hashtags + (madeWithAI ? aiHashtags : []))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
            .filter { !$0.isEmpty }
            .map { "#\($0)" }
            .joined(separator: " ")
    }
}
