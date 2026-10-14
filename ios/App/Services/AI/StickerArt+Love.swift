import UIKit

// Love: hearts, a love letter, a locket and a rose.
extension StickerArt {
    static func drawHeart(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let heart = heartPath(in: art)
        dieCut([heart])
        glossy(heart, .auraPink, in: cg)
        keyline([heart], deeper(.auraPink, 0.35).withAlphaComponent(0.6))
        shine(grid.r(0.08, 0.14, 0.36, 0.2), degrees: -38, clip: heart, in: cg)
        glint(grid.p(0.42, 0.17), art.width * 0.025)
        UIColor.white.withAlphaComponent(0.9).setFill()
        sparklePath(center: grid.p(0.76, 0.32), radius: art.width * 0.075).fill()
    }

    /// A candy-red heart, puffed up like a balloon.
    static func drawPuffyHeart(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let heart = heartPath(in: art)
        let red = UIColor(hex: 0xFF4F7B)
        dieCut([heart])
        radial(heart, [lighter(red, 0.55), red, deeper(red, 0.4)], [0, 0.45, 1], light: grid.p(0.34, 0.3), radius: art.width * 0.78, in: cg)
        // Light bouncing back along the lower edge.
        cg.saveGState()
        heart.addClip()
        let rim = heartPath(in: grid.r(-0.04, -0.06, 1.0, 1.0))
        lighter(red, 0.5).withAlphaComponent(0.45).setStroke()
        rim.lineWidth = art.width * 0.06
        rim.stroke()
        cg.restoreGState()
        keyline([heart], deeper(red, 0.45).withAlphaComponent(0.6))
        shine(grid.r(0.1, 0.12, 0.34, 0.24), degrees: -36, alpha: 0.85, clip: heart, in: cg)
        glint(grid.p(0.25, 0.42), art.width * 0.03)
        glint(grid.p(0.72, 0.24), art.width * 0.02, alpha: 0.7)
    }

