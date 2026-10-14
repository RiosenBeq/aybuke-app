import UIKit
import PencilKit
import AppCore

// MARK: Content

/// Fonts for text on a photo: the brand's Poppins and New York, plus system
/// faces that ship on every iPhone, iPad and Mac.
enum OverlayFont: String, CaseIterable, Identifiable, Sendable {
    case poppins, newYork, rounded, handwriting, script, typewriter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .poppins: return String(localized: "Bold", comment: "Text font in the photo editor (Poppins Bold)")
        case .newYork: return String(localized: "Elegant", comment: "Text font in the photo editor (New York italic)")
        case .rounded: return String(localized: "Round", comment: "Text font in the photo editor (rounded system font)")
        case .handwriting: return String(localized: "Handwritten", comment: "Text font in the photo editor (Noteworthy)")
        case .script: return String(localized: "Script", comment: "Text font in the photo editor (Snell Roundhand)")
        case .typewriter: return String(localized: "Typewriter", comment: "Text font in the photo editor (monospaced)")
        }
    }

    func uiFont(size: CGFloat) -> UIFont {
        switch self {
        case .poppins:
            return UIFont(name: BrandFont.postScriptName(for: .bold), size: size) ?? .systemFont(ofSize: size, weight: .bold)
        case .newYork:
            return Self.system(size: size, weight: .semibold, design: .serif, italic: true)
        case .rounded:
            return Self.system(size: size, weight: .heavy, design: .rounded)
        case .handwriting:
            return UIFont(name: "Noteworthy-Bold", size: size) ?? Self.system(size: size, weight: .bold, design: .rounded)
        case .script:
            return UIFont(name: "SnellRoundhand-Bold", size: size) ?? Self.system(size: size, weight: .semibold, design: .serif, italic: true)
        case .typewriter:
            return .monospacedSystemFont(ofSize: size, weight: .bold)
        }
    }

    private static func system(size: CGFloat, weight: UIFont.Weight, design: UIFontDescriptor.SystemDesign, italic: Bool = false) -> UIFont {
        var descriptor = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        descriptor = descriptor.withDesign(design) ?? descriptor
        if italic {
            descriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.traitItalic)) ?? descriptor
        }
        return UIFont(descriptor: descriptor, size: size)
    }
}

/// Colours for text, doodles and pills: the Blush swatches and the Aura accents.
enum OverlayColor: String, CaseIterable, Identifiable, Sendable {
    case white, ink, blush, petal, pink, lilac, peach, butter, mint, plum

    var id: String { rawValue }

    var hex: UInt32 {
        switch self {
        case .white: return 0xFFFFFF
        case .ink: return 0x121212
        case .blush: return 0xF7C1D9
        case .petal: return 0xF8E0EA
        case .pink: return 0xFF5CA1
        case .lilac: return 0xA78BFA
        case .peach: return 0xFFAA78
        case .butter: return 0xFFDE6E
        case .mint: return 0x78E1CD
        case .plum: return 0x3C185A
        }
    }

    var uiColor: UIColor { UIColor(hex: hex) }

    var isLight: Bool { self != .ink && self != .plum }

    /// Text on a pill of this colour, and the outline around text of it.
    var contrast: UIColor { isLight ? .brandInk : .white }

    var title: String {
        switch self {
        case .white: return String(localized: "White")
        case .ink: return String(localized: "Black")
        case .blush: return String(localized: "Blush")
        case .petal: return String(localized: "Petal")
        case .pink: return String(localized: "Pink")
        case .lilac: return String(localized: "Lilac")
        case .peach: return String(localized: "Peach")
        case .butter: return String(localized: "Butter")
        case .mint: return String(localized: "Mint")
        case .plum: return String(localized: "Plum")
        }
    }
}

