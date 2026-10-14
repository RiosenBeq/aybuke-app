import Foundation

// Collage / photo dump geometry: every layout is a list of rectangles in 0…1
// canvas coordinates plus rotations, so the live preview, the export and the
// carousel slices all draw the same picture. Pure math, tested on Linux.

// MARK: - Canvas

/// A rectangle in 0…1 coordinates of a collage canvas (top-left origin).
public struct CollageRect: Equatable, Sendable {
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
}

/// The collage's shape: a feed or story picture, or a seamless carousel of
/// 2–5 consecutive 4:5 slides.
public enum CollageFormat: Hashable, Sendable {
    case portrait
    case square
    case story
    case classic
    case carousel(slides: Int)

    public static let presets: [CollageFormat] = [.portrait, .square, .story, .classic]
    public static let slideRange = 2...5

    /// 1 for a single picture.
    public var slides: Int {
        guard case .carousel(let count) = self else { return 1 }
        return min(max(count, Self.slideRange.lowerBound), Self.slideRange.upperBound)
    }

    public var isCarousel: Bool {
        if case .carousel = self { return true }
        return false
    }

    /// Exact width:height of the whole canvas.
    public var ratio: (width: Int, height: Int) {
        switch self {
        case .portrait: return (4, 5)
        case .square: return (1, 1)
        case .story: return (9, 16)
        case .classic: return (3, 4)
        case .carousel: return (4 * slides, 5)
        }
    }

    public var widthOverHeight: Double { Double(ratio.width) / Double(ratio.height) }

    /// Export pixels: `longEdge` on the long side of one picture. A carousel
    /// is its slides side by side, `CarouselSlicer.slideSize` each.
    public func pixelSize(longEdge: Int = 2160) -> PixelSize {
        if isCarousel {
            let slide = CarouselSlicer.slideSize
            return PixelSize(width: slide.width * slides, height: slide.height)
        }
        let (width, height) = ratio
        return width >= height
            ? PixelSize(width: longEdge, height: longEdge * height / width)
            : PixelSize(width: longEdge * width / height, height: longEdge)
    }
}

/// Cuts a wide carousel canvas into its slides.
public enum CarouselSlicer {
    /// Instagram's tallest feed shape (1080 × 1350) at twice the size, so
    /// slides stay sharp after Instagram's own downscale.
    public static let slideSize = PixelSize(width: 2160, height: 2700)

    public struct Slice: Equatable, Sendable {
        /// Position in the post, from 1.
        public var number: Int
        /// The canvas columns `x ..< x + width`, at full height.
        public var x: Int
        public var width: Int
        public var height: Int
    }

    /// The slides of `canvas`, left to right, tiling it with no gap or overlap.
    public static func slices(of canvas: PixelSize, count: Int) -> [Slice] {
        let count = max(1, count)
        return (0..<count).map { index in
            let start = canvas.width * index / count
            let end = canvas.width * (index + 1) / count
            return Slice(number: index + 1, x: start, width: end - start, height: canvas.height)
        }
    }

    /// Where the seams fall, as shares of the canvas width.
    public static func seams(count: Int) -> [Double] {
        guard count > 1 else { return [] }
        return (1..<count).map { Double($0) / Double(count) }
    }
}

// MARK: - Styles

public enum CollageStyle: String, CaseIterable, Sendable {
    /// The classic photo dump: even rows or columns.
    case grid
    /// One big photo (the first) next to the rest.
    case mosaic
    /// Frames on dark film strips with sprocket holes.
    case filmStrip
    /// Instant-camera prints scattered with a slight tilt.
    case polaroid
    /// White-bordered prints with tape and stickers.
    case scrapbook
    /// A tight masonry board with a colour card sampled from the photos.
    case moodboard

    /// A white card with a shadow sits under each photo.
    public var hasCards: Bool { self == .polaroid || self == .scrapbook }

    /// How many arrangements "Shuffle" goes through for `count` photos.
    public func variantCount(for count: Int) -> Int {
        switch self {
        case .grid: return min(max(count, 1), 3)
        case .mosaic: return count < 2 ? 1 : (CollageLayout.hasLShape(count) ? 3 : 2)
        case .filmStrip: return 2
        case .polaroid, .scrapbook: return 6
        case .moodboard: return count < 2 ? 1 : 2
        }
    }

