import Foundation

/// A photo-sized surface: the canvas on screen (points) or the photo itself
/// (pixels). Overlays are placed relative to it, so the same placement lands
/// on the same spot of the preview and of the full-size photo.
public struct OverlayCanvas: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// Artwork is measured in units of a thousandth of the shorter side, so a
    /// sticker covers the same share of the photo at any resolution.
    public static let unitsPerShortSide = 1000.0

    /// Canvas points (or pixels) per artwork unit.
    public var unit: Double { max(min(width, height), 1) / Self.unitsPerShortSide }

    /// The photo measured in artwork units.
    public var sizeInUnits: (width: Double, height: Double) { (width / unit, height / unit) }
}

/// Where a text box or sticker sits: its centre, size and turn. Resolution
/// independent, so moving it on a small preview moves it on the photo.
public struct OverlayPlacement: Equatable, Sendable {
    /// Centre in 0…1 of the photo's width and height, top-left origin.
    public var x: Double
    public var y: Double
    /// 1 is the artwork's natural size.
    public var scale: Double
    /// Clockwise, in radians, within -π…π.
    public var rotation: Double

    public init(x: Double = 0.5, y: Double = 0.5, scale: Double = 1, rotation: Double = 0) {
        self.x = x
        self.y = y
        self.scale = scale
        self.rotation = rotation
    }

    public static let scaleRange: ClosedRange<Double> = 0.2...8
    /// Turns this close to a quarter turn snap to it (about 4°).
    public static let snapTolerance = 4 * Double.pi / 180

    /// Maps artwork units (origin at the artwork's centre, y down) onto
    /// `canvas`: scale, then turn clockwise, then move to the centre.
    public func transform(in canvas: OverlayCanvas) -> CropTransform {
        let size = scale * canvas.unit
        let cosine = cos(rotation) * size
        let sine = sin(rotation) * size
        return CropTransform(a: cosine, b: sine, c: -sine, d: cosine, tx: x * canvas.width, ty: y * canvas.height)
    }

    /// A canvas point in the artwork's own units (origin at its centre); the
    /// inverse of `transform`, for hit testing.
    public func artworkPoint(x px: Double, y py: Double, in canvas: OverlayCanvas) -> (x: Double, y: Double) {
        let size = max(scale * canvas.unit, .ulpOfOne)
        let dx = px - x * canvas.width
        let dy = py - y * canvas.height
        let cosine = cos(rotation)
        let sine = sin(rotation)
        return ((dx * cosine + dy * sine) / size, (-dx * sine + dy * cosine) / size)
    }

    /// Whether artwork of `width × height` units covers a canvas point.
    /// `slop` (canvas points) makes small stickers easier to grab.
    public func contains(x px: Double, y py: Double, artworkWidth: Double, artworkHeight: Double,
                         slop: Double = 0, in canvas: OverlayCanvas) -> Bool {
        let local = artworkPoint(x: px, y: py, in: canvas)
        let grow = slop / max(scale * canvas.unit, .ulpOfOne)
        return abs(local.x) <= artworkWidth / 2 + grow && abs(local.y) <= artworkHeight / 2 + grow
    }

    /// Moved by a drag of `dx, dy` canvas points. The centre stays on the
    /// photo, so nothing can be lost off the edge.
    public func moved(dx: Double, dy: Double, in canvas: OverlayCanvas) -> OverlayPlacement {
        var next = self
        next.x = min(max(x + dx / max(canvas.width, 1), 0), 1)
        next.y = min(max(y + dy / max(canvas.height, 1), 0), 1)
        return next
    }

    public func scaled(by factor: Double) -> OverlayPlacement {
        var next = self
        next.scale = Self.clampedScale(scale * factor)
        return next
    }

    public func rotated(by angle: Double) -> OverlayPlacement {
        var next = self
        next.rotation = Self.normalized(rotation + angle)
        return next
    }

    /// One-finger resize and turn, for a corner handle: the handle moved from
    /// `start` to `end` (canvas points) around the centre.
    public func dragged(handleFrom start: (x: Double, y: Double), to end: (x: Double, y: Double),
                        in canvas: OverlayCanvas) -> OverlayPlacement {
        let cx = x * canvas.width
        let cy = y * canvas.height
        let before = hypot(start.x - cx, start.y - cy)
        let after = hypot(end.x - cx, end.y - cy)
        guard before > 1, after > 1 else { return self }
        let turn = atan2(end.y - cy, end.x - cx) - atan2(start.y - cy, start.x - cx)
        return scaled(by: after / before).rotated(by: turn)
    }

    public static func clampedScale(_ scale: Double) -> Double {
        min(max(scale, scaleRange.lowerBound), scaleRange.upperBound)
    }

    /// The same turn within -π…π.
    public static func normalized(_ angle: Double) -> Double {
        var value = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if value > .pi { value -= 2 * .pi }
        if value <= -.pi { value += 2 * .pi }
        return value
    }

    /// Straight and quarter turns are easy to hit: a turn within
    /// `tolerance` of one snaps to it.
    public static func snapped(_ rotation: Double, tolerance: Double = snapTolerance) -> Double {
        let quarter = Double.pi / 2
        let nearest = (rotation / quarter).rounded() * quarter
        return abs(rotation - nearest) <= tolerance ? normalized(nearest) : normalized(rotation)
    }

    /// Where the `index`-th new item goes: a little lower and to the right of
    /// the one before, so new items don't hide each other.
    public static func newItem(index: Int) -> OverlayPlacement {
        let step = Double(((index % 5) + 5) % 5)
        return OverlayPlacement(x: 0.5 + (step - 2) * 0.06, y: 0.42 + (step - 2) * 0.05)
    }
}

/// The doodle is drawn on a canvas the size the photo had on screen when
/// drawing started. This maps that canvas onto the photo in pixels.
public enum DoodleMapping {
    /// Where the drawing canvas lands on `target`: scaled to its width, from
    /// the top-left corner. The same shape fills it exactly; if the photo's
    /// shape changed since (an Undo of a crop), the doodle keeps its own.
    public static func rect(drawnOn space: OverlayCanvas, onto target: OverlayCanvas) -> (x: Double, y: Double, width: Double, height: Double) {
        let scale = target.width / max(space.width, 1)
        return (0, 0, target.width, space.height * scale)
    }

    /// Target pixels per point of the drawing canvas.
    public static func scale(drawnOn space: OverlayCanvas, onto target: OverlayCanvas) -> Double {
        target.width / max(space.width, 1)
    }
}
