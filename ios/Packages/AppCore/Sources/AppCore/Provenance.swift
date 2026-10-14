import Foundation

/// Where an image's pixels came from, which decides every export marking:
/// the IPTC DigitalSourceType, the free-tier mark, the AI hashtags and the
/// visible "AI-edited" label. Re-edits carry it along, so editing an AI
/// result never strips its marking (EU AI Act Art. 50(2)).
public struct Provenance: Equatable, Sendable {
    /// The strongest Glowlit AI operation applied, cloud or on-device.
    public var operation: AIOperation?
    /// The marking the source already had: an imported file's XMP, or an
    /// Image Playground picture. Kept as is rather than rewritten.
    public var inheritedSourceType: DigitalSourceType?

    public init(operation: AIOperation? = nil, inheritedSourceType: DigitalSourceType? = nil) {
        self.operation = operation
        self.inheritedSourceType = inheritedSourceType
    }

    public static let none = Provenance()

    /// What to write as Iptc4xmpExt:DigitalSourceType; `nil` claims no AI.
    public var sourceType: DigitalSourceType? {
        DigitalSourceType.strongest(operation?.digitalSourceType, inheritedSourceType)
    }

    /// Glowlit's cloud models made or changed the pixels.
    public var usesGlowlitCloudAI: Bool { operation.map { !$0.runsOnDevice } ?? false }

    /// Generative AI made or changed the picture, so the AI hashtags, the
    /// "AI-edited" label and the "invisible tag" note apply. An on-device
    /// cut-out alone doesn't count.
    public var carriesAIProvenance: Bool { sourceType?.isGenerative ?? false }

    /// The free-tier mark is only for Glowlit's own cloud results. Images
    /// marked only by their source weren't made here (or, when they were,
    /// already have the mark in their pixels).
    public func showsMark(isPro: Bool) -> Bool { !isPro && usesGlowlitCloudAI }

    /// "Made with AI" rather than "AI-edited" on the visible label.
    public var isFullyGenerated: Bool {
        operation == .textToImage || (operation == nil && inheritedSourceType == .trainedAlgorithmicMedia)
    }
}

extension DigitalSourceType {
    /// Parses an IPTC value: the full NewsCodes URI or the bare term.
    /// Unknown values (a camera's `digitalCapture`, say) give `nil`.
    public init?(uri: String) {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        let term = trimmed.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? trimmed
        self.init(rawValue: term)
    }

    /// Higher means more of the picture was generated.
    public var rank: Int {
        switch self {
        case .trainedAlgorithmicMedia: return 3
        case .compositeWithTrainedAlgorithmicMedia: return 2
        case .algorithmicallyEnhanced: return 1
        }
    }

    /// Generative AI was involved (not just an algorithmic enhancement).
    public var isGenerative: Bool { self != .algorithmicallyEnhanced }

    public static func strongest(_ lhs: DigitalSourceType?, _ rhs: DigitalSourceType?) -> DigitalSourceType? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        return rhs.rank >= lhs.rank ? rhs : lhs
    }
}

extension AIOperation {
    /// The operation that marks a picture most strongly, so a later light
    /// edit never downgrades the label.
    public static func stronger(_ lhs: AIOperation?, _ rhs: AIOperation) -> AIOperation {
        guard let lhs else { return rhs }
        return rhs.digitalSourceType.rank >= lhs.digitalSourceType.rank ? rhs : lhs
    }
}
