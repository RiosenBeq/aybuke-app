#if DEBUG
import UIKit
import AppCore

/// Deterministic app states for App Store / QA screenshots (DEBUG builds only).
/// Launch with `-GLScreenshotScene <scene>`; see .github/workflows/screenshots.yml.
enum ScreenshotScene: String, CaseIterable {
    case onboarding
    case home
    case create
    case results
    case edit
    case editor
    case effects
    case crop
    case result
    case library
    case paywall
    case consent
    case settings
    case share
    case invite
    case tour
    case legal
    /// A collection page; `-GLCategory <id>` picks it (default: the seasonal row).
    case collection
    /// The Pro out-of-credits sheet: empty, and 2 credits for 4 images.
    case outOfCredits
    case outOfCreditsMulti
    /// Hide faces on a group of cartoon figures, with every friend covered.
    case hideFaces
    /// Cut out with a fixture subject mask and a backdrop.
    case cutout

    static var current: ScreenshotScene? {
        UserDefaults.standard.string(forKey: "GLScreenshotScene").flatMap(ScreenshotScene.init(rawValue:))
    }
}

/// Synthetic images so screenshots never contain real people's photos.
enum ScreenshotFixtures {
    /// A flat, overcast lake landscape — the "before" photo.
    static let overcastLandscape = landscape(golden: false)

    /// The same scene at golden hour — what "Golden hour light" produces.
    static let goldenLandscape = landscape(golden: true)

    static let createPrompt = "A dreamy pastel bedroom with fairy lights and a canopy bed at sunset"

    static func generatedArt(count: Int) -> [UIImage] {
        let styles = ["pastel", "kawaii", "anime", "watercolor", "fantasy", "neon"].map { StyleCatalog.style(id: $0) }
        return (0..<count).map { index in
            let style = styles[index % styles.count]
            return DemoArt.render(prompt: "\(createPrompt) \(index)", style: style, size: AspectRatio.portrait.pixelSize(longEdge: 1024), variant: index, stamped: false)
        }
    }

