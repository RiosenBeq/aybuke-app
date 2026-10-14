import UIKit
import CoreImage
import AppCore

/// The on-screen display of a 2006 camcorder: a red REC dot, "SP", a
/// battery and the date. On video the dot blinks and a timecode runs; those
/// parts are cached as small images and placed per frame, so nothing
/// frame-sized is drawn while the video plays.
enum CamcorderChrome {
    private struct Metrics {
        let size: CGSize
        let unit: CGFloat
        let margin: CGFloat
        let font: UIFont
        let attributes: [NSAttributedString.Key: Any]
        let advance: CGFloat
        let lineHeight: CGFloat
        let dotRadius: CGFloat
        /// Room around small cached images for the text shadow.
        let padding: CGFloat

        init(size: CGSize) {
            self.size = size
            unit = max(size.width, size.height) / 1000
            margin = 36 * unit
            font = UIFont.monospacedSystemFont(ofSize: 30 * unit, weight: .semibold)
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.55)
            shadow.shadowBlurRadius = 3 * unit
            shadow.shadowOffset = CGSize(width: 0, height: 1 * unit)
            attributes = [.font: font, .foregroundColor: UIColor(white: 1, alpha: 0.95), .shadow: shadow]
            advance = ("0" as NSString).size(withAttributes: attributes).width
            lineHeight = font.lineHeight
            dotRadius = 10 * unit
            padding = 6 * unit
        }

        var dotCenter: CGPoint { CGPoint(x: margin + dotRadius, y: margin + lineHeight / 2) }

