import UIKit

// Y2K: chrome, holo, jelly clips, a flip cell, a CD and retro camera bits.
extension StickerArt {
    /// The chrome bands both chrome stickers share: light, a dark horizon
    /// line and a blush reflection of the ground.
    private static let chromeColors: [UIColor] = [.white, .brandPetal, UIColor(hex: 0xD9CCF5), .auraLilac, .plum, UIColor(hex: 0xB86AA8), .brandBlush, .white]
    private static let chromeStops: [CGFloat] = [0, 0.16, 0.36, 0.47, 0.5, 0.57, 0.8, 1]

    /// Y2K chrome: bands of light, a dark horizon line and hard highlights.
    static func drawChromeHeart(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let heart = heartPath(in: art)
        dieCut([heart])
        linear(heart, chromeColors, chromeStops, in: cg)
        keyline([heart], UIColor.plum.withAlphaComponent(0.5), width: 4)
        UIColor.white.setFill()
        grid.ellipse(0.26, 0.26, 0.2, 0.08, degrees: -36).fill()
        sparklePath(center: grid.p(0.74, 0.3), radius: art.width * 0.1).fill()
        sparklePath(center: grid.p(0.3, 0.68), radius: art.width * 0.05).fill()
    }

    static func drawChromeStar(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let center = grid.p(0.5, 0.54)
        let outer = art.width * 0.5
        let inner = outer * 0.48
        let star = roundedPolygon(starPoints(center: center, outer: outer, inner: inner), radius: art.width * 0.03)
        dieCut([star])
        linear(star, chromeColors, chromeStops, in: cg)
        // Facets give the chrome its depth.
        cg.saveGState()
        star.addClip()
        facetedStar(center: center, outer: outer, inner: inner, light: UIColor.white.withAlphaComponent(0.25), shade: UIColor.plum.withAlphaComponent(0.16))
        cg.restoreGState()
        keyline([star], UIColor.plum.withAlphaComponent(0.5), width: 4)
        UIColor.white.setFill()
        sparklePath(center: grid.p(0.36, 0.34), radius: art.width * 0.09).fill()
        sparklePath(center: grid.p(0.76, 0.66), radius: art.width * 0.05).fill()
    }

    /// A heart with a holographic shimmer.
    static func drawHoloHeart(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let heart = heartPath(in: art)
        dieCut([heart])
        linear(heart, [lighter(.brandBlush, 0.2), lighter(.auraLilac, 0.35), lighter(.auraMint, 0.35), lighter(.auraButter, 0.3), lighter(.auraPink, 0.3)],
               from: art.origin, to: CGPoint(x: art.maxX, y: art.maxY), in: cg)
        // Diagonal bands of shimmer.
        cg.saveGState()
        heart.addClip()
        UIColor.white.withAlphaComponent(0.28).setFill()
        for (offset, thickness) in [(-0.3, 0.08), (-0.1, 0.04), (0.18, 0.1), (0.42, 0.05)] as [(CGFloat, CGFloat)] {
            let band = UIBezierPath(rect: CGRect(x: -art.width, y: -art.width * thickness / 2, width: art.width * 2, height: art.width * thickness))
            band.apply(CGAffineTransform(rotationAngle: -.pi / 4))
            band.apply(CGAffineTransform(translationX: art.midX + art.width * offset, y: art.midY + art.width * offset))
            band.fill()
        }
        cg.restoreGState()
        keyline([heart], deeper(.auraLilac, 0.3).withAlphaComponent(0.55))
        shine(grid.r(0.08, 0.14, 0.34, 0.18), degrees: -38, alpha: 0.8, clip: heart, in: cg)
        UIColor.white.setFill()
        sparklePath(center: grid.p(0.74, 0.3), radius: art.width * 0.08).fill()
        sparklePath(center: grid.p(0.4, 0.62), radius: art.width * 0.05).fill()
        sparklePath(center: grid.p(0.62, 0.74), radius: art.width * 0.035).fill()
    }

