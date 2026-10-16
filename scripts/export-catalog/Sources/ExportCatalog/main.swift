// Prints the template/style catalog as JSON for the backend.
// Usage: scripts/export-catalog.sh
import Foundation
import AppCore

struct Recipe: Encodable {
    let id: String
    let title: String
    let isPro: Bool
    let prompt: String
}

// `--policy` prints the prompt-policy terms instead (_shared/policy-terms.json).
if CommandLine.arguments.dropFirst().first == "--policy" {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let payload: [String: AnyEncodable] = [
        "_comment": AnyEncodable("Generated from ios/Packages/AppCore (ContentPolicy, PromptBuilder.editGuard). Do not edit by hand: run scripts/export-catalog.sh."),
        "editGuard": AnyEncodable(PromptBuilder.editGuard),
        "messages": AnyEncodable(ContentPolicy.exportedMessages),
        "terms": AnyEncodable(ContentPolicy.exportedTerms),
    ]
    print(String(data: try encoder.encode(payload), encoding: .utf8)!)
    exit(0)
}

// Makeup Studio's ids and English names, so the assist function can pick a
// look and choices for a described vibe and drop any id the app doesn't know.
struct MakeupOption: Encodable {
    let id: String
    let name: String
}

struct MakeupLook: Encodable {
    let id: String
    let name: String
    let lips: String
    let lipFinish: String
    let eyes: String
    let cheeks: String
    let extras: [String]
    let hair: String
    let intensity: String
}

struct MakeupExport: Encodable {
    let looks: [MakeupLook]
    let lips: [MakeupOption]
    /// Glossy, matte or shimmery, for a lip color (not "As is" or clear gloss).
    let lipFinish: [MakeupOption]
    let eyes: [MakeupOption]
    let cheeks: [MakeupOption]
    let extras: [MakeupOption]
    let hair: [MakeupOption]
    let intensity: [MakeupOption]
    /// The most extras a recipe holds.
    let maxExtras: Int
    /// The last sentence of every makeup request: the server leaves those requests as the catalog wrote them.
    let skinGuard: String
}

func options<C: MakeupChoice>(_ type: C.Type) -> [MakeupOption] where C.ID == String {
    C.allCases.map { MakeupOption(id: $0.id, name: $0.name) }
}

let makeup = MakeupExport(
    looks: MakeupStudio.presets.map { preset in
        MakeupLook(
            id: preset.id, name: preset.name,
            lips: preset.recipe.lips.id, lipFinish: preset.recipe.lipFinish.id,
            eyes: preset.recipe.eyes.id, cheeks: preset.recipe.cheeks.id,
            extras: MakeupExtra.allCases.filter(preset.recipe.extras.contains).map(\.id),
            hair: preset.recipe.hair.id, intensity: preset.recipe.intensity.id
        )
    },
    lips: options(MakeupLips.self),
    lipFinish: MakeupLipFinish.allCases.map { MakeupOption(id: $0.id, name: $0.name) },
    eyes: options(MakeupEyes.self),
    cheeks: options(MakeupCheeks.self),
    extras: options(MakeupExtra.self),
    hair: options(MakeupHair.self),
    intensity: MakeupIntensity.allCases.map { MakeupOption(id: $0.id, name: $0.name) },
    maxExtras: MakeupRecipe.maxExtras,
    skinGuard: MakeupStudio.skinGuard
)

let recipes = TemplateCatalog.all.map { Recipe(id: $0.id, title: $0.title, isPro: $0.isPro, prompt: $0.prompt) }

// Enhance's modes: the app sends only the id, the server writes the instruction.
struct EnhanceRecipe: Encodable {
    let id: String
    let prompt: String
}

let enhanceModes = EnhanceMode.allCases.map { EnhanceRecipe(id: $0.rawValue, prompt: $0.prompt) }

// The look finder's catalog ("Describe your vibe" on Explore): everything
// Aybik may suggest for a vibe she describes, by kind and id, with English
// names and a few words so Claude can choose. The assist function holds
// Claude to these ids and drops any other; the app opens each by its id.
struct FinderItem: Encodable {
    let id: String
    let name: String
    var about: String? = nil
    var isPro: Bool = false
    /// Looks: the Explore collection (TemplateCategory) and the season it's promoted in, if any.
    var collection: String? = nil
    var season: String? = nil
    /// Enhance: an AI fix (consent and credits) rather than the free Quick fix.
    var cloud: Bool? = nil
}

struct FinderExport: Encodable {
    let looks: [FinderItem]
    let styles: [FinderItem]
    let effects: [FinderItem]
    let enhance: [FinderItem]
    let glow: [FinderItem]
}

