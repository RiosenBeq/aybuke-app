import Foundation

/// Output aspect ratios offered on the Create screen. The raw value is the wire
/// format sent to the backend.
public enum AspectRatio: String, Codable, CaseIterable, Sendable, Identifiable {
    case square = "1:1"
    case portrait = "3:4"
    case story = "9:16"
    case landscape = "4:3"
    case wide = "16:9"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .square: return "Square"
        case .portrait: return "Portrait"
        case .story: return "Story"
        case .landscape: return "Landscape"
        case .wide: return "Wide"
        }
    }

    public var widthOverHeight: Double {
        let parts = rawValue.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2, parts[1] > 0 else { return 1 }
        return parts[0] / parts[1]
    }

    /// Pixel size with the given long edge, rounded to a multiple of 64 as most
    /// diffusion models require.
    public func pixelSize(longEdge: Int = 1536) -> PixelSize {
        let ratio = widthOverHeight
        let long = Double(longEdge)
        let width = ratio >= 1 ? long : long * ratio
        let height = ratio >= 1 ? long / ratio : long
        return PixelSize(width: Self.roundTo64(width), height: Self.roundTo64(height))
    }

    private static func roundTo64(_ value: Double) -> Int {
        max(64, Int((value / 64).rounded()) * 64)
    }
}

public struct PixelSize: Equatable, Hashable, Sendable, Codable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var longEdge: Int { max(width, height) }
}

public enum ImageSizing {
    /// Scales `size` down (never up) so its long edge is at most `maxLongEdge`,
    /// preserving the aspect ratio. Used before uploading photos.
    public static func fit(_ size: PixelSize, maxLongEdge: Int) -> PixelSize {
        guard size.width > 0, size.height > 0, maxLongEdge > 0 else { return size }
        guard size.longEdge > maxLongEdge else { return size }
        let scale = Double(maxLongEdge) / Double(size.longEdge)
        return PixelSize(
            width: max(1, Int((Double(size.width) * scale).rounded())),
            height: max(1, Int((Double(size.height) * scale).rounded()))
        )
    }
}