    /// A see-through jelly butterfly hair clip with glitter.
    static func drawButterflyClip(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let upper = [grid.ellipse(0.27, 0.35, 0.46, 0.52, degrees: -32), grid.ellipse(0.73, 0.35, 0.46, 0.52, degrees: 32)]
        let lower = [grid.ellipse(0.32, 0.73, 0.3, 0.36, degrees: 30), grid.ellipse(0.68, 0.73, 0.3, 0.36, degrees: -30)]
        let clip = UIBezierPath(roundedRect: grid.r(0.455, 0.12, 0.09, 0.8), cornerRadius: art.width * 0.045)
        dieCut(upper + lower + [clip])

        for (wings, color) in [(lower, UIColor.auraPink), (upper, UIColor.auraLilac)] {
            for wing in wings {
                // Jelly: pale and clear, deeper toward the body, a bright rim.
                linear(wing, [lighter(color, 0.75).withAlphaComponent(0.9), lighter(color, 0.3).withAlphaComponent(0.85)], in: cg)
                cg.saveGState()
                wing.addClip()
                UIColor.white.withAlphaComponent(0.7).setStroke()
                wing.lineWidth = 7
                wing.stroke()
                cg.restoreGState()
                keyline([wing], deeper(color, 0.3).withAlphaComponent(0.5))
            }
        }
        // Glitter.
        let glitter: [(CGFloat, CGFloat, CGFloat)] = [(0.18, 0.24, 0.02), (0.3, 0.38, 0.014), (0.22, 0.48, 0.016), (0.36, 0.22, 0.012),
                                                      (0.82, 0.24, 0.02), (0.7, 0.38, 0.014), (0.78, 0.48, 0.016), (0.64, 0.22, 0.012),
                                                      (0.28, 0.72, 0.014), (0.72, 0.72, 0.014), (0.34, 0.82, 0.012), (0.66, 0.82, 0.012)]
        for (index, (x, y, size)) in glitter.enumerated() {
            (index.isMultiple(of: 3) ? lighter(.auraButter, 0.2) : UIColor.white).setFill()
            sparklePath(center: grid.p(x, y), radius: art.width * size * 2.2).fill()
        }
        shine(grid.r(0.1, 0.14, 0.2, 0.1), degrees: -40, alpha: 0.8, clip: upper[0], in: cg)
        // The metal clip down the middle.
        let silver = UIColor(hex: 0xC9CDD8)
        let clipRect = grid.r(0.455, 0.12, 0.09, 0.8)
        linear(clip, [deeper(silver, 0.1), .white, silver, deeper(silver, 0.25)], [0, 0.35, 0.65, 1],
               from: CGPoint(x: clipRect.minX, y: clipRect.midY), to: CGPoint(x: clipRect.maxX, y: clipRect.midY), in: cg)
        keyline([clip], deeper(silver, 0.45).withAlphaComponent(0.6), width: 2.5)
        let ridges = UIBezierPath()
        for y in [0.2, 0.24, 0.28] as [CGFloat] {
            ridges.move(to: grid.p(0.47, y))
            ridges.addLine(to: grid.p(0.53, y))
        }
        deeper(silver, 0.4).setStroke()
        ridges.lineWidth = 2
        ridges.stroke()
    }

