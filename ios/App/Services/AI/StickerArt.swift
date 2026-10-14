import UIKit

enum StickerKind: String, CaseIterable, Identifiable, Sendable {
    case heart, chromeHeart, sparkles, star, butterfly, bow, cherries, flower, smiley, omg, slay, bestie, dateStamp

    var id: String { rawValue }

    /// The sticker's name for VoiceOver and the sticker tray.
    var title: String {
        switch self {
        case .heart: return String(localized: "Heart")
        case .chromeHeart: return String(localized: "Chrome heart", comment: "A shiny metallic Y2K-style heart sticker")
        case .sparkles: return String(localized: "Sparkles")
        case .star: return String(localized: "Star")
        case .butterfly: return String(localized: "Butterfly")
        case .bow: return String(localized: "Bow", comment: "A ribbon bow sticker")
        case .cherries: return String(localized: "Cherries")
        case .flower: return String(localized: "Flower")
        case .smiley: return String(localized: "Smiley")
        case .omg, .slay, .bestie:
            return String(localized: "Speech bubble: \(words ?? "")", comment: "A speech-bubble sticker and its words")
        case .dateStamp: return String(localized: "Date stamp")
        }
    }

    /// The words in a speech bubble.
    var words: String? {
        switch self {
        case .omg: return String(localized: "OMG", comment: "Speech-bubble sticker in the photo editor")
        case .slay: return String(localized: "slay", comment: "Speech-bubble sticker in the photo editor: praise, as in 'you look amazing'")
        case .bestie: return String(localized: "bestie", comment: "Speech-bubble sticker in the photo editor: best friend")
        default: return nil
        }
    }
}

/// A built-in sticker. Bubbles and the date stamp keep their words, so a
/// placed sticker never changes (at midnight, say).
struct Sticker: Hashable, Sendable {
    let kind: StickerKind
    let text: String?

    init(_ kind: StickerKind, date: Date = AppClock.now) {
        self.kind = kind
        text = kind == .dateStamp ? StickerArt.dateStampText(for: date) : kind.words
    }
}

/// The built-in sticker pack, drawn in code with the brand's colours: no
/// third-party art, and no emoji or SF Symbols baked into photos. Stickers
/// get a white die-cut edge and a soft shadow, like real ones.
enum StickerArt {
    /// The white edge, in units.
    static let edge: CGFloat = 12
    /// Edge plus room for the shadow, so preview bitmaps don't clip it.
    private static let margin: CGFloat = 26
    private static let bubbleTail: CGFloat = 34
    private static let bubbleOutline: CGFloat = 5

    static func size(of sticker: Sticker) -> CGSize {
        let art: CGSize
        switch sticker.kind {
        case .heart: art = CGSize(width: 210, height: 200)
        case .chromeHeart: art = CGSize(width: 220, height: 208)
        case .sparkles: art = CGSize(width: 220, height: 220)
        case .star: art = CGSize(width: 210, height: 204)
        case .butterfly: art = CGSize(width: 250, height: 206)
        case .bow: art = CGSize(width: 256, height: 194)
        case .cherries: art = CGSize(width: 190, height: 216)
        case .flower: art = CGSize(width: 208, height: 208)
        case .smiley: art = CGSize(width: 196, height: 196)
        case .omg, .slay, .bestie:
            let text = bubbleText(sticker).size()
            art = CGSize(width: max(ceil(text.width) + 88, 170), height: ceil(text.height) + 40 + bubbleTail)
        case .dateStamp:
            let text = dateText(sticker).size()
            return CGSize(width: ceil(text.width) + 40, height: ceil(text.height) + 32)
        }
        return CGSize(width: art.width + margin * 2, height: art.height + margin * 2)
    }

