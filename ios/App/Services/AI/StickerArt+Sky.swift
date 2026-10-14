import UIKit

// Sky: stars, sparkles, the moon, a rainbow, the sun and a planet.
extension StickerArt {
    static func drawStar(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let center = CGPoint(x: art.midX, y: art.minY + art.height * 0.53)
        let outer = art.width * 0.5
        let inner = outer * 0.47
        let star = roundedPolygon(starPoints(center: center, outer: outer, inner: inner), radius: art.width * 0.04)
        dieCut([star])
        let gold = UIColor.auraButter.mixed(with: .auraPeach, amount: 0.35)
        linear(star, [lighter(.auraButter, 0.4), .auraButter, gold], [0, 0.5, 1], in: cg)
        cg.saveGState()
        star.addClip()
        facetedStar(center: center, outer: outer, inner: inner, light: UIColor.white.withAlphaComponent(0.28), shade: gold.withAlphaComponent(0.45))
        cg.restoreGState()
        keyline([star], deeper(gold, 0.25).withAlphaComponent(0.6))
        glint(grid.p(0.42, 0.36), art.width * 0.03)
    }

    static func drawSparkles(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let big = sparklePath(center: grid.p(0.4, 0.58), radius: art.width * 0.4)
        let medium = sparklePath(center: grid.p(0.79, 0.21), radius: art.width * 0.2)
        let small = sparklePath(center: grid.p(0.82, 0.83), radius: art.width * 0.13)
        dieCut([big, medium, small], width: edge * 0.75)
        // A lilac rim, so the white sparkle shows on a bright sky too.
        keyline([big], UIColor.auraLilac, width: 4)
        radial(big, [.white, .white, lighter(.auraLilac, 0.7)], [0, 0.35, 1], light: grid.p(0.36, 0.52), radius: art.width * 0.32, in: cg)
        for (sparkle, color, center) in [(medium, UIColor.auraButter, grid.p(0.79, 0.21)), (small, UIColor.auraPink, grid.p(0.82, 0.83))] {
            keyline([sparkle], deeper(color, 0.2).withAlphaComponent(0.5), width: 3)
            radial(sparkle, [lighter(color, 0.55), color], light: center, radius: art.width * 0.14, in: cg)
        }
    }

    /// A sleepy crescent moon with two little stars.
    static func drawMoon(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let bite = grid.p(0.63, 0.41)
        let biteRadius = art.width * 0.33
        let moon = crescentPath(center: grid.p(0.42, 0.56), radius: art.width * 0.4, bite: bite, biteRadius: biteRadius)
        let bigStar = roundedPolygon(starPoints(center: grid.p(0.77, 0.2), outer: art.width * 0.13, inner: art.width * 0.065), radius: art.width * 0.012)
        let smallStar = roundedPolygon(starPoints(center: grid.p(0.88, 0.5), outer: art.width * 0.08, inner: art.width * 0.04), radius: art.width * 0.008)
        dieCut([moon, bigStar, smallStar])
        let warm = UIColor.auraButter.mixed(with: .auraPeach, amount: 0.35)
        radial(moon, [lighter(.auraButter, 0.5), .auraButter, warm], [0, 0.5, 1], light: grid.p(0.2, 0.36), radius: art.width * 0.6, in: cg)
        // A warmer shade along the inner curve.
        cg.saveGState()
        moon.addClip()
        let innerEdge = circle(bite, biteRadius)
        UIColor.auraPeach.withAlphaComponent(0.4).setStroke()
        innerEdge.lineWidth = art.width * 0.12
        innerEdge.stroke()
        cg.restoreGState()
        keyline([moon], deeper(warm, 0.25).withAlphaComponent(0.6))
        for (star, color) in [(bigStar, UIColor.auraLilac), (smallStar, UIColor.auraPink)] {
            glossy(star, color, in: cg)
            keyline([star], deeper(color, 0.35).withAlphaComponent(0.5), width: 2.5)
        }
        // A closed, smiling eye and a blush cheek.
        let eye = UIBezierPath(arcCenter: grid.p(0.21, 0.6), radius: art.width * 0.05,
                               startAngle: .pi * 0.1, endAngle: .pi * 0.9, clockwise: true)
        UIColor.plum.setStroke()
        eye.lineWidth = art.width * 0.025
        eye.lineCapStyle = .round
        eye.stroke()
        blush([grid.p(0.2, 0.74)], width: art.width * 0.11, height: art.width * 0.07)
        shine(grid.r(0.08, 0.3, 0.12, 0.22), degrees: 25, alpha: 0.7, clip: moon, in: cg)
    }

