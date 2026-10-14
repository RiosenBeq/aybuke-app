import UIKit

// Glam: bows, pearls, a crown and beauty objects (objects only, never lips
// or other body parts).
extension StickerArt {
    static func drawBow(in art: CGRect, context cg: CGContext) {
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

        let pink = UIColor.auraPink
        for path in tails {
            glossy(path, deeper(pink, 0.12), in: cg)
            keyline([path], deeper(pink, 0.45).withAlphaComponent(0.55))
        }
        for path in loops {
            glossy(path, pink, in: cg)
            keyline([path], deeper(pink, 0.45).withAlphaComponent(0.55))
        }
        // A fold inside each loop.
        let fold = UIBezierPath()
        fold.move(to: grid.p(0.42, 0.43))
        fold.addQuadCurve(to: grid.p(0.15, 0.3), controlPoint: grid.p(0.26, 0.28))
        deeper(pink, 0.4).withAlphaComponent(0.35).setStroke()
        for path in [fold, mirrored(fold, in: art)] {
            path.lineWidth = detailWidth
            path.lineCapStyle = .round
            path.stroke()
        }
        shine(grid.r(0.1, 0.12, 0.22, 0.12), degrees: -30, alpha: 0.7, clip: loops[0], in: cg)
        shine(grid.r(0.68, 0.12, 0.22, 0.12), degrees: 30, alpha: 0.55, clip: loops[1], in: cg)
        glossy(knot, deeper(pink, 0.22), in: cg)
        keyline([knot], deeper(pink, 0.5).withAlphaComponent(0.55))
        glint(grid.p(0.46, 0.36), art.width * 0.015, alpha: 0.7)
    }

    /// A pale satin bow with long, wavy ribbon tails.
    static func drawRibbonBow(in art: CGRect, context cg: CGContext) {
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
        let edgeColor = UIColor.auraPink.withAlphaComponent(0.6)
        for path in tails {
            linear(path, [lighter(satin, 0.3), deeper(satin, 0.08)], in: cg)
            keyline([path], edgeColor)
        }
        for path in loops {
            linear(path, [lighter(satin, 0.6), satin, deeper(satin, 0.08)], [0, 0.5, 1], in: cg)
            keyline([path], edgeColor)
        }
        // A fold inside each loop and a satin shine on top.
        let fold = UIBezierPath()
        fold.move(to: grid.p(0.42, 0.31))
        fold.addQuadCurve(to: grid.p(0.14, 0.2), controlPoint: grid.p(0.26, 0.18))
        UIColor.auraPink.withAlphaComponent(0.35).setStroke()
        for path in [fold, mirrored(fold, in: art)] {
            path.lineWidth = 4
            path.lineCapStyle = .round
            path.stroke()
        }
        shine(grid.r(0.12, 0.08, 0.18, 0.08), degrees: -28, alpha: 0.85, clip: loops[0], in: cg)
        shine(grid.r(0.7, 0.08, 0.18, 0.08), degrees: 28, alpha: 0.85, clip: loops[1], in: cg)
        linear(knot, [satin, deeper(satin, 0.15)], in: cg)
        keyline([knot], edgeColor)
    }