    static func draw(_ sticker: Sticker, in rect: CGRect, context cg: CGContext, pixelsPerUnit: CGFloat) {
        if sticker.kind == .dateStamp {
            drawDateStamp(sticker, in: rect, context: cg, pixelsPerUnit: pixelsPerUnit)
            return
        }
        cg.saveGState()
        // One shadow under the whole sticker. The layer is only as big as the
        // sticker, so a full-size photo doesn't need a second full-size buffer.
        cg.setShadow(offset: .zero, blur: 9 * pixelsPerUnit, color: UIColor.black.withAlphaComponent(0.22).cgColor)
        cg.beginTransparencyLayer(in: rect, auxiliaryInfo: nil)
        let art = rect.insetBy(dx: margin, dy: margin)
        switch sticker.kind {
        case .heart: drawHeart(in: art)
        case .chromeHeart: drawChromeHeart(in: art, context: cg)
        case .sparkles: drawSparkles(in: art)
        case .star: drawStar(in: art)
        case .butterfly: drawButterfly(in: art)
        case .bow: drawBow(in: art)
        case .cherries: drawCherries(in: art, context: cg)
        case .flower: drawFlower(in: art)
        case .smiley: drawSmiley(in: art)
        case .omg, .slay, .bestie: drawBubble(sticker, in: art)
        case .dateStamp: break
        }
        cg.endTransparencyLayer()
        cg.restoreGState()
    }

    // MARK: Shapes

    private static func drawHeart(in art: CGRect) {
        let grid = Grid(rect: art)
        let heart = heartPath(in: art)
        dieCut([heart])
        UIColor.auraPink.setFill()
        heart.fill()
        UIColor.white.withAlphaComponent(0.55).setFill()
        grid.ellipse(0.25, 0.27, 0.17, 0.1, degrees: -38).fill()
        grid.ellipse(0.37, 0.18, 0.05, 0.035, degrees: -38).fill()
    }

