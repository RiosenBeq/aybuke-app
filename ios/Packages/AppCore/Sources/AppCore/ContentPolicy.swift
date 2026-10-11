import Foundation

/// Lightweight client-side pre-check that rejects clearly disallowed requests
/// before they cost a network round-trip. It is NOT the safety system: the
/// backend runs provider safety checkers and moderation on every request.
public enum ContentPolicy {
    public enum Verdict: Equatable, Sendable {
        case allowed
        case blocked(reason: String)

        public var isAllowed: Bool { self == .allowed }
    }

    static let sexualTerms: Set<String> = [
        "nude", "nudes", "naked", "nsfw", "porn", "porno", "pornographic", "sex", "sexual", "sexy",
        "topless", "lingerie", "undress", "undressed", "undressing", "nudify", "nipple", "nipples",
        "genital", "genitals", "erotic", "hentai", "xxx", "onlyfans",
    ]

    static let minorTerms: Set<String> = [
        "child", "children", "kid", "kids", "minor", "minors", "teen", "teens", "teenager",
        "underage", "boy", "girl", "baby", "toddler", "schoolgirl", "schoolboy", "loli", "preteen",
    ]

    static let undressingPhrases: [String] = [
        "remove clothes", "remove her clothes", "remove his clothes", "remove their clothes",
        "take off clothes", "take off her clothes", "take off his clothes", "without clothes",
        "no clothes", "see through clothes", "x-ray clothes",
    ]

    public static func evaluate(_ prompt: String) -> Verdict {
        let lower = prompt.lowercased()
        let words = Set(lower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        let isSexual = !words.isDisjoint(with: sexualTerms) || undressingPhrases.contains { lower.contains($0) }
        guard isSexual else { return .allowed }
        if !words.isDisjoint(with: minorTerms) {
            return .blocked(reason: "This request violates our content policy and can't be created.")
        }
        return .blocked(reason: "Nudity and sexual content aren't allowed. Try a different idea.")
    }
}