    /// A bow in pink-and-white gingham.
    static func drawGinghamBow(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let loop = UIBezierPath()
        loop.move(to: grid.p(0.46, 0.4))
        loop.addCurve(to: grid.p(0.05, 0.14), controlPoint1: grid.p(0.3, 0.1), controlPoint2: grid.p(0.12, -0.02))
        loop.addCurve(to: grid.p(0.08, 0.72), controlPoint1: grid.p(-0.02, 0.32), controlPoint2: grid.p(-0.02, 0.62))
        loop.addCurve(to: grid.p(0.46, 0.54), controlPoint1: grid.p(0.2, 0.82), controlPoint2: grid.p(0.36, 0.64))
        loop.close()
        let tail = UIBezierPath()
        tail.move(to: grid.p(0.44, 0.54))
        tail.addLine(to: grid.p(0.28, 0.97))
        tail.addLine(to: grid.p(0.37, 0.9))
        tail.addLine(to: grid.p(0.43, 0.99))
        tail.addLine(to: grid.p(0.53, 0.56))
        tail.close()
        let loops = [loop, mirrored(loop, in: art)]
        let tails = [tail, mirrored(tail, in: art)]
        let knot = UIBezierPath(roundedRect: grid.r(0.4, 0.34, 0.2, 0.27), cornerRadius: art.width * 0.06)
        dieCut(loops + tails + [knot])

        let pink = UIColor.auraPink
        let check = art.width * 0.045
        for path in tails + loops {
            UIColor.white.setFill()
            path.fill()
            cg.saveGState()
            path.addClip()
            // See-through pink bands both ways; where they cross, deeper squares.
            pink.withAlphaComponent(0.36).setFill()
            var x = art.minX
            while x < art.maxX {
                UIBezierPath(rect: CGRect(x: x, y: art.minY, width: check, height: art.height)).fill()
                x += check * 2
            }
            var y = art.minY
            while y < art.maxY {
                UIBezierPath(rect: CGRect(x: art.minX, y: y, width: art.width, height: check)).fill()
                y += check * 2
            }
            cg.restoreGState()
            // Volume: light at the top, a little shade at the bottom.
            linear(path, [UIColor.white.withAlphaComponent(0.35), UIColor.white.withAlphaComponent(0), UIColor.plum.withAlphaComponent(0.14)],
                   [0, 0.45, 1], in: cg)
            keyline([path], deeper(pink, 0.3).withAlphaComponent(0.65))
        }
        glossy(knot, pink, in: cg)
        keyline([knot], deeper(pink, 0.45).withAlphaComponent(0.6))
        glint(grid.p(0.46, 0.4), art.width * 0.015, alpha: 0.75)
    }

