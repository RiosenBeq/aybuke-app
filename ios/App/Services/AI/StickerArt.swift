import UIKit

enum StickerKind: String, CaseIterable, Identifiable, Sendable {
    // Tray order: the tray fills two rows column by column.
    case heart, chromeHeart, sparkles, sparkleBurst, star, moon, butterfly, bow, ribbonBow, crown, cherries, flower, daisy
    case rainbow, cloud, smiley, musicNotes, camera, filmStrip, omg, slay, bestie, mainCharacter, yay, dateStamp

    var id: String { rawValue }

    /// The sticker's name for VoiceOver and the sticker tray.
    var title: String {
        switch self {
        case .heart: return String(localized: "Heart")
        case .chromeHeart: return String(localized: "Chrome heart", comment: "A shiny metallic Y2K-style heart sticker")
        case .sparkles: return String(localized: "Sparkles")
        case .sparkleBurst: return String(localized: "Sparkle burst", comment: "A sticker of one big sparkle with little rays around it")
        case .star: return String(localized: "Star")
        case .moon: return String(localized: "Moon and stars", comment: "A sticker of a sleepy crescent moon with two little stars")
        case .butterfly: return String(localized: "Butterfly")
        case .bow: return String(localized: "Bow", comment: "A ribbon bow sticker")
        case .ribbonBow: return String(localized: "Ribbon bow", comment: "A sticker of a pale pink bow with long, wavy ribbon tails")
        case .crown: return String(localized: "Crown", comment: "A sticker of a cute golden crown with pink gems")
        case .cherries: return String(localized: "Cherries")
        case .flower: return String(localized: "Flower")
        case .daisy: return String(localized: "Daisy", comment: "A sticker of a white daisy flower")
        case .rainbow: return String(localized: "Rainbow", comment: "A sticker of a pastel rainbow with a cloud at each end")
        case .cloud: return String(localized: "Cloud", comment: "A sticker of a smiling white cloud")
        case .smiley: return String(localized: "Smiley")
        case .musicNotes: return String(localized: "Music notes", comment: "A sticker of two joined music notes")
        case .camera: return String(localized: "Camera", comment: "A sticker of a cute retro photo camera")
        case .filmStrip: return String(localized: "Film strip")
        case .omg, .slay, .bestie, .mainCharacter, .yay:
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
        case .mainCharacter:
            return String(localized: "main character", comment: "Speech-bubble sticker in the photo editor: feeling like the star of your own story. Keep it short.")
        case .yay: return String(localized: "yay", comment: "Speech-bubble sticker in the photo editor: a happy cheer")
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
        case .sparkleBurst: art = CGSize(width: 220, height: 220)
        case .star: art = CGSize(width: 210, height: 204)
        case .moon: art = CGSize(width: 220, height: 220)
        case .butterfly: art = CGSize(width: 250, height: 206)
        case .bow: art = CGSize(width: 256, height: 194)
        case .ribbonBow: art = CGSize(width: 240, height: 236)
        case .crown: art = CGSize(width: 236, height: 196)
        case .cherries: art = CGSize(width: 190, height: 216)
        case .flower: art = CGSize(width: 208, height: 208)
        case .daisy: art = CGSize(width: 220, height: 220)
        case .rainbow: art = CGSize(width: 256, height: 172)
        case .cloud: art = CGSize(width: 246, height: 172)
        case .smiley: art = CGSize(width: 196, height: 196)
        case .musicNotes: art = CGSize(width: 206, height: 220)
        case .camera: art = CGSize(width: 248, height: 196)
        case .filmStrip: art = CGSize(width: 256, height: 168)
        case .omg, .slay, .bestie, .mainCharacter, .yay:
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
        case .sparkleBurst: drawSparkleBurst(in: art)
        case .star: drawStar(in: art)
        case .moon: drawMoon(in: art, context: cg)
        case .butterfly: drawButterfly(in: art)
        case .bow: drawBow(in: art)
        case .ribbonBow: drawRibbonBow(in: art)
        case .crown: drawCrown(in: art, context: cg)
        case .cherries: drawCherries(in: art, context: cg)
        case .flower: drawFlower(in: art)
        case .daisy: drawDaisy(in: art)
        case .rainbow: drawRainbow(in: art)
        case .cloud: drawCloud(in: art, context: cg)
        case .smiley: drawSmiley(in: art)
        case .musicNotes: drawMusicNotes(in: art)
        case .camera: drawCamera(in: art)
        case .filmStrip: drawFilmStrip(in: art, context: cg)
        case .omg, .slay, .bestie, .mainCharacter, .yay: drawBubble(sticker, in: art)
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

    /// One big sparkle with little rays around it, like a flash going off.
    private static func drawSparkleBurst(in art: CGRect) {
        let grid = Grid(rect: art)
        let center = grid.p(0.5, 0.5)
        let sparkle = sparklePath(center: center, radius: art.width * 0.34)
        // Rays between the sparkle's points, long and short in turn.
        let rays = UIBezierPath()
        for index in 0..<8 {
            let angle = CGFloat(index) * .pi / 4 + .pi / 8
            let inner = art.width * 0.31
            let outer = art.width * (index.isMultiple(of: 2) ? 0.47 : 0.41)
            rays.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            rays.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
        }
        let rayWidth = art.width * 0.055
        dieCut([sparkle])
        dieCut([rays], width: edge * 0.75 + rayWidth / 2)
        UIColor.auraPink.setStroke()
        rays.lineWidth = rayWidth
        rays.stroke()
        UIColor.auraButter.setFill()
        sparkle.fill()
        // Stroking in the same colour softens the points a little.
        UIColor.auraButter.setStroke()
        sparkle.lineWidth = 6
        sparkle.stroke()
        UIColor.white.withAlphaComponent(0.75).setFill()
        sparklePath(center: grid.p(0.42, 0.42), radius: art.width * 0.09).fill()
    }

    /// A sleepy crescent moon with two little stars.
    private static func drawMoon(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let bite = grid.p(0.63, 0.41)
        let biteRadius = art.width * 0.33
        let moon = crescentPath(center: grid.p(0.42, 0.56), radius: art.width * 0.4, bite: bite, biteRadius: biteRadius)
        let bigStar = starPath(center: grid.p(0.77, 0.2), outer: art.width * 0.13, inner: art.width * 0.065)
        let smallStar = starPath(center: grid.p(0.88, 0.5), outer: art.width * 0.08, inner: art.width * 0.04)
        dieCut([moon, bigStar, smallStar])
        UIColor.auraButter.setFill()
        moon.fill()
        // A warmer shade along the inner curve.
        cg.saveGState()
        moon.addClip()
        let innerEdge = UIBezierPath(ovalIn: CGRect(x: bite.x - biteRadius, y: bite.y - biteRadius, width: biteRadius * 2, height: biteRadius * 2))
        UIColor.auraPeach.withAlphaComponent(0.4).setStroke()
        innerEdge.lineWidth = art.width * 0.12
        innerEdge.stroke()
        cg.restoreGState()
        for (star, color) in [(bigStar, UIColor.auraLilac), (smallStar, UIColor.auraPink)] {
            color.setFill()
            star.fill()
            color.setStroke()
            star.lineWidth = 7
            star.lineJoinStyle = .round
            star.stroke()
        }
        // A closed, smiling eye and a blush cheek.
        let eye = UIBezierPath(arcCenter: grid.p(0.21, 0.6), radius: art.width * 0.05,
                               startAngle: .pi * 0.1, endAngle: .pi * 0.9, clockwise: true)
        UIColor.plum.setStroke()
        eye.lineWidth = art.width * 0.025
        eye.lineCapStyle = .round
        eye.stroke()
        UIColor.auraPink.withAlphaComponent(0.45).setFill()
        grid.ellipse(0.2, 0.74, 0.11, 0.07).fill()
    }

    /// A pale satin bow with long, wavy ribbon tails.
    private static func drawRibbonBow(in art: CGRect) {
        let grid = Grid(rect: art)
        let loop = UIBezierPath()
        loop.move(to: grid.p(0.46, 0.27))
        loop.addCurve(to: grid.p(0.09, 0.06), controlPoint1: grid.p(0.36, 0.08), controlPoint2: grid.p(0.18, -0.01))
        loop.addCurve(to: grid.p(0.12, 0.42), controlPoint1: grid.p(0.01, 0.12), controlPoint2: grid.p(0.01, 0.36))
        loop.addCurve(to: grid.p(0.46, 0.34), controlPoint1: grid.p(0.22, 0.48), controlPoint2: grid.p(0.36, 0.41))
        loop.close()
        let tail = UIBezierPath()
        tail.move(to: grid.p(0.45, 0.33))
        tail.addCurve(to: grid.p(0.28, 0.64), controlPoint1: grid.p(0.36, 0.43), controlPoint2: grid.p(0.25, 0.53))
        tail.addCurve(to: grid.p(0.2, 0.97), controlPoint1: grid.p(0.32, 0.77), controlPoint2: grid.p(0.22, 0.86))
        // The notched end of the ribbon.
        tail.addLine(to: grid.p(0.28, 0.91))
        tail.addLine(to: grid.p(0.33, 0.98))
        tail.addCurve(to: grid.p(0.38, 0.65), controlPoint1: grid.p(0.35, 0.88), controlPoint2: grid.p(0.43, 0.77))
        tail.addCurve(to: grid.p(0.53, 0.36), controlPoint1: grid.p(0.34, 0.55), controlPoint2: grid.p(0.46, 0.44))
        tail.close()
        let loops = [loop, mirrored(loop, in: art)]
        let tails = [tail, mirrored(tail, in: art)]
        let knot = UIBezierPath(roundedRect: grid.r(0.41, 0.22, 0.18, 0.17), cornerRadius: art.width * 0.06)
        dieCut(loops + tails + [knot])

        let satin = UIColor.brandBlush
        let shade = UIColor.brandBlush.mixed(with: .auraPink, amount: 0.3)
        shade.setFill()
        tails.forEach { $0.fill() }
        satin.setFill()
        loops.forEach { $0.fill() }
        // A fine pink edge, so the pale satin reads on light photos too.
        UIColor.auraPink.withAlphaComponent(0.6).setStroke()
        for path in loops + tails {
            path.lineWidth = 3.5
            path.lineJoinStyle = .round
            path.stroke()
        }
        // A fold inside each loop and a shine on top.
        let fold = UIBezierPath()
        fold.move(to: grid.p(0.42, 0.31))
        fold.addQuadCurve(to: grid.p(0.14, 0.2), controlPoint: grid.p(0.26, 0.18))
        UIColor.auraPink.withAlphaComponent(0.35).setStroke()
        for path in [fold, mirrored(fold, in: art)] {
            path.lineWidth = 4
            path.lineCapStyle = .round
            path.stroke()
        }
        UIColor.white.withAlphaComponent(0.6).setFill()
        grid.ellipse(0.2, 0.13, 0.1, 0.05, degrees: -28).fill()
        grid.ellipse(0.8, 0.13, 0.1, 0.05, degrees: 28).fill()
        shade.setFill()
        knot.fill()
        UIColor.auraPink.withAlphaComponent(0.6).setStroke()
        knot.lineWidth = 3.5
        knot.stroke()
    }

    /// A little golden crown with round tips, pink gems and a heart.
    private static func drawCrown(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let body = UIBezierPath()
        body.move(to: grid.p(0.12, 0.88))
        body.addLine(to: grid.p(0.08, 0.32))
        body.addLine(to: grid.p(0.31, 0.56))
        body.addLine(to: grid.p(0.5, 0.2))
        body.addLine(to: grid.p(0.69, 0.56))
        body.addLine(to: grid.p(0.92, 0.32))
        body.addLine(to: grid.p(0.88, 0.88))
        body.addQuadCurve(to: grid.p(0.12, 0.88), controlPoint: grid.p(0.5, 0.97))
        body.close()
        let tipRadius = art.width * 0.062
        let tipCenters = [grid.p(0.08, 0.27), grid.p(0.5, 0.14), grid.p(0.92, 0.27)]
        let tips = tipCenters.map { UIBezierPath(ovalIn: CGRect(x: $0.x - tipRadius, y: $0.y - tipRadius, width: tipRadius * 2, height: tipRadius * 2)) }
        dieCut([body] + tips)

        // Stroking the outline in deep gold first rounds the points.
        let deepGold = UIColor.auraButter.mixed(with: .auraPeach, amount: 0.55)
        deepGold.setStroke()
        body.lineWidth = 9
        body.lineJoinStyle = .round
        body.stroke()
        cg.saveGState()
        body.addClip()
        if let gold = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [UIColor.auraButter.mixed(with: .white, amount: 0.35).cgColor, UIColor.auraButter.cgColor, deepGold.cgColor] as CFArray,
                                 locations: [0, 0.45, 1]) {
            cg.drawLinearGradient(gold, start: CGPoint(x: art.midX, y: art.minY), end: CGPoint(x: art.midX, y: art.maxY), options: [])
        }
        // The band along the bottom.
        UIColor.auraPeach.withAlphaComponent(0.45).setFill()
        UIBezierPath(rect: grid.r(0, 0.7, 1, 0.3)).fill()
        cg.restoreGState()

        UIColor.auraPink.setFill()
        tips.forEach { $0.fill() }
        // Gems on the band: a heart between two round ones.
        UIColor.auraLilac.setFill()
        grid.ellipse(0.27, 0.79, 0.09, 0.09).fill()
        grid.ellipse(0.73, 0.79, 0.09, 0.09).fill()
        UIColor.auraPink.setFill()
        heartPath(in: grid.r(0.42, 0.69, 0.16, 0.17)).fill()
        UIColor.white.withAlphaComponent(0.7).setFill()
        for center in tipCenters {
            UIBezierPath(ovalIn: CGRect(x: center.x - tipRadius * 0.55, y: center.y - tipRadius * 0.6,
                                        width: tipRadius * 0.6, height: tipRadius * 0.45)).fill()
        }
        grid.ellipse(0.46, 0.73, 0.04, 0.03, degrees: -30).fill()
        sparklePath(center: grid.p(0.5, 0.45), radius: art.width * 0.07).fill()
    }

    /// A white daisy with a butter-yellow centre.
    private static func drawDaisy(in art: CGRect) {
        let grid = Grid(rect: art)
        let petals = (0..<12).map { index -> UIBezierPath in
            let angle = CGFloat(index) * 30 - 90
            let radians = angle * .pi / 180
            return grid.ellipse(0.5 + cos(radians) * 0.29, 0.5 + sin(radians) * 0.29, 0.15, 0.4, degrees: angle + 90)
        }
        let heart = UIBezierPath(ovalIn: grid.r(0.35, 0.35, 0.3, 0.3))
        dieCut(petals + [heart])
        // A soft lilac line first, so white petals show on the white edge
        // and on a bright sky; the fills cover its inner half.
        UIColor.auraLilac.withAlphaComponent(0.45).setStroke()
        for petal in petals {
            petal.lineWidth = 4
            petal.stroke()
        }
        UIColor.white.setFill()
        petals.forEach { $0.fill() }
        UIColor.auraButter.mixed(with: .auraPeach, amount: 0.25).setFill()
        heart.fill()
        UIColor.auraPeach.withAlphaComponent(0.7).setFill()
        for index in 0..<6 {
            let radians = (CGFloat(index) * 60 + 15) * .pi / 180
            grid.ellipse(0.5 + cos(radians) * 0.085, 0.5 + sin(radians) * 0.085, 0.035, 0.035).fill()
        }
        UIColor.white.withAlphaComponent(0.6).setFill()
        grid.ellipse(0.44, 0.42, 0.08, 0.05, degrees: -30).fill()
    }

    /// A pastel rainbow with a cloud at each end.
    private static func drawRainbow(in art: CGRect) {
        let grid = Grid(rect: art)
        let center = grid.p(0.5, 0.86)
        let outer = art.width * 0.44
        let band = art.width * 0.062
        let colors: [UIColor] = [.auraPink, .auraPeach, .auraButter, .auraMint, .auraLilac]
        let whole = arch(center: center, outer: outer, inner: outer - band * CGFloat(colors.count))
        let clouds = [grid.p(0.2, 0.83), grid.p(0.8, 0.83)].map { cloudPath(center: $0, width: art.width * 0.36) }
        dieCut([whole] + clouds)
        for (index, color) in colors.enumerated() {
            color.setFill()
            arch(center: center, outer: outer - band * CGFloat(index), inner: outer - band * CGFloat(index + 1)).fill()
        }
        // Rim first, then the fill, so only the clouds' outline shows.
        UIColor.auraLilac.withAlphaComponent(0.5).setStroke()
        for cloud in clouds {
            cloud.lineWidth = 5
            cloud.stroke()
        }
        UIColor.white.setFill()
        clouds.forEach { $0.fill() }
    }

    /// A smiling white cloud.
    private static func drawCloud(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let cloud = cloudPath(center: grid.p(0.5, 0.57), width: art.width * 0.92)
        dieCut([cloud])
        UIColor.auraLilac.withAlphaComponent(0.5).setStroke()
        cloud.lineWidth = 6
        cloud.stroke()
        UIColor.white.setFill()
        cloud.fill()
        // A soft lilac shade along the bottom.
        cg.saveGState()
        cloud.addClip()
        if let shade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [UIColor.auraLilac.withAlphaComponent(0).cgColor, UIColor.auraLilac.withAlphaComponent(0.22).cgColor] as CFArray,
                                  locations: [0.55, 1]) {
            cg.drawLinearGradient(shade, start: CGPoint(x: art.midX, y: art.minY), end: CGPoint(x: art.midX, y: art.maxY), options: [])
        }
        cg.restoreGState()
        UIColor.plum.setFill()
        grid.ellipse(0.41, 0.58, 0.04, 0.085).fill()
        grid.ellipse(0.59, 0.58, 0.04, 0.085).fill()
        let smile = UIBezierPath(arcCenter: grid.p(0.5, 0.63), radius: art.width * 0.04,
                                 startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: true)
        UIColor.plum.setStroke()
        smile.lineWidth = art.width * 0.02
        smile.lineCapStyle = .round
        smile.stroke()
        UIColor.auraPink.withAlphaComponent(0.4).setFill()
        grid.ellipse(0.32, 0.67, 0.09, 0.07).fill()
        grid.ellipse(0.68, 0.67, 0.09, 0.07).fill()
    }

