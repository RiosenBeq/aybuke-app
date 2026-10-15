import Foundation

// The share composer's sizes, backgrounds and editable text. The numbers
// live here so the layouts can be tested; `ShareRenderer` draws them.

/// Where she posts: a size for the Photo design and the Story card.
public enum ShareSize: String, CaseIterable, Identifiable, Sendable {
    /// The photo's own shape (Photo only).
    case original
    /// Instagram Stories and Reels, 9:16.
    case story
    /// An Instagram feed post, 4:5.
    case post
    case square
    /// 9:16, keeping clear of TikTok's buttons on the right and its caption.
    case tiktok
    /// X and other landscape feeds, 16:9.
    case wide
    /// Pinterest, 2:3.
    case pin

    public var id: String { rawValue }

    /// Pixels; nil for `original`.
    public var pixelSize: (width: Double, height: Double)? {
        switch self {
        case .original: return nil
        case .story, .tiktok: return (1080, 1920)
        case .post: return (1080, 1350)
        case .square: return (1080, 1080)
        case .wide: return (1600, 900)
        case .pin: return (1000, 1500)
        }
    }

    /// "9:16"; empty for `original`.
    public var ratio: String {
        switch self {
        case .original: return ""
        case .story, .tiktok: return "9:16"
        case .post: return "4:5"
        case .square: return "1:1"
        case .wide: return "16:9"
        case .pin: return "2:3"
        }
    }

    /// The edges the app's own buttons and captions cover, in pixels.
    public var safeInsets: ShareInsets {
        switch self {
        // Instagram keeps ~250 px at the top and bottom for its own UI.
        case .story: return ShareInsets(top: 250, left: 0, bottom: 250, right: 0)
        // TikTok: the tabs on top, the like and comment rail on the right,
        // the caption and sound at the bottom.
        case .tiktok: return ShareInsets(top: 160, left: 40, bottom: 420, right: 150)
        case .original, .post, .square, .wide, .pin: return ShareInsets()
        }
    }

    /// Sizes the Story card comes in (every one but the photo's own shape).
    public static let cardSizes: [ShareSize] = allCases.filter { $0 != .original }
}

public struct ShareInsets: Equatable, Sendable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

/// Behind the photo where a design has room around it.
public enum ShareBackdrop: Hashable, Sendable {
    /// The design's own brand gradient with soft glows.
    case glow
    /// Her photo, blurred.
    case blur
    case color(ShareSwatch)

    /// "glow", "blur" or a swatch name (DEBUG launch arguments).
    public init?(id: String) {
        switch id {
        case "glow": self = .glow
        case "blur": self = .blur
        default:
            guard let swatch = ShareSwatch(rawValue: id) else { return nil }
            self = .color(swatch)
        }
    }

    public static let all: [ShareBackdrop] = [.glow, .blur] + ShareSwatch.allCases.map { .color($0) }

    /// Light type reads better on it.
    public var isDark: Bool {
        if case .color(let swatch) = self { return swatch.isDark }
        return false
    }
}

/// Solid backgrounds: the Blush palette and the Aura accents.
public enum ShareSwatch: String, CaseIterable, Sendable {
    case petal, blush, butter, lilac, mint, white, ink

    public var hex: UInt32 {
        switch self {
        case .petal: return 0xF8E0EA
        case .blush: return 0xF7C1D9
        case .butter: return 0xFBE7A1
        case .lilac: return 0xD9C8F2
        case .mint: return 0xC9EDDC
        case .white: return 0xFFFFFF
        case .ink: return 0x121212
        }
    }

    public var isDark: Bool { self == .ink }
}

/// Text she can change on a design.
public enum ShareTextSlot: String, CaseIterable, Sendable {
    /// Her words under the photo on the Story card.
    case storyLine
    /// The Cover star's big title ("GLOW").
    case coverMasthead
    /// The Cover star's headline ("Main character energy").
    case coverHeadline
    /// Under the Photo strip's frames, in place of the date.
    case stripCaption

    public var maxLength: Int {
        switch self {
        case .storyLine: return 80
        case .coverMasthead: return 10
        case .coverHeadline: return 40
        case .stripCaption: return 24
        }
    }

    /// The headline may take two lines; everything else is one.
    public var allowsLineBreak: Bool { self == .coverHeadline }