    /// A pastel rainbow with a cloud at each end.
    static func drawRainbow(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let center = grid.p(0.5, 0.86)
        let outer = art.width * 0.44
        let band = art.width * 0.062
        let colors: [UIColor] = [.auraPink, .auraPeach, .auraButter, .auraMint, .auraLilac]
        let whole = arch(center: center, outer: outer, inner: outer - band * CGFloat(colors.count))
        let clouds = [grid.p(0.2, 0.83), grid.p(0.8, 0.83)].map { cloudPath(center: $0, width: art.width * 0.36) }
        dieCut([whole] + clouds)
        for (index, color) in colors.enumerated() {
            let arc = arch(center: center, outer: outer - band * CGFloat(index), inner: outer - band * CGFloat(index + 1))
            radial(arc, [lighter(color, 0.3), color], light: center, radius: outer - band * CGFloat(index), in: cg)
        }
        keyline([whole], deeper(.auraLilac, 0.2).withAlphaComponent(0.4), width: 3)
        // A bright line along the top of the arch.
        let highlight = UIBezierPath(arcCenter: center, radius: outer - band * 0.35, startAngle: .pi * 1.18, endAngle: .pi * 1.45, clockwise: true)
        UIColor.white.withAlphaComponent(0.7).setStroke()
        highlight.lineWidth = band * 0.3
        highlight.lineCapStyle = .round
        highlight.stroke()
        // Rim first, then the fill, so only the clouds' outline shows.
        keyline(clouds, UIColor.auraLilac.withAlphaComponent(0.5), width: 5)
        for cloud in clouds {
            linear(cloud, [.white, .white, lighter(.auraLilac, 0.75)], [0, 0.5, 1], in: cg)
        }
    }

    /// A smiling sun with soft rays.
    static func drawSun(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let center = grid.p(0.5, 0.5)
        let rays = (0..<12).map { index -> UIBezierPath in
            let angle = CGFloat(index) * .pi / 6 - .pi / 2
            let long = index.isMultiple(of: 2)
            let tip = art.width * (long ? 0.49 : 0.43)
            let base = art.width * 0.27
            let spread: CGFloat = long ? 0.2 : 0.16
            return roundedPolygon([
                CGPoint(x: center.x + cos(angle - spread) * base, y: center.y + sin(angle - spread) * base),
                CGPoint(x: center.x + cos(angle) * tip, y: center.y + sin(angle) * tip),
                CGPoint(x: center.x + cos(angle + spread) * base, y: center.y + sin(angle + spread) * base),
            ], radius: art.width * 0.02)
        }
        let disc = circle(center, art.width * 0.31)
        dieCut(rays + [disc])

        let peach = UIColor.auraPeach
        for (index, ray) in rays.enumerated() {
            linear(ray, [index.isMultiple(of: 2) ? peach : lighter(peach, 0.3), lighter(.auraButter, 0.2)], from: center,
                   to: CGPoint(x: center.x + cos(CGFloat(index) * .pi / 6 - .pi / 2) * art.width * 0.49,
                               y: center.y + sin(CGFloat(index) * .pi / 6 - .pi / 2) * art.width * 0.49), in: cg)
            keyline([ray], deeper(peach, 0.3).withAlphaComponent(0.45), width: 2.5)
        }
        radial(disc, [lighter(.auraButter, 0.5), .auraButter, .auraButter.mixed(with: peach, amount: 0.5)], [0, 0.5, 1],
               light: grid.p(0.42, 0.4), radius: art.width * 0.36, in: cg)
        keyline([disc], deeper(peach, 0.25).withAlphaComponent(0.6))
        // Closed, happy eyes, cheeks and a smile.
        let happy = UIBezierPath()
        for x in [0.4, 0.6] as [CGFloat] {
            happy.move(to: grid.p(x - 0.045, 0.48))
            happy.addQuadCurve(to: grid.p(x + 0.045, 0.48), controlPoint: grid.p(x, 0.42))
        }
        UIColor.plum.setStroke()
        happy.lineWidth = art.width * 0.022
        happy.lineCapStyle = .round
        happy.stroke()
        blush([grid.p(0.33, 0.56), grid.p(0.67, 0.56)], width: art.width * 0.1, height: art.width * 0.055, alpha: 0.5)
        smile(grid.p(0.5, 0.53), radius: art.width * 0.05, width: art.width * 0.022)
        shine(grid.r(0.28, 0.24, 0.2, 0.1), degrees: -30, alpha: 0.7, clip: disc, in: cg)
    }