    /// Two joined eighth notes and a little sparkle.
    private static func drawMusicNotes(in art: CGRect) {
        let grid = Grid(rect: art)
        let notes = UIBezierPath()
        notes.append(grid.ellipse(0.24, 0.8, 0.3, 0.2, degrees: -22))
        notes.append(grid.ellipse(0.74, 0.7, 0.3, 0.2, degrees: -22))
        notes.append(UIBezierPath(rect: grid.r(0.33, 0.2, 0.065, 0.6)))
        notes.append(UIBezierPath(rect: grid.r(0.83, 0.1, 0.065, 0.6)))
        let beam = UIBezierPath()
        beam.move(to: grid.p(0.33, 0.2))
        beam.addLine(to: grid.p(0.895, 0.08))
        beam.addLine(to: grid.p(0.895, 0.23))
        beam.addLine(to: grid.p(0.33, 0.35))
        beam.close()
        notes.append(beam)
        let sparkle = sparklePath(center: grid.p(0.12, 0.24), radius: art.width * 0.1)
        dieCut([notes, sparkle])
        UIColor.auraPink.setFill()
        notes.fill()
        // Stroking in the same colour rounds the corners.
        UIColor.auraPink.setStroke()
        notes.lineWidth = 6
        notes.lineJoinStyle = .round
        notes.stroke()
        UIColor.auraLilac.setFill()
        sparkle.fill()
        UIColor.white.withAlphaComponent(0.55).setFill()
        grid.ellipse(0.19, 0.77, 0.09, 0.05, degrees: -22).fill()
        grid.ellipse(0.69, 0.67, 0.09, 0.05, degrees: -22).fill()
        grid.ellipse(0.5, 0.23, 0.16, 0.035, degrees: -12).fill()
    }