    /// Corner radii for the slider's `amount` (0…1), in canvas-height units:
    /// the photo window, and the card around it when there is one.
    public func cornerRadii(amount: Double, aspect: Double) -> (card: Double, window: Double) {
        let amount = min(max(amount, 0), 1)
        let short = min(aspect, 1)
        switch self {
        case .grid, .mosaic, .moodboard: return (0, amount * 0.05 * short)
        case .filmStrip: return (0, amount * 0.02 * short)
        case .polaroid, .scrapbook: return (amount * 0.035 * short, amount * 0.015 * short)
        }
    }
}

// MARK: - Layout

/// Where one photo goes.
public struct CollageSlot: Equatable, Sendable {
    /// The cell, card or film frame, before rotation.
    public var frame: CollageRect
    /// Where the photo shows, inside `frame`.
    public var window: CollageRect
    /// Degrees, clockwise, about the frame's centre.
    public var rotation: Double

    public init(frame: CollageRect, window: CollageRect, rotation: Double = 0) {
        self.frame = frame
        self.window = window
        self.rotation = rotation
    }
}

/// A film strip behind its frames.
public struct CollageStrip: Equatable, Sendable {
    public var frame: CollageRect
    /// Degrees, clockwise, about the strip's centre.
    public var rotation: Double
    /// Sprocket holes in 0…1 coordinates of the strip itself.
    public var holes: [CollageRect]
}

/// Tape, stickers and the moodboard's colour card, drawn over the photos.
public struct CollageDecoration: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A strip of washi tape; the app picks its colour by `tone`.
        case tape(tone: Int)
        /// A die-cut sticker from the app's set.
        case sticker(Int)
        /// The moodboard's colour card.
        case palette
        /// A colour dot sampled from the photo in slot `photo`.
        case swatch(photo: Int)
    }

    public var kind: Kind
    public var frame: CollageRect
    /// Degrees, clockwise, about the frame's centre.
    public var rotation: Double
}

public struct CollageLayout: Equatable, Sendable {
    /// One per photo, in slot order; later slots sit on top.
    public var slots: [CollageSlot]
    /// Drawn under the slots.
    public var strips: [CollageStrip] = []
    /// Drawn over the slots.
    public var decorations: [CollageDecoration] = []
    /// The band for the date and caption line, when asked for. A carousel
    /// keeps it on the first slide.
    public var captionFrame: CollageRect?

    public static let empty = CollageLayout(slots: [])

    /// The layout of `count` photos. `spacing` (0…1) sets the gaps and
    /// margins, `variant` picks one of `style.variantCount(for:)`
    /// arrangements (any value; it wraps), and `photoAspects` (width over
    /// height, in slot order) helps pick shapes that crop the least.
    public static func make(
        style: CollageStyle,
        count: Int,
        format: CollageFormat,
        spacing: Double = 0.35,
        variant: Int = 0,
        photoAspects: [Double] = [],
        caption: Bool = false
    ) -> CollageLayout {
        let count = max(count, 0)
        guard count > 0 else { return .empty }
        let aspect = format.widthOverHeight
        let short = min(aspect, 1)
        let spacing = min(max(spacing, 0), 1)
        let gap = spacing * 0.05 * short
        // Cards, prints and strips never touch the canvas edge.
        let margin = style.hasCards || style == .filmStrip ? max(gap, 0.035 * short) : gap
        let bottom = caption ? max(margin, 0.085 * short) : margin
        let content = Box(x: margin, y: margin, w: aspect - 2 * margin, h: 1 - margin - bottom)
        let variants = style.variantCount(for: count)
        let variant = ((variant % variants) + variants) % variants
        let aspects = (0..<count).map { index in
            index < photoAspects.count && photoAspects[index] > 0 ? photoAspects[index] : 0.75
        }

        var builder = Builder(aspect: aspect, short: short, gap: gap, content: content)
        switch style {
        case .grid:
            let options = gridArrangements(count, in: content, gap: gap, aspects: aspects)
            builder.addFlat(options[min(variant, options.count - 1)])
        case .mosaic:
            builder.addFlat(mosaic(count, in: content, gap: gap, variant: variant, aspects: aspects))
        case .filmStrip:
            builder.addFilmStrips(count, variant: variant, aspects: aspects)
        case .polaroid:
            builder.addPolaroids(count, seed: seed(count, variant, salt: 3))
        case .scrapbook:
            builder.addScrapbook(count, aspects: aspects, seed: seed(count, variant, salt: 7))
        case .moodboard:
            builder.addMoodboard(count, variant: variant, aspects: aspects)
        }

        var layout = builder.layout
        if caption {
            let width = format.isCarousel ? aspect / Double(format.slides) : aspect
            layout.captionFrame = Box(x: margin, y: 1 - bottom, w: width - 2 * margin, h: bottom).normalized(aspect)
        }
        return layout
    }

