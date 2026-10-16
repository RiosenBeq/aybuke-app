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
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let payload: [String: AnyEncodable] = [
    "_comment": AnyEncodable("Generated from ios/Packages/AppCore (TemplateCatalog/StyleCatalog/MakeupStudio/EnhanceMode). Do not edit by hand: run scripts/export-catalog.sh."),
    "enhanceModes": AnyEncodable(enhanceModes),
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
