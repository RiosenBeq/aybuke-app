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

    /// Instruction for prompt-based editing. Short commands like "sunset sky"
    /// are turned into an explicit instruction that also protects identity.
    public static func editInstruction(_ userInstruction: String) -> String {
        let text = sanitize(userInstruction)
        guard !text.isEmpty else { return text }
        let protectsIdentity = text.localizedCaseInsensitiveContains("face")
            || text.localizedCaseInsensitiveContains("identity")
        let suffix = protectsIdentity ? "" : " Keep everything else, including people's faces and identity, unchanged."
        let sentence = text.hasSuffix(".") ? text : text + "."
        return sentence + suffix
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
        "A cozy reading nook inside a giant teacup, autumn afternoon light",
        "A red fox astronaut floating above a neon city at night",
        "Tiny island with a lighthouse inside a glass bottle on a wooden desk",
        "Portrait of an elderly fisherman with a weathered smile, golden hour",
        "A futuristic sneaker made of glass and moss, product shot",
        "Paper-cut diorama of a mountain village during a snowfall",
        "A koi pond seen from above with floating lanterns, ink wash style",
        "Retro diner on Mars with astronauts eating pancakes",
        "A cathedral made of coral under a turquoise sea",
        "Corgi wearing a tiny raincoat in a rainy Tokyo alley",
        "Minimalist poster of a hot-air balloon over lavender fields",
        "Steampunk owl made of brass gears, macro photo",
    ]

    public static func surprisePrompt<G: RandomNumberGenerator>(using generator: inout G) -> String {
        surprisePrompts.randomElement(using: &generator) ?? surprisePrompts[0]
    }

    public static func surprisePrompt() -> String {
        var generator = SystemRandomNumberGenerator()
        return surprisePrompt(using: &generator)
    }
}