    /// The photo under a point (0…1 canvas coordinates), topmost first,
    /// following each card's tilt.
    public func slotIndex(atX x: Double, y: Double, aspect: Double) -> Int? {
        let px = x * aspect
        for index in slots.indices.reversed() {
            let frame = slots[index].frame
            let angle = -slots[index].rotation * .pi / 180
            let dx = px - frame.midX * aspect
            let dy = y - frame.midY
            let localX = dx * cos(angle) - dy * sin(angle)
            let localY = dx * sin(angle) + dy * cos(angle)
            if abs(localX) <= frame.width * aspect / 2, abs(localY) <= frame.height / 2 {
                return index
            }
        }
        return nil
    }

    static func hasLShape(_ count: Int) -> Bool { count == 6 || count == 8 }

    private static func seed(_ count: Int, _ variant: Int, salt: UInt64) -> UInt64 {
        UInt64(truncatingIfNeeded: variant) &* 0x2545_F491_4F6C_DD1D &+ UInt64(truncatingIfNeeded: count) &* 0x9E37_79B9 &+ salt
    }
}

// MARK: - Arrangements

/// A rectangle in canvas units: the height is 1 and the width is the
/// canvas's aspect, so distances and rotations are the same on both axes.
struct Box: Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    var midX: Double { x + w / 2 }
    var midY: Double { y + h / 2 }

    func normalized(_ aspect: Double) -> CollageRect {
        CollageRect(x: x / aspect, y: y, width: w / aspect, height: h)
    }
}

extension CollageLayout {
    /// `count` items as evenly as possible over `lines`, the longer lines last.
    static func distribute(_ count: Int, into lines: Int) -> [Int] {
        let base = count / lines
        let extra = count % lines
        return (0..<lines).map { $0 < lines - extra ? base : base + 1 }
    }

    /// The share of a photo that survives cropping it to a cell.
    static func kept(photo: Double, cell: Double) -> Double {
        guard photo > 0, cell > 0 else { return 0 }
        return min(photo, cell) / max(photo, cell)
    }

    /// Rows (or, `transposed`, columns) of equal cells filling `box`.
    static func gridCells(_ plan: [Int], transposed: Bool, in box: Box, gap: Double) -> [Box] {
        let lines = Double(plan.count)
        var cells: [Box] = []
        if transposed {
            let lineWidth = (box.w - gap * (lines - 1)) / lines
            for (line, items) in plan.enumerated() {
                let cellHeight = (box.h - gap * Double(items - 1)) / Double(items)
                for item in 0..<items {
                    cells.append(Box(x: box.x + Double(line) * (lineWidth + gap), y: box.y + Double(item) * (cellHeight + gap),
                                     w: lineWidth, h: cellHeight))
                }
            }
        } else {
            let lineHeight = (box.h - gap * (lines - 1)) / lines
            for (line, items) in plan.enumerated() {
                let cellWidth = (box.w - gap * Double(items - 1)) / Double(items)
                for item in 0..<items {
                    cells.append(Box(x: box.x + Double(item) * (cellWidth + gap), y: box.y + Double(line) * (lineHeight + gap),
                                     w: cellWidth, h: lineHeight))
                }
            }
        }
        return cells
    }

    /// Every row and column plan for `count` photos, the one that crops the
    /// photos least first.
    static func gridArrangements(_ count: Int, in box: Box, gap: Double, aspects: [Double]) -> [[Box]] {
        var options: [(cells: [Box], score: Double)] = []
        for lines in 1...max(count, 1) {
            let plan = distribute(count, into: lines)
            for transposed in [false, true] {
                let cells = gridCells(plan, transposed: transposed, in: box, gap: gap)
                guard cells.allSatisfy({ $0.w > 0 && $0.h > 0 }), !options.contains(where: { $0.cells == cells }) else { continue }
                let share = cells.enumerated().reduce(0) { total, item in
                    total + kept(photo: aspects[item.offset], cell: item.element.w / item.element.h)
                } / Double(count)
                // Even lines (the 3 × 3 photo dump) win a near tie: they look tidier.
                options.append((cells, Set(plan).count == 1 ? share * 1.05 : share))
            }
        }
        // A stable sort: equal scores keep the simpler plan first.
        return options.enumerated()
            .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .map(\.element.cells)
    }

