import UIKit
import CoreImage
import CoreText
import AppCore

/// How captions look in the video editor.
enum CaptionStyle: String, CaseIterable, Identifiable, Sendable {
    /// Bold white with a dark outline.
    case pop
    /// Ink text on a blush pill.
    case bubble
    /// Pop, with the word being said lit up in pink.
    case karaoke
    /// Monospaced type on a dark box that types itself, for VHS and Camcorder '06.
    case typewriter

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .pop: return LocalizedStringResource("Pop", comment: "Caption style: bold white text with a dark outline")
        case .bubble: return LocalizedStringResource("Bubble", comment: "Caption style: text on a rounded pastel pill")
        case .karaoke: return LocalizedStringResource("Karaoke", comment: "Caption style: each word lights up as it's said")
        case .typewriter: return LocalizedStringResource("Typewriter", comment: "Caption style: retro monospaced text that types itself")
        }
    }

    func font(size: CGFloat) -> UIFont {
        switch self {
        case .pop, .karaoke: return Self.rounded(size, .heavy)
        case .bubble: return Self.rounded(size, .bold)
        case .typewriter: return UIFont.monospacedSystemFont(ofSize: size, weight: .bold)
        }
    }

    /// The system font has glyphs for every app language (the brand fonts
    /// don't); other scripts fall back to the system's own fonts.
    private static func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}

enum CaptionPosition: String, CaseIterable, Identifiable, Sendable {
    case bottom, middle

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .bottom: return LocalizedStringResource("Bottom", comment: "Where captions sit on the video")
        case .middle: return LocalizedStringResource("Middle", comment: "Where captions sit on the video")
        }
    }
}

enum CaptionSize: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .small: return LocalizedStringResource("Small", comment: "Caption text size")
        case .medium: return LocalizedStringResource("Medium", comment: "Caption text size")
        case .large: return LocalizedStringResource("Large", comment: "Caption text size")
        }
    }

    /// Font size as a share of the frame's shorter side. Medium fits a full
    /// 32-character line across a portrait video.
    var scale: CGFloat {
        switch self {
        case .small: return 0.045
        case .medium: return 0.056
        case .large: return 0.07
        }
    }
}

struct CaptionLook: Hashable, Sendable {
    var style: CaptionStyle = .pop
    var position: CaptionPosition = .bottom
    var size: CaptionSize = .medium
}

/// The captions of one preview or export: cues on the edited timeline and
/// their look. Each cue is drawn once per state (the lit Karaoke word) into
/// a small image, cached, and placed on the frames it covers, so no text is
/// laid out per frame. Preview and export go through the same track, so the
/// saved video matches what she saw.
final class CaptionTrack: @unchecked Sendable {
    /// What the effect draws at the bottom of the frame; captions stay above it.
    enum Reserve: Sendable {
        case none
        /// A date stamp or the camcorder's date and timecode.
        case stamp
        case letterbox
    }

    let cues: [CaptionCue]
    let look: CaptionLook
    private let reserve: Reserve
    private let lock = NSLock()
    private var canvas: CGSize = .zero
    private var cache: [Key: Drawn] = [:]
    private var recent: [Key] = []
    /// Cues near the playhead; a long video doesn't keep every caption in memory.
    private static let capacity = 12

    private struct Key: Hashable {
        let cue: Int
        let word: Int
    }

    /// Nil when nothing would show.
    init?(cues: [CaptionCue], look: CaptionLook, overlay: RetroEffect?) {
        let shown = cues.filter { !$0.isBlank && $0.end > $0.start }.sorted { $0.start < $1.start }
        guard !shown.isEmpty else { return nil }
        self.cues = shown
        self.look = look
        switch overlay?.option {
        case .dateStamp?, .cameraInfo?: reserve = .stamp
        case .letterbox?: reserve = .letterbox
        default: reserve = .none
        }
    }

    /// Captions over one frame at `seconds` on the edited timeline; called
    /// after the effect and its overlay, so they sit on top of everything.
    func composite(over frame: CIImage, seconds: Double) -> CIImage {
        guard let index = CaptionTimeline.index(at: seconds, in: cues) else { return frame }
        let cue = cues[index]
        // Lit a moment early, which reads as in time with the voice.
        let word = look.style == .karaoke ? (cue.activeWordIndex(at: seconds + 0.04) ?? -1) : -1
        guard let drawn = drawn(index, word: word, canvas: frame.extent.size) else { return frame }
        let age = seconds - cue.start
        let layer = look.style == .typewriter
            ? drawn.typed(characters: typedCharacters(drawn, cue: cue, age: age))
            : Self.popIn(drawn.image, age: age)
        return layer.transformed(by: CGAffineTransform(translationX: frame.extent.minX, y: frame.extent.minY))
            .composited(over: frame)
    }

