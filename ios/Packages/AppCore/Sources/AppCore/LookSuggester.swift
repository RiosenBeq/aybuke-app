import Foundation

/// What the app saw in a photo on device (Vision), reduced to plain values so
/// the suggestion rules stay testable here.
public struct PhotoInsight: Equatable, Sendable {
    public var faceCount: Int
    /// Vision classification identifiers, lowercase English ("sky", "food").
    public var labels: [String]
    public var hasAnimal: Bool
    /// "cat" or "dog" when Vision recognised one.
    public var animalKind: String?
    public var isDark: Bool
    public var isPortraitOrientation: Bool

    public init(
        faceCount: Int = 0, labels: [String] = [], hasAnimal: Bool = false, animalKind: String? = nil,
        isDark: Bool = false, isPortraitOrientation: Bool = false
    ) {
        self.faceCount = faceCount
        self.labels = labels.map { $0.lowercased() }
        self.hasAnimal = hasAnimal
        self.animalKind = animalKind?.lowercased()
        self.isDark = isDark
        self.isPortraitOrientation = isPortraitOrientation
    }

    /// A stable number from what the photo shows, so photos of the same kind
    /// can lead with different ideas while one photo always gets the same.
    var variety: Int {
        // FNV-1a: stable across launches (String.hashValue isn't).
        let key = labels.sorted().joined(separator: ",") + "|\(faceCount)|\(animalKind ?? "")"
        let hash = key.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        return Int(hash % 1_000)
    }

    public var kind: PhotoKind {
        if faceCount >= 2 { return .group }
        if faceCount == 1 { return .selfie }
        if hasAnimal || matches(Self.animalWords) { return .pet }
        if matches(Self.foodWords) { return .food }
        if isDark && matches(Self.cityWords) { return .cityNight }
        if matches(Self.outdoorWords) { return .landscape }
        if matches(Self.indoorWords) { return .indoor }
        // Streets and buildings by day, without sky or nature in view.
        if matches(Self.cityWords) { return .city }
        return .other
    }

    /// True when a label, or one of its underscore-separated words
    /// ("water_body" → "water"), is in `words`.
    private func matches(_ words: Set<String>) -> Bool {
        labels.contains { label in
            words.contains(label) || label.split(separator: "_").contains { words.contains(String($0)) }
        }
    }

    private static let animalWords: Set<String> = [
        "animal", "cat", "dog", "puppy", "kitten", "pet", "bird", "rabbit", "hamster", "horse", "canine", "feline",
    ]
    private static let foodWords: Set<String> = [
        "food", "dessert", "cake", "pizza", "fruit", "coffee", "drink", "beverage", "meal", "bread", "baked",
        "salad", "sushi", "pastry", "icecream", "breakfast", "cookie", "chocolate", "tea",
    ]
    private static let cityWords: Set<String> = [
        "city", "building", "street", "skyscraper", "cityscape", "road", "structure", "bridge", "urban",
    ]
    private static let outdoorWords: Set<String> = [
        "sky", "outdoor", "mountain", "beach", "ocean", "sea", "lake", "water", "tree", "forest", "field",
        "landscape", "cloud", "clouds", "grass", "flower", "snow", "sunset", "sunrise", "river", "park", "shore",
        "desert", "hill", "garden", "plant",
    ]
    private static let indoorWords: Set<String> = [
        "indoor", "room", "interior", "furniture", "bedroom", "kitchen", "table", "sofa", "couch", "bed", "desk",
        "shelf", "window", "wall",
    ]
}

/// The kind of photo, which decides the ideas offered for it.
public enum PhotoKind: String, CaseIterable, Sendable {
    case selfie, group, pet, landscape, city, cityNight, food, indoor, other

    /// People are in it: ideas never touch how anyone looks.
    public var hasPeople: Bool { self == .selfie || self == .group }
}

/// One idea for a photo in the editor.
public enum LookSuggestion: Hashable, Sendable {
    /// A free on-device effect, by the app's effect id.
    case effect(String)
    /// A one-tap look from `TemplateCatalog`, by id.
    case template(String)
    /// A Magic Edit request in English; show it with `L10n.core(_:)`.
    case magicEdit(prompt: String)
}

/// Picks up to four ideas that fit a photo: a free effect first (it applies
/// instantly, offline and without credits), then a look, a Magic Edit idea
/// and a second effect. Deterministic for the same input, so "Surprise me"
/// moves through them with `rotation` instead of randomness. Which free look
/// and which Magic Edit idea lead also follows what the photo shows
/// (`PhotoInsight.variety`), so different photos get different ones.
///
/// Ideas for photos with people only change hair colour, backgrounds, light,
/// props, outfits for the season or the art style, never a face or body.
public enum LookSuggester {
    public static let maxSuggestions = 4

