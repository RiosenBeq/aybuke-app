import Foundation

/// Every AI capability the app offers. The raw value is the wire format shared
/// with the backend (`backend/supabase/functions/ai-image`).
public enum AIOperation: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Text prompt → brand-new image.
    case textToImage = "text_to_image"
    /// Photo + natural-language instruction → edited photo ("make the sky a sunset").
    case magicEdit = "magic_edit"
    /// Photo → sharper, upscaled, face-restored photo.
    case enhance
    /// Photo → subject cut-out with transparent background (runs on device).
    case removeBackground = "remove_background"
    /// Photo + brush mask → photo with the masked object removed.
    case eraseObject = "erase_object"
    /// Photo + one-tap template → restyled photo (figurine, anime, headshot…).
    case restyle

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .textToImage: return "Create"
        case .magicEdit: return "Magic Edit"
        case .enhance: return "Enhance"
        case .removeBackground: return "Remove BG"
        case .eraseObject: return "Erase"
        case .restyle: return "Styles"
        }
    }

    /// SF Symbol used across the UI.
    public var symbolName: String {
        switch self {
        case .textToImage: return "sparkles"
        case .magicEdit: return "wand.and.stars"
        case .enhance: return "wand.and.rays"
        case .removeBackground: return "scissors"
        case .eraseObject: return "eraser"
        case .restyle: return "theatermask.and.paintbrush"
        }
    }

    public var requiresSourceImage: Bool { self != .textToImage }

    public var requiresPrompt: Bool { self == .textToImage || self == .magicEdit }

    public var requiresMask: Bool { self == .eraseObject }

    /// On-device operations never leave the phone, so they need neither AI
    /// data-sharing consent nor credits.
    public var runsOnDevice: Bool { self == .removeBackground }

    /// IPTC digital-source-type URI to embed in exported files
    /// (EU AI Act Art. 50 machine-readable marking). Cloud "Enhance" uses a
    /// generative upscaler, so it counts as generative augmentation; the
    /// on-device cut-out doesn't change the content.
    public var digitalSourceType: DigitalSourceType {
        switch self {
        case .textToImage, .restyle: return .trainedAlgorithmicMedia
        case .magicEdit, .eraseObject, .enhance: return .compositeWithTrainedAlgorithmicMedia
        case .removeBackground: return .algorithmicallyEnhanced
        }
    }
}

/// Subset of the IPTC "Digital Source Type" NewsCodes vocabulary that applies
/// to this app's outputs. See https://cv.iptc.org/newscodes/digitalsourcetype/
public enum DigitalSourceType: String, Sendable, CaseIterable {
    case trainedAlgorithmicMedia
    case compositeWithTrainedAlgorithmicMedia
    /// Elements from several images put together without generative AI,
    /// such as a cut-out placed on another photo.
    case composite
    case algorithmicallyEnhanced

    public static let vocabularyBase = "http://cv.iptc.org/newscodes/digitalsourcetype/"

    public var uri: String { Self.vocabularyBase + rawValue }

    /// How much of the image generative AI made: after several steps, the
    /// highest one describes the photo.
    public var generativeRank: Int {
        switch self {
        case .trainedAlgorithmicMedia: return 4
        case .compositeWithTrainedAlgorithmicMedia: return 3
        case .composite: return 2
        case .algorithmicallyEnhanced: return 1
        }
    }

    /// The type that describes a photo made with both steps.
    public static func strongest(_ lhs: DigitalSourceType?, _ rhs: DigitalSourceType?) -> DigitalSourceType? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        return rhs.generativeRank > lhs.generativeRank ? rhs : lhs
    }
}
