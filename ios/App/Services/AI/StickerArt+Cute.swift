import UIKit

// Cute: fruit, flowers, faces, animals, clouds and a cup of bubble tea.
extension StickerArt {
    static func drawCherries(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let radius = art.width * 0.22
        let centers = [grid.p(0.3, 0.72), grid.p(0.7, 0.77)]
        let cherries = centers.map { circle($0, radius) }
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

        let green = UIColor.auraMint.mixed(with: .plum, amount: 0.12)
        deeper(green, 0.45).setStroke()
        stems.lineWidth = stemWidth
        stems.lineCapStyle = .round
        stems.stroke()
        glossy(leaf, green, in: cg)
        keyline([leaf], deeper(green, 0.4).withAlphaComponent(0.55))
        let vein = UIBezierPath()
        vein.move(to: grid.p(0.62, 0.1))
        vein.addQuadCurve(to: grid.p(0.9, 0.12), controlPoint: grid.p(0.76, 0.07))
        deeper(green, 0.3).setStroke()
        vein.lineWidth = 3
        vein.lineCapStyle = .round
        vein.stroke()

        for (cherry, center) in zip(cherries, centers) {
            radial(cherry, [lighter(.auraPink, 0.3), .auraPink, deeper(.auraPink, 0.4)], [0, 0.4, 1],
                   light: CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.35), radius: radius * 1.5, in: cg)
            keyline([cherry], deeper(.auraPink, 0.45).withAlphaComponent(0.55))
            shine(CGRect(x: center.x - radius * 0.7, y: center.y - radius * 0.72, width: radius * 0.66, height: radius * 0.4),
                  degrees: -30, alpha: 0.85, clip: cherry, in: cg)
        }
    }

    static func drawFlower(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let center = grid.p(0.5, 0.5)
        var tips: [CGPoint] = []
        let petals = (0..<5).map { index -> UIBezierPath in
            let angle = CGFloat(index) * 72 - 90
            let radians = angle * .pi / 180
            tips.append(grid.p(0.5 + cos(radians) * 0.47, 0.5 + sin(radians) * 0.47))
            return grid.ellipse(0.5 + cos(radians) * 0.25, 0.5 + sin(radians) * 0.25, 0.34, 0.44, degrees: angle + 90)
        }
        let heart = circle(center, art.width * 0.14)
        dieCut(petals + [heart])
        // Each petal deepens toward the middle of the flower.
        for (petal, tip) in zip(petals, tips) {
            linear(petal, [deeper(.brandBlush, 0.12), .brandBlush, lighter(.brandBlush, 0.55)], [0, 0.45, 1], from: center, to: tip, in: cg)
        }
        keyline(petals, deeper(.brandBlush, 0.3).withAlphaComponent(0.5))
        radial(heart, [lighter(.auraButter, 0.4), .auraButter, deeper(.auraButter.mixed(with: .auraPeach, amount: 0.4), 0.1)],
               light: grid.p(0.45, 0.44), radius: art.width * 0.16, in: cg)
        keyline([heart], deeper(.auraPeach, 0.2).withAlphaComponent(0.55), width: 2.5)
        UIColor.auraPeach.setFill()
        for index in 0..<5 {
            let radians = (CGFloat(index) * 72 - 54) * .pi / 180
            grid.ellipse(0.5 + cos(radians) * 0.07, 0.5 + sin(radians) * 0.07, 0.035, 0.035).fill()
        }
        shine(grid.r(0.4, 0.06, 0.16, 0.1), degrees: -10, alpha: 0.7, clip: petals[0], in: cg)
    }

    /// A white daisy with a butter-yellow centre.
    static func drawDaisy(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let center = grid.p(0.5, 0.5)
        var tips: [CGPoint] = []
        let petals = (0..<12).map { index -> UIBezierPath in
            let angle = CGFloat(index) * 30 - 90
            let radians = angle * .pi / 180
            tips.append(grid.p(0.5 + cos(radians) * 0.49, 0.5 + sin(radians) * 0.49))
            return grid.ellipse(0.5 + cos(radians) * 0.29, 0.5 + sin(radians) * 0.29, 0.15, 0.4, degrees: angle + 90)
        }
        let heart = circle(center, art.width * 0.15)
        dieCut(petals + [heart])
        // A soft lilac line first, so white petals show on the white edge
        // and on a bright sky; the fills cover its inner half.
        keyline(petals, UIColor.auraLilac.withAlphaComponent(0.5), width: 4)
        for (petal, tip) in zip(petals, tips) {
            linear(petal, [lighter(.auraLilac, 0.78), .white], [0, 0.6], from: center, to: tip, in: cg)
        }
        radial(heart, [lighter(.auraButter, 0.45), .auraButter, .auraButter.mixed(with: .auraPeach, amount: 0.45)], [0, 0.5, 1],
               light: grid.p(0.45, 0.44), radius: art.width * 0.17, in: cg)
        keyline([heart], deeper(.auraPeach, 0.15).withAlphaComponent(0.5), width: 2.5)
        UIColor.auraPeach.withAlphaComponent(0.7).setFill()
        for index in 0..<6 {
            let radians = (CGFloat(index) * 60 + 15) * .pi / 180
            grid.ellipse(0.5 + cos(radians) * 0.085, 0.5 + sin(radians) * 0.085, 0.035, 0.035).fill()
        }
        shine(grid.r(0.39, 0.39, 0.12, 0.07), degrees: -30, alpha: 0.8, clip: heart, in: cg)
    }

    static func drawSmiley(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let face = UIBezierPath(ovalIn: art)
        dieCut([face])
        let warm = UIColor.auraButter.mixed(with: .auraPeach, amount: 0.45)
        radial(face, [lighter(.auraButter, 0.55), .auraButter, warm], [0, 0.55, 1], light: grid.p(0.38, 0.32), radius: art.width * 0.75, in: cg)
        keyline([face], deeper(warm, 0.2).withAlphaComponent(0.6))
        blush([grid.p(0.24, 0.62), grid.p(0.76, 0.62)], width: art.width * 0.17, height: art.width * 0.1)
        eyes([grid.p(0.36, 0.42), grid.p(0.64, 0.42)], width: art.width * 0.11, height: art.width * 0.16)
        let mouth = UIBezierPath(arcCenter: grid.p(0.5, 0.54), radius: art.width * 0.2,
                                 startAngle: .pi * 0.2, endAngle: .pi * 0.8, clockwise: true)
        UIColor.plum.setStroke()
        mouth.lineWidth = art.width * 0.05
        mouth.lineCapStyle = .round
        mouth.stroke()
        shine(grid.r(0.12, 0.08, 0.38, 0.2), degrees: -30, alpha: 0.75, clip: face, in: cg)
    }

    static func drawButterfly(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let upperLeft = grid.ellipse(0.28, 0.36, 0.46, 0.56, degrees: -24)
        let upperRight = grid.ellipse(0.72, 0.36, 0.46, 0.56, degrees: 24)
        let lowerLeft = grid.ellipse(0.33, 0.73, 0.32, 0.38, degrees: 28)
        let lowerRight = grid.ellipse(0.67, 0.73, 0.32, 0.38, degrees: -28)
        let body = UIBezierPath(roundedRect: grid.r(0.465, 0.2, 0.07, 0.7), cornerRadius: art.width * 0.035)
        let antennae = UIBezierPath()
        antennae.move(to: grid.p(0.49, 0.22))
        antennae.addQuadCurve(to: grid.p(0.36, 0.03), controlPoint: grid.p(0.45, 0.06))
        antennae.move(to: grid.p(0.51, 0.22))
        antennae.addQuadCurve(to: grid.p(0.64, 0.03), controlPoint: grid.p(0.55, 0.06))
        let antennaWidth = art.width * 0.022
        dieCut([upperLeft, upperRight, lowerLeft, lowerRight, body])
        dieCut([antennae], width: edge * 0.7 + antennaWidth / 2)

        for wing in [lowerLeft, lowerRight] {
            glossy(wing, .auraPink, in: cg)
            keyline([wing], deeper(.auraPink, 0.4).withAlphaComponent(0.5))
        }
        for wing in [upperLeft, upperRight] {
            glossy(wing, .auraLilac, in: cg)
            keyline([wing], deeper(.auraLilac, 0.4).withAlphaComponent(0.5))
        }
        // Wing markings.
        UIColor.brandPetal.withAlphaComponent(0.85).setFill()
        grid.ellipse(0.23, 0.33, 0.2, 0.24, degrees: -24).fill()
        grid.ellipse(0.77, 0.33, 0.2, 0.24, degrees: 24).fill()
        UIColor.white.withAlphaComponent(0.8).setFill()
        for (x, y) in [(0.12, 0.2), (0.88, 0.2), (0.16, 0.5), (0.84, 0.5)] as [(CGFloat, CGFloat)] {
            grid.ellipse(x, y, 0.035, 0.04).fill()
        }
        radial(grid.ellipse(0.31, 0.76, 0.11, 0.13), [lighter(.auraButter, 0.4), .auraButter], light: grid.p(0.29, 0.73), radius: art.width * 0.08, in: cg)
        radial(grid.ellipse(0.69, 0.76, 0.11, 0.13), [lighter(.auraButter, 0.4), .auraButter], light: grid.p(0.67, 0.73), radius: art.width * 0.08, in: cg)
        linear(body, [lighter(.plum, 0.3), .plum], from: grid.p(0.46, 0.5), to: grid.p(0.54, 0.5), in: cg)
        UIColor.plum.setStroke()
        antennae.lineWidth = antennaWidth
        antennae.lineCapStyle = .round
        antennae.stroke()
        UIColor.plum.setFill()
        for x in [0.36, 0.64] as [CGFloat] {
            grid.ellipse(x, 0.03, 0.05, 0.06).fill()
        }
        shine(grid.r(0.1, 0.14, 0.2, 0.12), degrees: -50, alpha: 0.7, clip: upperLeft, in: cg)
        shine(grid.r(0.7, 0.14, 0.2, 0.12), degrees: 50, alpha: 0.5, clip: upperRight, in: cg)
    }

    /// A smiling white cloud.
    static func drawCloud(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let cloud = cloudPath(center: grid.p(0.5, 0.57), width: art.width * 0.92)
        dieCut([cloud])
        // Rim first, then the fill, so only the cloud's outline shows.
        keyline([cloud], UIColor.auraLilac.withAlphaComponent(0.55), width: 6)
        linear(cloud, [.white, .white, lighter(.auraLilac, 0.72)], [0, 0.5, 1], in: cg)
        blush([grid.p(0.32, 0.67), grid.p(0.68, 0.67)], width: art.width * 0.09, height: art.width * 0.05, alpha: 0.4)
        eyes([grid.p(0.41, 0.58), grid.p(0.59, 0.58)], width: art.width * 0.045, height: art.width * 0.065)
        smile(grid.p(0.5, 0.63), radius: art.width * 0.04, width: art.width * 0.02)
        shine(grid.r(0.3, 0.16, 0.26, 0.14), degrees: -12, alpha: 0.9, clip: cloud, in: cg)
    }

    /// A pink cloud raining little hearts.
    static func drawHeartCloud(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let cloud = cloudPath(center: grid.p(0.5, 0.42), width: art.width * 0.92)
        let hearts = [heartPath(in: grid.r(0.2, 0.74, 0.14, 0.14)), heartPath(in: grid.r(0.45, 0.84, 0.12, 0.12)), heartPath(in: grid.r(0.66, 0.72, 0.15, 0.15))]
        dieCut([cloud] + hearts)
        keyline([cloud], UIColor.auraPink.withAlphaComponent(0.45), width: 6)
        linear(cloud, [.white, .brandPetal, .brandBlush], [0, 0.45, 1], in: cg)
        // Closed, happy eyes.
        let happy = UIBezierPath()
        for x in [0.4, 0.6] as [CGFloat] {
            happy.move(to: grid.p(x - 0.04, 0.46))
            happy.addQuadCurve(to: grid.p(x + 0.04, 0.46), controlPoint: grid.p(x, 0.4))
        }
        UIColor.plum.setStroke()
        happy.lineWidth = art.width * 0.02
        happy.lineCapStyle = .round
        happy.stroke()
        blush([grid.p(0.31, 0.52), grid.p(0.69, 0.52)], width: art.width * 0.09, height: art.width * 0.05, alpha: 0.5)
        smile(grid.p(0.5, 0.49), radius: art.width * 0.035, width: art.width * 0.02)
        for (heart, color) in zip(hearts, [UIColor.auraPink, .auraLilac, .auraPink]) {
            glossy(heart, color, in: cg)
            keyline([heart], deeper(color, 0.35).withAlphaComponent(0.5), width: 2.5)
        }
        shine(grid.r(0.3, 0.02, 0.26, 0.14), degrees: -12, alpha: 0.9, clip: cloud, in: cg)
    }

    static func drawStrawberry(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let berry = UIBezierPath()
        berry.move(to: grid.p(0.5, 0.26))
        berry.addCurve(to: grid.p(0.05, 0.44), controlPoint1: grid.p(0.28, 0.2), controlPoint2: grid.p(0.05, 0.26))
        berry.addCurve(to: grid.p(0.5, 0.98), controlPoint1: grid.p(0.05, 0.68), controlPoint2: grid.p(0.32, 0.92))
        berry.addCurve(to: grid.p(0.95, 0.44), controlPoint1: grid.p(0.68, 0.92), controlPoint2: grid.p(0.95, 0.68))
        berry.addCurve(to: grid.p(0.5, 0.26), controlPoint1: grid.p(0.95, 0.26), controlPoint2: grid.p(0.72, 0.2))
        berry.close()
        // Pointed leaves fanning out over the shoulders of the berry.
        let calyx = UIBezierPath()
        let base = grid.p(0.5, 0.27)
        for (degrees, length) in [(172, 0.27), (138, 0.22), (90, 0.17), (42, 0.22), (8, 0.27)] as [(CGFloat, CGFloat)] {
            let span = art.width * length
            let width = art.width * 0.075
            let leaf = UIBezierPath()
            leaf.move(to: .zero)
            leaf.addQuadCurve(to: CGPoint(x: span, y: 0), controlPoint: CGPoint(x: span * 0.45, y: -width))
            leaf.addQuadCurve(to: .zero, controlPoint: CGPoint(x: span * 0.45, y: width))
            leaf.close()
            leaf.apply(CGAffineTransform(rotationAngle: degrees * .pi / 180))
            leaf.apply(CGAffineTransform(translationX: base.x, y: base.y))
            calyx.append(leaf)
        }
        let stem = UIBezierPath(roundedRect: grid.r(0.465, 0.09, 0.07, 0.17), cornerRadius: art.width * 0.03)
        dieCut([berry, calyx, stem])

        let red = UIColor(hex: 0xFF4F7B)
        radial(berry, [lighter(red, 0.45), red, deeper(red, 0.35)], [0, 0.45, 1], light: grid.p(0.36, 0.42), radius: art.width * 0.8, in: cg)
        keyline([berry], deeper(red, 0.45).withAlphaComponent(0.55))
        // Seeds in staggered rows.
        let seeds: [(CGFloat, CGFloat)] = [(0.3, 0.45), (0.5, 0.42), (0.7, 0.45), (0.2, 0.58), (0.4, 0.58), (0.6, 0.58), (0.8, 0.58),
                                          (0.3, 0.71), (0.5, 0.72), (0.7, 0.71), (0.4, 0.84), (0.6, 0.84)]
        for (x, y) in seeds {
            UIColor.white.withAlphaComponent(0.35).setFill()
            grid.ellipse(x - 0.008, y - 0.01, 0.045, 0.05).fill()
            lighter(.auraButter, 0.2).setFill()
            grid.ellipse(x, y, 0.035, 0.045).fill()
        }
        let green = UIColor.auraMint.mixed(with: .plum, amount: 0.12)
        glossy(stem, deeper(green, 0.3), in: cg)
        glossy(calyx, green, in: cg)
        keyline([calyx], deeper(green, 0.4).withAlphaComponent(0.55), width: 2.5)
        shine(grid.r(0.14, 0.36, 0.22, 0.16), degrees: -40, alpha: 0.75, clip: berry, in: cg)
    }

    /// A spotted mushroom with a little face on its stem.
    static func drawMushroom(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let cap = UIBezierPath()
        cap.move(to: grid.p(0.03, 0.56))
        cap.addCurve(to: grid.p(0.5, 0.04), controlPoint1: grid.p(0.03, 0.24), controlPoint2: grid.p(0.24, 0.04))
        cap.addCurve(to: grid.p(0.97, 0.56), controlPoint1: grid.p(0.76, 0.04), controlPoint2: grid.p(0.97, 0.24))
        cap.addCurve(to: grid.p(0.03, 0.56), controlPoint1: grid.p(0.82, 0.66), controlPoint2: grid.p(0.18, 0.66))
        cap.close()
        let stem = UIBezierPath(roundedRect: grid.r(0.28, 0.5, 0.44, 0.47), cornerRadius: art.width * 0.14)
        dieCut([cap, stem])

        linear(stem, [.white, .brandPaper, lighter(.auraPeach, 0.6)], [0, 0.5, 1], in: cg)
        keyline([stem], deeper(.auraPeach, 0.25).withAlphaComponent(0.5))
        eyes([grid.p(0.41, 0.74), grid.p(0.59, 0.74)], width: art.width * 0.05, height: art.width * 0.07)
        blush([grid.p(0.35, 0.82), grid.p(0.65, 0.82)], width: art.width * 0.08, height: art.width * 0.045)
        smile(grid.p(0.5, 0.79), radius: art.width * 0.03, width: art.width * 0.018)
        let red = UIColor(hex: 0xFF4F7B)
        radial(cap, [lighter(red, 0.45), red, deeper(red, 0.35)], [0, 0.5, 1], light: grid.p(0.36, 0.2), radius: art.width * 0.75, in: cg)
        // The underside's shadow, then white spots.
        cg.saveGState()
        cap.addClip()
        deeper(red, 0.4).withAlphaComponent(0.35).setFill()
        grid.ellipse(0.5, 0.62, 0.9, 0.16).fill()
        for (x, y, size) in [(0.5, 0.18, 0.16), (0.24, 0.32, 0.13), (0.76, 0.3, 0.12), (0.4, 0.46, 0.08), (0.64, 0.47, 0.09), (0.12, 0.5, 0.07), (0.88, 0.5, 0.07)]
            as [(CGFloat, CGFloat, CGFloat)] {
            let spot = grid.ellipse(x, y, size, size)
            radial(spot, [.white, lighter(.brandBlush, 0.6)], light: grid.p(x - size * 0.2, y - size * 0.2), radius: art.width * size * 0.7, in: cg)
        }
        cg.restoreGState()
        keyline([cap], deeper(red, 0.45).withAlphaComponent(0.55))
        shine(grid.r(0.16, 0.08, 0.26, 0.12), degrees: -30, alpha: 0.6, clip: cap, in: cg)
    }

    static func drawBunny(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let leftEar = grid.ellipse(0.33, 0.25, 0.22, 0.5, degrees: -12)
        let rightEar = grid.ellipse(0.67, 0.25, 0.22, 0.5, degrees: 12)
        let head = grid.ellipse(0.5, 0.66, 0.86, 0.6)
        dieCut([leftEar, rightEar, head])

        let fur = [UIColor.white, .white, lighter(.auraLilac, 0.78)]
        let line = UIColor.auraLilac.withAlphaComponent(0.6)
        for (ear, inner) in [(leftEar, grid.ellipse(0.33, 0.27, 0.1, 0.36, degrees: -12)), (rightEar, grid.ellipse(0.67, 0.27, 0.1, 0.36, degrees: 12))] {
            keyline([ear], line)
            linear(ear, fur, [0, 0.5, 1], in: cg)
            linear(inner, [lighter(.brandBlush, 0.3), .brandBlush], in: cg)
        }
        keyline([head], line)
        linear(head, fur, [0, 0.55, 1], in: cg)
        blush([grid.p(0.25, 0.74), grid.p(0.75, 0.74)], width: art.width * 0.15, height: art.width * 0.08)
        eyes([grid.p(0.36, 0.63), grid.p(0.64, 0.63)], width: art.width * 0.08, height: art.width * 0.11)
        let nose = UIBezierPath()
        nose.move(to: grid.p(0.46, 0.7))
        nose.addQuadCurve(to: grid.p(0.54, 0.7), controlPoint: grid.p(0.5, 0.68))
        nose.addQuadCurve(to: grid.p(0.46, 0.7), controlPoint: grid.p(0.5, 0.76))
        nose.close()
        UIColor.auraPink.setFill()
        nose.fill()
        let mouth = UIBezierPath()
        mouth.move(to: grid.p(0.5, 0.735))
        mouth.addQuadCurve(to: grid.p(0.44, 0.76), controlPoint: grid.p(0.48, 0.775))
        mouth.move(to: grid.p(0.5, 0.735))
        mouth.addQuadCurve(to: grid.p(0.56, 0.76), controlPoint: grid.p(0.52, 0.775))
        UIColor.plum.setStroke()
        mouth.lineWidth = art.width * 0.018
        mouth.lineCapStyle = .round
        mouth.stroke()
        shine(grid.r(0.2, 0.4, 0.26, 0.1), degrees: -20, alpha: 0.9, clip: head, in: cg)
    }

    static func drawKitty(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let leftEar = roundedPolygon([grid.p(0.1, 0.5), grid.p(0.16, 0.03), grid.p(0.46, 0.28)], radius: art.width * 0.05)
        let rightEar = roundedPolygon([grid.p(0.9, 0.5), grid.p(0.84, 0.03), grid.p(0.54, 0.28)], radius: art.width * 0.05)
        let head = grid.ellipse(0.5, 0.6, 0.92, 0.74)
        dieCut([leftEar, rightEar, head])

        let fur = lighter(.auraPeach, 0.35)
        let line = deeper(.auraPeach, 0.25).withAlphaComponent(0.6)
        for (ear, inner) in [(leftEar, roundedPolygon([grid.p(0.17, 0.42), grid.p(0.2, 0.14), grid.p(0.38, 0.3)], radius: art.width * 0.03)),
                             (rightEar, roundedPolygon([grid.p(0.83, 0.42), grid.p(0.8, 0.14), grid.p(0.62, 0.3)], radius: art.width * 0.03))] {
            glossy(ear, fur, in: cg)
            keyline([ear], line)
            linear(inner, [lighter(.brandBlush, 0.2), .brandBlush], in: cg)
        }
        glossy(head, fur, in: cg)
        keyline([head], line)
        // Tabby stripes on the forehead.
        let stripes = UIBezierPath()
        for x in [0.44, 0.5, 0.56] as [CGFloat] {
            stripes.move(to: grid.p(x, 0.26))
            stripes.addLine(to: grid.p(x, x == 0.5 ? 0.37 : 0.33))
        }
        deeper(.auraPeach, 0.1).setStroke()
        stripes.lineWidth = art.width * 0.025
        stripes.lineCapStyle = .round
        stripes.stroke()
        blush([grid.p(0.24, 0.7), grid.p(0.76, 0.7)], width: art.width * 0.13, height: art.width * 0.07)
        eyes([grid.p(0.35, 0.56), grid.p(0.65, 0.56)], width: art.width * 0.075, height: art.width * 0.1)
        let nose = UIBezierPath()
        nose.move(to: grid.p(0.47, 0.64))
        nose.addLine(to: grid.p(0.53, 0.64))
        nose.addLine(to: grid.p(0.5, 0.675))
        nose.close()
        UIColor.auraPink.setFill()
        nose.fill()
        // An "ω" mouth and whiskers.
        let face = UIBezierPath()
        face.move(to: grid.p(0.5, 0.675))
        face.addQuadCurve(to: grid.p(0.44, 0.7), controlPoint: grid.p(0.48, 0.72))
        face.move(to: grid.p(0.5, 0.675))
        face.addQuadCurve(to: grid.p(0.56, 0.7), controlPoint: grid.p(0.52, 0.72))
        UIColor.plum.setStroke()
        face.lineWidth = art.width * 0.016
        face.lineCapStyle = .round
        face.stroke()
        let whiskers = UIBezierPath()
        for (y, tilt) in [(0.62, -0.03), (0.67, 0.0), (0.72, 0.03)] as [(CGFloat, CGFloat)] {
            whiskers.move(to: grid.p(0.2, y))
            whiskers.addLine(to: grid.p(0.03, y + tilt))
            whiskers.move(to: grid.p(0.8, y))
            whiskers.addLine(to: grid.p(0.97, y + tilt))
        }
        UIColor.plum.withAlphaComponent(0.55).setStroke()
        whiskers.lineWidth = art.width * 0.012
        whiskers.lineCapStyle = .round
        whiskers.stroke()
        shine(grid.r(0.16, 0.3, 0.26, 0.1), degrees: -20, alpha: 0.75, clip: head, in: cg)
    }

    static func drawBear(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let ears = [circle(grid.p(0.2, 0.22), art.width * 0.15), circle(grid.p(0.8, 0.22), art.width * 0.15)]
        let head = grid.ellipse(0.5, 0.58, 0.86, 0.8)
        dieCut(ears + [head])

        let caramel = UIColor(hex: 0xE0A274)
        let line = deeper(caramel, 0.35).withAlphaComponent(0.6)
        for (ear, center) in zip(ears, [grid.p(0.2, 0.22), grid.p(0.8, 0.22)]) {
            glossy(ear, caramel, in: cg)
            keyline([ear], line)
            radial(circle(center, art.width * 0.08), [lighter(.auraPeach, 0.5), lighter(.auraPeach, 0.2)], light: center, radius: art.width * 0.08, in: cg)
        }
        glossy(head, caramel, in: cg)
        keyline([head], line)
        let muzzle = grid.ellipse(0.5, 0.72, 0.38, 0.27)
        linear(muzzle, [lighter(.auraPeach, 0.75), lighter(.auraPeach, 0.5)], in: cg)
        blush([grid.p(0.24, 0.68), grid.p(0.76, 0.68)], width: art.width * 0.13, height: art.width * 0.07)
        eyes([grid.p(0.34, 0.54), grid.p(0.66, 0.54)], width: art.width * 0.08, height: art.width * 0.1)
        let nose = grid.ellipse(0.5, 0.66, 0.13, 0.08)
        radial(nose, [lighter(.plum, 0.25), .plum], light: grid.p(0.47, 0.64), radius: art.width * 0.08, in: cg)
        glint(grid.p(0.47, 0.645), art.width * 0.015)
        let mouth = UIBezierPath()
        mouth.move(to: grid.p(0.5, 0.7))
        mouth.addLine(to: grid.p(0.5, 0.74))
        mouth.addQuadCurve(to: grid.p(0.44, 0.76), controlPoint: grid.p(0.48, 0.78))
        mouth.move(to: grid.p(0.5, 0.74))
        mouth.addQuadCurve(to: grid.p(0.56, 0.76), controlPoint: grid.p(0.52, 0.78))
        UIColor.plum.setStroke()
        mouth.lineWidth = art.width * 0.016
        mouth.lineCapStyle = .round
        mouth.stroke()
        shine(grid.r(0.18, 0.26, 0.28, 0.12), degrees: -24, alpha: 0.6, clip: head, in: cg)
    }

    /// A cup of milk tea with a straw and tapioca pearls.
    static func drawBoba(in art: CGRect, context cg: CGContext) {
        let grid = Grid(rect: art)
        let cup = UIBezierPath()
        cup.move(to: grid.p(0.12, 0.34))
        cup.addLine(to: grid.p(0.88, 0.34))
        cup.addLine(to: grid.p(0.8, 0.92))
        cup.addQuadCurve(to: grid.p(0.72, 0.98), controlPoint: grid.p(0.79, 0.98))
        cup.addLine(to: grid.p(0.28, 0.98))
        cup.addQuadCurve(to: grid.p(0.2, 0.92), controlPoint: grid.p(0.21, 0.98))
        cup.close()
        let lid = UIBezierPath()
        lid.move(to: grid.p(0.06, 0.35))
        lid.addCurve(to: grid.p(0.94, 0.35), controlPoint1: grid.p(0.1, 0.16), controlPoint2: grid.p(0.9, 0.16))
        lid.close()
        let rim = UIBezierPath(roundedRect: grid.r(0.04, 0.32, 0.92, 0.06), cornerRadius: art.width * 0.03)
        let straw = UIBezierPath(roundedRect: CGRect(x: -art.width * 0.05, y: -art.height * 0.2, width: art.width * 0.1, height: art.height * 0.4),
                                 cornerRadius: art.width * 0.03)
        straw.apply(CGAffineTransform(rotationAngle: 0.18))
        straw.apply(CGAffineTransform(translationX: grid.p(0.6, 0.18).x, y: grid.p(0.6, 0.18).y))
        dieCut([straw, lid, rim, cup])

        glossy(straw, .auraPink, in: cg)
        keyline([straw], deeper(.auraPink, 0.35).withAlphaComponent(0.5), width: 2.5)
        // The tea, the pearls at the bottom and the clear cup around them.
        let tea = UIColor(hex: 0xE8B48C)
        linear(cup, [lighter(tea, 0.55), lighter(tea, 0.2), tea], [0, 0.4, 1], in: cg)
        cg.saveGState()
        cup.addClip()
        for (x, y) in [(0.3, 0.9), (0.42, 0.93), (0.55, 0.92), (0.68, 0.9), (0.36, 0.83), (0.5, 0.84), (0.63, 0.83), (0.25, 0.94), (0.75, 0.95)]
            as [(CGFloat, CGFloat)] {
            let pearl = circle(grid.p(x, y), art.width * 0.055)
            radial(pearl, [lighter(.plum, 0.3), .plum], light: grid.p(x - 0.02, y - 0.015), radius: art.width * 0.07, in: cg)
            glint(grid.p(x - 0.02, y - 0.012), art.width * 0.012, alpha: 0.7)
        }
        cg.restoreGState()
        eyes([grid.p(0.39, 0.57), grid.p(0.61, 0.57)], width: art.width * 0.065, height: art.width * 0.085)
        blush([grid.p(0.31, 0.64), grid.p(0.69, 0.64)], width: art.width * 0.1, height: art.width * 0.05)
        smile(grid.p(0.5, 0.61), radius: art.width * 0.04, width: art.width * 0.02)
        keyline([cup], deeper(tea, 0.3).withAlphaComponent(0.6))
        linear(lid, [.white, lighter(.auraLilac, 0.8)], in: cg)
        keyline([lid], UIColor.auraLilac.withAlphaComponent(0.55))
        linear(rim, [.white, lighter(.auraLilac, 0.7)], in: cg)
        keyline([rim], UIColor.auraLilac.withAlphaComponent(0.55), width: 2.5)
        shine(grid.r(0.16, 0.4, 0.1, 0.4), degrees: -6, alpha: 0.7, clip: cup, in: cg)
    }

    /// Two joined eighth notes and a little sparkle.
    static func drawMusicNotes(in art: CGRect, context cg: CGContext) {
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
        // Stroking in the same colour rounds the corners.
        deeper(.auraPink, 0.1).setStroke()
        notes.lineWidth = 6
        notes.lineJoinStyle = .round
        notes.stroke()
        glossy(notes, .auraPink, in: cg)
        glossy(sparkle, .auraLilac, in: cg)
        UIColor.white.withAlphaComponent(0.6).setFill()
        grid.ellipse(0.19, 0.77, 0.09, 0.05, degrees: -22).fill()
        grid.ellipse(0.69, 0.67, 0.09, 0.05, degrees: -22).fill()
        shine(grid.r(0.36, 0.13, 0.5, 0.08), degrees: -12, alpha: 0.6, clip: notes, in: cg)
    }
}
