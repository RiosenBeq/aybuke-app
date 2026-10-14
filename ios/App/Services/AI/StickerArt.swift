import UIKit
import SwiftUI

/// The sticker tray's sections. Each sticker sits in one; All shows them all.
enum StickerCategory: String, CaseIterable, Identifiable, Sendable {
    case all, cute, y2k, glam, love, sky, words

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .all: return "All"
        case .cute: return "Cute"
        // Like the effects' era tags, Y2K reads the same in every language.
        case .y2k: return "Y2K"
        case .glam: return "Glam"
        case .love: return "Love"
        case .sky: return "Sky"
        case .words: return "Words"
        }
    }

    /// The stickers in this section, in tray order.
    var kinds: [StickerKind] {
        self == .all ? StickerKind.allCases : StickerKind.allCases.filter { $0.category == self }
    }
}

enum StickerKind: String, CaseIterable, Identifiable, Sendable {
    // Tray order for All: favourites first, then the rest by section.
    case heart, sparkles, bow, butterfly, star, cherries, flower, smiley, chromeHeart
    case puffyHeart, strawberry, ribbonBow, crown, moon, rainbow, cloud, bunny, kitty, bear
    case mushroom, heartCloud, boba, daisy, musicNotes
    case pearls, ginghamBow, heartLocket, lipGloss, compactMirror, nailPolish, mascara, perfume
    case chromeStar, holoHeart, butterflyClip, flipCell, cd, sparkleBurst, camera, filmStrip
    case twinHearts, loveLetter, rose, sun, shootingStar, planet
    case omg, slay, bestie, mainCharacter, yay, itGirl, vibes, coreMemory, dateStamp

    var id: String { rawValue }