        /// Top-left of the timecode's first character (bottom-right corner).
        var timecodeOrigin: CGPoint {
            CGPoint(x: size.width - margin - advance * 11, y: size.height - margin - lineHeight)
        }
    }

    // MARK: Static layer

    /// Everything that doesn't change between frames. Photos also get the
    /// dot and the clock time; video draws those per frame instead.
    static func layer(size: CGSize, date: Date, showsDot: Bool) -> UIImage {
        let m = Metrics(size: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            if showsDot { drawDot(center: m.dotCenter, radius: m.dotRadius, unit: m.unit) }
            ("REC" as NSString).draw(at: CGPoint(x: m.margin + m.dotRadius * 2 + 10 * m.unit, y: m.margin), withAttributes: m.attributes)

            let battery = CGRect(x: m.size.width - m.margin - 46 * m.unit, y: m.margin + (m.lineHeight - 22 * m.unit) / 2,
                                 width: 42 * m.unit, height: 22 * m.unit)
            drawBattery(in: battery, unit: m.unit)
            let sp = "SP" as NSString
            let spWidth = sp.size(withAttributes: m.attributes).width
            sp.draw(at: CGPoint(x: battery.minX - 18 * m.unit - spWidth, y: m.margin), withAttributes: m.attributes)

            (dateText(date) as NSString).draw(at: CGPoint(x: m.margin, y: m.size.height - m.margin - m.lineHeight), withAttributes: m.attributes)
            if showsDot {
                let time = timeText(date) as NSString
                let width = time.size(withAttributes: m.attributes).width
                time.draw(at: CGPoint(x: m.size.width - m.margin - width, y: m.size.height - m.margin - m.lineHeight), withAttributes: m.attributes)
            }
        }
    }

    /// "OCT 14 2006": today's day, in the camcorder's year.
    private static func dateText(_ date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.month, .day], from: date)
        let names = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
        return String(format: "%@ %02d 2006", names[(parts.month ?? 1) - 1], parts.day ?? 1)
    }

    /// "PM 6:42", the way camcorders printed the time.
    private static func timeText(_ date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%@ %d:%02d", hour < 12 ? "AM" : "PM", twelve, parts.minute ?? 0)
    }

    private static func drawDot(center: CGPoint, radius: CGFloat, unit: CGFloat) {
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.setShadow(offset: .zero, blur: 4 * unit, color: UIColor.red.withAlphaComponent(0.6).cgColor)
        UIColor(red: 1, green: 0.16, blue: 0.12, alpha: 1).setFill()
        UIBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
        context?.restoreGState()
    }

    /// A full battery: outline, nub and three bars (drawn, not an SF Symbol).
    private static func drawBattery(in rect: CGRect, unit: CGFloat) {
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.setShadow(offset: CGSize(width: 0, height: unit), blur: 3 * unit, color: UIColor.black.withAlphaComponent(0.55).cgColor)
        UIColor(white: 1, alpha: 0.95).set()
        let body = UIBezierPath(roundedRect: rect, cornerRadius: 3 * unit)
        body.lineWidth = 2.5 * unit
        body.stroke()
        UIBezierPath(rect: CGRect(x: rect.maxX, y: rect.midY - 5 * unit, width: 4 * unit, height: 10 * unit)).fill()
        let inset = 5 * unit
        let gap = 3 * unit
        let barWidth = (rect.width - inset * 2 - gap * 2) / 3
        for index in 0..<3 {
            let x = rect.minX + inset + CGFloat(index) * (barWidth + gap)
            UIBezierPath(rect: CGRect(x: x, y: rect.minY + inset, width: barWidth, height: rect.height - inset * 2)).fill()
        }
        context?.restoreGState()
    }

    // MARK: Video

    /// The moving parts for video frames of one size: the dot and one small
    /// image per timecode character, placed in Core Image coordinates.
    final class VideoParts: @unchecked Sendable {
        private let dot: CIImage
        private let glyphs: [Character: CIImage]
        private let advance: CGFloat
        private let glyphOrigin: CGPoint

        init(size: CGSize) {
            let m = Metrics(size: size)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false

            let dotSide = (m.dotRadius + m.padding) * 2
            let dotImage = UIGraphicsImageRenderer(size: CGSize(width: dotSide, height: dotSide), format: format).image { _ in
                CamcorderChrome.drawDot(center: CGPoint(x: dotSide / 2, y: dotSide / 2), radius: m.dotRadius, unit: m.unit)
            }
            // Core Image's origin is bottom-left, UIKit's top-left.
            let dotTop = m.dotCenter.y - dotSide / 2
            dot = (CIImage(image: dotImage) ?? CIImage.empty())
                .transformed(by: CGAffineTransform(translationX: m.dotCenter.x - dotSide / 2, y: size.height - dotTop - dotSide))

            let glyphSize = CGSize(width: m.advance + m.padding * 2, height: m.lineHeight + m.padding * 2)
            var glyphs: [Character: CIImage] = [:]
            for character in "0123456789:" {
                let image = UIGraphicsImageRenderer(size: glyphSize, format: format).image { _ in
                    (String(character) as NSString).draw(at: CGPoint(x: m.padding, y: m.padding), withAttributes: m.attributes)
                }
                glyphs[character] = CIImage(image: image)
            }
            self.glyphs = glyphs
            advance = m.advance
            let origin = m.timecodeOrigin
            glyphOrigin = CGPoint(x: origin.x - m.padding, y: size.height - origin.y - m.lineHeight - m.padding)
        }

        /// The blinking dot and running timecode over one frame.
        func composite(over frame: CIImage, seconds: Double, fps: Double) -> CIImage {
            let shift = CGAffineTransform(translationX: frame.extent.minX, y: frame.extent.minY)
            var output = frame
            if CamcorderClock.isRecDotVisible(at: seconds) {
                output = dot.transformed(by: shift).composited(over: output)
            }
            for (index, character) in CamcorderClock.timecode(seconds: seconds, fps: fps).enumerated() {
                guard let glyph = glyphs[character] else { continue }
                let place = CGAffineTransform(translationX: glyphOrigin.x + CGFloat(index) * advance, y: glyphOrigin.y).concatenating(shift)
                output = glyph.transformed(by: place).composited(over: output)
            }
            return output
        }
    }
}
