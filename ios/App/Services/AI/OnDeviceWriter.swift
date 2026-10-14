import Foundation
import Observation
import AppCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Short creative text from Apple's on-device language model (Apple
/// Intelligence, iOS 26+). Nothing leaves the device, so it needs no consent
/// and no credits, and it works while the backend is offline.
///
/// Owned by `AppModel` (`app.writer`). The API is deliberately small:
/// - `isAvailable`: the model can answer in the app's language right now.
///   Hide model-only controls when it's false.
/// - `enhance(prompt:style:)`: one richer image prompt, or `nil`.
/// - `ideas(_:count:)`: up to three model ideas, or `[]`. Fall back to
///   `CuratedIdeas.for(_:)` when it's empty.
/// - `prewarm()`: call when a screen that will use the writer appears.
///
/// Calls never throw: errors, guardrail refusals, unsupported languages and
/// the 8-second timeout all come back as `nil` / `[]`, and every line passes
/// `ContentPolicy` before it's returned.
@MainActor
@Observable
final class OnDeviceWriter {
    enum IdeaContext: Equatable {
        /// Ideas for Create's prompt field.
        case create(season: Season)
        /// Edit instructions for a photo; `labels` are what's in it ("cat", "beach").
        case magicEdit(labels: [String], peopleCount: Int)
        /// Share captions; `look` is the template name when there is one.
        case caption(look: String?, madeWithAI: Bool)
    }

    private(set) var isAvailable = false
    /// Held between `prewarm()` and the next request (a `LanguageModelSession`;
    /// stored untyped because the type only exists on iOS 26).
    @ObservationIgnored private var warmSession: AnyObject?

    private static let timeout: Duration = .seconds(8)

    init() {
        refreshAvailability()
    }

