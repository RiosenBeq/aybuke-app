import UIKit

// Spooky, in the tray only around Halloween: a jack-o'-lantern, a ghost, a
// bat, a wrapped sweet, a witch hat and a web for a photo's corner. Cute,
// never scary: round shapes, kawaii faces and the sheet's candy colours.
extension StickerArt {
    private static let pumpkinOrange = UIColor(hex: 0xFF9142)
    private static let glow = UIColor(hex: 0xFFE27A)
    private static let leafGreen = UIColor.auraMint.mixed(with: .plum, amount: 0.22)
    /// The bat and the witch hat: plum lifted with lilac.
    private static let witchPurple = UIColor.plum.mixed(with: .auraLilac, amount: 0.3)

    /// A smiling jack-o'-lantern: a lobed body, a curly stem with a leaf, a
    /// carved face glowing butter yellow, and rosy cheeks.
    static func drawPumpkin(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let lobes = [grid.ellipse(0.26, 0.6, 0.48, 0.74), grid.ellipse(0.74, 0.6, 0.48, 0.74), grid.ellipse(0.5, 0.58, 0.52, 0.8)]
        let stem = roundedPolygon([grid.p(0.44, 0.24), grid.p(0.46, 0.04), grid.p(0.57, 0.03), grid.p(0.56, 0.24)], radius: art.width * 0.02)
        let leaf = UIBezierPath()
        leaf.move(to: grid.p(0.56, 0.14))
        leaf.addQuadCurve(to: grid.p(0.82, 0.07), controlPoint: grid.p(0.66, -0.01))
        leaf.addQuadCurve(to: grid.p(0.56, 0.14), controlPoint: grid.p(0.74, 0.2))
        leaf.close()
        let vine = UIBezierPath()
        vine.move(to: grid.p(0.46, 0.15))
        vine.addCurve(to: grid.p(0.32, 0.12), controlPoint1: grid.p(0.42, 0.04), controlPoint2: grid.p(0.32, 0.02))
        vine.addQuadCurve(to: grid.p(0.38, 0.16), controlPoint: grid.p(0.33, 0.19))
        dieCut(lobes + [stem, leaf])
        dieCut([vine], width: edge + detailWidth / 2)

        leafGreen.setStroke()
        vine.lineWidth = detailWidth
        vine.lineCapStyle = .round
        vine.stroke()
        glossy(stem, deeper(leafGreen, 0.3), in: cg)
        keyline([stem], deeper(leafGreen, 0.5).withAlphaComponent(0.6))
        glossy(leaf, leafGreen, in: cg)
        keyline([leaf], deeper(leafGreen, 0.4).withAlphaComponent(0.55))
        // The side lobes a touch deeper, so the middle one stands out.
        for (lobe, color) in zip(lobes, [deeper(pumpkinOrange, 0.08), deeper(pumpkinOrange, 0.08), pumpkinOrange]) {
            glossy(lobe, color, in: cg)
            keyline([lobe], deeper(pumpkinOrange, 0.4).withAlphaComponent(0.6))
        }
        shine(grid.r(0.3, 0.24, 0.2, 0.13), degrees: -30, alpha: 0.7, clip: lobes[2], in: cg)

        // The carved face, lit from inside.
        let leftEye = roundedPolygon([grid.p(0.29, 0.55), grid.p(0.42, 0.55), grid.p(0.36, 0.42)], radius: art.width * 0.018)
        let rightEye = mirrored(leftEye, in: art)
        let mouth = UIBezierPath()
        mouth.move(to: grid.p(0.3, 0.66))
        mouth.addQuadCurve(to: grid.p(0.7, 0.66), controlPoint: grid.p(0.5, 0.74))
        mouth.addQuadCurve(to: grid.p(0.3, 0.66), controlPoint: grid.p(0.5, 0.94))
        mouth.close()
        for path in [leftEye, rightEye, mouth] {
            let bounds = path.bounds
            radial(path, [lighter(glow, 0.55), glow, glow.mixed(with: pumpkinOrange, amount: 0.5)], [0, 0.45, 1],
                   light: CGPoint(x: bounds.midX, y: bounds.midY), radius: max(bounds.width, bounds.height) * 0.75, in: cg)
            keyline([path], deeper(pumpkinOrange, 0.5).withAlphaComponent(0.75), width: 3)
        }
        // One tooth left in the smile.
        let tooth = UIBezierPath(roundedRect: grid.r(0.465, 0.685, 0.07, 0.075), cornerRadius: art.width * 0.012)
        pumpkinOrange.setFill()
        tooth.fill()
        keyline([tooth], deeper(pumpkinOrange, 0.5).withAlphaComponent(0.6), width: 2.5)
        blush([grid.p(0.22, 0.67), grid.p(0.78, 0.67)], width: art.width * 0.1, height: art.height * 0.06, alpha: 0.5)
        glint(grid.p(0.33, 0.33), art.width * 0.02)
    }

