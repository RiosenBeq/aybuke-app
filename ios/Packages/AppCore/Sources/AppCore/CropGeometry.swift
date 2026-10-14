import Foundation

/// Crop shapes in the editor's Crop tool. Not `AspectRatio`: that one is the
/// Create screen's wire format and has no 4:5.
public enum CropAspect: String, CaseIterable, Identifiable, Sendable {
    case original, free, square, portrait, story, landscape

    public var id: String { rawValue }

    /// Exact width:height; nil for Original (follows the photo) and Free.
    public var ratio: (width: Int, height: Int)? {
        switch self {
        case .original, .free: return nil
        case .square: return (1, 1)
        case .portrait: return (4, 5)
        case .story: return (9, 16)
        case .landscape: return (16, 9)
        }
    }

    /// Pixel width over height for a photo of `size`; nil when free.
    public func widthOverHeight(for size: CropSize) -> Double? {
        if let ratio { return Double(ratio.width) / Double(ratio.height) }
        return self == .original ? size.width / max(size.height, 1) : nil
    }
}

public struct CropSize: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// A rectangle in 0…1 coordinates of the turned photo, so it survives window
/// resizes and maps onto any resolution of the same picture.
public struct CropRect: Equatable, Sendable {
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

    public static let full = CropRect(x: 0, y: 0, width: 1, height: 1)

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    func isClose(to other: CropRect) -> Bool {
        abs(x - other.x) < 1e-6 && abs(y - other.y) < 1e-6
            && abs(width - other.width) < 1e-6 && abs(height - other.height) < 1e-6
    }
}

/// x' = a·x + c·y + tx, y' = b·x + d·y + ty (the CGAffineTransform layout).
public struct CropTransform: Equatable, Sendable {
    public var a, b, c, d, tx, ty: Double

    public static let identity = CropTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    public func apply(x: Double, y: Double) -> (x: Double, y: Double) {
        (a * x + c * y + tx, b * x + d * y + ty)
    }

    /// `self`, then `next`.
    public func then(_ next: CropTransform) -> CropTransform {
        CropTransform(
            a: next.a * a + next.c * b,
            b: next.b * a + next.d * b,
            c: next.a * c + next.c * d,
            d: next.b * c + next.d * d,
            tx: next.a * tx + next.c * ty + next.tx,
            ty: next.b * tx + next.d * ty + next.ty
        )
    }
}

/// Crop, quarter turns, mirror and straighten: geometry only. Scaling is
/// always uniform (no stretch, no perspective), so a crop can't reshape anyone.
public struct CropGeometry: Equatable, Sendable {
    /// Clockwise quarter turns, 0…3.
    public var quarterTurns = 0
    /// Mirrored left to right, after the turns.
    public var isFlipped = false
    /// Straighten, in degrees; positive turns the picture clockwise.
    public var angle = 0.0
    public var rect = CropRect.full

    public static let maxAngle = 15.0
    /// Smallest crop side, as a fraction of the photo.
    public static let minFraction = 0.1

    public init() {}

    public var isIdentity: Bool {
        quarterTurns == 0 && !isFlipped && angle == 0 && rect.isClose(to: .full)
    }

    /// The photo's size after the quarter turns.
    public func orientedSize(of source: CropSize) -> CropSize {
        quarterTurns % 2 == 0 ? source : CropSize(width: source.height, height: source.width)
    }

    /// Straighten angles this close to level snap to 0.
    public static func snappedAngle(_ degrees: Double) -> Double {
        let clamped = min(max(degrees, -maxAngle), maxAngle)
        return abs(clamped) < 0.5 ? 0 : clamped
    }

    // MARK: Editing

    /// Turns what's on screen a quarter to the left.
    public mutating func rotateLeft(aspect: CropAspect, source: CropSize) {
        // Mirroring reverses the direction of the underlying turn.
        quarterTurns = (quarterTurns + (isFlipped ? 1 : 3)) % 4
        rect = CropRect(x: rect.y, y: 1 - rect.maxX, width: rect.height, height: rect.width)
        if aspect.ratio != nil {
            rect = Self.largestRect(ratio: aspect.widthOverHeight(for: orientedSize(of: source)), in: orientedSize(of: source))
        }
    }

    public mutating func flip() {
        isFlipped.toggle()
        rect.x = 1 - rect.maxX
        angle = -angle
    }

    /// Largest centred rect of `ratio` (pixel width over height); the whole photo when nil.
    public static func largestRect(ratio: Double?, in size: CropSize) -> CropRect {
        guard let ratio, size.width > 0, size.height > 0 else { return .full }
        let normalized = ratio * size.height / size.width
        let width = normalized >= 1 ? 1 : normalized
        let height = normalized >= 1 ? 1 / normalized : 1
        return CropRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }

    /// The rect moved by a normalized offset, kept inside the photo.
    public static func moved(_ rect: CropRect, dx: Double, dy: Double) -> CropRect {
        var moved = rect
        moved.x = min(max(rect.x + dx, 0), 1 - rect.width)
        moved.y = min(max(rect.y + dy, 0), 1 - rect.height)
        return moved
    }