    /// Availability changes while the model downloads or when Apple
    /// Intelligence is turned on, so screens refresh it when they appear.
    func refreshAvailability() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            isAvailable = model.availability == .available && model.supportsLocale(Locale.current)
            return
        }
        #endif
        isAvailable = false
    }

    func prewarm() {
        refreshAvailability()
        guard isAvailable, warmSession == nil else { return }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = Self.makeSession()
            session.prewarm()
            warmSession = session
        }
        #endif
    }

    /// Rewrites a short Create prompt into one vivid image prompt (≤ 50 words)
    /// in the prompt's own language. `nil` when the model can't help.
    func enhance(prompt: String, style: ImageStyle?) async -> String? {
        let idea = PromptBuilder.sanitize(prompt)
        guard isAvailable, !idea.isEmpty, ContentPolicy.evaluate(idea) == .allowed else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            var request = """
            Rewrite this image idea as one vivid image prompt of at most 50 words, \
            in the same language as the idea. Keep her idea; add a setting, light, \
            colours, composition and mood.
            """
            if let style, style != StyleCatalog.auto {
                request += " The picture's style is \(style.name)."
            }
            request += "\nIdea: \(idea)"
            guard let output = await respond(request, generating: EnhancedPrompt.self) else { return nil }
            return Self.screened([output.prompt]).first
        }
        #endif
        return nil
    }

    /// Up to three fresh ideas (fewer when some fail the content check), or
    /// `[]` when the model is unavailable or fails.
    func ideas(_ context: IdeaContext, count: Int = 3) async -> [String] {
        guard isAvailable, count > 0 else { return [] }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard let output = await respond(Self.request(for: context), generating: Ideas.self) else { return [] }
            return Array(Self.screened(output.items).prefix(count))
        }
        #endif
        return []
    }

    // MARK: Model

    private static func request(for context: IdeaContext) -> String {
        switch context {
        case .create(let season):
            return """
            Suggest 3 different, fun ideas for a picture she could create, fitting \(season.rawValue) \
            (or any time of year). One sentence each, under 20 words, with a place, light and colours.
            """
        case .magicEdit(let labels, let peopleCount):
            let contents = labels.isEmpty ? "unknown" : labels.prefix(8).joined(separator: ", ")
            return """
            Her photo shows: \(contents). People in it: \(peopleCount). Suggest 3 playful edits she \
            could ask for, written as short requests (under 12 words), like "Turn the sky into a pink \
            sunset". Change only backgrounds, light, colours, hair colour, outfits, props or art style.
            """
        case .caption(let look, let madeWithAI):
            var text = "Suggest 3 short, warm captions (under 12 words, one emoji at most) for sharing a picture."
            if let look { text += " The picture uses the look \"\(look)\"." }
            if madeWithAI { text += " It was made with AI." }
            text += " Talk about the mood, the moment or the colours, never about how anyone looks."
            return text
        }
    }

    /// Keeps lines that are non-empty, short enough and allowed by the policy.
    private static func screened(_ lines: [String]) -> [String] {
        lines
            .map { PromptBuilder.sanitize($0.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”«»"))) }
            .filter { !$0.isEmpty && $0.count <= 400 && ContentPolicy.evaluate($0) == .allowed }
    }

    /// The writer's rules, in English; it answers in the app's language.
    private static var instructions: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        let language = Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
        return """
        You are the creative helper in Glowlit, a photo and art app for girls and young women aged 13 and up. \
        Be playful, kind and age-appropriate. Write in \(language) unless asked to keep the user's language.
        Focus on colours, light, backgrounds, seasons, everyday, cozy or costume outfits, props, pets, \
        art styles and fun scenes.
        Never suggest changing a person's body, weight, face shape, skin tone or texture, age or \
        attractiveness, and never comment on how anyone looks.
        Never mention revealing clothes, real celebrities or public figures, violence, mean jokes, \
        alcohol, drugs or dating.
        """
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func makeSession() -> LanguageModelSession {
        LanguageModelSession(instructions: instructions)
    }

    /// One guided request with a timeout. Any error (guardrails, language,
    /// cancellation, timeout) becomes `nil`.
    @available(iOS 26.0, *)
    private func respond<Content: Generable>(_ prompt: String, generating type: Content.Type) async -> Content? {
        // A fresh session per request keeps earlier answers out of the context.
        let session = (warmSession as? LanguageModelSession) ?? Self.makeSession()
        warmSession = nil
        // Race the model against the clock: whichever finishes first answers.
        // (Don't rely on cancellation; the model may not stop promptly.)
        return await withCheckedContinuation { continuation in
            let answer = Answer()
            let work = Task { @MainActor in
                let content = try? await session.respond(to: prompt, generating: type, options: GenerationOptions(temperature: 0.9)).content
                if answer.claim() { continuation.resume(returning: content) }
            }
            Task { @MainActor in
                try? await Task.sleep(for: Self.timeout)
                if answer.claim() {
                    work.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    #endif
}

/// Lets exactly one of two racing tasks resume a continuation.
@MainActor
private final class Answer {
    private var isClaimed = false

    func claim() -> Bool {
        defer { isClaimed = true }
        return !isClaimed
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct EnhancedPrompt {
    @Guide(description: "One vivid, family-friendly image prompt of at most 50 words, in the same language as the idea")
    var prompt: String
}

@available(iOS 26.0, *)
@Generable
private struct Ideas {
    @Guide(description: "Three different, family-friendly suggestions", .count(3))
    var items: [String]
}
#endif

extension Season {
    /// Today's season where she is.
    static var current: Season {
        Season.of(Date(), southernHemisphere: Season.southernRegions.contains(Locale.current.region?.identifier ?? ""))
    }
}

/// Hand-written ideas for when the on-device model isn't available (most
/// devices, the simulator, unsupported languages).
enum CuratedIdeas {
    static func `for`(_ context: OnDeviceWriter.IdeaContext) -> [String] {
        switch context {
        case .create(let season):
            return seasonal(season) + PromptBuilder.surprisePrompts.map { L10n.core($0) }
        case .magicEdit(let labels, let peopleCount):
            let pets: Set<String> = ["cat", "dog", "pet", "animal", "puppy", "kitten", "bird", "rabbit"]
            if labels.contains(where: { pets.contains($0.lowercased()) }) { return petEdits }
            if peopleCount > 1 { return groupEdits }
            if peopleCount == 1 { return portraitEdits }
            return sceneEdits
        case .caption(_, let madeWithAI):
            return madeWithAI ? captions + [aiCaption] : captions
        }
    }

    private static func seasonal(_ season: Season) -> [String] {
        switch season {
        case .autumn:
            return [
                String(localized: "A cozy pumpkin patch at golden hour with fairy lights and a plaid blanket", comment: "Autumn idea for creating an image"),
                String(localized: "A cute ghost reading a book in a candle-lit library", comment: "Autumn idea for creating an image"),
                String(localized: "A witch's kitchen full of pastel potions and sleepy black cats", comment: "Autumn idea for creating an image"),
                String(localized: "A rainy autumn street with orange leaves and a glowing café window", comment: "Autumn idea for creating an image"),
                String(localized: "A Halloween costume party for woodland animals, soft watercolor", comment: "Autumn idea for creating an image"),
                String(localized: "A mug of hot chocolate on a windowsill while leaves fall outside", comment: "Autumn idea for creating an image"),
            ]
        case .winter:
            return [
                String(localized: "A snowy cabin with warm windows and a pink sky at dusk", comment: "Winter idea for creating an image"),
                String(localized: "A gingerbread house village with tiny glowing windows", comment: "Winter idea for creating an image"),
                String(localized: "A polar bear cub ice-skating on a frozen pond under the northern lights", comment: "Winter idea for creating an image"),
                String(localized: "A cozy reading nook with a knitted blanket, fairy lights and falling snow outside", comment: "Winter idea for creating an image"),
                String(localized: "A winter market at night with lanterns, ribbons and steaming cocoa", comment: "Winter idea for creating an image"),
                String(localized: "A snow globe holding a tiny pastel city", comment: "Winter idea for creating an image"),
            ]
        case .spring:
            return [
                String(localized: "A bicycle with a basket of tulips on a canal bridge in spring", comment: "Spring idea for creating an image"),
                String(localized: "A garden tea party for bunnies under blooming cherry trees", comment: "Spring idea for creating an image"),
                String(localized: "A greenhouse full of butterflies and pastel flowers in morning light", comment: "Spring idea for creating an image"),
                String(localized: "A rainy spring day seen through a window with raindrops and a rainbow", comment: "Spring idea for creating an image"),
                String(localized: "A meadow picnic with strawberries, daisies and a striped blanket", comment: "Spring idea for creating an image"),
                String(localized: "A tiny hedgehog carrying a flower umbrella", comment: "Spring idea for creating an image"),
            ]
        case .summer:
            return [
                String(localized: "A pastel ice-cream truck on a beach boardwalk at sunset", comment: "Summer idea for creating an image"),
                String(localized: "A lemon grove by the sea with a striped parasol and a sketchbook", comment: "Summer idea for creating an image"),
                String(localized: "A turtle surfing a sparkly wave under a cotton-candy sky", comment: "Summer idea for creating an image"),
                String(localized: "A rooftop garden at night with string lights and fireflies", comment: "Summer idea for creating an image"),
                String(localized: "A watermelon-themed pool party for ducks, bright and playful", comment: "Summer idea for creating an image"),
                String(localized: "A camper van under the stars beside a calm lake", comment: "Summer idea for creating an image"),
            ]
        }
    }

    private static let portraitEdits = [
        String(localized: "Give me pastel pink hair", comment: "Example request for editing a photo of one person"),
        String(localized: "Put me in a cherry blossom street", comment: "Example request for editing a photo of one person"),
        String(localized: "Add soft fairy lights behind me", comment: "Example request for editing a photo of one person"),
        String(localized: "Turn it into a dreamy watercolor painting", comment: "Example request for editing a photo of one person"),
    ]

    private static let groupEdits = [
        String(localized: "Give us matching cozy sweaters", comment: "Example request for editing a photo of several people"),
        String(localized: "Turn the background into a sunset beach", comment: "Example request for editing a photo of several people"),
        String(localized: "Add confetti and party lights around us", comment: "Example request for editing a photo of several people"),
        String(localized: "Make it look like a retro film photo", comment: "Example request for editing a photo of several people"),
    ]

    private static let petEdits = [
        String(localized: "Give my pet a tiny strawberry hat", comment: "Example request for editing a photo of a pet"),
        String(localized: "Put my pet on a cloud in a pink sky", comment: "Example request for editing a photo of a pet"),
        String(localized: "Add a little bow tie and party balloons", comment: "Example request for editing a photo of a pet"),
        String(localized: "Turn it into a cute cartoon", comment: "Example request for editing a photo of a pet"),
    ]

    private static let sceneEdits = [
        String(localized: "Turn the sky into a pink sunset", comment: "Example request for editing a photo without people"),
        String(localized: "Make it a snowy evening with warm lights", comment: "Example request for editing a photo without people"),
        String(localized: "Add a rainbow and a few butterflies", comment: "Example request for editing a photo without people"),
        String(localized: "Turn it into a storybook illustration", comment: "Example request for editing a photo without people"),
    ]

    private static let captions = [
        String(localized: "Today's mood: pastel ✨", comment: "Caption idea for sharing a picture"),
        String(localized: "Saving this one for the memories", comment: "Caption idea for sharing a picture"),
        String(localized: "Small moments, big glow", comment: "Caption idea for sharing a picture"),
        String(localized: "Soft colours, happy heart", comment: "Caption idea for sharing a picture"),
        String(localized: "Plot twist: it's art now", comment: "Caption idea for sharing a picture"),
        String(localized: "A little magic for your feed", comment: "Caption idea for sharing a picture"),
        String(localized: "Weekend energy 🌸", comment: "Caption idea for sharing a picture"),
        String(localized: "Golden hour, every hour", comment: "Caption idea for sharing a picture"),
        String(localized: "New favourite, no notes", comment: "Caption idea for sharing a picture"),
        String(localized: "Colour me happy", comment: "Caption idea for sharing a picture"),
        String(localized: "Just a little daydream", comment: "Caption idea for sharing a picture"),
    ]

    /// Only offered when the picture really was made with AI.
    private static let aiCaption = String(localized: "Made this one with a little help from AI", comment: "Caption idea for sharing a picture made with AI")
}