    /// A little ghost with a wavy hem, its arms out and a surprised "o".
    static func drawGhost(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let body = UIBezierPath()
        body.move(to: grid.p(0.14, 0.9))
        body.addLine(to: grid.p(0.14, 0.44))
        body.addCurve(to: grid.p(0.5, 0.04), controlPoint1: grid.p(0.14, 0.18), controlPoint2: grid.p(0.3, 0.04))
        body.addCurve(to: grid.p(0.86, 0.44), controlPoint1: grid.p(0.7, 0.04), controlPoint2: grid.p(0.86, 0.18))
        body.addLine(to: grid.p(0.86, 0.9))
        body.addQuadCurve(to: grid.p(0.62, 0.9), controlPoint: grid.p(0.74, 1.02))
        body.addQuadCurve(to: grid.p(0.38, 0.9), controlPoint: grid.p(0.5, 1.02))
        body.addQuadCurve(to: grid.p(0.14, 0.9), controlPoint: grid.p(0.26, 1.02))
        body.close()
        let arms = [grid.ellipse(0.11, 0.57, 0.17, 0.1, degrees: -35), grid.ellipse(0.89, 0.57, 0.17, 0.1, degrees: 35)]
        let sparkle = sparklePath(center: grid.p(0.9, 0.14), radius: art.width * 0.07)
        dieCut(arms + [body])
        dieCut([sparkle], width: edge * 0.6)

        let mist = UIColor.auraLilac.mixed(with: .white, amount: 0.62)
        let outline = deeper(.auraLilac, 0.2).withAlphaComponent(0.6)
        for arm in arms {
            linear(arm, [.white, mist], in: cg)
            keyline([arm], outline)
        }
        linear(body, [.white, .white, mist], [0, 0.5, 1], in: cg)
        keyline([body], outline)
        shine(grid.r(0.2, 0.1, 0.24, 0.14), degrees: -30, alpha: 0.9, clip: body, in: cg)
        eyes([grid.p(0.37, 0.4), grid.p(0.63, 0.4)], width: art.width * 0.09, height: art.height * 0.1)
        blush([grid.p(0.26, 0.5), grid.p(0.74, 0.5)], width: art.width * 0.12, height: art.height * 0.05, alpha: 0.5)
        UIColor.plum.setFill()
        grid.ellipse(0.5, 0.53, 0.08, 0.06).fill()
        UIColor.auraLilac.setFill()
        sparkle.fill()
    }