    /// The first photo large, the rest in a grid along the long side; for 6
    /// or 8 photos also an L of small ones around a big square.
    static func mosaic(_ count: Int, in box: Box, gap: Double, variant: Int, aspects: [Double]) -> [Box] {
        guard count > 1 else { return [box] }
        if variant == 2, hasLShape(count) {
            let side = count / 2
            let cellWidth = (box.w - gap * Double(side - 1)) / Double(side)
            let cellHeight = (box.h - gap * Double(side - 1)) / Double(side)
            let last = Double(side - 1)
            var cells = [Box(x: box.x, y: box.y, w: cellWidth * last + gap * (last - 1), h: cellHeight * last + gap * (last - 1))]
            for row in 0..<(side - 1) {
                cells.append(Box(x: box.x + last * (cellWidth + gap), y: box.y + Double(row) * (cellHeight + gap), w: cellWidth, h: cellHeight))
            }
            for column in 0..<side {
                cells.append(Box(x: box.x + Double(column) * (cellWidth + gap), y: box.y + last * (cellHeight + gap), w: cellWidth, h: cellHeight))
            }
            return cells
        }
        let heroFirst = variant == 0
        let share = count == 2 ? 0.62 : count <= 4 ? 0.6 : 0.56
        let hero: Box
        let rest: Box
        if box.w >= box.h {
            let heroWidth = (box.w - gap) * share
            let restWidth = box.w - gap - heroWidth
            hero = Box(x: heroFirst ? box.x : box.x + restWidth + gap, y: box.y, w: heroWidth, h: box.h)
            rest = Box(x: heroFirst ? box.x + heroWidth + gap : box.x, y: box.y, w: restWidth, h: box.h)
        } else {
            let heroHeight = (box.h - gap) * share
            let restHeight = box.h - gap - heroHeight
            hero = Box(x: box.x, y: heroFirst ? box.y : box.y + restHeight + gap, w: box.w, h: heroHeight)
            rest = Box(x: box.x, y: heroFirst ? box.y + heroHeight + gap : box.y, w: box.w, h: restHeight)
        }
        let others = gridArrangements(count - 1, in: rest, gap: gap, aspects: Array(aspects.dropFirst())).first ?? []
        return [hero] + others
    }
}

// MARK: - Builder

/// Collects slots, strips and decorations in canvas units, then normalizes.
private struct Builder {
    let aspect: Double
    let short: Double
    let gap: Double
    let content: Box
    var layout = CollageLayout.empty

    init(aspect: Double, short: Double, gap: Double, content: Box) {
        self.aspect = aspect
        self.short = short
        self.gap = gap
        self.content = content
    }

    mutating func addFlat(_ cells: [Box]) {
        for cell in cells {
            let rect = cell.normalized(aspect)
            layout.slots.append(CollageSlot(frame: rect, window: rect))
        }
    }

    // MARK: Film strips

