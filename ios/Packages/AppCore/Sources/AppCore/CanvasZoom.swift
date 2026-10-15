import Foundation

/// A rectangle in points or pixels (top-left origin): the editor canvas, a
/// loupe, a share design's parts.
public struct CanvasRect: Equatable, Sendable {
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

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    /// Whether `other` lies inside, allowing for rounding.
    public func contains(_ other: CanvasRect, tolerance: Double = 0.5) -> Bool {
        other.minX >= minX - tolerance && other.minY >= minY - tolerance
            && other.maxX <= maxX + tolerance && other.maxY <= maxY + tolerance
    }
}

/// The editor canvas's zoom, the same in every tool: pinch up to 4×,
/// double-tap to 2× where she tapped and back to fit, a short "2×" badge,
/// and a pinch that lets go just above fit settles at fit (with a light tap).
public enum CanvasZoomMath {
    /// Previews are ~1200 px and photos at most 2048 px: more is just blur.
    public static let maximumScale = 4.0
    public static let doubleTapScale = 2.0
    /// A pinch that ends below this goes back to fit.
    public static let snapToFitBelow = 1.12
    private static let tolerance = 0.01

    public static func isAtFit(_ scale: Double) -> Bool { scale <= 1 + tolerance }

    /// Where a double tap goes: back to fit when zoomed in, else 2×.
    public static func doubleTapTarget(from scale: Double) -> Double {
        isAtFit(scale) ? doubleTapScale : 1
    }

    /// Where a pinch that just ended settles: fit when it's barely zoomed.
    public static func settledScale(_ scale: Double) -> Double {
        scale < snapToFitBelow ? 1 : min(scale, maximumScale)
    }

    /// The badge's number ("2", "1.5"), to one decimal; nil at fit.
    public static func badgeValue(for scale: Double) -> Double? {
        guard !isAtFit(scale) else { return nil }
        return (min(scale, maximumScale) * 10).rounded() / 10
    }

    /// The part of a `width` × `height` canvas (at fit) to fill the view
    /// with at `scale`, centred on the tapped point and kept on the canvas,
    /// so the spot she tapped comes to the middle wherever there's room.
    public static func zoomRect(around x: Double, _ y: Double, width: Double, height: Double, scale: Double) -> CanvasRect {
        let scale = max(scale, 1)
        let size = (width: width / scale, height: height / scale)
        let originX = min(max(x - size.width / 2, 0), max(width - size.width, 0))
        let originY = min(max(y - size.height / 2, 0), max(height - size.height, 0))
        return CanvasRect(x: originX, y: originY, width: size.width, height: size.height)
    }

    /// The scroll position that keeps the same spot in the middle after the
    /// canvas changed size (the tool bars hid or came back) at `scale`.
    /// `center` is that spot as a fraction (0…1) of the content.
    public static func offset(keeping center: (x: Double, y: Double), contentWidth: Double, contentHeight: Double,
                              viewWidth: Double, viewHeight: Double) -> (x: Double, y: Double) {
        let x = center.x * contentWidth - viewWidth / 2
        let y = center.y * contentHeight - viewHeight / 2
        return (min(max(x, 0), max(contentWidth - viewWidth, 0)), min(max(y, 0), max(contentHeight - viewHeight, 0)))
    }
}

/// The loupe over a brush canvas: a magnified circle above her finger, so
/// she sees the edge she's painting. Beside the finger near the top, and
/// always inside the canvas.
public enum LoupeLayout {
    /// How much bigger than the canvas on screen.
    public static let magnification = 2.0

    /// The loupe's frame for a touch at (`x`, `y`) on a `width` × `height` canvas.
    public static func frame(touchX x: Double, touchY y: Double, width: Double, height: Double,
                             diameter: Double, gap: Double) -> CanvasRect {
        var center = (x: x, y: y - gap - diameter / 2)
        if center.y - diameter / 2 < 0 {
            // No room above: beside the finger, on the side with more room.
            let side: Double = x > width / 2 ? -1 : 1
            center = (x: x + side * (gap + diameter / 2), y: y)
        }
        let originX = min(max(center.x - diameter / 2, 0), max(width - diameter, 0))
        let originY = min(max(center.y - diameter / 2, 0), max(height - diameter, 0))
        return CanvasRect(x: originX, y: originY, width: diameter, height: diameter)
    }

    /// The part of the canvas the loupe shows: a square around the touch.
    public static func source(touchX x: Double, touchY y: Double, diameter: Double) -> CanvasRect {
        let side = diameter / magnification
        return CanvasRect(x: x - side / 2, y: y - side / 2, width: side, height: side)
    }
}