    /// A big pink heart with a little lilac one leaning on it.
    static func drawTwinHearts(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        func turned(_ rect: CGRect, degrees: CGFloat) -> UIBezierPath {
            let heart = heartPath(in: CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height))
            heart.apply(CGAffineTransform(rotationAngle: degrees * .pi / 180))
            heart.apply(CGAffineTransform(translationX: rect.midX, y: rect.midY))
            return heart
        }
        let small = turned(grid.r(0.52, 0.02, 0.44, 0.46), degrees: 16)
        let big = turned(grid.r(0.02, 0.2, 0.68, 0.76), degrees: -10)
        dieCut([small, big])
        for (heart, color, box) in [(small, UIColor.auraLilac, grid.r(0.52, 0.02, 0.44, 0.46)), (big, UIColor.auraPink, grid.r(0.02, 0.2, 0.68, 0.76))] {
            glossy(heart, color, in: cg)
            keyline([heart], deeper(color, 0.35).withAlphaComponent(0.6))
            shine(CGRect(x: box.minX + box.width * 0.1, y: box.minY + box.height * 0.14, width: box.width * 0.36, height: box.height * 0.2),
                  degrees: -36, clip: heart, in: cg)
        }
        UIColor.white.withAlphaComponent(0.9).setFill()
        sparklePath(center: grid.p(0.86, 0.62), radius: art.width * 0.06).fill()
    }

    /// An envelope closed with a heart seal, with hearts floating out.
    static func drawLoveLetter(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let body = UIBezierPath(roundedRect: grid.r(0.03, 0.3, 0.94, 0.66), cornerRadius: art.width * 0.05)
        let flap = UIBezierPath()
        flap.move(to: grid.p(0.05, 0.33))
        flap.addLine(to: grid.p(0.5, 0.7))
        flap.addLine(to: grid.p(0.95, 0.33))
        flap.close()
        let seal = heartPath(in: grid.r(0.39, 0.56, 0.22, 0.24))
        let floating = [heartPath(in: grid.r(0.7, 0.02, 0.16, 0.17)), heartPath(in: grid.r(0.84, 0.16, 0.11, 0.12))]
        dieCut([body] + floating)

        linear(body, [.white, .brandPetal, lighter(.brandBlush, 0.2)], [0, 0.6, 1], in: cg)
        // The folds: the lower flaps meet in the middle, the top flap covers them.
        let folds = UIBezierPath()
        folds.move(to: grid.p(0.05, 0.93))
        folds.addLine(to: grid.p(0.42, 0.62))
        folds.move(to: grid.p(0.95, 0.93))
        folds.addLine(to: grid.p(0.58, 0.62))
        deeper(.brandBlush, 0.2).withAlphaComponent(0.5).setStroke()
        folds.lineWidth = keylineWidth
        folds.lineCapStyle = .round
        folds.stroke()
        linear(flap, [lighter(.brandBlush, 0.55), lighter(.brandBlush, 0.15)], in: cg)
        keyline([flap], deeper(.brandBlush, 0.25).withAlphaComponent(0.55))
        keyline([body], deeper(.brandBlush, 0.3).withAlphaComponent(0.6))
        // The wax seal.
        glossy(seal, .auraPink, in: cg)
        keyline([seal], deeper(.auraPink, 0.4).withAlphaComponent(0.6))
        shine(grid.r(0.41, 0.58, 0.09, 0.06), degrees: -36, clip: seal, in: cg)
        for (heart, color) in zip(floating, [UIColor.auraPink, .auraLilac]) {
            glossy(heart, color, in: cg)
        }
        shine(grid.r(0.08, 0.34, 0.3, 0.1), degrees: -8, alpha: 0.6, clip: body, in: cg)
    }

    /// A golden heart locket on a fine chain.
    static func drawHeartLocket(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let lightGold = lighter(.auraButter, 0.5)
        let gold = UIColor.auraButter.mixed(with: .auraPeach, amount: 0.3)
        let deepGold = deeper(gold, 0.35)
        // The chain: two strands of beads meeting at the bail.
        var beads: [UIBezierPath] = []
        let bail = grid.p(0.5, 0.31)
        for start in [grid.p(0.1, 0.02), grid.p(0.9, 0.02)] {
            let count = 9
            for index in 0..<count {
                let t = CGFloat(index) / CGFloat(count)
                let point = CGPoint(x: start.x + (bail.x - start.x) * t, y: start.y + (bail.y - start.y) * t)
                beads.append(circle(point, art.width * 0.022))
            }
        }
        let ring = circle(bail, art.width * 0.05)
        let locket = heartPath(in: grid.r(0.08, 0.34, 0.84, 0.64))
        dieCut(beads + [ring, locket], width: edge * 0.8)

        for bead in beads {
            radial(bead, [lightGold, gold, deepGold], light: bead.bounds.origin, radius: bead.bounds.width, in: cg)
        }
        deepGold.setStroke()
        ring.lineWidth = art.width * 0.03
        ring.stroke()
        radial(locket, [lightGold, gold, deepGold], [0, 0.5, 1], light: grid.p(0.36, 0.44), radius: art.width * 0.8, in: cg)
        // An engraved inner edge and a pink heart gem.
        let bevel = heartPath(in: grid.r(0.2, 0.43, 0.6, 0.46))
        lightGold.withAlphaComponent(0.8).setStroke()
        bevel.lineWidth = keylineWidth
        bevel.stroke()
        deepGold.withAlphaComponent(0.35).setStroke()
        let groove = heartPath(in: grid.r(0.21, 0.445, 0.6, 0.46))
        groove.lineWidth = 2
        groove.stroke()
        let gem = heartPath(in: grid.r(0.4, 0.55, 0.2, 0.17))
        glossy(gem, .auraPink, in: cg)
        keyline([gem], deeper(.auraPink, 0.4).withAlphaComponent(0.5), width: 2.5)
        glint(grid.p(0.45, 0.59), art.width * 0.018)
        keyline([locket], deepGold.withAlphaComponent(0.7))
        shine(grid.r(0.14, 0.4, 0.28, 0.12), degrees: -36, alpha: 0.85, clip: locket, in: cg)
    }

    /// A pink rose in bloom, seen from above, on a short stem with two leaves.
    static func drawRose(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let stemWidth = art.width * 0.06
        let stem = UIBezierPath()
        stem.move(to: grid.p(0.5, 0.6))
        stem.addQuadCurve(to: grid.p(0.46, 0.98), controlPoint: grid.p(0.54, 0.8))
        let leftLeaf = UIBezierPath()
        leftLeaf.move(to: grid.p(0.49, 0.82))
        leftLeaf.addQuadCurve(to: grid.p(0.1, 0.7), controlPoint: grid.p(0.26, 0.9))
        leftLeaf.addQuadCurve(to: grid.p(0.49, 0.82), controlPoint: grid.p(0.26, 0.62))
        leftLeaf.close()
        let rightLeaf = UIBezierPath()
        rightLeaf.move(to: grid.p(0.51, 0.76))
        rightLeaf.addQuadCurve(to: grid.p(0.9, 0.64), controlPoint: grid.p(0.74, 0.82))
        rightLeaf.addQuadCurve(to: grid.p(0.51, 0.76), controlPoint: grid.p(0.74, 0.56))
        rightLeaf.close()
        // Scalloped outer petals around the middle of the bloom.
        let center = grid.p(0.5, 0.36)
        let radius = art.width * 0.36
        let bloom = UIBezierPath()
        for index in 0..<6 {
            let angle = CGFloat(index) * .pi / 3 - .pi / 2
            bloom.append(circle(CGPoint(x: center.x + cos(angle) * radius * 0.48, y: center.y + sin(angle) * radius * 0.48), radius * 0.56))
        }
        dieCut([bloom, leftLeaf, rightLeaf])
        dieCut([stem], width: edge + stemWidth / 2)

        let leaf = UIColor.auraMint.mixed(with: .plum, amount: 0.15)
        deeper(leaf, 0.35).setStroke()
        stem.lineWidth = stemWidth
        stem.lineCapStyle = .round
        stem.stroke()
        for path in [leftLeaf, rightLeaf] {
            glossy(path, leaf, in: cg)
            keyline([path], deeper(leaf, 0.4).withAlphaComponent(0.55))
        }
        let rose = UIColor.auraPink.mixed(with: .brandBlush, amount: 0.15)
        // Outline first: the fill covers where the scallops overlap.
        keyline([bloom], deeper(rose, 0.45).withAlphaComponent(0.6))
        radial(bloom, [lighter(rose, 0.45), rose, deeper(rose, 0.2)], [0, 0.55, 1], light: CGPoint(x: center.x - radius * 0.2, y: center.y - radius * 0.25),
               radius: radius * 1.25, in: cg)
        // Petals wrapped around the heart of the rose, ring by ring.
        let petals = UIBezierPath()
        for (scale, start, end) in [(0.82, 1.15, 1.85), (0.82, 0.15, 0.85), (0.58, 0.62, 1.38), (0.58, 1.62, 2.38), (0.34, 1.05, 2.0), (0.15, 0.0, 1.5)]
            as [(CGFloat, CGFloat, CGFloat)] {
            petals.move(to: CGPoint(x: center.x + cos(start * .pi) * radius * scale, y: center.y + sin(start * .pi) * radius * scale))
            petals.addArc(withCenter: center, radius: radius * scale, startAngle: start * .pi, endAngle: end * .pi, clockwise: true)
        }
        deeper(rose, 0.4).withAlphaComponent(0.75).setStroke()
        petals.lineWidth = detailWidth
        petals.lineCapStyle = .round
        petals.stroke()
        shine(CGRect(x: center.x - radius * 0.8, y: center.y - radius * 0.95, width: radius * 0.7, height: radius * 0.35),
              degrees: -25, alpha: 0.65, clip: bloom, in: cg)
    }
}