    /// Frames on one to four strips: down a tall canvas, across a wide one
    /// (variant 1 turns them). Sizes are picked for the biggest frames.
    mutating func addFilmStrips(_ count: Int, variant: Int, aspects: [Double]) {
        let vertical = (content.w <= content.h * 1.1) != (variant == 1)
        let mainLength = (vertical ? content.h : content.w) * 0.94
        let crossLength = vertical ? content.w : content.h
        let average = aspects.reduce(0, +) / Double(max(aspects.count, 1))
        let frameAspect = min(max(average, 0.6), 1.6)
        // Frame cross size over main size.
        let rho = vertical ? frameAspect : 1 / frameAspect
        let frameShare = 0.76, inner = 0.07, endPad = 0.14
        let stripGap = max(gap, 0.04 * short)

        var best = (strips: 1, main: 0.0)
        for strips in 1...min(count, 4) {
            let perStrip = Int((Double(count) / Double(strips)).rounded(.up))
            let alongMain = mainLength / (Double(perStrip) + rho / frameShare * (inner * Double(perStrip - 1) + 2 * endPad))
            let alongCross = (crossLength - Double(strips - 1) * stripGap) / Double(strips) * frameShare / rho
            let main = min(alongMain, alongCross)
            if main > best.main * 1.0001 { best = (strips, main) }
        }

        let frameMain = best.main
        let frameCross = rho * frameMain
        let band = frameCross / frameShare
        let counts = Array(CollageLayout.distribute(count, into: best.strips).reversed())
        let total = Double(best.strips) * band + Double(best.strips - 1) * stripGap
        let crossStart = (vertical ? content.x : content.y) + (crossLength - total) / 2
        let tilts = vertical ? [-2.0, 1.6, -1.2, 2.0] : [-1.0, 0.8, -0.6, 1.0]

        for (strip, frames) in counts.enumerated() {
            let length = Double(frames) * frameMain + Double(frames - 1) * inner * band + 2 * endPad * band
            let mainStart = (vertical ? content.y : content.x) + ((vertical ? content.h : content.w) - length) / 2
            let cross = crossStart + Double(strip) * (band + stripGap)
            let stripBox = vertical
                ? Box(x: cross, y: mainStart, w: band, h: length)
                : Box(x: mainStart, y: cross, w: length, h: band)
            let tilt = tilts[strip % tilts.count]
            layout.strips.append(CollageStrip(frame: stripBox.normalized(aspect), rotation: tilt,
                                              holes: Self.sprocketHoles(band: band, length: length, vertical: vertical)))
            for index in 0..<frames {
                let along = mainStart + endPad * band + Double(index) * (frameMain + inner * band)
                let across = cross + (band - frameCross) / 2
                var frame = vertical
                    ? Box(x: across, y: along, w: frameCross, h: frameMain)
                    : Box(x: along, y: across, w: frameMain, h: frameCross)
                let center = Self.rotate(x: frame.midX, y: frame.midY, aroundX: stripBox.midX, y: stripBox.midY, degrees: tilt)
                frame.x = center.x - frame.w / 2
                frame.y = center.y - frame.h / 2
                let rect = frame.normalized(aspect)
                layout.slots.append(CollageSlot(frame: rect, window: rect, rotation: tilt))
            }
        }
    }

    /// 35 mm-style perforations down both edges, in 0…1 of the strip.
    static func sprocketHoles(band: Double, length: Double, vertical: Bool) -> [CollageRect] {
        let along = 0.075 * band, across = 0.05 * band, pitch = 0.13 * band, inset = 0.06 * band
        let count = max(1, Int((length - 0.12 * band) / pitch))
        let start = (length - Double(count - 1) * pitch) / 2
        var holes: [CollageRect] = []
        for index in 0..<count {
            let center = start + Double(index) * pitch
            for edge in [inset, band - inset] {
                holes.append(vertical
                    ? CollageRect(x: (edge - across / 2) / band, y: (center - along / 2) / length, width: across / band, height: along / length)
                    : CollageRect(x: (center - along / 2) / length, y: (edge - across / 2) / band, width: along / length, height: across / band))
            }
        }
        return holes
    }

    // MARK: Scattered prints

    /// Instant-camera prints (the instax mini's 54 × 86 mm card) on a
    /// jittered grid, each tilted a little the other way from its neighbour.
    mutating func addPolaroids(_ count: Int, seed: UInt64) {
        let cardAspect = 54.0 / 86.0
        var random = CollageRandom(seed: seed)
        let spots = scatter(count, cardAspects: Array(repeating: cardAspect, count: count), fill: 1.18 - 0.35 * gapShare,
                            jitter: 0.12, maxTilt: 9, random: &random)
        for spot in spots {
            let card = spot.box
            let window = Box(x: card.x + card.w * 0.074, y: card.y + card.h * 0.0756, w: card.w * 0.852, h: card.h * 0.7209)
            layout.slots.append(CollageSlot(frame: card.normalized(aspect), window: window.normalized(aspect), rotation: spot.rotation))
        }
    }