    public static func suggest(
        for insight: PhotoInsight,
        date: Date,
        calendar: Calendar = .current,
        catalog: [PhotoTemplate] = TemplateCatalog.all,
        freeEffects: [String],
        rotation: Int = 0
    ) -> [LookSuggestion] {
        let kind = insight.kind
        let theme = SeasonalTheme.current(on: date, calendar: calendar)

        let effects = rotated(effectIDs(for: kind, theme: theme).filter(freeEffects.contains), by: rotation)
        let templates = templateCandidates(
            for: kind, theme: theme, date: date, calendar: calendar, catalog: catalog, variety: insight.variety
        )
        let ideas = magicEditIdeas(for: kind, theme: theme, offset: insight.variety + rotation)

        var result: [LookSuggestion] = []
        if let effect = effects.first { result.append(.effect(effect)) }
        if let template = templates.first { result.append(.template(template.id)) }
        if let idea = ideas.first { result.append(.magicEdit(prompt: idea)) }
        if effects.count > 1 { result.append(.effect(effects[1])) }
        return Array(result.prefix(maxSuggestions))
    }

    /// Every Magic Edit idea the suggester can return (for tests and checks).
    public static var allMagicEditIdeas: [String] {
        var all: [String] = []
        for kind in PhotoKind.allCases {
            for theme in [nil] + SeasonalTheme.allCases.map(Optional.some) {
                for idea in magicEditIdeas(for: kind, theme: theme) where !all.contains(idea) {
                    all.append(idea)
                }
            }
        }
        return all
    }

    // MARK: Rules

    /// Effect ids by kind. Glamour '92 is left out: a soft-focus portrait
    /// filter is too close to beauty retouching to suggest unasked. Tiny
    /// World's tilt-shift turns streets and wide views into a model, so it
    /// leads for cities by day and follows for landscapes and nights out.
    static func effectIDs(for kind: PhotoKind, theme: SeasonalTheme?) -> [String] {
        var ids: [String]
        switch kind {
        case .selfie: ids = ["digicam", "instant", "disposable", "kira"]
        case .group: ids = ["disposable", "instant", "throwback16", "camcorder06"]
        case .pet: ids = ["instant", "kira", "throwback16", "disposable"]
        case .landscape: ids = ["filmStill", "tinyWorld", "instant", "vhs"]
        case .city: ids = ["tinyWorld", "disposable", "filmStill", "throwback16"]
        case .cityNight: ids = ["neon", "filmStill", "tinyWorld", "vhs"]
        case .food: ids = ["instant", "disposable", "throwback16", "filmStill"]
        case .indoor: ids = ["camcorder06", "digicam", "vhs", "instant"]
        case .other: ids = ["instant", "digicam", "vhs", "kira"]
        }
        // A VHS tape feels like a horror-movie night in spooky season.
        if theme == .halloween, kind != .food, let index = ids.firstIndex(of: "vhs") {
            ids.remove(at: index)
            ids.insert("vhs", at: 1)
        }
        return ids
    }

    /// Looks that fit the kind: in-season seasonal looks first (people only),
    /// then free looks (turned by `variety`), then Pro ones, so a locked look
    /// never leads.
    static func templateCandidates(
        for kind: PhotoKind, theme: SeasonalTheme?, date: Date, calendar: Calendar, catalog: [PhotoTemplate],
        variety: Int = 0
    ) -> [PhotoTemplate] {
        let preferred: [String]
        switch kind {
        case .selfie:
            preferred = ["y2k", "polaroid", "pink-hair", "anime-film", "golden-glow", "80s-studio", "watercolor",
                         "soft-film", "sticker-sheet", "manga"]
        case .group: preferred = ["polaroid", "y2k", "birthday", "disco-79", "anime-film", "bracelet-club"]
        case .pet: preferred = ["royal-pet", "pet-astronaut", "pet-figurine", "pet-party", "pet-studio", "plushie-pet"]
        case .landscape: preferred = ["golden-sky", "watercolor", "anime-film", "oil-painting"]
        case .city: preferred = ["golden-sky", "anime-film", "watercolor", "comic"]
        case .cityNight: preferred = ["anime-film", "comic", "neon-city"]
        case .food, .indoor: preferred = ["watercolor", "oil-painting", "anime-film", "comic"]
        case .other: preferred = ["watercolor", "anime-film", "comic"]
        }
        let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var candidates = preferred.compactMap { byID[$0] }
        if kind.hasPeople, let theme {
            let seasonal = catalog.filter { $0.season == theme && TemplateCatalog.isAvailable($0, on: date, calendar: calendar) }
            candidates = seasonal + candidates
        }
        // Stable: keeps the order above within free and within Pro. Free
        // in-season looks still lead; the year-round free ones take turns.
        let free = candidates.filter { !$0.isPro }
        return free.filter { $0.season != nil } + rotated(free.filter { $0.season == nil }, by: variety)
            + candidates.filter(\.isPro)
    }