    /// A pink flip-open mobile from the 2000s, a pixel heart on its screen
    /// and a charm on its antenna.
    static func drawFlipCell(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let topRect = grid.r(0.1, 0.07, 0.72, 0.42)
        let bottomRect = grid.r(0.1, 0.54, 0.72, 0.44)
        let top = UIBezierPath(roundedRect: topRect, cornerRadius: art.width * 0.14)
        let bottom = UIBezierPath(roundedRect: bottomRect, cornerRadius: art.width * 0.14)
        let hinge = UIBezierPath(roundedRect: grid.r(0.08, 0.46, 0.76, 0.1), cornerRadius: art.width * 0.05)
        let antenna = UIBezierPath(roundedRect: grid.r(0.62, 0.0, 0.11, 0.12), cornerRadius: art.width * 0.05)
        let string = UIBezierPath()
        string.move(to: grid.p(0.68, 0.02))
        string.addQuadCurve(to: grid.p(0.88, 0.16), controlPoint: grid.p(0.86, 0.02))
        let charm = heartPath(in: grid.r(0.8, 0.15, 0.18, 0.12))
        dieCut([antenna, top, hinge, bottom, charm])
        dieCut([string], width: edge * 0.6)

        let pink = UIColor.auraPink
        func metal(_ path: UIBezierPath, _ rect: CGRect) {
            linear(path, [deeper(pink, 0.12), lighter(pink, 0.5), pink, deeper(pink, 0.22)], [0, 0.32, 0.62, 1],
                   from: CGPoint(x: rect.minX, y: rect.midY), to: CGPoint(x: rect.maxX, y: rect.midY), in: cg)
            keyline([path], deeper(pink, 0.45).withAlphaComponent(0.6))
        }
        UIColor.plum.withAlphaComponent(0.6).setStroke()
        string.lineWidth = 2.5
        string.lineCapStyle = .round
        string.stroke()
        glossy(charm, .auraLilac, in: cg)
        keyline([charm], deeper(.auraLilac, 0.35).withAlphaComponent(0.5), width: 2.5)
        metal(antenna, grid.r(0.62, 0, 0.11, 0.12))
        metal(bottom, bottomRect)
        metal(top, topRect)
        metal(hinge, grid.r(0.08, 0.46, 0.76, 0.1))
        // The screen and its pixel heart.
        let screen = UIBezierPath(roundedRect: grid.r(0.2, 0.15, 0.52, 0.27), cornerRadius: art.width * 0.05)
        linear(screen, [lighter(.auraMint, 0.45), lighter(.auraLilac, 0.45)], in: cg)
        keyline([screen], deeper(pink, 0.4).withAlphaComponent(0.5), width: 2.5)
        let pattern = [".XX.XX.", "XXXXXXX", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..."]
        let pixel = art.width * 0.045
        let origin = CGPoint(x: grid.p(0.46, 0).x - pixel * 3.5, y: grid.p(0, 0.285).y - pixel * 3)
        pink.setFill()
        for (row, line) in pattern.enumerated() {
            for (column, mark) in line.enumerated() where mark == "X" {
                UIBezierPath(rect: CGRect(x: origin.x + CGFloat(column) * pixel, y: origin.y + CGFloat(row) * pixel, width: pixel + 0.5, height: pixel + 0.5)).fill()
            }
        }
        shine(grid.r(0.2, 0.15, 0.5, 0.08), degrees: 0, alpha: 0.5, clip: screen, in: cg)
        // Keys under a round navigation button.
        let nav = circle(grid.p(0.46, 0.63), art.width * 0.09)
        linear(nav, [.white, lighter(.auraLilac, 0.75)], in: cg)
        keyline([nav], deeper(pink, 0.35).withAlphaComponent(0.5), width: 2.5)
        glossy(circle(grid.p(0.46, 0.63), art.width * 0.035), pink, in: cg)
        for row in 0..<3 {
            for column in 0..<3 {
                let key = UIBezierPath(roundedRect: grid.r(0.21 + CGFloat(column) * 0.18, 0.72 + CGFloat(row) * 0.075, 0.14, 0.055),
                                       cornerRadius: art.width * 0.02)
                linear(key, [.white, lighter(.auraLilac, 0.7)], in: cg)
            }
        }
        shine(grid.r(0.14, 0.09, 0.14, 0.3), degrees: 0, alpha: 0.5, clip: top, in: cg)
    }

    /// A shiny compact disc with a rainbow shimmer and a see-through hole.
    static func drawCD(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let center = grid.p(0.5, 0.5)
        let outerRadius = art.width * 0.48
        let holeRadius = art.width * 0.085
        let hubRadius = art.width * 0.19
        let rim = circle(center, outerRadius)
        let hole = circle(center, holeRadius)
        let disc = circle(center, outerRadius)
        disc.append(circle(center, holeRadius))
        disc.usesEvenOddFillRule = true
        dieCut([rim, hole])

        let silver = UIColor(hex: 0xC9CFE3)
        radial(disc, [.white, lighter(.auraLilac, 0.8), silver], [0, 0.55, 1], light: grid.p(0.38, 0.36), radius: outerRadius * 1.3, in: cg)
        // Iridescent wedges and a cross of light.
        cg.saveGState()
        disc.addClip()
        let tints: [UIColor] = [.auraPink, .auraMint, .auraLilac, .auraButter, .auraPink, .auraMint, .auraLilac, .auraPeach]
        for (index, tint) in tints.enumerated() {
            let wedge = UIBezierPath()
            wedge.move(to: center)
            wedge.addArc(withCenter: center, radius: outerRadius * 1.1, startAngle: CGFloat(index) * .pi / 4, endAngle: CGFloat(index + 1) * .pi / 4, clockwise: true)
            wedge.close()
            tint.withAlphaComponent(0.3).setFill()
            wedge.fill()
        }
        UIColor.white.withAlphaComponent(0.5).setFill()
        for angle in [-0.6, 0.97] as [CGFloat] {
            let glare = UIBezierPath()
            glare.move(to: center)
            glare.addArc(withCenter: center, radius: outerRadius * 1.1, startAngle: angle, endAngle: angle + 0.22, clockwise: true)
            glare.close()
            glare.fill()
            let opposite = UIBezierPath()
            opposite.move(to: center)
            opposite.addArc(withCenter: center, radius: outerRadius * 1.1, startAngle: angle + .pi, endAngle: angle + .pi + 0.22, clockwise: true)
            opposite.close()
            opposite.fill()
        }
        cg.restoreGState()
        // The clear hub around the hole.
        let hub = circle(center, hubRadius)
        hub.append(circle(center, holeRadius))
        hub.usesEvenOddFillRule = true
        UIColor.white.withAlphaComponent(0.5).setFill()
        hub.fill()
        keyline([circle(center, hubRadius)], UIColor.auraLilac.withAlphaComponent(0.45), width: 2.5)
        keyline([rim], deeper(silver, 0.35).withAlphaComponent(0.6))
        keyline([hole], deeper(silver, 0.35).withAlphaComponent(0.6), width: 2.5)
        UIColor.white.setFill()
        sparklePath(center: grid.p(0.76, 0.24), radius: art.width * 0.07).fill()
    }

    /// One big sparkle with little rays around it, like a flash going off.
    static func drawSparkleBurst(in art: CGRect, context cg: CGContext) {
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
        deeper(.auraPink, 0.1).setStroke()
        rays.lineWidth = rayWidth
        rays.stroke()
        lighter(.auraPink, 0.35).setStroke()
        rays.lineWidth = rayWidth * 0.35
        rays.stroke()
        // Stroking in a deeper colour first softens the points.
        let butter = UIColor.auraButter
        deeper(butter.mixed(with: .auraPeach, amount: 0.4), 0.1).setStroke()
        sparkle.lineWidth = 6
        sparkle.stroke()
        radial(sparkle, [lighter(butter, 0.6), butter, butter.mixed(with: .auraPeach, amount: 0.45)], [0, 0.45, 1],
               light: grid.p(0.44, 0.42), radius: art.width * 0.4, in: cg)
        UIColor.white.withAlphaComponent(0.85).setFill()
        sparklePath(center: grid.p(0.42, 0.42), radius: art.width * 0.09).fill()
    }

    /// A cute retro camera with a big lens and a heart on it.
    static func drawCamera(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let body = UIBezierPath(roundedRect: grid.r(0.02, 0.24, 0.96, 0.72), cornerRadius: art.width * 0.1)
        let top = UIBezierPath(roundedRect: grid.r(0.3, 0.08, 0.34, 0.24), cornerRadius: art.width * 0.05)
        let button = UIBezierPath(roundedRect: grid.r(0.73, 0.13, 0.15, 0.15), cornerRadius: art.width * 0.03)
        dieCut([body, top, button])

        let line = deeper(.brandBlush, 0.35).withAlphaComponent(0.6)
        glossy(button, .auraPink, in: cg)
        keyline([button], deeper(.auraPink, 0.4).withAlphaComponent(0.55))
        glossy(top, UIColor.brandBlush.mixed(with: .auraPink, amount: 0.3), in: cg)
        keyline([top], line)
        glossy(body, .brandBlush, in: cg)
        // A grip band across the middle.
        cg.saveGState()
        body.addClip()
        UIColor.auraPink.withAlphaComponent(0.2).setFill()
        UIBezierPath(rect: grid.r(0, 0.5, 1, 0.2)).fill()
        cg.restoreGState()
        keyline([body], line)
        // The lens, ring by ring, and its glints.
        let lens = grid.p(0.5, 0.6)
        let rings: [(CGFloat, [UIColor])] = [(0.25, [lighter(.brandInk, 0.35), .brandInk]), (0.2, [lighter(.plum, 0.3), .plum]),
                                             (0.135, [lighter(.auraLilac, 0.5), .auraLilac, deeper(.auraLilac, 0.35)]), (0.07, [lighter(.brandInk, 0.2), .brandInk])]
        for (radius, colors) in rings {
            let r = art.width * radius
            radial(circle(lens, r), colors, light: CGPoint(x: lens.x - r * 0.4, y: lens.y - r * 0.4), radius: r * 1.6, in: cg)
        }
        UIColor.white.withAlphaComponent(0.85).setFill()
        grid.ellipse(0.45, 0.52, 0.07, 0.05, degrees: -35).fill()
        glint(grid.p(0.56, 0.68), art.width * 0.015, alpha: 0.6)
        let flash = UIBezierPath(roundedRect: grid.r(0.09, 0.33, 0.15, 0.11), cornerRadius: art.width * 0.02)
        glossy(flash, .auraButter, in: cg)
        keyline([flash], deeper(.auraButter.mixed(with: .auraPeach, amount: 0.5), 0.2).withAlphaComponent(0.5), width: 2.5)
        let heart = heartPath(in: grid.r(0.8, 0.36, 0.1, 0.11))
        glossy(heart, .auraPink, in: cg)
        shine(grid.r(0.06, 0.28, 0.3, 0.1), degrees: -8, alpha: 0.7, clip: body, in: cg)
    }

    /// A tilted strip of film with three pastel frames.
    static func drawFilmStrip(in art: CGRect, context cg: CGContext) {
        cg.saveGState()
        cg.translateBy(x: art.midX, y: art.midY)
        cg.rotate(by: -7 * .pi / 180)
        let width = art.width * 0.86
        let height = art.height * 0.64
        let stripRect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        let strip = UIBezierPath(roundedRect: stripRect, cornerRadius: height * 0.08)
        dieCut([strip])
        linear(strip, [lighter(.brandInk, 0.18), .brandInk], in: cg)
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
            glossy(UIBezierPath(roundedRect: rect, cornerRadius: frame.height * 0.08), color, in: cg)
            let mark = CGRect(x: rect.midX - frame.height * 0.22, y: rect.midY - frame.height * 0.2,
                              width: frame.height * 0.44, height: frame.height * 0.4)
            UIColor.white.setFill()
            switch index {
            case 0: heartPath(in: mark).fill()
            case 1: sparklePath(center: CGPoint(x: mark.midX, y: mark.midY), radius: mark.width * 0.55).fill()
            default: starPath(center: CGPoint(x: mark.midX, y: mark.midY + mark.height * 0.04), outer: mark.width * 0.5, inner: mark.width * 0.25).fill()
            }
        }
        shine(CGRect(x: stripRect.minX + width * 0.05, y: stripRect.minY + height * 0.02, width: width * 0.5, height: height * 0.12),
              degrees: -2, alpha: 0.35, clip: strip, in: cg)
        cg.restoreGState()
    }
}