    /// Prints with a thin white border that keep each photo's shape, taped
    /// down, with a sticker on every other one.
    mutating func addScrapbook(_ count: Int, aspects: [Double], seed: UInt64) {
        var random = CollageRandom(seed: seed)
        let shapes = aspects.map { min(max($0, 0.65), 1.5) }
        let spots = scatter(count, cardAspects: shapes, fill: 1.02 - 0.3 * gapShare, jitter: 0.08, maxTilt: 5, random: &random)
        for (index, spot) in spots.enumerated() {
            let card = spot.box
            let border = 0.045 * min(card.w, card.h)
            let window = Box(x: card.x + border, y: card.y + border, w: card.w - 2 * border, h: card.h - 2 * border)
            layout.slots.append(CollageSlot(frame: card.normalized(aspect), window: window.normalized(aspect), rotation: spot.rotation))

            // Tape across the top edge, or over both top corners on every third print.
            let tapeTilt = (random.next() - 0.5) * 12
            if index % 3 == 2 {
                let width = 0.3 * card.w
                for side in [-1.0, 1.0] {
                    addDecoration(.tape(tone: index % 4), on: card, rotation: spot.rotation,
                                  local: (side * (card.w / 2 - 0.05 * card.w), -card.h / 2 + 0.05 * card.w),
                                  size: (width, width * 0.3), tilt: side * 40 + tapeTilt)
                }
            } else {
                let width = max(0.36 * card.w, 0.06 * short)
                addDecoration(.tape(tone: index % 4), on: card, rotation: spot.rotation,
                              local: (0, -card.h / 2), size: (width, width * 0.3), tilt: tapeTilt)
            }
            if index % 2 == 1 {
                let size = max(0.2 * min(card.w, card.h), 0.06 * short)
                let side = index % 4 == 1 ? 1.0 : -1.0
                addDecoration(.sticker((index / 2) % 6), on: card, rotation: spot.rotation,
                              local: (side * (card.w / 2 - size * 0.2), card.h / 2 - size * 0.25),
                              size: (size, size), tilt: (random.next() - 0.5) * 30)
            }
        }
    }

    /// Spacing as a 0…1 share again (the gap is spacing × 5% of the short edge).
    private var gapShare: Double { short > 0 ? min(gap / (0.05 * short), 1) : 0 }

    private struct Spot {
        var box: Box
        var rotation: Double
    }

    /// Cards on a jittered grid of rows, as big as the cells allow (`fill`
    /// above 1 lets neighbours overlap), kept on the canvas after tilting.
    private func scatter(_ count: Int, cardAspects: [Double], fill: Double, jitter: Double, maxTilt: Double,
                         random: inout CollageRandom) -> [Spot] {
        let typical = cardAspects.reduce(0, +) / Double(max(cardAspects.count, 1))
        var best = (rows: 1, area: 0.0)
        for rows in 1...count {
            let columns = Double(CollageLayout.distribute(count, into: rows).max() ?? 1)
            let height = min(content.h / Double(rows), content.w / columns / typical)
            let area = height * height * typical
            if area > best.area * 1.0001 { best = (rows, area) }
        }
        let plan = CollageLayout.distribute(count, into: best.rows)
        let cellHeight = content.h / Double(best.rows)
        let cellWidth = content.w / Double(plan.max() ?? 1)
        let edge = 0.012 * short

        var spots: [Spot] = []
        for (row, items) in plan.enumerated() {
            let rowStart = content.x + (content.w - Double(items) * cellWidth) / 2
            for item in 0..<items {
                let cardAspect = cardAspects[spots.count]
                var height = min(cellHeight, cellWidth / cardAspect) * fill
                var width = height * cardAspect
                let sign: Double = (row + item).isMultiple(of: 2) ? -1 : 1
                let tilt = sign * maxTilt * (0.35 + 0.65 * random.next())
                var centerX = rowStart + (Double(item) + 0.5) * cellWidth + (random.next() - 0.5) * 2 * jitter * cellWidth
                var centerY = content.y + (Double(row) + 0.5) * cellHeight + (random.next() - 0.5) * 2 * jitter * cellHeight
                // The tilted card's bounding box stays inside the content:
                // first shrunk to fit (one row on a wide carousel), then moved.
                let radians = tilt * .pi / 180
                let boundsX = width * abs(cos(radians)) + height * abs(sin(radians))
                let boundsY = width * abs(sin(radians)) + height * abs(cos(radians))
                let shrink = min(1, (content.w + 2 * edge) / boundsX, (content.h + 2 * edge) / boundsY)
                width *= shrink
                height *= shrink
                let halfX = boundsX * shrink / 2
                let halfY = boundsY * shrink / 2
                centerX = Self.clamp(centerX, content.x - edge + halfX, content.x + content.w + edge - halfX)
                centerY = Self.clamp(centerY, content.y - edge + halfY, content.y + content.h + edge - halfY)
                spots.append(Spot(box: Box(x: centerX - width / 2, y: centerY - height / 2, w: width, h: height), rotation: tilt))
            }
        }
        return spots
    }