    public enum Corner: CaseIterable, Sendable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
    }

    /// The rect with `corner` dragged to a normalized point; the opposite
    /// corner stays put and a locked `ratio` (pixel width over height) holds.
    public static func resized(
        _ rect: CropRect, corner: Corner, to point: (x: Double, y: Double), ratio: Double?, in size: CropSize
    ) -> CropRect {
        let movesLeft = corner == .topLeading || corner == .bottomLeading
        let movesUp = corner == .topLeading || corner == .topTrailing
        let anchorX = movesLeft ? rect.maxX : rect.x
        let anchorY = movesUp ? rect.maxY : rect.y
        let roomX = movesLeft ? anchorX : 1 - anchorX
        let roomY = movesUp ? anchorY : 1 - anchorY
        let px = min(max(point.x, 0), 1)
        let py = min(max(point.y, 0), 1)
        var width = movesLeft ? anchorX - px : px - anchorX
        var height = movesUp ? anchorY - py : py - anchorY

        if let ratio, size.width > 0, size.height > 0 {
            let normalized = ratio * size.height / size.width
            width = max(width, height * normalized)
            let minimum = max(minFraction, minFraction * normalized)
            width = max(width, minimum)
            width = min(width, roomX, roomY * normalized)
            height = width / normalized
        } else {
            width = min(max(width, minFraction), roomX)
            height = min(max(height, minFraction), roomY)
        }
        return CropRect(
            x: movesLeft ? anchorX - width : anchorX,
            y: movesUp ? anchorY - height : anchorY,
            width: width,
            height: height
        )
    }

    /// The rect grown or shrunk around its centre (VoiceOver's adjustable action).
    /// Both sides scale by the same factor, so a locked shape holds.
    public static func scaled(_ rect: CropRect, by factor: Double) -> CropRect {
        guard rect.width > 0, rect.height > 0 else { return rect }
        var f = min(factor, 1 / rect.width, 1 / rect.height)
        f = max(f, minFraction / rect.width, minFraction / rect.height)
        let width = rect.width * f, height = rect.height * f
        let centred = CropRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
        return moved(centred, dx: 0, dy: 0)
    }

    // MARK: Rendering

    /// How much the straightened photo is enlarged around the crop's centre so
    /// the crop never shows empty corners.
    public func coverScale(in oriented: CropSize) -> Double {
        guard angle != 0 else { return 1 }
        let radians = angle * .pi / 180
        let cosine = cos(radians), sine = sin(radians)
        let cx = rect.midX * oriented.width, cy = rect.midY * oriented.height
        var scale = 1.0
        for (fx, fy) in [(rect.x, rect.y), (rect.maxX, rect.y), (rect.x, rect.maxY), (rect.maxX, rect.maxY)] {
            let dx = fx * oriented.width - cx, dy = fy * oriented.height - cy
            // The output corner, turned back into the photo.
            let ux = dx * cosine + dy * sine
            let uy = -dx * sine + dy * cosine
            if ux > 0 { scale = max(scale, ux / max(oriented.width - cx, 1e-9)) }
            if ux < 0 { scale = max(scale, -ux / max(cx, 1e-9)) }
            if uy > 0 { scale = max(scale, uy / max(oriented.height - cy, 1e-9)) }
            if uy < 0 { scale = max(scale, -uy / max(cy, 1e-9)) }
        }
        // A hair more, so anti-aliased edges never show.
        return scale * 1.002
    }

    /// Output pixels; fixed shapes are exact (4:5 gives 4k × 5k).
    public func outputSize(for source: CropSize, aspect: CropAspect) -> (width: Int, height: Int) {
        let oriented = orientedSize(of: source)
        let width = rect.width * oriented.width + 1e-6
        let height = rect.height * oriented.height + 1e-6
        if let ratio = aspect.ratio {
            let k = max(1, Int(min(width / Double(ratio.width), height / Double(ratio.height))))
            return (ratio.width * k, ratio.height * k)
        }
        return (max(1, Int(width)), max(1, Int(height)))
    }

    /// Maps source pixels onto output pixels of `output` size.
    public func transform(source: CropSize, output: (width: Int, height: Int)) -> CropTransform {
        let w = source.width, h = source.height
        let turn: CropTransform
        switch ((quarterTurns % 4) + 4) % 4 {
        case 1: turn = CropTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
        case 2: turn = CropTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)
        case 3: turn = CropTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
        default: turn = .identity
        }
        let oriented = orientedSize(of: source)
        let mirror = isFlipped ? CropTransform(a: -1, b: 0, c: 0, d: 1, tx: oriented.width, ty: 0) : .identity

        let cx = rect.midX * oriented.width, cy = rect.midY * oriented.height
        let scale = coverScale(in: oriented)
        let radians = angle * .pi / 180
        let a = scale * cos(radians), b = scale * sin(radians)
        let straighten = CropTransform(a: a, b: b, c: -b, d: a, tx: cx - (a * cx - b * cy), ty: cy - (b * cx + a * cy))

        let place = CropTransform(a: 1, b: 0, c: 0, d: 1, tx: Double(output.width) / 2 - cx, ty: Double(output.height) / 2 - cy)
        return turn.then(mirror).then(straighten).then(place)
    }
}