    /// Typewriter types the whole caption within the first 40% of its time
    /// (at most a second), so there's time left to read it.
    private func typedCharacters(_ drawn: Drawn, cue: CaptionCue, age: Double) -> Int {
        let typing = min(1, max(0.3, (cue.end - cue.start) * 0.4))
        return min(drawn.characters, Int((age / typing * Double(drawn.characters)).rounded(.up)))
    }

    /// A quick scale-and-fade in when a caption appears.
    private static func popIn(_ image: CIImage, age: Double) -> CIImage {
        let duration = 0.14
        guard age >= 0, age < duration else { return image }
        let eased = 1 - pow(1 - age / duration, 3)
        let scale = 0.86 + 0.14 * eased
        let center = CGPoint(x: image.extent.midX, y: image.extent.midY)
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -center.x, y: -center.y)
        return image.transformed(by: transform)
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: eased)])
    }

    private func drawn(_ index: Int, word: Int, canvas size: CGSize) -> Drawn? {
        let key = Key(cue: index, word: word)
        lock.lock()
        if canvas != size {
            canvas = size
            cache.removeAll()
            recent.removeAll()
        }
        if let hit = cache[key] {
            if recent.last != key, let position = recent.firstIndex(of: key) {
                recent.remove(at: position)
                recent.append(key)
            }
            lock.unlock()
            return hit
        }
        lock.unlock()
        // Drawn outside the lock: the export renders frames on several threads.
        guard let layout = CaptionDrawing(cue: cues[index], highlight: word >= 0 ? word : nil, look: look, reserve: reserve, canvas: size),
              let made = layout.render() else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if canvas == size, cache[key] == nil {
            cache[key] = made
            recent.append(key)
            while recent.count > Self.capacity { cache[recent.removeFirst()] = nil }
        }
        return made
    }

    /// A style tile: "Aa" in the look over the clip's first frame.
    static func sample(_ style: CaptionStyle, over background: UIImage?, size: CGSize) -> UIImage {
        let cue = CaptionCue(start: 0, end: 1, text: "Aa", words: [CaptionWord(text: "Aa", start: 0, end: 1)])
        let look = CaptionLook(style: style, position: .middle, size: .large)
        let drawing = CaptionDrawing(cue: cue, highlight: 0, look: look, reserve: .none, canvas: size, fontSize: size.height * 0.24)
        let caption = drawing?.draw()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.brandCharcoal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            if let background {
                let fill = max(size.width / background.size.width, size.height / background.size.height)
                let drawn = CGSize(width: background.size.width * fill, height: background.size.height * fill)
                background.draw(in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2, width: drawn.width, height: drawn.height))
                // Dimmed a little, like a frame behind real captions (plain
                // `fill` copies the colour instead of blending it).
                UIColor.black.withAlphaComponent(0.18).setFill()
                context.fill(CGRect(origin: .zero, size: size), blendMode: .normal)
            }
            if let caption {
                UIImage(cgImage: caption.image).draw(in: caption.bounds)
            }
        }
    }
}

/// A cue drawn once, ready to place on frames.
private struct Drawn {
    /// The caption in frame coordinates (Core Image: origin bottom left).
    let image: CIImage
    /// Typewriter: each line's box and how wide it is after each character.
    let lines: [TypedLine]

    var characters: Int { lines.reduce(0) { $0 + $1.edges.count } }

    struct TypedLine {
        let band: CGRect
        let edges: [CGFloat]
    }

    /// The caption typed up to `characters`: each line's box grows with it.
    func typed(characters: Int) -> CIImage {
        guard characters < self.characters else { return image }
        var output = CIImage.empty()
        var left = characters
        for line in lines where left > 0 && !line.edges.isEmpty {
            let count = min(left, line.edges.count)
            let crop = CGRect(x: line.band.minX, y: line.band.minY, width: line.edges[count - 1], height: line.band.height)
            output = image.cropped(to: crop).composited(over: output)
            left -= line.edges.count
        }
        return output
    }
}

/// Lays out and draws one caption with CoreText: balanced lines from
/// `CaptionLayout`, shrunk to fit the frame's width, above the effect's own
/// overlay at the bottom or centred in the middle.
private struct CaptionDrawing {
    let cue: CaptionCue
    let highlight: Int?
    let look: CaptionLook
    let font: UIFont
    let lines: [Line]
    let em: CGFloat
    let ascent: CGFloat
    let slots: [CGRect]
    let bounds: CGRect
    let canvas: CGSize