    var category: StickerCategory {
        switch self {
        case .cherries, .flower, .smiley, .butterfly, .strawberry, .cloud, .bunny, .kitty, .bear, .mushroom, .heartCloud,
             .boba, .daisy, .musicNotes:
            return .cute
        case .chromeHeart, .chromeStar, .holoHeart, .butterflyClip, .flipCell, .cd, .sparkleBurst, .camera, .filmStrip, .dateStamp:
            return .y2k
        case .bow, .ribbonBow, .crown, .pearls, .ginghamBow, .lipGloss, .compactMirror, .nailPolish, .mascara, .perfume:
            return .glam
        case .heart, .puffyHeart, .heartLocket, .twinHearts, .loveLetter, .rose:
            return .love
        case .sparkles, .star, .moon, .rainbow, .sun, .shootingStar, .planet:
            return .sky
        case .omg, .slay, .bestie, .mainCharacter, .yay, .itGirl, .vibes, .coreMemory:
            return .words
        }
    }

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
        case .puffyHeart: return String(localized: "Puffy heart", comment: "A sticker of a glossy, puffy 3D heart")
        case .twinHearts: return String(localized: "Two hearts", comment: "A sticker of two overlapping hearts")
        case .loveLetter: return String(localized: "Love letter", comment: "A sticker of an envelope closed with a heart seal")
        case .heartLocket: return String(localized: "Heart locket", comment: "A sticker of a golden heart-shaped locket on a chain")
        case .rose: return String(localized: "Rose", comment: "A sticker of a pink rose flower")
        case .strawberry: return String(localized: "Strawberry")
        case .mushroom: return String(localized: "Mushroom", comment: "A sticker of a cute spotted mushroom with a little face")
        case .bunny: return String(localized: "Bunny", comment: "A sticker of a cute bunny's face")
        case .kitty: return String(localized: "Kitty", comment: "A sticker of a cute cat's face")
        case .bear: return String(localized: "Teddy bear", comment: "A sticker of a cute teddy bear's face")
        case .heartCloud: return String(localized: "Heart cloud", comment: "A sticker of a pink cloud raining little hearts")
        case .boba: return String(localized: "Bubble tea", comment: "A sticker of a cup of bubble tea with a straw")
        case .pearls: return String(localized: "Pearls", comment: "A sticker of a pearl necklace with a little bow")
        case .ginghamBow: return String(localized: "Gingham bow", comment: "A sticker of a bow in pink and white checked fabric")
        case .lipGloss: return String(localized: "Lip gloss", comment: "A sticker of a lip gloss tube (the object only)")
        case .compactMirror: return String(localized: "Compact mirror", comment: "A sticker of an open makeup compact with a mirror")
        case .nailPolish: return String(localized: "Nail polish", comment: "A sticker of a bottle of nail polish (the object only)")
        case .mascara: return String(localized: "Mascara", comment: "A sticker of a mascara tube and wand (the object only)")
        case .perfume: return String(localized: "Perfume", comment: "A sticker of a heart-shaped perfume bottle")
        case .chromeStar: return String(localized: "Chrome star", comment: "A shiny metallic Y2K-style star sticker")
        case .holoHeart: return String(localized: "Holo heart", comment: "A sticker of a holographic, rainbow-shimmer heart")
        case .butterflyClip: return String(localized: "Butterfly clip", comment: "A sticker of a Y2K butterfly hair clip")
        case .flipCell: return String(localized: "Flip cell", comment: "A sticker of a pink Y2K flip-open mobile with a heart on its screen")
        case .cd: return String(localized: "CD", comment: "A sticker of a shiny compact disc")
        case .sun: return String(localized: "Sun", comment: "A sticker of a smiling sun")
        case .shootingStar: return String(localized: "Shooting star", comment: "A sticker of a star with a rainbow trail")
        case .planet: return String(localized: "Planet", comment: "A sticker of a ringed planet")
        case .omg, .slay, .bestie, .mainCharacter, .yay, .itGirl, .vibes, .coreMemory:
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
        case .itGirl:
            return String(localized: "it girl", comment: "Speech-bubble sticker in the photo editor: the girl everyone wants to be like. Keep it short.")
        case .vibes: return String(localized: "vibes", comment: "Speech-bubble sticker in the photo editor: good mood, good atmosphere")
        case .coreMemory:
            return String(localized: "core memory", comment: "Speech-bubble sticker in the photo editor: a moment you'll remember forever. Keep it short.")
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
/// third-party art, and no emoji or SF Symbols baked into photos. Like a
/// printed sticker sheet, each one has layered shapes with soft gradients
/// and a glossy shine, a thin deeper keyline, a white die-cut edge and a
/// soft shadow. All vector, so the canvas and the full-size photo match at
/// any scale. The shapes live in the StickerArt+… files, one per section.
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
        case .puffyHeart: art = CGSize(width: 216, height: 200)
        case .twinHearts: art = CGSize(width: 250, height: 210)
        case .loveLetter: art = CGSize(width: 250, height: 200)
        case .heartLocket: art = CGSize(width: 190, height: 250)
        case .rose: art = CGSize(width: 200, height: 240)
        case .strawberry: art = CGSize(width: 196, height: 224)
        case .mushroom: art = CGSize(width: 220, height: 220)
        case .bunny: art = CGSize(width: 210, height: 250)
        case .kitty: art = CGSize(width: 236, height: 206)
        case .bear: art = CGSize(width: 230, height: 210)
        case .heartCloud: art = CGSize(width: 240, height: 220)
        case .boba: art = CGSize(width: 180, height: 250)
        case .pearls: art = CGSize(width: 250, height: 200)
        case .ginghamBow: art = CGSize(width: 256, height: 200)
        case .lipGloss: art = CGSize(width: 150, height: 256)
        case .compactMirror: art = CGSize(width: 200, height: 250)
        case .nailPolish: art = CGSize(width: 170, height: 250)
        case .mascara: art = CGSize(width: 226, height: 246)
        case .perfume: art = CGSize(width: 210, height: 240)
        case .chromeStar: art = CGSize(width: 220, height: 212)
        case .holoHeart: art = CGSize(width: 216, height: 200)
        case .butterflyClip: art = CGSize(width: 250, height: 210)
        case .flipCell: art = CGSize(width: 170, height: 256)
        case .cd: art = CGSize(width: 220, height: 220)
        case .sun: art = CGSize(width: 230, height: 230)
        case .shootingStar: art = CGSize(width: 256, height: 196)
        case .planet: art = CGSize(width: 250, height: 200)
        case .omg, .slay, .bestie, .mainCharacter, .yay, .itGirl, .vibes, .coreMemory:
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
        case .heart: drawHeart(in: art, context: cg)
        case .chromeHeart: drawChromeHeart(in: art, context: cg)
        case .sparkles: drawSparkles(in: art, context: cg)
        case .sparkleBurst: drawSparkleBurst(in: art, context: cg)
        case .star: drawStar(in: art, context: cg)
        case .moon: drawMoon(in: art, context: cg)
        case .butterfly: drawButterfly(in: art, context: cg)
        case .bow: drawBow(in: art, context: cg)
        case .ribbonBow: drawRibbonBow(in: art, context: cg)
        case .crown: drawCrown(in: art, context: cg)
        case .cherries: drawCherries(in: art, context: cg)
        case .flower: drawFlower(in: art, context: cg)
        case .daisy: drawDaisy(in: art, context: cg)
        case .rainbow: drawRainbow(in: art, context: cg)
        case .cloud: drawCloud(in: art, context: cg)
        case .smiley: drawSmiley(in: art, context: cg)
        case .musicNotes: drawMusicNotes(in: art, context: cg)
        case .camera: drawCamera(in: art, context: cg)
        case .filmStrip: drawFilmStrip(in: art, context: cg)
        case .puffyHeart: drawPuffyHeart(in: art, context: cg)
        case .twinHearts: drawTwinHearts(in: art, context: cg)
        case .loveLetter: drawLoveLetter(in: art, context: cg)
        case .heartLocket: drawHeartLocket(in: art, context: cg)
        case .rose: drawRose(in: art, context: cg)
        case .strawberry: drawStrawberry(in: art, context: cg)
        case .mushroom: drawMushroom(in: art, context: cg)
        case .bunny: drawBunny(in: art, context: cg)
        case .kitty: drawKitty(in: art, context: cg)
        case .bear: drawBear(in: art, context: cg)
        case .heartCloud: drawHeartCloud(in: art, context: cg)
        case .boba: drawBoba(in: art, context: cg)
        case .pearls: drawPearls(in: art, context: cg)
        case .ginghamBow: drawGinghamBow(in: art, context: cg)
        case .lipGloss: drawLipGloss(in: art, context: cg)
        case .compactMirror: drawCompactMirror(in: art, context: cg)
        case .nailPolish: drawNailPolish(in: art, context: cg)
        case .mascara: drawMascara(in: art, context: cg)
        case .perfume: drawPerfume(in: art, context: cg)
        case .chromeStar: drawChromeStar(in: art, context: cg)
        case .holoHeart: drawHoloHeart(in: art, context: cg)
        case .butterflyClip: drawButterflyClip(in: art, context: cg)
        case .flipCell: drawFlipCell(in: art, context: cg)
        case .cd: drawCD(in: art, context: cg)
        case .sun: drawSun(in: art, context: cg)
        case .shootingStar: drawShootingStar(in: art, context: cg)
        case .planet: drawPlanet(in: art, context: cg)
        case .omg, .slay, .bestie, .mainCharacter, .yay, .itGirl, .vibes, .coreMemory: drawBubble(sticker, in: art, context: cg)
        case .dateStamp: break
        }
        cg.endTransparencyLayer()
        cg.restoreGState()
    }

    // MARK: Words

    private static func drawBubble(_ sticker: Sticker, in art: CGRect, context cg: CGContext) {
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
        let fill = bubbleColors(sticker.kind).fill
        fill.setFill()
        tail.fill()
        // A soft sheen from the top, like a glossy printed bubble.
        linear(bubble, [lighter(fill, 0.3), fill, fill], [0, 0.55, 1], in: cg)
        shine(CGRect(x: body.minX + body.height * 0.3, y: body.minY + body.height * 0.12, width: min(body.width * 0.3, 120), height: body.height * 0.2),
              degrees: -4, alpha: 0.45, clip: bubble, in: cg)
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

    private static func bubbleColors(_ kind: StickerKind) -> (fill: UIColor, text: UIColor) {
        switch kind {
        case .slay: return (.brandInk, .brandBlush)
        case .bestie: return (.brandBlush, .brandInk)
        case .mainCharacter: return (.auraButter, .plum)
        case .yay: return (.auraPink, .white)
        case .itGirl: return (.auraLilac, .white)
        case .vibes: return (.auraMint, .plum)
        case .coreMemory: return (.auraPeach, .plum)
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

    // MARK: Paint

    /// Every sticker's keyline, so the sheet shares one stroke weight.
    static let keylineWidth: CGFloat = 3.5
    /// Faces, folds and other drawn lines.
    static let detailWidth: CGFloat = 5

    /// `color` lifted toward white.
    static func lighter(_ color: UIColor, _ amount: CGFloat = 0.4) -> UIColor {
        color.mixed(with: .white, amount: amount)
    }

    /// `color` deepened toward plum, the brand's shadow colour.
    static func deeper(_ color: UIColor, _ amount: CGFloat = 0.25) -> UIColor {
        color.mixed(with: .plum, amount: amount)
    }

    /// Fills `path` with a linear gradient, top to bottom of its bounds
    /// unless `start` and `end` say otherwise.
    static func linear(_ path: UIBezierPath, _ colors: [UIColor], _ locations: [CGFloat]? = nil,
                       from start: CGPoint? = nil, to end: CGPoint? = nil, in cg: CGContext) {
        let stops = locations ?? colors.indices.map { CGFloat($0) / CGFloat(max(colors.count - 1, 1)) }
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray,
                                        locations: stops) else { return }
        let bounds = path.bounds
        cg.saveGState()
        path.addClip()
        cg.drawLinearGradient(gradient, start: start ?? CGPoint(x: bounds.midX, y: bounds.minY),
                              end: end ?? CGPoint(x: bounds.midX, y: bounds.maxY),
                              options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        cg.restoreGState()
    }

    /// The sheet's usual body: lighter at the top, the colour, a deeper
    /// shade toward the bottom.
    static func glossy(_ path: UIBezierPath, _ color: UIColor, in cg: CGContext) {
        linear(path, [lighter(color, 0.45), color, deeper(color, 0.2)], [0, 0.5, 1], in: cg)
    }

    /// A round, lit-from-the-top-left fill, for balls, pearls and puffy shapes.
    static func radial(_ path: UIBezierPath, _ colors: [UIColor], _ locations: [CGFloat]? = nil,
                       light: CGPoint, radius: CGFloat, in cg: CGContext) {
        let stops = locations ?? colors.indices.map { CGFloat($0) / CGFloat(max(colors.count - 1, 1)) }
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray,
                                        locations: stops) else { return }
        cg.saveGState()
        path.addClip()
        cg.drawRadialGradient(gradient, startCenter: light, startRadius: 0, endCenter: light, endRadius: radius,
                              options: [.drawsAfterEndLocation])
        cg.restoreGState()
    }

    /// A thin, deeper line around the art inside the white edge, as on
    /// printed sticker sheets.
    static func keyline(_ paths: [UIBezierPath], _ color: UIColor, width: CGFloat = keylineWidth) {
        color.setStroke()
        for path in paths {
            path.lineWidth = width
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.stroke()
        }
    }

    /// A glossy shine: a turned ellipse in `rect`, white at its top and
    /// fading out, inside `clip` when given.
    static func shine(_ rect: CGRect, degrees: CGFloat = -30, alpha: CGFloat = 0.75, clip: UIBezierPath? = nil, in cg: CGContext) {
        let ellipse = UIBezierPath(ovalIn: CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height))
        ellipse.apply(CGAffineTransform(rotationAngle: degrees * .pi / 180))
        ellipse.apply(CGAffineTransform(translationX: rect.midX, y: rect.midY))
        let bounds = ellipse.bounds
        cg.saveGState()
        clip?.addClip()
        ellipse.addClip()
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [UIColor.white.withAlphaComponent(alpha).cgColor, UIColor.white.withAlphaComponent(alpha * 0.15).cgColor] as CFArray,
                                     locations: [0, 1]) {
            cg.drawLinearGradient(gradient, start: CGPoint(x: bounds.midX, y: bounds.minY), end: CGPoint(x: bounds.midX, y: bounds.maxY), options: [])
        }
        cg.restoreGState()
    }

    /// A small, solid white glint.
    static func glint(_ center: CGPoint, _ radius: CGFloat, alpha: CGFloat = 0.9) {
        UIColor.white.withAlphaComponent(alpha).setFill()
        circle(center, radius).fill()
    }

    /// Kawaii eyes: plum ovals with a white catchlight.
    static func eyes(_ centers: [CGPoint], width: CGFloat, height: CGFloat) {
        for center in centers {
            UIColor.plum.setFill()
            UIBezierPath(ovalIn: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)).fill()
            UIColor.white.setFill()
            let glintSize = width * 0.42
            UIBezierPath(ovalIn: CGRect(x: center.x - width * 0.32, y: center.y - height * 0.36, width: glintSize, height: glintSize)).fill()
        }
    }

    /// Rosy cheeks.
    static func blush(_ centers: [CGPoint], width: CGFloat, height: CGFloat, alpha: CGFloat = 0.45) {
        UIColor.auraPink.withAlphaComponent(alpha).setFill()
        for center in centers {
            UIBezierPath(ovalIn: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)).fill()
        }
    }

    /// A small smile, as an arc under `center`.
    static func smile(_ center: CGPoint, radius: CGFloat, width: CGFloat = detailWidth) {
        let path = UIBezierPath(arcCenter: center, radius: radius, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: true)
        UIColor.plum.setStroke()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.stroke()
    }

    // MARK: Paths

    static func circle(_ center: CGPoint, _ radius: CGFloat) -> UIBezierPath {
        UIBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    static func heartPath(in rect: CGRect) -> UIBezierPath {
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

    /// A polygon whose corners are rounded with `radius`.
    static func roundedPolygon(_ points: [CGPoint], radius: CGFloat) -> UIBezierPath {
        guard let first = points.first, let last = points.last else { return UIBezierPath() }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for (index, corner) in points.enumerated() {
            path.addArc(tangent1End: corner, tangent2End: points[(index + 1) % points.count], radius: radius)
        }
        path.closeSubpath()
        return UIBezierPath(cgPath: path)
    }

    /// The corners of a five-point star, from the top point clockwise.
    static func starPoints(center: CGPoint, outer: CGFloat, inner: CGFloat) -> [CGPoint] {
        (0..<10).map { index in
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = CGFloat(index) * .pi / 5 - .pi / 2
            return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
    }

    static func starPath(center: CGPoint, outer: CGFloat, inner: CGFloat) -> UIBezierPath {
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

    /// A star lit from the top left: each point's two halves get a light
    /// and a shaded face, like a folded paper star. Clip to the star first.
    static func facetedStar(center: CGPoint, outer: CGFloat, inner: CGFloat, light: UIColor, shade: UIColor) {
        let points = starPoints(center: center, outer: outer, inner: inner)
        for index in 0..<10 {
            let facet = UIBezierPath()
            facet.move(to: center)
            facet.addLine(to: points[index])
            facet.addLine(to: points[(index + 1) % 10])
            facet.close()
            // Faces turned up and left catch the light.
            let mid = CGPoint(x: (points[index].x + points[(index + 1) % 10].x) / 2, y: (points[index].y + points[(index + 1) % 10].y) / 2)
            let facing = (mid.x - center.x) * -0.6 + (mid.y - center.y) * -0.8
            (facing > 0 ? light : shade).setFill()
            facet.fill()
        }
    }

    static func mirrored(_ path: UIBezierPath, in rect: CGRect) -> UIBezierPath {
        let copy = UIBezierPath(cgPath: path.cgPath)
        copy.apply(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.midX * 2, ty: 0))
        return copy
    }

    /// The part of a circle that a second circle (the bite, overlapping its
    /// edge) doesn't cover: a crescent.
    static func crescentPath(center: CGPoint, radius: CGFloat, bite: CGPoint, biteRadius: CGFloat) -> UIBezierPath {
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
    static func arch(center: CGPoint, outer: CGFloat, inner: CGFloat) -> UIBezierPath {
        let path = UIBezierPath(arcCenter: center, radius: outer, startAngle: .pi, endAngle: 2 * .pi, clockwise: true)
        path.addArc(withCenter: center, radius: inner, startAngle: 2 * .pi, endAngle: .pi, clockwise: false)
        path.close()
        return path
    }

    /// A puffy cloud about `width` wide and 0.6 of that tall, centred on
    /// `center`: three bumps on a rounded base.
    static func cloudPath(center: CGPoint, width: CGFloat) -> UIBezierPath {
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

    /// The white die-cut edge, drawn under the shapes' fills.
    static func dieCut(_ paths: [UIBezierPath], width: CGFloat = edge) {
        UIColor.white.setStroke()
        for path in paths {
            path.lineWidth = width * 2
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.stroke()
        }
    }

    /// 0…1 coordinates in a rectangle.
    struct Grid {
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