    /// A strand of pearls tied with a little bow.
    static func drawPearls(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        // Even steps along a U from the top left to the top right.
        func point(_ t: CGFloat) -> CGPoint {
            grid.p(0.07 + 0.86 * t, 0.08 + 0.6 * (1 - pow(2 * t - 1, 2)))
        }
        let samples: [CGPoint] = (0...200).map { point(CGFloat($0) / 200) }
        var lengths: [CGFloat] = [0]
        for index in 1..<samples.count {
            lengths.append(lengths[index - 1] + hypot(samples[index].x - samples[index - 1].x, samples[index].y - samples[index - 1].y))
        }
        let count = 15
        var centers: [CGPoint] = []
        for step in 0..<count {
            let target = lengths.last! * CGFloat(step) / CGFloat(count - 1)
            let index = lengths.firstIndex { $0 >= target } ?? samples.count - 1
            centers.append(samples[index])
        }
        let radius = art.width * 0.05
        let pearls = centers.map { circle($0, radius) }
        let bowCenter = grid.p(0.5, 0.84)
        let loops = [grid.ellipse(0.4, 0.82, 0.18, 0.12, degrees: -20), grid.ellipse(0.6, 0.82, 0.18, 0.12, degrees: 20)]
        let tails = [roundedPolygon([grid.p(0.48, 0.85), grid.p(0.4, 0.99), grid.p(0.46, 0.96)], radius: 2),
                     roundedPolygon([grid.p(0.52, 0.85), grid.p(0.6, 0.99), grid.p(0.54, 0.96)], radius: 2)]
        let knot = circle(bowCenter, art.width * 0.04)
        dieCut(pearls + loops + tails + [knot], width: edge * 0.85)

        for (pearl, center) in zip(pearls, centers) {
            radial(pearl, [.white, lighter(.auraLilac, 0.85), lighter(.auraLilac, 0.5)], [0, 0.5, 1],
                   light: CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.4), radius: radius * 1.6, in: cg)
            keyline([pearl], UIColor.auraLilac.withAlphaComponent(0.45), width: 2.5)
            glint(CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.38), radius * 0.22)
        }
        for path in tails + loops {
            glossy(path, .auraPink, in: cg)
            keyline([path], deeper(.auraPink, 0.4).withAlphaComponent(0.5), width: 2.5)
        }
        glossy(knot, deeper(.auraPink, 0.15), in: cg)
    }

    /// A little golden crown with round tips, pink gems and a heart.
    static func drawCrown(in art: CGRect, context cg: CGContext) {
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
        let tips = tipCenters.map { circle($0, tipRadius) }
        dieCut([body] + tips)

        // Stroking the outline in deep gold first rounds the points.
        let deepGold = UIColor.auraButter.mixed(with: .auraPeach, amount: 0.55)
        deepGold.setStroke()
        body.lineWidth = 9
        body.lineJoinStyle = .round
        body.stroke()
        linear(body, [lighter(.auraButter, 0.4), .auraButter, deepGold], [0, 0.45, 1], in: cg)
        // The band along the bottom.
        cg.saveGState()
        body.addClip()
        UIColor.auraPeach.withAlphaComponent(0.45).setFill()
        UIBezierPath(rect: grid.r(0, 0.7, 1, 0.3)).fill()
        UIColor.white.withAlphaComponent(0.45).setFill()
        UIBezierPath(rect: grid.r(0, 0.7, 1, 0.012)).fill()
        cg.restoreGState()
        keyline([body], deeper(deepGold, 0.3).withAlphaComponent(0.6))

        for (tip, center) in zip(tips, tipCenters) {
            radial(tip, [lighter(.auraPink, 0.5), .auraPink, deeper(.auraPink, 0.3)], light: CGPoint(x: center.x - tipRadius * 0.3, y: center.y - tipRadius * 0.3),
                   radius: tipRadius * 1.4, in: cg)
            keyline([tip], deeper(.auraPink, 0.4).withAlphaComponent(0.5), width: 2.5)
            glint(CGPoint(x: center.x - tipRadius * 0.3, y: center.y - tipRadius * 0.35), tipRadius * 0.25)
        }
        // Gems on the band: a heart between two round ones.
        for x in [0.27, 0.73] as [CGFloat] {
            let gem = grid.ellipse(x, 0.79, 0.09, 0.09)
            glossy(gem, .auraLilac, in: cg)
            glint(grid.p(x - 0.015, 0.775), art.width * 0.01)
        }
        let heart = heartPath(in: grid.r(0.42, 0.69, 0.16, 0.17))
        glossy(heart, .auraPink, in: cg)
        glint(grid.p(0.465, 0.74), art.width * 0.012)
        UIColor.white.setFill()
        sparklePath(center: grid.p(0.5, 0.45), radius: art.width * 0.07).fill()
        shine(grid.r(0.16, 0.42, 0.2, 0.1), degrees: -30, alpha: 0.6, clip: body, in: cg)
    }

    /// A lip gloss tube with a rose-gold cap, tilted (the object only).
    static func drawLipGloss(in art: CGRect, context cg: CGContext) {
        cg.saveGState()
        cg.translateBy(x: art.midX, y: art.midY)
        cg.rotate(by: -14 * .pi / 180)
        let width = art.width * 0.56
        let height = art.height * 0.9
        let top = -height / 2
        let capRect = CGRect(x: -width * 0.42, y: top, width: width * 0.84, height: height * 0.36)
        let collarRect = CGRect(x: -width * 0.46, y: top + height * 0.35, width: width * 0.92, height: height * 0.06)
        let tubeRect = CGRect(x: -width / 2, y: top + height * 0.4, width: width, height: height * 0.6)
        let cap = UIBezierPath(roundedRect: capRect, cornerRadius: width * 0.2)
        let collar = UIBezierPath(roundedRect: collarRect, cornerRadius: 3)
        let tube = UIBezierPath(roundedRect: tubeRect, cornerRadius: width * 0.24)
        dieCut([cap, collar, tube])

        // Clear tube, pink gloss inside, a heart on the front.
        linear(tube, [UIColor.white, lighter(.auraLilac, 0.82)], in: cg)
        let liquid = UIBezierPath(roundedRect: tubeRect.insetBy(dx: width * 0.14, dy: width * 0.14), cornerRadius: width * 0.16)
        linear(liquid, [lighter(.auraPink, 0.35), .auraPink, deeper(.auraPink, 0.2)], [0, 0.5, 1],
               from: CGPoint(x: tubeRect.minX, y: 0), to: CGPoint(x: tubeRect.maxX, y: 0), in: cg)
        UIColor.white.withAlphaComponent(0.9).setFill()
        heartPath(in: CGRect(x: -width * 0.14, y: tubeRect.midY - width * 0.06, width: width * 0.28, height: width * 0.26)).fill()
        keyline([tube], UIColor.auraLilac.withAlphaComponent(0.6))
        shine(CGRect(x: tubeRect.minX + width * 0.06, y: tubeRect.minY + width * 0.1, width: width * 0.14, height: tubeRect.height * 0.7),
              degrees: 0, alpha: 0.8, clip: tube, in: cg)
        // Rose-gold metal: light down the middle, as on a cylinder.
        let roseGold = UIColor.auraPeach.mixed(with: .brandBlush, amount: 0.4)
        for path in [cap, collar] {
            linear(path, [deeper(roseGold, 0.12), lighter(roseGold, 0.55), roseGold, deeper(roseGold, 0.25)], [0, 0.3, 0.6, 1],
                   from: CGPoint(x: capRect.minX, y: 0), to: CGPoint(x: capRect.maxX, y: 0), in: cg)
            keyline([path], deeper(roseGold, 0.4).withAlphaComponent(0.55))
        }
        cg.restoreGState()
    }

    /// An open compact: a mirror in the lid, pressed powder with a heart below.
    static func drawCompactMirror(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let radius = art.width * 0.3
        let lidCenter = grid.p(0.5, 0.25)
        let baseCenter = grid.p(0.5, 0.75)
        let lid = circle(lidCenter, radius)
        let base = circle(baseCenter, radius)
        let hinge = UIBezierPath(roundedRect: grid.r(0.4, 0.46, 0.2, 0.08), cornerRadius: art.width * 0.03)
        dieCut([lid, base, hinge])

        let roseGold = UIColor.auraPeach.mixed(with: .brandBlush, amount: 0.4)
        for (shell, center) in [(lid, lidCenter), (base, baseCenter)] {
            radial(shell, [lighter(roseGold, 0.5), roseGold, deeper(roseGold, 0.25)], [0, 0.55, 1],
                   light: CGPoint(x: center.x - radius * 0.4, y: center.y - radius * 0.4), radius: radius * 1.9, in: cg)
            keyline([shell], deeper(roseGold, 0.4).withAlphaComponent(0.55))
        }
        linear(hinge, [lighter(roseGold, 0.4), deeper(roseGold, 0.2)], in: cg)
        // The mirror, with two streaks of reflected light.
        let mirror = circle(lidCenter, radius * 0.8)
        linear(mirror, [lighter(.auraLilac, 0.8), .white, lighter(.auraMint, 0.7)], [0, 0.5, 1],
               from: CGPoint(x: lidCenter.x - radius, y: lidCenter.y - radius), to: CGPoint(x: lidCenter.x + radius, y: lidCenter.y + radius), in: cg)
        cg.saveGState()
        mirror.addClip()
        UIColor.white.withAlphaComponent(0.85).setFill()
        for (offset, thickness) in [(-0.25, 0.16), (0.12, 0.07)] as [(CGFloat, CGFloat)] {
            let streak = UIBezierPath(rect: CGRect(x: -radius * 1.5, y: -radius * thickness / 2, width: radius * 3, height: radius * thickness))
            streak.apply(CGAffineTransform(rotationAngle: -.pi / 4))
            streak.apply(CGAffineTransform(translationX: lidCenter.x + radius * offset, y: lidCenter.y + radius * offset))
            streak.fill()
        }
        cg.restoreGState()
        keyline([mirror], deeper(roseGold, 0.3).withAlphaComponent(0.5), width: 2.5)
        // Pressed powder with an embossed heart.
        let powder = circle(baseCenter, radius * 0.8)
        radial(powder, [lighter(.brandBlush, 0.4), .brandBlush, deeper(.brandBlush, 0.12)], light: CGPoint(x: baseCenter.x - radius * 0.3, y: baseCenter.y - radius * 0.3),
               radius: radius, in: cg)
        keyline([powder], deeper(roseGold, 0.3).withAlphaComponent(0.5), width: 2.5)
        let emboss = heartPath(in: CGRect(x: baseCenter.x - radius * 0.38, y: baseCenter.y - radius * 0.32, width: radius * 0.76, height: radius * 0.68))
        UIColor.white.withAlphaComponent(0.45).setFill()
        emboss.fill()
        deeper(.brandBlush, 0.2).withAlphaComponent(0.5).setStroke()
        emboss.lineWidth = 2
        emboss.stroke()
        UIColor.white.setFill()
        sparklePath(center: CGPoint(x: lidCenter.x + radius * 0.42, y: lidCenter.y - radius * 0.38), radius: radius * 0.18).fill()
    }

    /// A bottle of pink nail polish (the object only).
    static func drawNailPolish(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let cap = UIBezierPath(roundedRect: grid.r(0.3, 0.02, 0.4, 0.38), cornerRadius: art.width * 0.08)
        let neck = UIBezierPath(rect: grid.r(0.36, 0.38, 0.28, 0.07))
        let bottle = UIBezierPath(roundedRect: grid.r(0.06, 0.43, 0.88, 0.55), cornerRadius: art.width * 0.24)
        dieCut([cap, neck, bottle])

        linear(bottle, [.white, lighter(.auraLilac, 0.8)], in: cg)
        let polish = UIBezierPath(roundedRect: grid.r(0.14, 0.5, 0.72, 0.42), cornerRadius: art.width * 0.17)
        glossy(polish, .auraPink, in: cg)
        UIColor.white.withAlphaComponent(0.92).setFill()
        heartPath(in: grid.r(0.38, 0.62, 0.24, 0.17)).fill()
        keyline([bottle], UIColor.auraLilac.withAlphaComponent(0.6))
        shine(grid.r(0.12, 0.5, 0.12, 0.38), degrees: 0, alpha: 0.85, clip: bottle, in: cg)
        linear(neck, [.white, lighter(.auraLilac, 0.7)], in: cg)
        keyline([neck], UIColor.auraLilac.withAlphaComponent(0.5), width: 2.5)
        let capRect = grid.r(0.3, 0.02, 0.4, 0.38)
        linear(cap, [deeper(.plum, 0.1), lighter(.plum, 0.4), .plum, deeper(.plum, 0.3)], [0, 0.3, 0.6, 1],
               from: CGPoint(x: capRect.minX, y: capRect.midY), to: CGPoint(x: capRect.maxX, y: capRect.midY), in: cg)
        keyline([cap], UIColor.plum.withAlphaComponent(0.6))
        shine(grid.r(0.36, 0.06, 0.07, 0.28), degrees: 0, alpha: 0.6, clip: cap, in: cg)
    }

    /// A mascara tube and its wand, side by side (the objects only).
    static func drawMascara(in art: CGRect, context cg: CGContext) {
        let tubeWidth = art.width * 0.2
        let tubeHeight = art.height * 0.78
        let pink = UIColor.auraPink
        // The tube, tilted.
        cg.saveGState()
        cg.translateBy(x: art.minX + art.width * 0.36, y: art.minY + art.height * 0.53)
        cg.rotate(by: 0.5)
        let tubeRect = CGRect(x: -tubeWidth / 2, y: -tubeHeight / 2, width: tubeWidth, height: tubeHeight)
        let tube = UIBezierPath(roundedRect: tubeRect, cornerRadius: tubeWidth * 0.4)
        dieCut([tube])
        linear(tube, [deeper(pink, 0.15), lighter(pink, 0.45), pink, deeper(pink, 0.25)], [0, 0.3, 0.6, 1],
               from: CGPoint(x: tubeRect.minX, y: 0), to: CGPoint(x: tubeRect.maxX, y: 0), in: cg)
        let band = UIBezierPath(rect: CGRect(x: tubeRect.minX, y: tubeRect.minY + tubeHeight * 0.3, width: tubeWidth, height: tubeHeight * 0.05))
        cg.saveGState()
        tube.addClip()
        linear(band, [lighter(.auraButter, 0.4), .auraButter.mixed(with: .auraPeach, amount: 0.4)], in: cg)
        cg.restoreGState()
        UIColor.white.withAlphaComponent(0.9).setFill()
        heartPath(in: CGRect(x: -tubeWidth * 0.26, y: tubeHeight * 0.05, width: tubeWidth * 0.52, height: tubeWidth * 0.48)).fill()
        keyline([tube], deeper(pink, 0.45).withAlphaComponent(0.55))
        cg.restoreGState()
        // The wand: its cap, the stick and the brush.
        cg.saveGState()
        cg.translateBy(x: art.minX + art.width * 0.68, y: art.minY + art.height * 0.44)
        cg.rotate(by: 0.5)
        let handleRect = CGRect(x: -tubeWidth / 2, y: -tubeHeight / 2, width: tubeWidth, height: tubeHeight * 0.36)
        let handle = UIBezierPath(roundedRect: handleRect, cornerRadius: tubeWidth * 0.4)
        let stick = UIBezierPath(roundedRect: CGRect(x: -tubeWidth * 0.08, y: handleRect.maxY - 2, width: tubeWidth * 0.16, height: tubeHeight * 0.28),
                                 cornerRadius: tubeWidth * 0.08)
        let brushRect = CGRect(x: -tubeWidth * 0.32, y: handleRect.maxY + tubeHeight * 0.2, width: tubeWidth * 0.64, height: tubeHeight * 0.32)
        let brush = UIBezierPath(roundedRect: brushRect, cornerRadius: tubeWidth * 0.3)
        dieCut([handle, stick, brush])
        linear(handle, [deeper(pink, 0.15), lighter(pink, 0.45), pink, deeper(pink, 0.25)], [0, 0.3, 0.6, 1],
               from: CGPoint(x: handleRect.minX, y: 0), to: CGPoint(x: handleRect.maxX, y: 0), in: cg)
        keyline([handle], deeper(pink, 0.45).withAlphaComponent(0.55))
        linear(stick, [lighter(.plum, 0.5), .plum], from: CGPoint(x: -tubeWidth * 0.08, y: 0), to: CGPoint(x: tubeWidth * 0.08, y: 0), in: cg)
        linear(brush, [lighter(.plum, 0.25), .brandInk], from: CGPoint(x: brushRect.minX, y: 0), to: CGPoint(x: brushRect.maxX, y: 0), in: cg)
        // Bristles.
        let bristles = UIBezierPath()
        var y = brushRect.minY + 5
        while y < brushRect.maxY - 3 {
            bristles.move(to: CGPoint(x: brushRect.minX - 3, y: y))
            bristles.addLine(to: CGPoint(x: brushRect.maxX + 3, y: y))
            y += 7
        }
        UIColor.brandInk.setStroke()
        bristles.lineWidth = 2.5
        bristles.lineCapStyle = .round
        bristles.stroke()
        cg.restoreGState()
    }

    /// A heart-shaped perfume bottle with a pink gem stopper.
    static func drawPerfume(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let bottle = heartPath(in: grid.r(0.04, 0.32, 0.92, 0.66))
        let neck = UIBezierPath(roundedRect: grid.r(0.4, 0.23, 0.2, 0.12), cornerRadius: art.width * 0.03)
        let gemPoints = [grid.p(0.5, 0.01), grid.p(0.71, 0.1), grid.p(0.63, 0.24), grid.p(0.37, 0.24), grid.p(0.29, 0.1)]
        let gem = roundedPolygon(gemPoints, radius: art.width * 0.02)
        dieCut([bottle, neck, gem])

        linear(bottle, [.white, lighter(.auraLilac, 0.75)], in: cg)
        // The perfume, about two thirds full.
        let inner = heartPath(in: grid.r(0.12, 0.39, 0.76, 0.54))
        cg.saveGState()
        UIBezierPath(rect: grid.r(0, 0.53, 1, 0.5)).addClip()
        linear(inner, [lighter(.auraPink, 0.45), .auraPink.mixed(with: .auraLilac, amount: 0.3)], in: cg)
        cg.restoreGState()
        UIColor.white.withAlphaComponent(0.6).setFill()
        UIBezierPath(rect: grid.r(0.2, 0.525, 0.6, 0.01)).fill()
        keyline([bottle], UIColor.auraLilac.withAlphaComponent(0.65))
        shine(grid.r(0.12, 0.38, 0.22, 0.14), degrees: -36, alpha: 0.9, clip: bottle, in: cg)
        shine(grid.r(0.72, 0.5, 0.08, 0.2), degrees: 10, alpha: 0.5, clip: bottle, in: cg)
        let gold = UIColor.auraButter.mixed(with: .auraPeach, amount: 0.3)
        linear(neck, [lighter(gold, 0.5), gold, deeper(gold, 0.3)], in: cg)
        keyline([neck], deeper(gold, 0.35).withAlphaComponent(0.55), width: 2.5)
        // A cut gem: light and shaded facets around a flat top.
        glossy(gem, .auraPink, in: cg)
        cg.saveGState()
        gem.addClip()
        let center = grid.p(0.5, 0.12)
        for (index, corner) in gemPoints.enumerated() {
            let facet = UIBezierPath()
            facet.move(to: center)
            facet.addLine(to: corner)
            facet.addLine(to: gemPoints[(index + 1) % gemPoints.count])
            facet.close()
            UIColor.white.withAlphaComponent(index.isMultiple(of: 2) ? 0.28 : 0.05).setFill()
            facet.fill()
        }
        cg.restoreGState()
        keyline([gem], deeper(.auraPink, 0.4).withAlphaComponent(0.55))
        glint(grid.p(0.44, 0.08), art.width * 0.018)
        UIColor.white.setFill()
        sparklePath(center: grid.p(0.84, 0.3), radius: art.width * 0.06).fill()
    }
}