    /// A decoration at `local` (from the card's centre, before its
    /// rotation), turned with the card plus its own `tilt`.
    private mutating func addDecoration(_ kind: CollageDecoration.Kind, on card: Box, rotation: Double,
                                        local: (x: Double, y: Double), size: (w: Double, h: Double), tilt: Double) {
        let center = Self.rotate(x: card.midX + local.x, y: card.midY + local.y, aroundX: card.midX, y: card.midY, degrees: rotation)
        let box = Box(x: center.x - size.w / 2, y: center.y - size.h / 2, w: size.w, h: size.h)
        layout.decorations.append(CollageDecoration(kind: kind, frame: box.normalized(aspect), rotation: rotation + tilt))
    }

    // MARK: Moodboard

    /// Masonry columns that each fill the height, plus a colour card with a
    /// dot sampled from each of the first five photos.
    mutating func addMoodboard(_ count: Int, variant: Int, aspects: [Double]) {
        let items = count + (count > 1 ? 1 : 0)
        let base = Int((Double(items) * content.w / content.h * 0.75).squareRoot().rounded())
        var columns = min(max(base, 2), max(items - 1, 1))
        if variant == 1 { columns = columns + 1 <= items - 1 ? columns + 1 : max(columns - 1, 1) }
        let columnWidth = (content.w - gap * Double(columns - 1)) / Double(columns)

        // Shortest column first, so the board fills evenly.
        var stacks = Array(repeating: [(item: Int, height: Double)](), count: columns)
        var heights = Array(repeating: 0.0, count: columns)
        for item in 0..<items {
            let shape = item < count ? min(max(aspects[item], 0.6), 1.5) : 1.7
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            stacks[column].append((item, columnWidth / shape))
            heights[column] += columnWidth / shape + gap
        }

        var boxes = Array(repeating: Box(x: 0, y: 0, w: 0, h: 0), count: items)
        for (column, stack) in stacks.enumerated() where !stack.isEmpty {
            let available = content.h - gap * Double(stack.count - 1)
            let scale = available / stack.reduce(0) { $0 + $1.height }
            var y = content.y
            for entry in stack {
                let height = entry.height * scale
                boxes[entry.item] = Box(x: content.x + Double(column) * (columnWidth + gap), y: y, w: columnWidth, h: height)
                y += height + gap
            }
        }
        addFlat(Array(boxes.prefix(count)))

        guard items > count, let palette = boxes.last else { return }
        layout.decorations.append(CollageDecoration(kind: .palette, frame: palette.normalized(aspect), rotation: 0))
        let dots = min(count, 5)
        let diameter = min(palette.h * 0.46, palette.w / (Double(dots) * 1.45))
        let spacing = (palette.w - Double(dots) * diameter) / Double(dots + 1)
        for dot in 0..<dots {
            let box = Box(x: palette.x + spacing + Double(dot) * (diameter + spacing), y: palette.midY - diameter / 2, w: diameter, h: diameter)
            layout.decorations.append(CollageDecoration(kind: .swatch(photo: dot), frame: box.normalized(aspect), rotation: 0))
        }
    }

    // MARK: Math

    /// Clockwise in a y-down space, like SwiftUI's and UIKit's rotations.
    static func rotate(x: Double, y: Double, aroundX cx: Double, y cy: Double, degrees: Double) -> (x: Double, y: Double) {
        let radians = degrees * .pi / 180
        let dx = x - cx, dy = y - cy
        return (cx + dx * cos(radians) - dy * sin(radians), cy + dx * sin(radians) + dy * cos(radians))
    }

    static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        low > high ? (low + high) / 2 : min(max(value, low), high)
    }
}

/// SplitMix64: the same scatter for the same photos and variant, so the
/// preview and the export always match.
struct CollageRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// 0 ..< 1.
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }
}

// MARK: - Pan and zoom inside a window

/// How a photo sits in its window: `zoom` 1 just covers the window (lower
/// shows more of the photo, down to all of it), and the offset of its centre
/// is a share of the window, so it survives layout and size changes.
public struct CollageCrop: Equatable, Sendable {
    public var zoom: Double
    public var offsetX: Double
    public var offsetY: Double

