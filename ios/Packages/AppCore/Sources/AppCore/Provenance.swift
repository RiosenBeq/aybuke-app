import Foundation

/// Where an image's pixels came from, which decides every export marking:
/// the IPTC DigitalSourceType, the free-tier mark, the AI hashtags and the
/// visible "AI-edited" label. Re-edits carry it along, so editing an AI
/// result never strips its marking (EU AI Act Art. 50(2)).
public struct Provenance: Equatable, Sendable {
    /// The strongest Aybuke AI operation applied, cloud or on-device.
    public var operation: AIOperation?
    /// The marking the source already had: an imported file's XMP, or an
    /// Image Playground picture. Kept as is rather than rewritten.
    public var inheritedSourceType: DigitalSourceType?
    /// A cut-out was placed on another photo in this edit (IPTC "composite").
    public var isComposite: Bool

    public init(operation: AIOperation? = nil, inheritedSourceType: DigitalSourceType? = nil, isComposite: Bool = false) {
        self.operation = operation
        self.inheritedSourceType = inheritedSourceType
        self.isComposite = isComposite
    }

    public static let none = Provenance()

    /// What to write as Iptc4xmpExt:DigitalSourceType; `nil` claims no AI.
    public var sourceType: DigitalSourceType? {
        DigitalSourceType.strongest(
            DigitalSourceType.strongest(operation?.digitalSourceType, inheritedSourceType),
            isComposite ? .composite : nil
        )
    }

    /// What a Library copy keeps as its inherited marking: the source's own
    /// plus a composite made here, which `operation` alone can't express.
    public var storedSourceType: DigitalSourceType? {
        DigitalSourceType.strongest(inheritedSourceType, isComposite ? .composite : nil)
    }

    /// Aybuke's cloud models made or changed the pixels.
    public var usesGlowlitCloudAI: Bool { operation.map { !$0.runsOnDevice } ?? false }

    /// Generative AI made or changed the picture, so the AI hashtags, the
    /// "AI-edited" label and the "invisible tag" note apply. An on-device
    /// cut-out alone, or one placed on another photo, doesn't count.
    public var carriesAIProvenance: Bool { sourceType?.isGenerative ?? false }

    /// The free-tier mark is only for Aybuke's own cloud results. Images
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

    /// Generative AI was involved (not just an algorithmic enhancement or a
    /// composite of her own photos).
    public var isGenerative: Bool {
        self == .trainedAlgorithmicMedia || self == .compositeWithTrainedAlgorithmicMedia
    }
}

extension AIOperation {
    /// The operation that marks a picture most strongly, so a later light
    /// edit never downgrades the label.
    public static func stronger(_ lhs: AIOperation?, _ rhs: AIOperation) -> AIOperation {
        guard let lhs else { return rhs }
        return rhs.digitalSourceType.generativeRank >= lhs.digitalSourceType.generativeRank ? rhs : lhs
    }
}
