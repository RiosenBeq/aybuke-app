import Foundation

public enum PromptBuilder {
    public static let maxPromptLength = 800

    /// Trims, collapses whitespace, replaces control characters and truncates.
    public static func sanitize(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            // Only C0/C1 controls (tabs, newlines, NUL…); keeps emoji joiners intact.
            scalars.append(scalar.properties.generalCategory == .control ? " " : scalar)
        }
        let collapsed = String(scalars)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > maxPromptLength else { return collapsed }
        return String(collapsed.prefix(maxPromptLength)).trimmingCharacters(in: .whitespaces)
    }

    /// Final prompt for text-to-image: user idea + style descriptors.
    public static func textToImagePrompt(_ userPrompt: String, style: ImageStyle) -> String {
        let base = sanitize(userPrompt)
        guard !style.promptSuffix.isEmpty else { return base }
        guard !base.isEmpty else { return style.promptSuffix }
        let separator = base.hasSuffix(".") || base.hasSuffix(",") ? " " : ", "
        return base + separator + style.promptSuffix
    }

    /// Appended to every Magic Edit, whatever the instruction says (the server
    /// appends it too). Scoped to faces, bodies and skin so makeup, outfit and
    /// art-style edits still work. 800 + 1 + its length must stay within the
    /// server's 1,000-character limit.
    public static let editGuard = " Keep everything else the same. Don't change anyone's face or body shape, facial features, skin tone, skin texture or age, and keep clothing at least as modest as in the photo."

    /// Instruction for prompt-based editing. Short commands like "sunset sky"
    /// are turned into an explicit instruction that also protects identity.
    public static func editInstruction(_ userInstruction: String) -> String {
        let text = sanitize(userInstruction)
        guard !text.isEmpty else { return text }
        if text.hasSuffix(editGuard.trimmingCharacters(in: .whitespaces)) { return text }
        let sentence = text.hasSuffix(".") ? text : text + "."
        return sentence + editGuard
    }

    /// Offline "magic prompt": enriches very short prompts with composition and
    /// quality cues. The server may further improve it with an LLM.
    public static func enhance(_ prompt: String) -> String {
        let text = sanitize(prompt)
        guard !text.isEmpty else { return text }
        let wordCount = text.split(separator: " ").count
        guard wordCount < 12 else { return text }
        let cues = ["highly detailed", "beautiful composition", "soft natural lighting", "rich colors"]
        let missing = cues.filter { !text.localizedCaseInsensitiveContains($0) }
        guard !missing.isEmpty else { return text }
        return text + ", " + missing.joined(separator: ", ")
    }

    /// Ideas for the "Surprise me" button.
    public static let surprisePrompts: [String] = [
        "A dreamy pastel bedroom with a canopy bed, fairy lights and a window seat at sunset",
        "A cat wearing a tiny strawberry hat in a field of pink tulips",
        "A cozy Parisian café at sunrise, painted in soft watercolor",
        "A unicorn made of cotton-candy clouds above a glittering lake",
        "A bakery window full of pink macarons and heart-shaped cupcakes",
        "A tiny fairy house inside a teacup with glowing mushrooms",
        "A vintage pink convertible parked by the sea at golden hour",
        "A cherry blossom street in Kyoto in the rain, soft reflections",
        "A reading nook full of plants and pastel books, cozy afternoon light",
        "A corgi wearing a pink raincoat in a rainy Tokyo alley",
        "A minimalist poster of a hot-air balloon over lavender fields",
        "A pastel macaron tower on a marble table, product shot",
    ]

    public static func surprisePrompt<G: RandomNumberGenerator>(using generator: inout G) -> String {
        surprisePrompts.randomElement(using: &generator) ?? surprisePrompts[0]
    }

    public static func surprisePrompt() -> String {
        var generator = SystemRandomNumberGenerator()
        return surprisePrompt(using: &generator)
    }
}