    /// A round little bat with scalloped wings and a tiny fang in its smile.
    static func drawBat(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let wing = UIBezierPath()
        wing.move(to: grid.p(0.42, 0.4))
        wing.addQuadCurve(to: grid.p(0.03, 0.14), controlPoint: grid.p(0.2, 0.06))
        wing.addQuadCurve(to: grid.p(0.1, 0.62), controlPoint: grid.p(0.0, 0.42))
        wing.addQuadCurve(to: grid.p(0.22, 0.56), controlPoint: grid.p(0.17, 0.49))
        wing.addQuadCurve(to: grid.p(0.33, 0.68), controlPoint: grid.p(0.29, 0.55))
        wing.addQuadCurve(to: grid.p(0.44, 0.62), controlPoint: grid.p(0.4, 0.62))
        wing.close()
        let wings = [wing, mirrored(wing, in: art)]
        let ear = roundedPolygon([grid.p(0.37, 0.3), grid.p(0.47, 0.24), grid.p(0.39, 0.04)], radius: art.width * 0.012)
        let ears = [ear, mirrored(ear, in: art)]
        let body = grid.ellipse(0.5, 0.56, 0.36, 0.72)
        dieCut(wings + ears + [body])

        let wingColor = witchPurple.mixed(with: .auraLilac, amount: 0.22)
        let outline = deeper(witchPurple, 0.45).withAlphaComponent(0.7)
        for side in wings {
            glossy(side, wingColor, in: cg)
            keyline([side], outline)
        }
        // The wing bones, from the shoulder to each scallop.
        let bones = UIBezierPath()
        for (x, y) in [(0.1, 0.62), (0.22, 0.56), (0.33, 0.68)] as [(CGFloat, CGFloat)] {
            bones.move(to: grid.p(0.4, 0.42))
            bones.addLine(to: grid.p(x, y))
            bones.move(to: grid.p(0.6, 0.42))
            bones.addLine(to: grid.p(1 - x, y))
        }
        deeper(wingColor, 0.3).withAlphaComponent(0.55).setStroke()
        bones.lineWidth = 2.5
        bones.lineCapStyle = .round
        bones.stroke()
        for side in ears {
            glossy(side, witchPurple, in: cg)
        }
        radial(body, [lighter(witchPurple, 0.35), witchPurple, deeper(witchPurple, 0.3)], [0, 0.55, 1],
               light: grid.p(0.42, 0.34), radius: art.width * 0.3, in: cg)
        keyline(ears + [body], outline)
        UIColor.auraPink.withAlphaComponent(0.55).setFill()
        roundedPolygon([grid.p(0.39, 0.27), grid.p(0.44, 0.25), grid.p(0.4, 0.12)], radius: 2).fill()
        mirrored(roundedPolygon([grid.p(0.39, 0.27), grid.p(0.44, 0.25), grid.p(0.4, 0.12)], radius: 2), in: art).fill()
        shine(grid.r(0.39, 0.3, 0.12, 0.12), degrees: -30, alpha: 0.5, clip: body, in: cg)

        // On a dark body the eyes are white, with plum pupils.
        for center in [grid.p(0.44, 0.52), grid.p(0.56, 0.52)] {
            let width = art.width * 0.05
            let height = art.height * 0.15
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)).fill()
            UIColor.plum.setFill()
            UIBezierPath(ovalIn: CGRect(x: center.x - width * 0.32, y: center.y - height * 0.15, width: width * 0.64, height: height * 0.6)).fill()
            glint(CGPoint(x: center.x - width * 0.1, y: center.y), width * 0.14)
        }
        blush([grid.p(0.4, 0.66), grid.p(0.6, 0.66)], width: art.width * 0.05, height: art.height * 0.07, alpha: 0.6)
        let grin = UIBezierPath(arcCenter: grid.p(0.5, 0.64), radius: art.width * 0.025, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: true)
        lighter(.auraPink, 0.4).setStroke()
        grin.lineWidth = 3.5
        grin.lineCapStyle = .round
        grin.stroke()
        let fang = UIBezierPath()
        fang.move(to: grid.p(0.485, 0.69))
        fang.addLine(to: grid.p(0.505, 0.69))
        fang.addLine(to: grid.p(0.494, 0.74))
        fang.close()
        UIColor.white.setFill()
        fang.fill()
    }

    /// A round sweet with an orange-and-cream pinwheel, twisted in lilac wrapper.
    static func drawCandy(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let wrapper = roundedPolygon([grid.p(0.36, 0.5), grid.p(0.03, 0.06), grid.p(0.1, 0.5), grid.p(0.03, 0.94)], radius: art.width * 0.02)
        let wrappers = [wrapper, mirrored(wrapper, in: art)]
        let knots = [grid.ellipse(0.255, 0.5, 0.07, 0.34), grid.ellipse(0.745, 0.5, 0.07, 0.34)]
        let center = grid.p(0.5, 0.5)
        let radius = art.height * 0.4
        let sweet = circle(center, radius)
        dieCut(wrappers + knots + [sweet])

        let wrap = UIColor.auraLilac
        let outline = deeper(wrap, 0.35).withAlphaComponent(0.6)
        for side in wrappers {
            linear(side, [lighter(wrap, 0.55), lighter(wrap, 0.15), wrap], [0, 0.5, 1], in: cg)
            keyline([side], outline)
        }
        // Crinkles in the wrapper.
        let crinkles = UIBezierPath()
        for (x, y) in [(0.12, 0.2), (0.15, 0.5), (0.12, 0.8)] as [(CGFloat, CGFloat)] {
            crinkles.move(to: grid.p(0.3, 0.5))
            crinkles.addLine(to: grid.p(x, y))
            crinkles.move(to: grid.p(0.7, 0.5))
            crinkles.addLine(to: grid.p(1 - x, y))
        }
        UIColor.white.withAlphaComponent(0.6).setStroke()
        crinkles.lineWidth = 2.5
        crinkles.lineCapStyle = .round
        crinkles.stroke()
        for knot in knots {
            glossy(knot, deeper(wrap, 0.1), in: cg)
            keyline([knot], outline)
        }
        // The pinwheel: eight wedges, orange and cream.
        cg.saveGState()
        sweet.addClip()
        for index in 0..<8 {
            let start = CGFloat(index) * .pi / 4
            let wedge = UIBezierPath()
            wedge.move(to: center)
            wedge.addArc(withCenter: center, radius: radius * 1.1, startAngle: start, endAngle: start + .pi / 4, clockwise: true)
            wedge.close()
            (index.isMultiple(of: 2) ? pumpkinOrange : UIColor(hex: 0xFFF4E2)).setFill()
            wedge.fill()
        }
        cg.restoreGState()
        radial(sweet, [UIColor.white.withAlphaComponent(0.45), UIColor.white.withAlphaComponent(0)], light: grid.p(0.42, 0.32),
               radius: radius * 1.2, in: cg)
        keyline([sweet], deeper(pumpkinOrange, 0.4).withAlphaComponent(0.6))
        shine(CGRect(x: center.x - radius * 0.7, y: center.y - radius * 0.8, width: radius * 0.7, height: radius * 0.4),
              degrees: -30, alpha: 0.8, clip: sweet, in: cg)
        glint(CGPoint(x: center.x + radius * 0.45, y: center.y + radius * 0.4), radius * 0.07, alpha: 0.7)
    }

    /// A pointy witch hat with a bent tip, a pink band, a gold buckle and stars.
    static func drawWitchHat(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let brim = grid.ellipse(0.5, 0.84, 0.98, 0.26)
        let cone = UIBezierPath()
        cone.move(to: grid.p(0.22, 0.86))
        cone.addCurve(to: grid.p(0.55, 0.12), controlPoint1: grid.p(0.32, 0.58), controlPoint2: grid.p(0.42, 0.22))
        cone.addQuadCurve(to: grid.p(0.92, 0.24), controlPoint: grid.p(0.76, 0.0))
        cone.addQuadCurve(to: grid.p(0.65, 0.32), controlPoint: grid.p(0.75, 0.2))
        cone.addCurve(to: grid.p(0.78, 0.86), controlPoint1: grid.p(0.64, 0.54), controlPoint2: grid.p(0.7, 0.72))
        cone.close()
        let twinkle = sparklePath(center: grid.p(0.9, 0.5), radius: art.width * 0.05)
        dieCut([brim, cone])
        dieCut([twinkle], width: edge * 0.6)

        let outline = deeper(witchPurple, 0.45).withAlphaComponent(0.7)
        let brimColor = deeper(witchPurple, 0.1)
        glossy(brim, brimColor, in: cg)
        keyline([brim], outline)
        glossy(cone, witchPurple, in: cg)
        // The band follows the cone.
        cg.saveGState()
        cone.addClip()
        glossy(UIBezierPath(rect: grid.r(0, 0.6, 1, 0.14)), .auraPink, in: cg)
        cg.restoreGState()
        keyline([cone], outline)
        shine(grid.r(0.36, 0.3, 0.08, 0.26), degrees: 22, alpha: 0.45, clip: cone, in: cg)
        // The front of the brim sits over the cone.
        cg.saveGState()
        UIBezierPath(rect: grid.r(0, 0.84, 1, 0.2)).addClip()
        glossy(brim, brimColor, in: cg)
        keyline([brim], outline)
        cg.restoreGState()

        let buckle = UIBezierPath(roundedRect: grid.r(0.44, 0.61, 0.13, 0.12), cornerRadius: art.width * 0.02)
        UIColor.auraButter.setStroke()
        buckle.lineWidth = art.width * 0.022
        buckle.stroke()
        UIColor.auraButter.setFill()
        sparklePath(center: grid.p(0.42, 0.46), radius: art.width * 0.05).fill()
        starPath(center: grid.p(0.56, 0.3), outer: art.width * 0.035, inner: art.width * 0.016).fill()
        twinkle.fill()
    }

    /// A web for a photo's corner (top left), with a tiny friendly spider on its thread.
    static func drawSpiderWeb(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let corner = grid.p(0.02, 0.02)
        let reach = art.width * 0.94
        let spokes: [CGFloat] = [0, 0.125, 0.25, 0.375, 0.5].map { $0 * .pi }
        func point(_ angle: CGFloat, _ distance: CGFloat) -> CGPoint {
            CGPoint(x: corner.x + cos(angle) * distance, y: corner.y + sin(angle) * distance)
        }
        let web = UIBezierPath()
        for angle in spokes {
            web.move(to: corner)
            web.addLine(to: point(angle, reach))
        }
        // Each ring sags toward the corner between two spokes.
        for ring in [0.36, 0.65, 0.94] as [CGFloat] {
            web.move(to: point(spokes[0], ring * reach))
            for (from, to) in zip(spokes, spokes.dropFirst()) {
                web.addQuadCurve(to: point(to, ring * reach), controlPoint: point((from + to) / 2, ring * reach * 0.86))
            }
        }
        let threadWidth: CGFloat = 4.5
        let spider = grid.p(0.56, 0.82)
        let body = circle(spider, art.width * 0.075)
        let line = UIBezierPath()
        line.move(to: grid.p(0.56, 0.56))
        line.addLine(to: spider)
        let legs = UIBezierPath()
        for side in [-1, 1] as [CGFloat] {
            for index in 0..<3 {
                let lift = CGFloat(index) * 0.035
                legs.move(to: grid.p(0.56 + side * 0.05, 0.8 + lift))
                legs.addQuadCurve(to: grid.p(0.56 + side * 0.13, 0.82 + lift * 1.6),
                                  controlPoint: grid.p(0.56 + side * 0.11, 0.75 + lift))
            }
        }
        // A slimmer edge than the sheet's, so the web stays open.
        dieCut([web, line], width: edge * 0.6 + threadWidth / 2)
        dieCut([legs], width: edge * 0.8 + detailWidth / 2)
        dieCut([body])

        let silk = deeper(.auraLilac, 0.15)
        silk.setStroke()
        for path in [web, line] {
            path.lineWidth = threadWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }

        let spiderColor = witchPurple
        spiderColor.setStroke()
        legs.lineWidth = detailWidth
        legs.lineCapStyle = .round
        legs.stroke()
        radial(body, [lighter(spiderColor, 0.35), spiderColor, deeper(spiderColor, 0.3)], [0, 0.55, 1],
               light: CGPoint(x: spider.x - art.width * 0.03, y: spider.y - art.width * 0.04), radius: art.width * 0.1, in: cg)
        keyline([body], deeper(spiderColor, 0.45).withAlphaComponent(0.7))
        for dx in [-0.024, 0.024] as [CGFloat] {
            let center = CGPoint(x: spider.x + dx * art.width, y: spider.y - art.width * 0.008)
            let size = art.width * 0.03
            UIColor.white.setFill()
            circle(center, size / 2).fill()
            UIColor.plum.setFill()
            circle(CGPoint(x: center.x, y: center.y + size * 0.1), size * 0.3).fill()
        }
        blush([CGPoint(x: spider.x - art.width * 0.045, y: spider.y + art.width * 0.03),
               CGPoint(x: spider.x + art.width * 0.045, y: spider.y + art.width * 0.03)],
              width: art.width * 0.03, height: art.width * 0.018, alpha: 0.7)
    }
}