    public init(zoom: Double = 1, offsetX: Double = 0, offsetY: Double = 0) {
        self.zoom = zoom
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    public static let fill = CollageCrop()
    public static let maxZoom = 4.0

    /// The zoom at which the whole photo shows inside the window.
    public static func fitZoom(photoAspect: Double, windowAspect: Double) -> Double {
        guard photoAspect > 0, windowAspect > 0 else { return 1 }
        let ratio = photoAspect / windowAspect
        return min(ratio, 1 / ratio)
    }

    /// The photo's size at zoom 1, in window widths and heights.
    private static func coverSize(photoAspect: Double, windowAspect: Double) -> (width: Double, height: Double) {
        guard photoAspect > 0, windowAspect > 0 else { return (1, 1) }
        let ratio = photoAspect / windowAspect
        return ratio >= 1 ? (ratio, 1) : (1, 1 / ratio)
    }

    /// Within the zoom range, and never showing a gap along an axis where
    /// the photo is big enough to cover the window; centred where it isn't.
    public func clamped(photoAspect: Double, windowAspect: Double) -> CollageCrop {
        let zoom = min(max(self.zoom, Self.fitZoom(photoAspect: photoAspect, windowAspect: windowAspect)), Self.maxZoom)
        let cover = Self.coverSize(photoAspect: photoAspect, windowAspect: windowAspect)
        func limit(_ offset: Double, size: Double) -> Double {
            guard size > 1 else { return 0 }
            let reach = (size - 1) / 2
            return min(max(offset, -reach), reach)
        }
        return CollageCrop(zoom: zoom, offsetX: limit(offsetX, size: cover.width * zoom), offsetY: limit(offsetY, size: cover.height * zoom))
    }

    /// Where the photo goes, in 0…1 coordinates of its window; it may reach
    /// past the window's edges, which clip it.
    public func photoRect(photoAspect: Double, windowAspect: Double) -> CollageRect {
        let crop = clamped(photoAspect: photoAspect, windowAspect: windowAspect)
        let cover = Self.coverSize(photoAspect: photoAspect, windowAspect: windowAspect)
        let width = cover.width * crop.zoom, height = cover.height * crop.zoom
        return CollageRect(x: 0.5 + crop.offsetX - width / 2, y: 0.5 + crop.offsetY - height / 2, width: width, height: height)
    }

    /// After a drag of `dx`, `dy` (shares of the window's width and height).
    public func moved(dx: Double, dy: Double, photoAspect: Double, windowAspect: Double) -> CollageCrop {
        CollageCrop(zoom: zoom, offsetX: offsetX + dx, offsetY: offsetY + dy).clamped(photoAspect: photoAspect, windowAspect: windowAspect)
    }

    /// After a pinch: the photo point under the window's centre stays there.
    public func zoomed(by factor: Double, photoAspect: Double, windowAspect: Double) -> CollageCrop {
        let target = CollageCrop(zoom: zoom * factor).clamped(photoAspect: photoAspect, windowAspect: windowAspect).zoom
        let ratio = zoom > 0 ? target / zoom : 1
        return CollageCrop(zoom: target, offsetX: offsetX * ratio, offsetY: offsetY * ratio)
            .clamped(photoAspect: photoAspect, windowAspect: windowAspect)
    }

    /// Double-tap: the whole photo, or back to just covering the window.
    public func toggledFit(photoAspect: Double, windowAspect: Double) -> CollageCrop {
        let fit = Self.fitZoom(photoAspect: photoAspect, windowAspect: windowAspect)
        guard fit < 0.999 else { return .fill }
        return clamped(photoAspect: photoAspect, windowAspect: windowAspect).zoom > fit + 0.001 ? CollageCrop(zoom: fit) : .fill
    }
}

// MARK: - Provenance

extension Provenance {
    /// A collage of her own photos claims nothing, like any manual edit.
    /// Once a source already carries a marking, the collage is a composite:
    /// "with AI" when any source was made or changed by generative AI, and
    /// still fully AI-made when every one of them was.
    public static func collage(of sources: [DigitalSourceType?]) -> Provenance {
        let marked = sources.compactMap { $0 }
        guard !marked.isEmpty else { return .none }
        if marked.count == sources.count, marked.allSatisfy({ $0 == .trainedAlgorithmicMedia }) {
            return Provenance(inheritedSourceType: .trainedAlgorithmicMedia)
        }
        if marked.contains(where: \.isGenerative) {
            return Provenance(inheritedSourceType: .compositeWithTrainedAlgorithmicMedia)
        }
        return Provenance(inheritedSourceType: .composite)
    }
}
