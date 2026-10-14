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
}
#endif