/// The editor's retro effects (RetroEffect in ios/App/Services/AI/RetroEffects.swift,
/// which lives in the app, not AppCore: add new effects here too). Glamour '92
/// is left out, as LookSuggester leaves it out: a soft-focus portrait filter is
/// too close to beauty retouching to suggest unasked.
let finderEffects: [FinderItem] = [
    FinderItem(id: "vhs", name: "VHS '86", about: "an 80s home-video tape look with a date stamp"),
    FinderItem(id: "disposable", name: "Disposable '98", about: "a 90s disposable film camera with flash and a date stamp"),
    FinderItem(id: "kira", name: "Kira Kira", about: "sparkles and glints over the photo"),
    FinderItem(id: "digicam", name: "Digicam '04", about: "a Y2K pocket digital camera with a date stamp"),
    FinderItem(id: "instant", name: "Instant '82", about: "an 80s instant film print"),
    FinderItem(id: "neon", name: "Neon '84", about: "an 80s neon glow, for nights and city lights"),
    FinderItem(id: "throwback16", name: "Throwback '16", about: "a 2016 phone photo, with an optional white square border"),
    FinderItem(id: "camcorder06", name: "Camcorder '06", about: "a 2006 camcorder with its REC display and timecode"),
    FinderItem(id: "toyCam", name: "Toy Cam '09", about: "a 2009 toy camera with cross-processed colour"),
    FinderItem(id: "rainbow", name: "Rainbow '17", about: "2017's rainbow prism light"),
    FinderItem(id: "dslr12", name: "DSLR '12", about: "a 2012 DSLR portrait: real lens blur with round bokeh behind the subject"),
    FinderItem(id: "filmStill", name: "Film Still", about: "a movie frame with letterbox bars and a subtitle"),
    FinderItem(id: "tinyWorld", name: "Tiny World", about: "tilt-shift that turns streets and wide views into a tiny model world"),
]

func finderEnhance(_ option: EnhanceOption) -> FinderItem {
    let words: (name: String, about: String) = {
        switch option {
        case .quickFix: return ("Quick fix", "less noise, crisper detail and balanced light, free on the device")
        case .unblur: return ("Unblur & sharpen", "sharpens blurry shots")
        case .restore: return ("Restore old photo", "removes scratches, dust, creases and fading from old prints")
        case .lowLight: return ("Brighten low light", "brightens dark shots naturally")
        case .hd: return ("HD 2×", "finer detail, up to twice the size")
        }
    }()
    return FinderItem(id: option.rawValue, name: words.name, about: words.about, cloud: option.isCloud)
}

/// Retro Cam's Glow looks: light and colour only, live in the camera.
func finderGlowAbout(_ id: String) -> String {
    switch id {
    case "dreamy": return "a soft, dreamy glow"
    case "golden": return "warm golden-hour light"
    case "analog": return "faded film colour with grain"
    case "moody": return "deeper shadows and a moody grade"
    default: return "a live camera look"
    }
}

let finder = FinderExport(
    looks: TemplateCatalog.all.map {
        FinderItem(id: $0.id, name: $0.title, about: $0.subtitle, isPro: $0.isPro,
                   collection: $0.category.rawValue, season: $0.season?.rawValue)
    },
    styles: StyleCatalog.all.filter { $0.id != "auto" }.map { FinderItem(id: $0.id, name: $0.name, isPro: $0.isPro) },
    effects: finderEffects,
    enhance: EnhanceOption.allCases.map(finderEnhance),
    glow: [FinderItem(id: "natural", name: "Natural", about: "clean, natural light")]
        + GlowCam.vibes.map { FinderItem(id: $0.id, name: $0.name, about: finderGlowAbout($0.id)) }
)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let payload: [String: AnyEncodable] = [
    "_comment": AnyEncodable("Generated from ios/Packages/AppCore (TemplateCatalog/StyleCatalog/MakeupStudio/EnhanceMode/GlowCam) and scripts/export-catalog (the finder's effects). Do not edit by hand: run scripts/export-catalog.sh."),
    "enhanceModes": AnyEncodable(enhanceModes),
    "finder": AnyEncodable(finder),
    "templates": AnyEncodable(recipes),
    "proStyles": AnyEncodable(StyleCatalog.all.filter(\.isPro).map(\.id)),
    "makeup": AnyEncodable(makeup),
]
print(String(data: try encoder.encode(payload), encoding: .utf8)!)

struct AnyEncodable: Encodable {
    let encodeValue: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) { encodeValue = value.encode }
    func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
}