    /// A cute retro camera with a big lens and a heart on it.
    private static func drawCamera(in art: CGRect) {
        let grid = Grid(rect: art)
        let body = UIBezierPath(roundedRect: grid.r(0.02, 0.24, 0.96, 0.72), cornerRadius: art.width * 0.1)
        let top = UIBezierPath(roundedRect: grid.r(0.3, 0.08, 0.34, 0.24), cornerRadius: art.width * 0.05)
        let button = UIBezierPath(roundedRect: grid.r(0.73, 0.13, 0.15, 0.15), cornerRadius: art.width * 0.03)
        dieCut([body, top, button])
        UIColor.auraPink.setFill()
        button.fill()
        UIColor.brandBlush.mixed(with: .auraPink, amount: 0.3).setFill()
        top.fill()
        UIColor.brandBlush.setFill()
        body.fill()
        // A grip band across the middle.
        UIColor.auraPink.withAlphaComponent(0.22).setFill()
        UIBezierPath(rect: grid.r(0.02, 0.5, 0.96, 0.2)).fill()
        // The lens, ring by ring, and its glint.
        let lens = grid.p(0.5, 0.6)
        let rings: [(CGFloat, UIColor)] = [(0.25, .brandInk), (0.2, .plum), (0.135, .auraLilac), (0.07, .brandInk)]
        for (radius, color) in rings {
            let r = art.width * radius
            color.setFill()
            UIBezierPath(ovalIn: CGRect(x: lens.x - r, y: lens.y - r, width: r * 2, height: r * 2)).fill()
        }
        UIColor.white.withAlphaComponent(0.8).setFill()
        grid.ellipse(0.45, 0.52, 0.07, 0.05, degrees: -35).fill()
        UIColor.auraButter.setFill()
        UIBezierPath(roundedRect: grid.r(0.09, 0.33, 0.15, 0.11), cornerRadius: art.width * 0.02).fill()
        UIColor.auraPink.setFill()
        heartPath(in: grid.r(0.8, 0.36, 0.1, 0.11)).fill()
    }