    private static func landscape(golden: Bool) -> UIImage {
        let size = CGSize(width: 1200, height: 1500)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let horizon = size.height * 0.58

            // Sky
            let skyColors: [UIColor] = golden
                ? [UIColor(red: 0.16, green: 0.20, blue: 0.40, alpha: 1), UIColor(red: 0.98, green: 0.55, blue: 0.30, alpha: 1), UIColor(red: 1.0, green: 0.80, blue: 0.45, alpha: 1)]
                : [UIColor(red: 0.55, green: 0.60, blue: 0.66, alpha: 1), UIColor(red: 0.70, green: 0.73, blue: 0.76, alpha: 1), UIColor(red: 0.78, green: 0.80, blue: 0.82, alpha: 1)]
            if let sky = CGGradient(colorsSpace: space, colors: skyColors.map(\.cgColor) as CFArray, locations: [0, 0.7, 1]) {
                cg.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: horizon), options: [])
            }

            // Sun glow
            if golden {
                let sun = CGPoint(x: size.width * 0.62, y: horizon - 70)
                let glowColors = [UIColor(red: 1, green: 0.93, blue: 0.70, alpha: 1).cgColor, UIColor(red: 1, green: 0.62, blue: 0.30, alpha: 0).cgColor] as CFArray
                if let glow = CGGradient(colorsSpace: space, colors: glowColors, locations: [0, 1]) {
                    cg.drawRadialGradient(glow, startCenter: sun, startRadius: 0, endCenter: sun, endRadius: 520, options: [])
                }
                UIColor(red: 1, green: 0.96, blue: 0.84, alpha: 1).setFill()
                cg.fillEllipse(in: CGRect(x: sun.x - 60, y: sun.y - 60, width: 120, height: 120))
            }

            // Mountains (far → near)
            let ranges: [(CGFloat, [CGFloat], UIColor, UIColor)] = [
                (0.40, [0.0, 0.42, 0.20, 0.30, 0.38, 0.18, 0.62, 0.33, 0.85, 0.22, 1.0, 0.36],
                 UIColor(red: 0.45, green: 0.36, blue: 0.48, alpha: 1), UIColor(red: 0.62, green: 0.66, blue: 0.70, alpha: 1)),
                (0.50, [0.0, 0.52, 0.15, 0.40, 0.33, 0.48, 0.55, 0.34, 0.78, 0.46, 1.0, 0.41],
                 UIColor(red: 0.28, green: 0.20, blue: 0.30, alpha: 1), UIColor(red: 0.46, green: 0.50, blue: 0.54, alpha: 1)),
            ]
            for (_, points, goldenColor, flatColor) in ranges {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 0, y: horizon))
                for index in stride(from: 0, to: points.count, by: 2) {
                    path.addLine(to: CGPoint(x: points[index] * size.width, y: points[index + 1] * size.height))
                }
                path.addLine(to: CGPoint(x: size.width, y: horizon))
                path.close()
                (golden ? goldenColor : flatColor).setFill()
                path.fill()
            }

            // Lake with reflection
            let lakeColors: [UIColor] = golden
                ? [UIColor(red: 0.95, green: 0.58, blue: 0.34, alpha: 1), UIColor(red: 0.20, green: 0.17, blue: 0.30, alpha: 1)]
                : [UIColor(red: 0.62, green: 0.66, blue: 0.70, alpha: 1), UIColor(red: 0.32, green: 0.36, blue: 0.40, alpha: 1)]
            if let lake = CGGradient(colorsSpace: space, colors: lakeColors.map(\.cgColor) as CFArray, locations: [0, 1]) {
                cg.saveGState()
                cg.clip(to: CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon))
                cg.drawLinearGradient(lake, start: CGPoint(x: 0, y: horizon), end: CGPoint(x: 0, y: size.height), options: [])
                cg.restoreGState()
            }
            // Ripples
            (golden ? UIColor(red: 1, green: 0.85, blue: 0.6, alpha: 0.35) : UIColor(white: 0.85, alpha: 0.2)).setFill()
            for row in 0..<14 {
                let y = horizon + 30 + CGFloat(row) * 42
                let width = CGFloat(220 - row * 9)
                cg.fill(CGRect(x: size.width * 0.62 - width / 2, y: y, width: width, height: 4))
            }

            // Foreground shore
            let shore = UIBezierPath()
            shore.move(to: CGPoint(x: 0, y: size.height * 0.86))
            shore.addCurve(to: CGPoint(x: size.width, y: size.height * 0.93),
                           controlPoint1: CGPoint(x: size.width * 0.3, y: size.height * 0.80),
                           controlPoint2: CGPoint(x: size.width * 0.7, y: size.height * 0.98))
            shore.addLine(to: CGPoint(x: size.width, y: size.height))
            shore.addLine(to: CGPoint(x: 0, y: size.height))
            shore.close()
            (golden ? UIColor(red: 0.12, green: 0.09, blue: 0.12, alpha: 1) : UIColor(red: 0.20, green: 0.22, blue: 0.24, alpha: 1)).setFill()
            shore.fill()
        }
    }

    // MARK: Hide faces and Cut out

    /// Head circles (centre x, centre y, radius as a share of the width) for
    /// a group of cartoon figures; the second one is the largest ("me").
    private static let groupHeads: [(CGFloat, CGFloat, CGFloat)] = [(0.17, 0.55, 0.065), (0.40, 0.47, 0.095), (0.63, 0.53, 0.07), (0.85, 0.57, 0.055)]

    /// Cartoon figures by the lake: Vision finds no real faces in them, so
    /// the scene uses `groupFaces` instead.
    static let groupPhoto = figures(heads: groupHeads, pet: false)

    /// Face boxes for `groupPhoto`, normalized with a top-left origin.
    static var groupFaces: [CGRect] {
        groupHeads.map { x, y, r in
            let height = r * 1200 / 1500
            return CGRect(x: x - r, y: y - height, width: r * 2, height: height * 2)
        }
    }

    private static let cutoutHeads: [(CGFloat, CGFloat, CGFloat)] = [(0.34, 0.42, 0.11)]

    /// A cartoon person and a pet for the Cut out scene.
    static let cutoutPhoto = figures(heads: cutoutHeads, pet: true)

    /// A stand-in for Vision's subject lifting on `cutoutPhoto`: the same
    /// shapes as label map and masks.
    static func cutoutAnalysis(for image: UIImage) -> CutoutAnalysis? {
        guard let source = image.cgImage else { return nil }
        let size = CGSize(width: source.width, height: source.height)
        let labelWidth = 240, labelHeight = Int((240 * size.height / size.width).rounded())
        guard let labelContext = CGContext(
            data: nil, width: labelWidth, height: labelHeight, bitsPerComponent: 8, bytesPerRow: labelWidth,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        labelContext.setShouldAntialias(false)
        // Top-left origin, like Vision's label map.
        labelContext.translateBy(x: 0, y: CGFloat(labelHeight))
        labelContext.scaleBy(x: 1, y: -1)
        let labelScale = CGFloat(labelWidth) / size.width
        for (index, path) in figurePaths(heads: cutoutHeads, pet: true, size: size).enumerated() {
            labelContext.saveGState()
            labelContext.scaleBy(x: labelScale, y: labelScale)
            labelContext.addPath(path.cgPath)
            labelContext.setFillColor(gray: CGFloat(index + 1) / 255, alpha: 1)
            labelContext.fillPath()
            labelContext.restoreGState()
        }
        guard let data = labelContext.data else { return nil }
        let labels = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: labelWidth * labelHeight))
        return CutoutAnalysis(source: source, labels: labels, labelWidth: labelWidth, labelHeight: labelHeight) { ids in
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let mask = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                UIColor.black.setFill()
                UIRectFill(CGRect(origin: .zero, size: size))
                UIColor.white.setFill()
                for (index, path) in figurePaths(heads: cutoutHeads, pet: true, size: size).enumerated() where ids.contains(index + 1) {
                    path.fill()
                }
            }
            return mask.cgImage.map { CIImage(cgImage: $0) } ?? CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        }
    }

    private static func figures(heads: [(CGFloat, CGFloat, CGFloat)], pet: Bool) -> UIImage {
        let base = goldenLandscape
        let size = base.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let colors: [UIColor] = [.auraLilac, .auraPink, .auraMint, .auraPeach, .auraButter]
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            base.draw(at: .zero)
            for (index, path) in figurePaths(heads: heads, pet: pet, size: size).enumerated() {
                colors[index % colors.count].setFill()
                path.fill()
                UIColor.white.withAlphaComponent(0.8).setStroke()
                path.lineWidth = 3
                path.stroke()
            }
        }
    }

    /// One path per subject: a head on a rounded body, and optionally a pet.
    private static func figurePaths(heads: [(CGFloat, CGFloat, CGFloat)], pet: Bool, size: CGSize) -> [UIBezierPath] {
        var paths = heads.map { x, y, r -> UIBezierPath in
            let radius = r * size.width
            let center = CGPoint(x: x * size.width, y: y * size.height)
            let path = UIBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            path.append(UIBezierPath(
                roundedRect: CGRect(x: center.x - radius * 1.5, y: center.y + radius * 1.05, width: radius * 3, height: size.height - center.y),
                cornerRadius: radius
            ))
            return path
        }
        if pet {
            let body = CGRect(x: size.width * 0.6, y: size.height * 0.7, width: size.width * 0.3, height: size.height * 0.16)
            let path = UIBezierPath(ovalIn: body)
            let head = CGRect(x: body.maxX - body.width * 0.35, y: body.minY - body.height * 0.55, width: body.width * 0.4, height: body.width * 0.4)
            path.append(UIBezierPath(ovalIn: head))
            for dx in [0.08, 0.62] as [CGFloat] {
                path.append(UIBezierPath(ovalIn: CGRect(x: head.minX + head.width * dx, y: head.minY - head.height * 0.18, width: head.width * 0.3, height: head.height * 0.45)))
            }
            paths.append(path)
        }
        return paths
    }
}
#endif
