import Foundation

/// Retro Cam's Photo Booth: four shots with a countdown before each, printed
/// as a vertical strip or a 2×2 grid. The timing and layout maths live here
/// so they run in the Linux tests; the camera and the drawing live in the app.
public enum PhotoBooth {
    /// Shots in one booth session.
    public static let shotCount = 4
    /// Seconds counted down before every shot ("3, 2, 1").
    public static let countdown = 3
    /// Self-timer choices of the camera, in seconds (0 = off).
    public static let timerChoices = [0, 3, 10]

    /// Seconds counted down before each shot: the self-timer for the first
    /// one (never less than the usual 3-2-1), then 3-2-1 between shots.
    public static func countdowns(timer: Int) -> [Int] {
        [max(timer, countdown)] + Array(repeating: countdown, count: shotCount - 1)
    }

    /// The timer choice after `seconds` (off → 3 s → 10 s → off).
    public static func nextTimer(after seconds: Int) -> Int {
        guard let index = timerChoices.firstIndex(of: seconds) else { return timerChoices[0] }
        return timerChoices[(index + 1) % timerChoices.count]
    }

    /// The caption under the shots: one short line.
    public static let captionMaxLength = 40

    /// Trims, joins lines and caps the length of what she typed.
    public static func cleanCaption(_ text: String) -> String {
        let oneLine = text.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return String(oneLine.prefix(captionMaxLength))
    }
}

/// A rectangle in pixels, top-left origin.
public struct BoothRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
}

/// Where everything goes on a booth print.
public struct BoothPlan: Equatable, Sendable {
    public var width: Double
    public var height: Double
    /// The four shots, in shooting order (top to bottom; rows left to right).
    public var cells: [BoothRect]
    /// The caption and date area under the shots; nil when there's neither.
    public var footer: BoothRect?
}

public enum BoothLayout: String, CaseIterable, Identifiable, Sendable {
    /// The classic 2×6 strip: four landscape frames stacked.
    case strip
    /// A 4×6-style print: two rows of two portrait frames.
    case grid

    public var id: String { rawValue }

    public var columns: Int { self == .strip ? 1 : 2 }

    /// Frame width over height: booth strips crop wide, the grid keeps
    /// portrait selfies almost whole.
    public var cellAspect: Double { self == .strip ? 4.0 / 3.0 : 3.0 / 4.0 }

    var canvasWidth: Double { self == .strip ? 1200 : 2400 }
    var margin: Double { self == .strip ? 60 : 72 }
    var gap: Double { self == .strip ? 30 : 36 }
    var footerHeight: Double { self == .strip ? 300 : 440 }

    /// The print for `PhotoBooth.shotCount` shots, with room for a caption
    /// and the date when `hasFooter`.
    public func plan(hasFooter: Bool) -> BoothPlan {
        let columns = self.columns
        let rows = (PhotoBooth.shotCount + columns - 1) / columns
        let cellWidth = ((canvasWidth - margin * 2 - gap * Double(columns - 1)) / Double(columns)).rounded(.down)
        let cellHeight = (cellWidth / cellAspect).rounded(.down)
        // Centre the cells if rounding left a pixel or two at the sides.
        let left = ((canvasWidth - cellWidth * Double(columns) - gap * Double(columns - 1)) / 2).rounded(.down)
        var cells: [BoothRect] = []
        for index in 0..<PhotoBooth.shotCount {
            let row = index / columns
            let column = index % columns
            cells.append(BoothRect(
                x: left + Double(column) * (cellWidth + gap),
                y: margin + Double(row) * (cellHeight + gap),
                width: cellWidth,
                height: cellHeight
            ))
        }
        let bottom = margin + Double(rows) * cellHeight + Double(rows - 1) * gap
        guard hasFooter else {
            return BoothPlan(width: canvasWidth, height: bottom + margin, cells: cells, footer: nil)
        }
        let footer = BoothRect(x: left, y: bottom, width: canvasWidth - left * 2, height: footerHeight)
        return BoothPlan(width: canvasWidth, height: footer.maxY, cells: cells, footer: footer)
    }
}