    /// A star with a pastel trail.
    static func drawShootingStar(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let head = grid.p(0.72, 0.36)
        let tail = grid.p(0.06, 0.86)
        let control = grid.p(0.28, 0.42)
        let lanes: [(UIColor, CGFloat)] = [(.auraPink, -0.075), (.auraLilac, 0), (.auraMint, 0.075)]
        // Each lane is a tapering stroke turned into a shape, so it can fade.
        let trails = lanes.map { lane -> UIBezierPath in
            let offset = lane.1
            let path = UIBezierPath()
            path.move(to: CGPoint(x: head.x, y: head.y + art.height * offset))
            path.addQuadCurve(to: CGPoint(x: tail.x, y: tail.y + art.height * offset * 0.4),
                              controlPoint: CGPoint(x: control.x, y: control.y + art.height * offset))
            return UIBezierPath(cgPath: path.cgPath.copy(strokingWithWidth: art.height * 0.07, lineCap: .round, lineJoin: .round, miterLimit: 1))
        }
        let star = roundedPolygon(starPoints(center: head, outer: art.width * 0.22, inner: art.width * 0.105), radius: art.width * 0.02)
        dieCut(trails + [star])
        for (trail, lane) in zip(trails, lanes) {
            linear(trail, [lane.0, lighter(lane.0, 0.75)], from: head, to: tail, in: cg)
        }
        let gold = UIColor.auraButter.mixed(with: .auraPeach, amount: 0.35)
        linear(star, [lighter(.auraButter, 0.4), .auraButter, gold], [0, 0.5, 1], in: cg)
        cg.saveGState()
        star.addClip()
        facetedStar(center: head, outer: art.width * 0.22, inner: art.width * 0.105, light: UIColor.white.withAlphaComponent(0.28), shade: gold.withAlphaComponent(0.45))
        cg.restoreGState()
        keyline([star], deeper(gold, 0.25).withAlphaComponent(0.6))
        glint(CGPoint(x: head.x - art.width * 0.04, y: head.y - art.width * 0.05), art.width * 0.018)
        UIColor.white.setFill()
        sparklePath(center: grid.p(0.42, 0.18), radius: art.width * 0.05).fill()
        sparklePath(center: grid.p(0.94, 0.72), radius: art.width * 0.04).fill()
    }

    /// A ringed planet.
    static func drawPlanet(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let center = grid.p(0.5, 0.5)
        let radius = art.height * 0.4
        let ringAngle: CGFloat = -0.26
        let ringSize = CGSize(width: art.width * 0.98, height: art.height * 0.3)
        func ring(_ scale: CGFloat) -> UIBezierPath {
            let path = UIBezierPath(ovalIn: CGRect(x: -ringSize.width * scale / 2, y: -ringSize.height * scale / 2,
                                                   width: ringSize.width * scale, height: ringSize.height * scale))
            path.apply(CGAffineTransform(rotationAngle: ringAngle))
            path.apply(CGAffineTransform(translationX: center.x, y: center.y))
            return path
        }
        let planet = circle(center, radius)
        let outerRing = ring(1)
        let band = ring(1)
        band.append(ring(0.74))
        band.usesEvenOddFillRule = true
        dieCut([planet, outerRing])
        // The die-cut paper inside the ring.
        UIColor.white.setFill()
        outerRing.fill()
        planet.fill()

        let gold = UIColor.auraButter.mixed(with: .auraPeach, amount: 0.3)
        func drawBand() {
            linear(band, [lighter(gold, 0.45), gold, deeper(gold, 0.2)], in: cg)
            keyline([ring(1), ring(0.74)], deeper(gold, 0.3).withAlphaComponent(0.5), width: 2.5)
        }
        // The back of the ring, then the planet, then the front of the ring.
        cg.saveGState()
        cg.translateBy(x: center.x, y: center.y)
        cg.rotate(by: ringAngle)
        UIBezierPath(rect: CGRect(x: -art.width, y: -art.height, width: art.width * 2, height: art.height)).addClip()
        cg.rotate(by: -ringAngle)
        cg.translateBy(x: -center.x, y: -center.y)
        drawBand()
        cg.restoreGState()

        radial(planet, [lighter(.auraLilac, 0.5), .auraLilac, deeper(.auraLilac.mixed(with: .auraPink, amount: 0.3), 0.15)], [0, 0.5, 1],
               light: CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.4), radius: radius * 1.5, in: cg)
        cg.saveGState()
        planet.addClip()
        UIColor.auraPink.withAlphaComponent(0.22).setFill()
        for (y, thickness) in [(-0.35, 0.12), (0.12, 0.16), (0.48, 0.1)] as [(CGFloat, CGFloat)] {
            let stripe = UIBezierPath(rect: CGRect(x: center.x - radius, y: center.y + radius * y, width: radius * 2, height: radius * thickness))
            stripe.apply(CGAffineTransform(translationX: -center.x, y: -center.y))
            stripe.apply(CGAffineTransform(rotationAngle: ringAngle))
            stripe.apply(CGAffineTransform(translationX: center.x, y: center.y))
            stripe.fill()
        }
        cg.restoreGState()
        keyline([planet], deeper(.auraLilac, 0.35).withAlphaComponent(0.55))
        shine(CGRect(x: center.x - radius * 0.75, y: center.y - radius * 0.8, width: radius * 0.7, height: radius * 0.4),
              degrees: -30, alpha: 0.75, clip: planet, in: cg)

        cg.saveGState()
        cg.translateBy(x: center.x, y: center.y)
        cg.rotate(by: ringAngle)
        UIBezierPath(rect: CGRect(x: -art.width, y: 0, width: art.width * 2, height: art.height)).addClip()
        cg.rotate(by: -ringAngle)
        cg.translateBy(x: -center.x, y: -center.y)
        drawBand()
        cg.restoreGState()
        UIColor.white.setFill()
        sparklePath(center: grid.p(0.86, 0.14), radius: art.width * 0.05).fill()
        sparklePath(center: grid.p(0.12, 0.84), radius: art.width * 0.04).fill()
    }
}