    /// Trimmed, cut to the slot's length, one line (two for the headline).
    public func clean(_ text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !allowsLineBreak || lines.count > 2 {
            lines = allowsLineBreak ? [lines[0], lines.dropFirst().joined(separator: " ")] : [lines.joined(separator: " ")]
        }
        let joined = lines.joined(separator: "\n")
        return String(joined.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Where the Story card's parts go in any size: the brand line on top (free
/// cloud AI results), the photo, her words or the prompt under it, and the
/// "Made with" footer, all clear of the app's own buttons. At 9:16 for
/// Stories it's the card it has always been.
public struct StoryCardLayout: Equatable, Sendable {
    public var canvas: CanvasRect
    /// Pixels per point of the 1080-wide original.
    public var unit: Double
    /// The room for the photo; the photo is fitted inside and centred.
    public var photoArea: CanvasRect
    public var header: CanvasRect?
    public var footer: CanvasRect?
    /// Height kept under the photo for her words or the prompt (0 for none).
    public var captionHeight: Double

    public init(size: ShareSize, branded: Bool, hasCaption: Bool) {
        let pixels = size.pixelSize ?? ShareSize.story.pixelSize!
        let (width, height) = pixels
        let unit = min(width, height) / 1080
        let insets = size.safeInsets
        canvas = CanvasRect(x: 0, y: 0, width: width, height: height)
        self.unit = unit
        captionHeight = hasCaption ? 190 * unit : 0

        let header = CanvasRect(x: 0, y: max(insets.top - 100 * unit, 30 * unit), width: width, height: 90 * unit)
        let footerTop = height - max(insets.bottom + 50 * unit, 90 * unit)
        let footer = CanvasRect(x: 0, y: footerTop, width: width, height: 60 * unit)
        self.header = branded ? header : nil
        self.footer = branded ? footer : nil

        let top = max(insets.top + 50 * unit, branded ? header.maxY + 40 * unit : 80 * unit)
        let bottom = height - max(insets.bottom + 70 * unit, branded ? footer.height + 100 * unit : 80 * unit) - captionHeight
        let left = max(110 * unit, insets.left + 60 * unit)
        let right = max(110 * unit, insets.right + 60 * unit)
        photoArea = CanvasRect(x: left, y: top, width: max(width - left - right, 1), height: max(bottom - top, 1))
    }

    /// The photo, as large as fits, centred in its room.
    public func photoFrame(imageWidth: Double, imageHeight: Double) -> CanvasRect {
        ShareLayout.fit(width: imageWidth, height: imageHeight, in: photoArea)
    }

    /// Her words or the prompt, under the photo as placed.
    public func caption(under photo: CanvasRect) -> CanvasRect? {
        guard captionHeight > 0 else { return nil }
        return CanvasRect(x: 120 * unit, y: photo.maxY + 40 * unit, width: canvas.width - 240 * unit, height: captionHeight - 20 * unit)
    }
}

public enum ShareLayout {
    /// `width` × `height` as large as it fits in `box`, centred, whole.
    public static func fit(width: Double, height: Double, in box: CanvasRect) -> CanvasRect {
        guard width > 0, height > 0 else { return box }
        let scale = min(box.width / width, box.height / height)
        let size = (width: (width * scale).rounded(.down), height: (height * scale).rounded(.down))
        return CanvasRect(x: (box.midX - size.width / 2).rounded(), y: (box.midY - size.height / 2).rounded(),
                          width: size.width, height: size.height)
    }

    /// Whether the photo leaves room around it at this size, so a
    /// background shows (more than 1% apart in shape).
    public static func showsBackdrop(imageWidth: Double, imageHeight: Double, size: ShareSize) -> Bool {
        guard let pixels = size.pixelSize, imageWidth > 0, imageHeight > 0 else { return false }
        let ratio = (imageWidth / imageHeight) / (pixels.width / pixels.height)
        return abs(ratio - 1) > 0.01
    }

    /// Room kept at the bottom for the visible AI label, clear of the app's
    /// own buttons: a Story card's footer, or a padded photo's safe edge.
    public static func labelReserve(size: ShareSize, isCard: Bool) -> Double {
        let bottom = size.safeInsets.bottom
        guard isCard else { return bottom }
        let unit = (size.pixelSize.map { min($0.width, $0.height) } ?? 1080) / 1080
        return max(bottom + 50 * unit, 90 * unit)
    }

    /// 9:16, so Instagram takes it as the Story's background rather than a sticker.
    public static func isStoryShaped(width: Double, height: Double) -> Bool {
        guard width > 0, height > 0 else { return false }
        return abs(width / height - 9.0 / 16.0) < 0.01
    }
}