    /// The kind's ideas, the season's first; `offset` turns the others.
    static func magicEditIdeas(for kind: PhotoKind, theme: SeasonalTheme?, offset: Int = 0) -> [String] {
        let base = rotated(baseIdeas(for: kind), by: offset)
        guard let theme, let seasonal = seasonalIdea(for: kind, theme: theme) else { return base }
        return [seasonal] + base
    }

    private static func baseIdeas(for kind: PhotoKind) -> [String] {
        switch kind {
        case .selfie:
            return [
                idea("Give me pastel pink hair"),
                idea("Add soft fairy lights behind me"),
                idea("Put me in a cherry blossom street"),
                idea("Turn it into a dreamy watercolor painting"),
                idea("Add a soft rainbow glow behind me"),
                idea("Give me a sparkly butterfly hair clip"),
                idea("Turn the background into a starry night sky"),
            ]
        case .group:
            return [
                idea("Add confetti and party lights around us"),
                idea("Turn the background into a sunset beach"),
                idea("Make it look like a retro film photo"),
                idea("Give us matching friendship bracelets"),
                idea("Turn the background into a pastel cloud sky"),
                idea("Add heart balloons and fairy lights around us"),
            ]
        case .pet:
            return [
                idea("Give my pet a tiny party hat"),
                idea("Put my pet on a cloud in a pink sky"),
                idea("Add a little bow tie and party balloons"),
                idea("Give my pet a tiny strawberry hat"),
                idea("Put my pet in a field of daisies"),
                idea("Turn it into a cute cartoon"),
            ]
        case .landscape:
            return [
                idea("Turn the sky into a golden-hour glow"),
                idea("Make it an aurora night with soft green lights"),
                idea("Add a rainbow and a few butterflies"),
                idea("Turn the sky into a pink sunset"),
                idea("Add hot-air balloons in the sky"),
                idea("Make it a starry night with a big full moon"),
            ]
        case .cityNight:
            return [
                idea("Add pink and blue neon reflections on the street"),
                idea("Add soft falling snow under the street lights"),
                idea("Turn it into an anime city at night"),
                idea("Add glowing paper lanterns above the street"),
                idea("Make it a starry night with a big full moon"),
            ]
        case .city:
            return [
                idea("Turn the sky into a golden-hour glow"),
                idea("Turn it into an anime city at night"),
                idea("Add a rainbow and a few butterflies"),
                idea("Add cherry blossom trees along the street"),
                idea("Turn the sky into a pink sunset"),
            ]
        case .food:
            return [
                idea("Turn it into a sunny picnic with a checked blanket"),
                idea("Add fresh flowers and soft morning light"),
                idea("Make it a cozy café table by the window"),
                idea("Add sparkles and a birthday candle"),
                idea("Turn it into a cozy storybook illustration"),
            ]
        case .indoor:
            return [
                idea("Add warm fairy lights around the room"),
                idea("Turn it into a cozy storybook illustration"),
                idea("Make it golden hour through the window"),
                idea("Add plants and soft morning light"),
                idea("Make it snow softly outside the window"),
            ]
        case .other:
            return [
                idea("Add sparkles and soft pastel light"),
                idea("Turn it into a dreamy watercolor painting"),
                idea("Make it look like a retro film photo"),
                idea("Turn it into a cute sticker with a white border"),
                idea("Add a dreamy pastel glow and tiny stars"),
            ]
        }
    }

    private static func seasonalIdea(for kind: PhotoKind, theme: SeasonalTheme) -> String? {
        switch (theme, kind) {
        case (.halloween, .selfie): return idea("Give me a cute witch hat and glowing pumpkins")
        case (.halloween, .group): return idea("Give us cute witch hats and glowing pumpkins")
        case (.halloween, .pet): return idea("Give my pet a tiny pumpkin costume")
        case (.halloween, .landscape), (.halloween, .city), (.halloween, .cityNight):
            return idea("Add a big harvest moon and glowing jack-o'-lanterns")
        case (.halloween, _): return idea("Add glowing pumpkins and candlelight")
        case (.winter, .selfie): return idea("Put me in a cozy knitted scarf with falling snow")
        case (.winter, .group): return idea("Give us matching cozy sweaters")
        case (.winter, .pet): return idea("Give my pet a tiny knitted scarf")
        case (.winter, _): return idea("Make it a snowy evening with warm lights")
        case (.galentines, .selfie), (.galentines, .group): return idea("Add floating pink hearts and a pastel sky")
        case (.galentines, .pet): return idea("Give my pet a tiny heart-shaped balloon")
        case (.galentines, _): return idea("Add floating pink hearts and soft pastel light")
        }
    }

    /// Marks English text for `scripts/export-core-strings.py`.
    private static func idea(_ english: String) -> String { english }

    private static func rotated<T>(_ items: [T], by rotation: Int) -> [T] {
        guard !items.isEmpty else { return items }
        let shift = ((rotation % items.count) + items.count) % items.count
        return Array(items[shift...] + items[..<shift])
    }
}