    struct Line {
        let ctLine: CTLine
        /// UTF-16 range of the line in the cue's text.
        let range: Range<Int>
        let width: CGFloat
        let text: String
    }

    init?(cue: CaptionCue, highlight: Int?, look: CaptionLook, reserve: CaptionTrack.Reserve, canvas: CGSize, fontSize: CGFloat? = nil) {
        let ranges = CaptionLayout.lineRanges(for: cue.text)
        guard !ranges.isEmpty, canvas.width > 1, canvas.height > 1 else { return nil }
        self.cue = cue
        self.highlight = highlight
        self.look = look
        self.canvas = canvas
        let source = cue.text as NSString
        let texts = ranges.map { source.substring(with: NSRange(location: $0.lowerBound, length: $0.count)) }

        var size = fontSize ?? min(canvas.width, canvas.height) * look.size.scale
        var font = look.style.font(size: size)
        var lines = Self.lines(texts, ranges: ranges, font: font)
        // Long lines shrink to fit rather than run off the frame.
        let room = canvas.width * 0.88 - 2 * Self.padding(look.style).x * size
        if let widest = lines.map(\.width).max(), widest > room, widest > 0 {
            size *= room / widest
            font = look.style.font(size: size)
            lines = Self.lines(texts, ranges: ranges, font: font)
        }
        self.font = font
        self.lines = lines
        em = size
        ascent = font.ascender
        let textHeight = font.ascender - font.descender
        let pad = Self.padding(look.style)
        let slotHeight = textHeight + 2 * pad.y * size
        let step: CGFloat
        switch look.style {
        case .pop, .karaoke: step = size * 1.16
        // Pills overlap a little so two lines read as one bubble.
        case .bubble: step = slotHeight - size * 0.12
        // Separate boxes, like TV captions.
        case .typewriter: step = slotHeight + size * 0.06
        }
        let blockHeight = step * CGFloat(lines.count - 1) + slotHeight
        let top: CGFloat
        switch look.position {
        case .bottom: top = canvas.height - Self.bottomInset(canvas: canvas, reserve: reserve) - blockHeight
        case .middle: top = (canvas.height - blockHeight) / 2
        }
        slots = lines.enumerated().map { index, line in
            CGRect(x: (canvas.width - line.width) / 2 - pad.x * size, y: top + CGFloat(index) * step,
                   width: line.width + 2 * pad.x * size, height: slotHeight)
        }
        let margin = size * 0.4
        bounds = slots.reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -margin, dy: -margin).integral
    }

    private static func lines(_ texts: [String], ranges: [Range<Int>], font: UIFont) -> [Line] {
        zip(texts, ranges).map { text, range in
            let attributed = NSAttributedString(string: text, attributes: [
                .font: font,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            return Line(ctLine: line, range: range, width: CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)), text: text)
        }
    }

    /// Room around the text inside a pill or box, in ems.
    private static func padding(_ style: CaptionStyle) -> (x: CGFloat, y: CGFloat) {
        switch style {
        case .pop, .karaoke: return (0, 0)
        case .bubble: return (0.42, 0.16)
        case .typewriter: return (0.32, 0.1)
        }
    }

    /// Bottom captions sit in the lower part of the frame, clear of the
    /// apps' own buttons when posted, and above a date stamp, the camcorder
    /// display or the letterbox bar.
    static func bottomInset(canvas: CGSize, reserve: CaptionTrack.Reserve) -> CGFloat {
        let unit = max(canvas.width, canvas.height) / 1000
        var inset = canvas.height * (canvas.height > canvas.width * 1.15 ? 0.15 : 0.08)
        switch reserve {
        case .stamp: inset = max(inset, 104 * unit)
        case .letterbox: inset = max(inset, CGFloat(Letterbox.barHeight(width: Double(canvas.width), height: Double(canvas.height))) + 24 * unit)
        case .none: break
        }
        return inset
    }

    private func baseline(_ index: Int) -> CGFloat {
        slots[index].minY + Self.padding(look.style).y * em + ascent
    }

    private func origin(_ index: Int) -> CGPoint {
        CGPoint(x: (canvas.width - lines[index].width) / 2, y: baseline(index))
    }

    /// The caption as an image covering `bounds` (top-left origin).
    func draw() -> (image: CGImage, bounds: CGRect)? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            let cg = context.cgContext
            cg.translateBy(x: -bounds.minX, y: -bounds.minY)
            // CoreText draws y-up; flip the glyphs in UIKit's y-down space.
            cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            switch look.style {
            case .pop, .karaoke: drawPop(cg)
            case .bubble: drawBubble(cg)
            case .typewriter: drawTypewriter(cg)
            }
        }
        guard let cgImage = image.cgImage else { return nil }
        return (cgImage, bounds)
    }

    func render() -> Drawn? {
        guard let (image, bounds) = draw() else { return nil }
        let flip = canvas.height - bounds.maxY
        let placed = CIImage(cgImage: image).transformed(by: CGAffineTransform(translationX: bounds.minX, y: flip))
        guard look.style == .typewriter else { return Drawn(image: placed, lines: []) }
        let typed = lines.enumerated().map { index, line -> Drawn.TypedLine in
            let slot = slots[index]
            let pad = Self.padding(look.style).x * em
            // A sliver of the gap above and below, never the next line's box.
            let band = CGRect(x: slot.minX - em * 0.3, y: canvas.height - slot.maxY - em * 0.03,
                              width: slot.width + em * 0.6, height: slot.height + em * 0.06)
            var edges: [CGFloat] = []
            let utf16 = line.text.utf16
            var offset = 0
            for character in line.text {
                offset += character.utf16.count
                guard offset <= utf16.count else { break }
                let x = CTLineGetOffsetForStringIndex(line.ctLine, offset, nil)
                edges.append(em * 0.3 + pad * 2 + x)
            }
            return Drawn.TypedLine(band: band, edges: edges)
        }
        return Drawn(image: placed, lines: typed)
    }

    private func drawLines(_ cg: CGContext) {
        for index in lines.indices {
            cg.textPosition = origin(index)
            CTLineDraw(lines[index].ctLine, cg)
        }
    }

    private func drawPop(_ cg: CGContext) {
        // One shadowed layer for the outline (and the lit word), so overlapping
        // strokes don't darken each other.
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: em * 0.05), blur: em * 0.16, color: UIColor.black.withAlphaComponent(0.42).cgColor)
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        if look.style == .karaoke, let highlight, let ranges = cue.wordRanges, ranges.indices.contains(highlight) {
            UIColor.auraPink.setFill()
            for rect in highlightRects(ranges[highlight]) {
                UIBezierPath(roundedRect: rect, cornerRadius: em * 0.22).fill()
            }
        }
        cg.setLineJoin(.round)
        cg.setLineWidth(em * 0.17)
        cg.setStrokeColor(UIColor.brandInk.cgColor)
        cg.setFillColor(UIColor.brandInk.cgColor)
        cg.setTextDrawingMode(.fillStroke)
        drawLines(cg)
        cg.endTransparencyLayer()
        cg.restoreGState()
        cg.setTextDrawingMode(.fill)
        cg.setFillColor(UIColor.white.cgColor)
        drawLines(cg)
    }

    /// The lit word's box on each line it's on (Chinese and Japanese words
    /// can wrap).
    private func highlightRects(_ word: Range<Int>) -> [CGRect] {
        lines.indices.compactMap { index in
            let line = lines[index]
            let lower = max(word.lowerBound, line.range.lowerBound) - line.range.lowerBound
            let upper = min(word.upperBound, line.range.upperBound) - line.range.lowerBound
            guard upper > lower else { return nil }
            let x0 = CTLineGetOffsetForStringIndex(line.ctLine, lower, nil)
            let x1 = CTLineGetOffsetForStringIndex(line.ctLine, upper, nil)
            let start = origin(index)
            return CGRect(x: start.x + x0 - em * 0.13, y: slots[index].minY - em * 0.02,
                          width: x1 - x0 + em * 0.26, height: slots[index].height + em * 0.04)
        }
    }

    private func drawBubble(_ cg: CGContext) {
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: em * 0.06), blur: em * 0.24, color: UIColor.black.withAlphaComponent(0.22).cgColor)
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        UIColor.brandBlush.setFill()
        for slot in slots {
            UIBezierPath(roundedRect: slot, cornerRadius: slot.height * 0.42).fill()
        }
        cg.endTransparencyLayer()
        cg.restoreGState()
        cg.setTextDrawingMode(.fill)
        cg.setFillColor(UIColor.brandInk.cgColor)
        drawLines(cg)
    }

    private func drawTypewriter(_ cg: CGContext) {
        UIColor.brandInk.withAlphaComponent(0.84).setFill()
        for slot in slots {
            UIBezierPath(roundedRect: slot, cornerRadius: em * 0.12).fill()
        }
        // A soft blush glow, like an old TV's text.
        cg.saveGState()
        cg.setShadow(offset: .zero, blur: em * 0.22, color: UIColor.brandBlush.withAlphaComponent(0.75).cgColor)
        cg.setTextDrawingMode(.fill)
        cg.setFillColor(UIColor(hex: 0xFFF6EC).cgColor)
        drawLines(cg)
        cg.restoreGState()
    }
}
