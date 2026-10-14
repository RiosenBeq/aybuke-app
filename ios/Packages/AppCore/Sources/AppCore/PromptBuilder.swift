import Foundation

public enum PromptBuilder {
    /// Her words, in characters.
    public static let maxPromptLength = 800
    /// The server's limit on the whole prompt, in code points after NFKC (MAX_PROMPT_CHARS in _shared/input.ts).
    public static let maxServerCodePoints = 1_200

    /// Trims, collapses whitespace, replaces control characters and cuts her
    /// words: to `maxPromptLength` characters, and to the code points that leave
    /// `reserving` more under the server's limit for a suffix added after.
    public static func sanitize(_ raw: String, reserving: Int = 0) -> String {
        var cut = normalized(raw)
        if cut.count > maxPromptLength { cut = String(cut.prefix(maxPromptLength)) }
        let room = max(0, maxServerCodePoints - reserving)
        if cut.unicodeScalars.count > room {
            cut = String(String.UnicodeScalarView(cut.unicodeScalars.prefix(room)))
        }
        return cut.trimmingCharacters(in: .whitespaces)
    }

    /// NFKC (as the server counts), control characters as spaces, whitespace collapsed. Never cuts.
    static func normalized(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.precomposedStringWithCompatibilityMapping.unicodeScalars {
            // Only C0/C1 controls (tabs, newlines, NUL…); keeps emoji joiners intact.
            scalars.append(scalar.properties.generalCategory == .control ? " " : scalar)
        }
        return String(scalars)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Final prompt for text-to-image: user idea + style descriptors.
    public static func textToImagePrompt(_ userPrompt: String, style: ImageStyle) -> String {
        // The style and its separator are sent too, so they count toward the server's limit.
        let reserve = style.promptSuffix.isEmpty ? 0 : style.promptSuffix.unicodeScalars.count + 2
        let base = sanitize(userPrompt, reserving: reserve)
        guard !style.promptSuffix.isEmpty else { return base }
        guard !base.isEmpty else { return style.promptSuffix }
        let separator = base.hasSuffix(".") || base.hasSuffix(",") ? " " : ", "
        return base + separator + style.promptSuffix
    }

    /// Appended to every Magic Edit, whatever the instruction says (the server
    /// appends it too). Scoped to faces, bodies and skin so makeup, outfit and
    /// art-style edits still work. Her words are cut to leave room for it under
    /// the server's `maxServerCodePoints`.
    public static let editGuard = " Keep everything else the same. Don't change anyone's face or body shape, facial features, skin tone, skin texture or age, and keep clothing at least as modest as in the photo."

    /// Instruction for prompt-based editing. Short commands like "sunset sky"
    /// are turned into an explicit instruction that also protects identity.
    public static func editInstruction(_ userInstruction: String) -> String {
        let guardText = editGuard.trimmingCharacters(in: .whitespaces)
        var text = normalized(userInstruction)
        // Already finished: kept whole, never cut.
        if text.hasSuffix(guardText) { return text }
        // "Only edit me" comes after her words, which onlyMainPerson cut already: keep it whole.
        let onlyMe = text.hasSuffix(onlyMainPersonSentence)
        if onlyMe { text = String(text.dropLast(onlyMainPersonSentence.count)).trimmingCharacters(in: .whitespaces) }
        let tail = onlyMe ? " " + onlyMainPersonSentence : ""
        let hers = sanitize(text, reserving: 1 + tail.unicodeScalars.count + editGuard.unicodeScalars.count)
        guard !hers.isEmpty else { return hers }
        let sentence = hers.hasSuffix(".") ? hers : hers + "."
        return sentence + tail + editGuard
    }

    /// "Only edit me" from the editor's kindness note: the edit leaves
    /// everyone else in the photo as they are. Her words are cut first; the
    /// sentence after them is never cut.
    public static func onlyMainPerson(_ instruction: String) -> String {
        let text = sanitize(instruction)
        guard !text.isEmpty else { return text }
        return text + (text.hasSuffix(".") ? " " : ". ") + onlyMainPersonSentence
    }

    private static let onlyMainPersonSentence = "Only change the main person in front; keep everyone else exactly as they are."

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
        "A cozy bookshop café with a sleepy cat on a stack of pastel books",
        "A tiny dragon sipping bubble tea at a lantern-lit night market",
        "A floating island with a pink waterfall and a little cottage at sunrise",
        "A whale swimming through the clouds above a sleepy seaside town",
        "A glass greenhouse full of glowing flowers under a starry sky",
        "A pastel space station with a flower garden and a view of Saturn",
        "A bunny astronaut planting carrots on the moon",
        "A snail with a tiny lantern exploring a mossy forest at night",
        "A vintage train winding through lavender fields at golden hour",
        "A treehouse with fairy lights and a rope bridge in a misty forest",
        "A koi pond with cherry petals and a little wooden bridge, seen from above",
        "An underwater tea party with jellyfish lanterns and seashell cups",
    ]

    public static func surprisePrompt<G: RandomNumberGenerator>(using generator: inout G) -> String {
        surprisePrompts.randomElement(using: &generator) ?? surprisePrompts[0]
    }

    public static func surprisePrompt() -> String {
        var generator = SystemRandomNumberGenerator()
        return surprisePrompt(using: &generator)
    }
}