enum OverlayTextLook: String, CaseIterable, Identifiable, Sendable {
    case plain, outline, pill, neon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plain: return String(localized: "Plain", comment: "Text style: just the letters")
        case .outline: return String(localized: "Outline", comment: "Text style: letters with an outline")
        case .pill: return String(localized: "Pill", comment: "Text style: letters on a rounded colour background")
        case .neon: return String(localized: "Neon", comment: "Text style: glowing letters")
        }
    }

    var next: OverlayTextLook {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

enum OverlayAlignment: String, CaseIterable, Sendable {
    case leading, center, trailing

    var textAlignment: NSTextAlignment {
        switch self {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }

    var symbolName: String {
        switch self {
        case .leading: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .trailing: return "text.alignright"
        }
    }

    var title: String {
        switch self {
        case .leading: return String(localized: "Left", comment: "Text alignment")
        case .center: return String(localized: "Centered", comment: "Text alignment")
        case .trailing: return String(localized: "Right", comment: "Text alignment")
        }
    }

    var next: OverlayAlignment {
        switch self {
        case .leading: return .center
        case .center: return .trailing
        case .trailing: return .leading
        }
    }
}

struct TextOverlay: Hashable, Sendable {
    var text: String
    var font: OverlayFont = .poppins
    var color: OverlayColor = .white
    var look: OverlayTextLook = .plain
    var alignment: OverlayAlignment = .center

    static let maxLength = 200
}

/// A sticker she pasted (a Cut out copied as a sticker), already downsampled.
final class PastedSticker: Hashable, @unchecked Sendable {
    let image: UIImage
    /// The AI marking the pasted file carried, if any.
    let sourceType: DigitalSourceType?

    init(image: UIImage, sourceType: DigitalSourceType?) {
        self.image = image
        self.sourceType = sourceType
    }

    static func == (lhs: PastedSticker, rhs: PastedSticker) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

enum OverlayContent: Hashable, Sendable {
    case text(TextOverlay)
    case sticker(Sticker)
    case pasted(PastedSticker)

    var text: TextOverlay? {
        if case .text(let text) = self { return text }
        return nil
    }

    /// What VoiceOver calls it.
    var accessibilityName: String {
        switch self {
        case .text(let text): return text.text
        case .sticker(let sticker): return sticker.kind.title
        case .pasted: return String(localized: "Pasted sticker")
        }
    }
}

/// A text box or sticker on the photo while Text & Stickers is open.
struct EditorOverlay: Identifiable, Equatable {
    let id: Int
    var content: OverlayContent
    var placement: OverlayPlacement
    /// The artwork's size in units at scale 1 (text is measured once per change).
    var size: CGSize

    init(id: Int, content: OverlayContent, placement: OverlayPlacement) {
        self.id = id
        self.content = content
        self.placement = placement
        size = OverlayRenderer.artworkSize(of: content)
    }
}

// MARK: Rendering

/// Draws text boxes and stickers. The canvas shows each one as a bitmap from
/// `image(of:)` and Apply draws them into the photo with `flatten`; both go
/// through `draw`, and AppCore's `OverlayPlacement` places them, so what she
/// arranges on screen is what the full-size photo gets.
enum OverlayRenderer {
    /// Text size in units (a thousandth of the photo's shorter side).
    static let textSize: CGFloat = 64
    /// Longer lines wrap.
    static let maxTextWidth: CGFloat = 760
    /// Longest side of a pasted sticker, in units.
    static let pastedSide: CGFloat = 400

    static func artworkSize(of content: OverlayContent) -> CGSize {
        switch content {
        case .text(let text):
            return TextArt.layout(text).size
        case .sticker(let sticker):
            return StickerArt.size(of: sticker)
        case .pasted(let pasted):
            let size = pasted.image.size
            let scale = pastedSide / max(size.width, size.height, 1)
            return CGSize(width: max(size.width * scale, 1), height: max(size.height * scale, 1))
        }
    }

    /// Draws `content` centred on the origin, in artwork units. Quartz doesn't
    /// scale shadow blur with the transform, so glows use `pixelsPerUnit`.
    static func draw(_ content: OverlayContent, size: CGSize, in context: CGContext, pixelsPerUnit: CGFloat) {
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        switch content {
        case .text(let text):
            TextArt.draw(text, in: rect, context: context, pixelsPerUnit: pixelsPerUnit)
        case .sticker(let sticker):
            StickerArt.draw(sticker, in: rect, context: context, pixelsPerUnit: pixelsPerUnit)
        case .pasted(let pasted):
            pasted.image.draw(in: rect)
        }
    }

    /// The artwork alone, unturned, at `pixelsPerUnit`: the canvas preview.
    static func image(of content: OverlayContent, size: CGSize, pixelsPerUnit: CGFloat) -> UIImage {
        let pixels = CGSize(width: max(ceil(size.width * pixelsPerUnit), 1), height: max(ceil(size.height * pixelsPerUnit), 1))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: pixels, format: format).image { context in
            let cg = context.cgContext
            cg.translateBy(x: pixels.width / 2, y: pixels.height / 2)
            cg.scaleBy(x: pixelsPerUnit, y: pixelsPerUnit)
            draw(content, size: size, in: cg, pixelsPerUnit: pixelsPerUnit)
        }
    }

    struct Layer: Sendable {
        let content: OverlayContent
        let size: CGSize
        let placement: OverlayPlacement
    }

    /// The doodle and the canvas it was drawn on (screen points).
    struct Doodle: @unchecked Sendable {
        let drawing: PKDrawing
        let space: OverlayCanvas
    }

    /// The photo with every layer, then the doodle, drawn in at full size.
    /// Off the main actor: a 2048 px photo takes a moment.
    static func flatten(_ photo: UIImage, layers: [Layer], doodle: Doodle?) -> UIImage {
        let pixels = ImageUtilities.pixelSize(of: photo)
        let canvas = OverlayCanvas(width: Double(pixels.width), height: Double(pixels.height))
        let size = CGSize(width: pixels.width, height: pixels.height)
        let doodleImage = doodle.flatMap { doodleLayer($0, onto: canvas) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = !ImageUtilities.hasAlpha(photo)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            photo.draw(in: CGRect(origin: .zero, size: size))
            for layer in layers {
                let t = layer.placement.transform(in: canvas)
                cg.saveGState()
                cg.concatenate(CGAffineTransform(a: t.a, b: t.b, c: t.c, d: t.d, tx: t.tx, ty: t.ty))
                draw(layer.content, size: layer.size, in: cg, pixelsPerUnit: CGFloat(layer.placement.scale * canvas.unit))
                cg.restoreGState()
            }
            if let doodleImage {
                doodleImage.image.draw(in: doodleImage.rect)
            }
        }
    }

    /// PencilKit renders the drawing at the photo's resolution. Light
    /// appearance, or it would swap dark inks for light ones in Dark Mode.
    private static func doodleLayer(_ doodle: Doodle, onto canvas: OverlayCanvas) -> (image: UIImage, rect: CGRect)? {
        guard !doodle.drawing.strokes.isEmpty else { return nil }
        let mapped = DoodleMapping.rect(drawnOn: doodle.space, onto: canvas)
        let scale = CGFloat(DoodleMapping.scale(drawnOn: doodle.space, onto: canvas))
        let bounds = CGRect(x: 0, y: 0, width: doodle.space.width, height: doodle.space.height)
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = doodle.drawing.image(from: bounds, scale: scale)
        }
        guard let image else { return nil }
        return (image, CGRect(x: mapped.x, y: mapped.y, width: mapped.width, height: mapped.height))
    }
}

// MARK: Text

enum TextArt {
    struct Layout {
        let string: NSAttributedString
        let textSize: CGSize
        let padding: CGSize

        var size: CGSize {
            CGSize(width: textSize.width + padding.width * 2, height: textSize.height + padding.height * 2)
        }
    }

    static func layout(_ text: TextOverlay) -> Layout {
        let em = OverlayRenderer.textSize
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = text.alignment.textAlignment
        paragraph.lineBreakMode = .byWordWrapping
        let string = NSAttributedString(
            // A space keeps an empty box measurable while she starts typing.
            string: text.text.isEmpty ? " " : text.text,
            attributes: [.font: text.font.uiFont(size: em), .paragraphStyle: paragraph]
        )
        let bounds = string.boundingRect(
            with: CGSize(width: OverlayRenderer.maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
        )
        var padding: CGSize
        switch text.look {
        case .plain: padding = CGSize(width: em * 0.2, height: em * 0.15)
        case .outline: padding = CGSize(width: em * 0.25, height: em * 0.2)
        case .pill: padding = CGSize(width: em * 0.45, height: em * 0.2)
        case .neon: padding = CGSize(width: em * 0.6, height: em * 0.5)
        }
        // Script and italic letters reach past their advance.
        if text.font == .script || text.font == .newYork { padding.width += em * 0.2 }
        return Layout(string: string, textSize: CGSize(width: ceil(bounds.width), height: ceil(bounds.height)), padding: padding)
    }

    static func draw(_ text: TextOverlay, in rect: CGRect, context cg: CGContext, pixelsPerUnit: CGFloat) {
        let layout = layout(text)
        let em = OverlayRenderer.textSize
        let textRect = CGRect(
            x: rect.midX - layout.textSize.width / 2, y: rect.midY - layout.textSize.height / 2,
            width: layout.textSize.width, height: layout.textSize.height
        )
        let color = text.color.uiColor
        switch text.look {
        case .plain:
            // A faint shadow keeps plain text readable on a busy photo.
            cg.saveGState()
            let shadow = (text.color.isLight ? UIColor.black : UIColor.white).withAlphaComponent(0.3)
            cg.setShadow(offset: .zero, blur: em * 0.12 * pixelsPerUnit, color: shadow.cgColor)
            drawString(layout.string, fill: color, in: textRect)
            cg.restoreGState()
        case .outline:
            cg.saveGState()
            cg.setLineJoin(.round)
            // The outline is stroked first, so the letters cover its inner half.
            drawString(layout.string, stroke: text.color.contrast, strokeWidth: 18, in: textRect)
            cg.restoreGState()
            drawString(layout.string, fill: color, in: textRect)
        case .pill:
            let pill = UIBezierPath(roundedRect: rect, cornerRadius: min(rect.height / 2, em * 0.55))
            color.setFill()
            pill.fill()
            drawString(layout.string, fill: text.color.contrast, in: textRect)
        case .neon:
            let core = color.mixed(with: .white, amount: 0.6)
            cg.saveGState()
            cg.setShadow(offset: .zero, blur: em * 0.45 * pixelsPerUnit, color: color.cgColor)
            drawString(layout.string, fill: color, in: textRect)
            cg.setShadow(offset: .zero, blur: em * 0.16 * pixelsPerUnit, color: color.cgColor)
            drawString(layout.string, fill: core, in: textRect)
            cg.restoreGState()
            drawString(layout.string, fill: core, in: textRect)
        }
    }

    private static func drawString(_ base: NSAttributedString, fill: UIColor? = nil, stroke: UIColor? = nil,
                                   strokeWidth: CGFloat = 0, in rect: CGRect) {
        let string = NSMutableAttributedString(attributedString: base)
        let range = NSRange(location: 0, length: string.length)
        if let stroke {
            // A positive width strokes without filling (percent of the size).
            string.addAttributes([.strokeColor: stroke, .strokeWidth: strokeWidth], range: range)
        } else if let fill {
            string.addAttribute(.foregroundColor, value: fill, range: range)
        }
        string.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }
}

extension UIColor {
    /// `amount` of the way from this colour to `other`.
    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = min(max(amount, 0), 1)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }
}