    /// Y2K chrome: bands of light, a dark horizon line and hard highlights.
    private static func drawChromeHeart(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let heart = heartPath(in: art)
        dieCut([heart])
        cg.saveGState()
        heart.addClip()
        let colors = [UIColor.white, .brandPetal, UIColor(hex: 0xD9CCF5), .auraLilac, .plum, UIColor(hex: 0xB86AA8), .brandBlush, .white]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray,
                                     locations: [0, 0.16, 0.36, 0.47, 0.5, 0.57, 0.8, 1]) {
            cg.drawLinearGradient(gradient, start: CGPoint(x: art.midX, y: art.minY), end: CGPoint(x: art.midX, y: art.maxY), options: [])
        }
        cg.restoreGState()
        UIColor.plum.withAlphaComponent(0.45).setStroke()
        heart.lineWidth = 4
        heart.stroke()
        UIColor.white.setFill()
        grid.ellipse(0.26, 0.26, 0.2, 0.08, degrees: -36).fill()
        sparklePath(center: grid.p(0.74, 0.3), radius: art.width * 0.1).fill()
    }

    private static func drawSparkles(in art: CGRect) {
        let grid = Grid(rect: art)
        let big = sparklePath(center: grid.p(0.4, 0.58), radius: art.width * 0.4)
        let medium = sparklePath(center: grid.p(0.79, 0.21), radius: art.width * 0.2)
        let small = sparklePath(center: grid.p(0.82, 0.83), radius: art.width * 0.13)
        dieCut([big, medium, small], width: edge * 0.75)
        UIColor.white.setFill()
        big.fill()
        // A lilac rim, so the white sparkle shows on a bright sky too.
        UIColor.auraLilac.setStroke()
        big.lineWidth = 4
        big.stroke()
        UIColor.auraButter.setFill()
        medium.fill()
        UIColor.auraPink.setFill()
        small.fill()
    }

    private static func drawStar(in art: CGRect) {
        let center = CGPoint(x: art.midX, y: art.minY + art.height * 0.53)
        let outer = art.width * 0.5
        let star = starPath(center: center, outer: outer, inner: outer * 0.47)
        dieCut([star])
        UIColor.auraButter.setFill()
        star.fill()
        // Stroking in the same colour rounds the points.
        UIColor.auraButter.setStroke()
        star.lineWidth = 10
        star.lineJoinStyle = .round
        star.stroke()
        UIColor.white.withAlphaComponent(0.35).setFill()
        starPath(center: center, outer: outer * 0.5, inner: outer * 0.24).fill()
    }

    private static func drawButterfly(in art: CGRect) {
        let grid = Grid(rect: art)
        let upperLeft = grid.ellipse(0.28, 0.36, 0.46, 0.56, degrees: -24)
        let upperRight = grid.ellipse(0.72, 0.36, 0.46, 0.56, degrees: 24)
        let lowerLeft = grid.ellipse(0.33, 0.73, 0.32, 0.38, degrees: 28)
        let lowerRight = grid.ellipse(0.67, 0.73, 0.32, 0.38, degrees: -28)
        let body = UIBezierPath(roundedRect: grid.r(0.47, 0.2, 0.06, 0.7), cornerRadius: art.width * 0.03)
        let antennae = UIBezierPath()
        antennae.move(to: grid.p(0.49, 0.22))
        antennae.addQuadCurve(to: grid.p(0.36, 0.03), controlPoint: grid.p(0.45, 0.06))
        antennae.move(to: grid.p(0.51, 0.22))
        antennae.addQuadCurve(to: grid.p(0.64, 0.03), controlPoint: grid.p(0.55, 0.06))
        let antennaWidth = art.width * 0.022
        dieCut([upperLeft, upperRight, lowerLeft, lowerRight, body])
        dieCut([antennae], width: edge * 0.7 + antennaWidth / 2)

        UIColor.auraPink.setFill()
        lowerLeft.fill()
        lowerRight.fill()
        UIColor.auraLilac.setFill()
        upperLeft.fill()
        upperRight.fill()
        UIColor.brandPetal.withAlphaComponent(0.9).setFill()
        grid.ellipse(0.23, 0.33, 0.2, 0.24, degrees: -24).fill()
        grid.ellipse(0.77, 0.33, 0.2, 0.24, degrees: 24).fill()
        UIColor.auraButter.setFill()
        grid.ellipse(0.31, 0.76, 0.11, 0.13).fill()
        grid.ellipse(0.69, 0.76, 0.11, 0.13).fill()
        UIColor.plum.setFill()
        body.fill()
        UIColor.plum.setStroke()
        antennae.lineWidth = antennaWidth
        antennae.lineCapStyle = .round
        antennae.stroke()
        for x in [0.36, 0.64] as [CGFloat] {
            grid.ellipse(x, 0.03, 0.05, 0.06).fill()
        }
    }

    private static func drawBow(in art: CGRect) {
        let grid = Grid(rect: art)
        let loop = UIBezierPath()
        loop.move(to: grid.p(0.47, 0.36))
        loop.addCurve(to: grid.p(0.06, 0.12), controlPoint1: grid.p(0.34, 0.12), controlPoint2: grid.p(0.14, -0.02))
        loop.addCurve(to: grid.p(0.1, 0.66), controlPoint1: grid.p(-0.02, 0.3), controlPoint2: grid.p(-0.01, 0.6))
        loop.addCurve(to: grid.p(0.47, 0.5), controlPoint1: grid.p(0.22, 0.72), controlPoint2: grid.p(0.36, 0.6))
        loop.close()
        let tail = UIBezierPath()
        tail.move(to: grid.p(0.45, 0.48))
        tail.addCurve(to: grid.p(0.22, 0.95), controlPoint1: grid.p(0.4, 0.66), controlPoint2: grid.p(0.3, 0.84))
        tail.addLine(to: grid.p(0.32, 0.88))
        tail.addLine(to: grid.p(0.38, 0.99))
        tail.addCurve(to: grid.p(0.53, 0.5), controlPoint1: grid.p(0.44, 0.84), controlPoint2: grid.p(0.5, 0.66))
        tail.close()
        let loops = [loop, mirrored(loop, in: art)]
        let tails = [tail, mirrored(tail, in: art)]
        let knot = UIBezierPath(roundedRect: grid.r(0.41, 0.3, 0.18, 0.26), cornerRadius: art.width * 0.06)
        dieCut(loops + tails + [knot])

        UIColor.auraPink.mixed(with: .plum, amount: 0.15).setFill()
        tails.forEach { $0.fill() }
        UIColor.auraPink.setFill()
        loops.forEach { $0.fill() }
        // A fold inside each loop.
        let fold = UIBezierPath()
        fold.move(to: grid.p(0.42, 0.43))
        fold.addQuadCurve(to: grid.p(0.15, 0.3), controlPoint: grid.p(0.26, 0.28))
        UIColor.plum.withAlphaComponent(0.25).setStroke()
        for path in [fold, mirrored(fold, in: art)] {
            path.lineWidth = 5
            path.lineCapStyle = .round
            path.stroke()
        }
        UIColor.white.withAlphaComponent(0.4).setFill()
        grid.ellipse(0.2, 0.2, 0.1, 0.06, degrees: -30).fill()
        grid.ellipse(0.8, 0.2, 0.1, 0.06, degrees: 30).fill()
        UIColor.auraPink.mixed(with: .plum, amount: 0.25).setFill()
        knot.fill()
    }

    private static func drawCherries(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let radius = art.width * 0.22
        let centers = [grid.p(0.3, 0.72), grid.p(0.7, 0.77)]
        let cherries = centers.map { UIBezierPath(ovalIn: CGRect(x: $0.x - radius, y: $0.y - radius, width: radius * 2, height: radius * 2)) }
        let stems = UIBezierPath()
        stems.move(to: grid.p(0.32, 0.53))
        stems.addCurve(to: grid.p(0.58, 0.1), controlPoint1: grid.p(0.36, 0.34), controlPoint2: grid.p(0.46, 0.18))
        stems.move(to: grid.p(0.68, 0.58))
        stems.addCurve(to: grid.p(0.58, 0.1), controlPoint1: grid.p(0.7, 0.36), controlPoint2: grid.p(0.62, 0.2))
        let leaf = UIBezierPath()
        leaf.move(to: grid.p(0.58, 0.1))
        leaf.addCurve(to: grid.p(0.96, 0.12), controlPoint1: grid.p(0.68, -0.04), controlPoint2: grid.p(0.88, -0.02))
        leaf.addCurve(to: grid.p(0.58, 0.1), controlPoint1: grid.p(0.86, 0.26), controlPoint2: grid.p(0.68, 0.24))
        leaf.close()
        let stemWidth = art.width * 0.045
        dieCut(cherries + [leaf])
        dieCut([stems], width: edge + stemWidth / 2)

        let stemColor = UIColor.auraMint.mixed(with: .plum, amount: 0.45)
        stemColor.setStroke()
        stems.lineWidth = stemWidth
        stems.lineCapStyle = .round
        stems.stroke()
        UIColor.auraMint.setFill()
        leaf.fill()
        let vein = UIBezierPath()
        vein.move(to: grid.p(0.62, 0.1))
        vein.addQuadCurve(to: grid.p(0.9, 0.12), controlPoint: grid.p(0.76, 0.07))
        vein.lineWidth = 3
        vein.stroke()

        let deep = UIColor.auraPink.mixed(with: .plum, amount: 0.35)
        let space = CGColorSpaceCreateDeviceRGB()
        for (cherry, center) in zip(cherries, centers) {
            cg.saveGState()
            cherry.addClip()
            if let shine = CGGradient(colorsSpace: space, colors: [UIColor.auraPink.cgColor, deep.cgColor] as CFArray, locations: [0.2, 1]) {
                let light = CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.35)
                cg.drawRadialGradient(shine, startCenter: light, startRadius: 0, endCenter: center, endRadius: radius * 1.15, options: [])
            }
            cg.restoreGState()
            UIColor.white.withAlphaComponent(0.7).setFill()
            UIBezierPath(ovalIn: CGRect(x: center.x - radius * 0.55, y: center.y - radius * 0.6, width: radius * 0.4, height: radius * 0.26)).fill()
        }
    }

    private static func drawFlower(in art: CGRect) {
        let grid = Grid(rect: art)
        let petals = (0..<5).map { index -> UIBezierPath in
            let angle = CGFloat(index) * 72 - 90
            let radians = angle * .pi / 180
            return grid.ellipse(0.5 + cos(radians) * 0.25, 0.5 + sin(radians) * 0.25, 0.34, 0.44, degrees: angle + 90)
        }
        let heart = UIBezierPath(ovalIn: grid.r(0.36, 0.36, 0.28, 0.28))
        dieCut(petals + [heart])
        UIColor.brandBlush.setFill()
        petals.forEach { $0.fill() }
        UIColor.white.withAlphaComponent(0.55).setStroke()
        for petal in petals {
            petal.lineWidth = 3
            petal.stroke()
        }
        UIColor.auraButter.setFill()
        heart.fill()
        UIColor.auraPeach.setFill()
        for index in 0..<5 {
            let radians = (CGFloat(index) * 72 - 54) * .pi / 180
            grid.ellipse(0.5 + cos(radians) * 0.07, 0.5 + sin(radians) * 0.07, 0.04, 0.04).fill()
        }
    }

    private static func drawSmiley(in art: CGRect) {
        let grid = Grid(rect: art)
        let face = UIBezierPath(ovalIn: art)
        dieCut([face])
        UIColor.auraButter.setFill()
        face.fill()
        UIColor.auraPink.withAlphaComponent(0.45).setFill()
        grid.ellipse(0.23, 0.6, 0.15, 0.09).fill()
        grid.ellipse(0.77, 0.6, 0.15, 0.09).fill()
        UIColor.plum.setFill()
        grid.ellipse(0.36, 0.38, 0.1, 0.17).fill()
        grid.ellipse(0.64, 0.38, 0.1, 0.17).fill()
        let smile = UIBezierPath(arcCenter: grid.p(0.5, 0.52), radius: art.width * 0.26,
                                 startAngle: .pi * 0.18, endAngle: .pi * 0.82, clockwise: true)
        UIColor.plum.setStroke()
        smile.lineWidth = art.width * 0.06
        smile.lineCapStyle = .round
        smile.stroke()
    }

    private static func drawBubble(_ sticker: Sticker, in art: CGRect) {
        let body = CGRect(x: art.minX, y: art.minY, width: art.width, height: art.height - bubbleTail)
        let bubble = UIBezierPath(roundedRect: body, cornerRadius: min(body.height / 2, 64))
        let tail = UIBezierPath()
        tail.move(to: CGPoint(x: body.minX + body.width * 0.2, y: body.maxY - 10))
        tail.addLine(to: CGPoint(x: body.minX + body.width * 0.1, y: art.maxY))
        tail.addLine(to: CGPoint(x: body.minX + body.width * 0.38, y: body.maxY - 10))
        tail.close()
        // Outlines first, then fills, so the tail joins the bubble seamlessly.
        dieCut([bubble, tail], width: edge + bubbleOutline)
        UIColor.brandInk.setStroke()
        for path in [bubble, tail] {
            path.lineWidth = bubbleOutline * 2
            path.lineJoinStyle = .round
            path.stroke()
        }
        bubbleColors(sticker.kind).fill.setFill()
        bubble.fill()
        tail.fill()
        let text = bubbleText(sticker)
        let size = text.size()
        text.draw(at: CGPoint(x: body.midX - size.width / 2, y: body.midY - size.height / 2))
    }

    private static func drawDateStamp(_ sticker: Sticker, in rect: CGRect, context cg: CGContext, pixelsPerUnit: CGFloat) {
        let text = dateText(sticker)
        let size = text.size()
        cg.saveGState()
        // The orange glow of a disposable camera's printed date.
        cg.setShadow(offset: .zero, blur: 7 * pixelsPerUnit, color: UIColor(red: 1, green: 0.3, blue: 0, alpha: 0.6).cgColor)
        text.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        cg.restoreGState()
    }

    // MARK: Text

    private static func bubbleColors(_ kind: StickerKind) -> (fill: UIColor, text: UIColor) {
        switch kind {
        case .slay: return (.brandInk, .brandBlush)
        case .bestie: return (.brandBlush, .brandInk)
        default: return (.white, .auraPink)
        }
    }

    private static func bubbleText(_ sticker: Sticker) -> NSAttributedString {
        let font = UIFont(name: BrandFont.postScriptName(for: .heavy), size: 60) ?? .systemFont(ofSize: 60, weight: .heavy)
        return NSAttributedString(string: sticker.text ?? "", attributes: [.font: font, .foregroundColor: bubbleColors(sticker.kind).text])
    }

    private static func dateText(_ sticker: Sticker) -> NSAttributedString {
        NSAttributedString(string: sticker.text ?? "", attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 52, weight: .semibold),
            .foregroundColor: UIColor(red: 1, green: 0.55, blue: 0.18, alpha: 0.95),
        ])
    }

    /// "'26 10 14", like a disposable camera's date.
    static func dateStampText(for date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return String(format: "'%02d %02d %02d", (parts.year ?? 2026) % 100, parts.month ?? 1, parts.day ?? 1)
    }

    // MARK: Paths

    private static func heartPath(in rect: CGRect) -> UIBezierPath {
        let grid = Grid(rect: rect)
        let heart = UIBezierPath()
        heart.move(to: grid.p(0.5, 0.98))
        heart.addCurve(to: grid.p(0, 0.33), controlPoint1: grid.p(0.2, 0.77), controlPoint2: grid.p(0, 0.56))
        heart.addCurve(to: grid.p(0.5, 0.16), controlPoint1: grid.p(0, 0.05), controlPoint2: grid.p(0.38, -0.01))
        heart.addCurve(to: grid.p(1, 0.33), controlPoint1: grid.p(0.62, -0.01), controlPoint2: grid.p(1, 0.05))
        heart.addCurve(to: grid.p(0.5, 0.98), controlPoint1: grid.p(1, 0.56), controlPoint2: grid.p(0.8, 0.77))
        heart.close()
        return heart
    }

    /// The brand's four-point sparkle.
    static func sparklePath(center: CGPoint, radius: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        for index in 0..<4 {
            let angle = CGFloat(index) * .pi / 2 - .pi / 2
            let next = angle + .pi / 2
            let tip = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            let nextTip = CGPoint(x: center.x + cos(next) * radius, y: center.y + sin(next) * radius)
            let waist = CGPoint(x: center.x + cos(angle + .pi / 4) * radius * 0.22, y: center.y + sin(angle + .pi / 4) * radius * 0.22)
            if index == 0 { path.move(to: tip) }
            path.addQuadCurve(to: nextTip, controlPoint: waist)
        }
        path.close()
        return path
    }

    private static func starPath(center: CGPoint, outer: CGFloat, inner: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        for index in 0..<10 {
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = CGFloat(index) * .pi / 5 - .pi / 2
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.close()
        return path
    }

    private static func mirrored(_ path: UIBezierPath, in rect: CGRect) -> UIBezierPath {
        let copy = UIBezierPath(cgPath: path.cgPath)
        copy.apply(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.midX * 2, ty: 0))
        return copy
    }

    /// The white die-cut edge, drawn under the shapes' fills.
    private static func dieCut(_ paths: [UIBezierPath], width: CGFloat = edge) {
        UIColor.white.setStroke()
        for path in paths {
            path.lineWidth = width * 2
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.stroke()
        }
    }

    /// 0…1 coordinates in a rectangle.
    private struct Grid {
        let rect: CGRect

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }

        func r(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height, width: width * rect.width, height: height * rect.height)
        }

        /// An ellipse centred on (x, y), turned clockwise by `degrees`.
        func ellipse(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, degrees: CGFloat = 0) -> UIBezierPath {
            let w = width * rect.width
            let h = height * rect.height
            let path = UIBezierPath(ovalIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
            path.apply(CGAffineTransform(rotationAngle: degrees * .pi / 180))
            path.apply(CGAffineTransform(translationX: rect.minX + x * rect.width, y: rect.minY + y * rect.height))
            return path
        }
    }
}