    /// A tilted strip of film with three pastel frames.
    private static func drawFilmStrip(in art: CGRect, context cg: CGContext) {
        cg.saveGState()
        cg.translateBy(x: art.midX, y: art.midY)
        cg.rotate(by: -7 * .pi / 180)
        let width = art.width * 0.86
        let height = art.height * 0.64
        let strip = UIBezierPath(roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height), cornerRadius: height * 0.08)
        dieCut([strip])
        UIColor.brandInk.setFill()
        strip.fill()
        // Sprocket holes along both edges.
        let holes = 9
        let hole = CGSize(width: width * 0.05, height: height * 0.09)
        let step = width / CGFloat(holes)
        UIColor.white.withAlphaComponent(0.9).setFill()
        for index in 0..<holes {
            let x = -width / 2 + step * (CGFloat(index) + 0.5) - hole.width / 2
            for y in [-height / 2 + height * 0.06, height / 2 - height * 0.06 - hole.height] {
                UIBezierPath(roundedRect: CGRect(x: x, y: y, width: hole.width, height: hole.height), cornerRadius: hole.height * 0.3).fill()
            }
        }
        // Three frames, each with a little drawing.
        let gap = width * 0.035
        let frame = CGSize(width: (width - gap * 4) / 3, height: height * 0.6)
        let colors: [UIColor] = [.brandBlush, .auraButter, .auraMint]
        for (index, color) in colors.enumerated() {
            let rect = CGRect(x: -width / 2 + gap + CGFloat(index) * (frame.width + gap), y: -frame.height / 2,
                              width: frame.width, height: frame.height)
            color.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: frame.height * 0.08).fill()
            let mark = CGRect(x: rect.midX - frame.height * 0.22, y: rect.midY - frame.height * 0.2,
                              width: frame.height * 0.44, height: frame.height * 0.4)
            UIColor.white.setFill()
            switch index {
            case 0: heartPath(in: mark).fill()
            case 1: sparklePath(center: CGPoint(x: mark.midX, y: mark.midY), radius: mark.width * 0.55).fill()
            default: starPath(center: CGPoint(x: mark.midX, y: mark.midY + mark.height * 0.04), outer: mark.width * 0.5, inner: mark.width * 0.25).fill()
            }
        }
        cg.restoreGState()
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
        case .mainCharacter: return (.auraButter, .plum)
        case .yay: return (.auraPink, .white)
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

    /// The part of a circle that a second circle (the bite, overlapping its
    /// edge) doesn't cover: a crescent.
    private static func crescentPath(center: CGPoint, radius: CGFloat, bite: CGPoint, biteRadius: CGFloat) -> UIBezierPath {
        let dx = bite.x - center.x
        let dy = bite.y - center.y
        let distance = max(hypot(dx, dy), 0.001)
        // Where the two circles cross.
        let along = (radius * radius - biteRadius * biteRadius + distance * distance) / (2 * distance)
        let across = sqrt(max(radius * radius - along * along, 0))
        let base = CGPoint(x: center.x + along * dx / distance, y: center.y + along * dy / distance)
        let first = CGPoint(x: base.x - across * dy / distance, y: base.y + across * dx / distance)
        let second = CGPoint(x: base.x + across * dy / distance, y: base.y - across * dx / distance)
        let path = UIBezierPath()
        // The outer circle the long way round, away from the bite, then
        // back along the bite's edge inside it.
        path.addArc(withCenter: center, radius: radius, startAngle: atan2(first.y - center.y, first.x - center.x),
                    endAngle: atan2(second.y - center.y, second.x - center.x), clockwise: true)
        path.addArc(withCenter: bite, radius: biteRadius, startAngle: atan2(second.y - bite.y, second.x - bite.x),
                    endAngle: atan2(first.y - bite.y, first.x - bite.x), clockwise: false)
        path.close()
        return path
    }

    /// The top half of a ring, for rainbow bands.
    private static func arch(center: CGPoint, outer: CGFloat, inner: CGFloat) -> UIBezierPath {
        let path = UIBezierPath(arcCenter: center, radius: outer, startAngle: .pi, endAngle: 2 * .pi, clockwise: true)
        path.addArc(withCenter: center, radius: inner, startAngle: 2 * .pi, endAngle: .pi, clockwise: false)
        path.close()
        return path
    }

    /// A puffy cloud about `width` wide and 0.6 of that tall, centred on
    /// `center`: three bumps on a rounded base.
    private static func cloudPath(center: CGPoint, width: CGFloat) -> UIBezierPath {
        func bump(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> UIBezierPath {
            UIBezierPath(ovalIn: CGRect(x: center.x + (x - r) * width, y: center.y + (y - r) * width, width: r * 2 * width, height: r * 2 * width))
        }
        let cloud = bump(-0.27, 0.04, 0.2)
        cloud.append(bump(-0.02, -0.08, 0.27))
        cloud.append(bump(0.26, 0.01, 0.21))
        cloud.append(UIBezierPath(roundedRect: CGRect(x: center.x - 0.45 * width, y: center.y - 0.02 * width, width: 0.9 * width, height: 0.24 * width),
                                  cornerRadius: 0.12 * width))
        return cloud
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
