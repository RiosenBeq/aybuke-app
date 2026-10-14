import Foundation

// Makeup Studio: looks to try on a photo, made of a few simple choices (lips,
// eyes, cheeks, extras, an optional hair color and how strong). Makeup here is
// play and self-expression, never "fixing" a face: a request only adds color,
// shine and sparkle, and always keeps her face, features, expression, skin
// tone, skin texture, body and age exactly as they are. It runs as a Magic
// Edit, so it goes through the same gates, guard and server checks.
//
// Names are English; the app shows them with `L10n.core(_:)`, and
// scripts/export-core-strings.py registers every name marked with `look` or
// `option` for translators. Requests are English for the image model and
// never shown.

/// Marks a look's name for scripts/export-core-strings.py.
private func look(_ english: String) -> String { english }

/// Marks a choice's name for scripts/export-core-strings.py.
private func option(_ english: String) -> String { english }

/// One kind of choice on a row of chips: a lip color, an eye look, a blush,
/// an extra or a hair color.
public protocol MakeupChoice: CaseIterable, Hashable, Identifiable, Sendable where AllCases == [Self] {
    /// English name on its chip.
    var name: String { get }
    /// "#RRGGBB" for the chip's color dot; nil for "As is".
    var swatch: String? { get }
}

extension MakeupChoice where Self: RawRepresentable, RawValue == String {
    public var id: String { rawValue }
}

/// Lip color. Every color follows the natural lip line, so lips are never
/// overlined or made to look fuller.
public enum MakeupLips: String, MakeupChoice {
    case none, clearGloss, softPink, rosy, cherryRed, berry, coral, plum, mocha

    public var name: String {
        switch self {
        case .none: return option("As is")
        case .clearGloss: return option("Clear gloss")
        case .softPink: return option("Soft pink")
        case .rosy: return option("Rosy")
        case .cherryRed: return option("Cherry red")
        case .berry: return option("Berry")
        case .coral: return option("Coral")
        case .plum: return option("Plum")
        case .mocha: return option("Mocha")
        }
    }

    public var swatch: String? {
        switch self {
        case .none: return nil
        case .clearGloss: return "#F6E3EA"
        case .softPink: return "#E8A6B4"
        case .rosy: return "#D8627E"
        case .cherryRed: return "#C8102E"
        case .berry: return "#8E2A55"
        case .coral: return "#FF6F61"
        case .plum: return "#5E1B47"
        case .mocha: return "#8B5A44"
        }
    }

    var request: String? {
        switch self {
        case .none: return nil
        case .clearGloss: return "a clear, shiny gloss"
        case .softPink: return "a soft pink tint"
        case .rosy: return "a rosy pink color"
        case .cherryRed: return "a cherry-red color"
        case .berry: return "a berry color"
        case .coral: return "a bright coral color"
        case .plum: return "a deep plum color"
        case .mocha: return "a warm mocha-brown color"
        }
    }
}

/// Eyeshadow or eyeliner. Liner follows the lash line; the eye's shape and
/// size never change.
public enum MakeupEyes: String, MakeupChoice {
    case none, softShimmer, smokyBrown, pastelWash, glitterLid, sunset, wingedLiner, colorLiner

    public var name: String {
        switch self {
        case .none: return option("As is")
        case .softShimmer: return option("Soft shimmer")
        case .smokyBrown: return option("Smoky brown")
        case .pastelWash: return option("Pastel wash")
        case .glitterLid: return option("Glitter lid")
        case .sunset: return option("Sunset")
        case .wingedLiner: return option("Winged liner")
        case .colorLiner: return option("Color liner")
        }
    }

    public var swatch: String? {
        switch self {
        case .none: return nil
        case .softShimmer: return "#EBD3B5"
        case .smokyBrown: return "#7A5240"
        case .pastelWash: return "#C9B8F2"
        case .glitterLid: return "#E7C4F0"
        case .sunset: return "#FF9E6D"
        case .wingedLiner: return "#121212"
        case .colorLiner: return "#78C8F0"
        }
    }

    var request: String? {
        switch self {
        case .none: return nil
        case .softShimmer: return "a soft champagne shimmer on the eyelids"
        case .smokyBrown: return "smoky brown eyeshadow blended on the eyelids"
        case .pastelWash: return "a wash of pastel lilac and sky-blue eyeshadow on the eyelids"
        case .glitterLid: return "sparkly glitter eyeshadow on the eyelids"
        case .sunset: return "a sunset blend of peach, coral and gold eyeshadow on the eyelids"
        case .wingedLiner: return "classic black winged eyeliner along the upper lash line"
        case .colorLiner: return "playful pastel rainbow eyeliner along the upper lash line"
        }
    }
}

/// Blush: color only, never contour or a change of skin tone.
public enum MakeupCheeks: String, MakeupChoice {
    case none, softBlush, drapedBlush, sunKissed, rosyFlush

    public var name: String {
        switch self {
        case .none: return option("As is")
        case .softBlush: return option("Soft blush")
        case .drapedBlush: return option("Draped blush")
        case .sunKissed: return option("Sun-kissed")
        case .rosyFlush: return option("Rosy flush")
        }
    }

    public var swatch: String? {
        switch self {
        case .none: return nil
        case .softBlush: return "#F4A7A3"
        case .drapedBlush: return "#E9799A"
        case .sunKissed: return "#F5A26F"
        case .rosyFlush: return "#F28FA8"
        }
    }

    var request: String? {
        switch self {
        case .none: return nil
        case .softBlush: return "a soft rosy-peach blush on the apples of the cheeks"
        case .drapedBlush: return "a rosy blush draped from the cheeks up toward the temples"
        case .sunKissed: return "a warm peach blush across the cheeks and nose bridge"
        case .rosyFlush: return "a cool rosy flush on the cheeks and the tip of the nose"
        }
    }
}

/// Little extras, any number of them, painted or placed on top of the skin.
public enum MakeupExtra: String, MakeupChoice {
    case faceGems, fauxFreckles, starStickers, glitter

    public var name: String {
        switch self {
        case .faceGems: return option("Face gems")
        case .fauxFreckles: return option("Faux freckles")
        case .starStickers: return option("Star stickers")
        case .glitter: return option("Glitter")
        }
    }

    public var swatch: String? {
        switch self {
        case .faceGems: return "#7FD8E8"
        case .fauxFreckles: return "#9C6644"
        case .starStickers: return "#FFD45C"
        case .glitter: return "#E8C8FF"
        }
    }

    var request: String {
        switch self {
        case .faceGems: return "a few face gems by the outer eye corners"
        case .fauxFreckles: return "faux freckles across the nose and cheeks"
        case .starStickers: return "star stickers on the cheekbones"
        case .glitter: return "glitter on the cheekbones"
        }
    }
}

/// A new hair color ("give me pink hair"), keeping the hairstyle and cut.
public enum MakeupHair: String, MakeupChoice {
    case none, pastelPink, lilac, copper, honeyBlonde, blue

    public var name: String {
        switch self {
        case .none: return option("As is")
        case .pastelPink: return option("Pastel pink")
        case .lilac: return option("Lilac")
        case .copper: return option("Copper")
        case .honeyBlonde: return option("Honey blonde")
        case .blue: return option("Blue")
        }
    }

    public var swatch: String? {
        switch self {
        case .none: return nil
        case .pastelPink: return "#F7B6CF"
        case .lilac: return "#C3A6E8"
        case .copper: return "#B5562B"
        case .honeyBlonde: return "#D9A55B"
        case .blue: return "#3D7DD8"
        }
    }

    var request: String? {
        switch self {
        case .none: return nil
        case .pastelPink: return "soft pastel pink"
        case .lilac: return "dreamy lilac"
        case .copper: return "warm copper"
        case .honeyBlonde: return "golden honey blonde"
        case .blue: return "ocean blue"
        }
    }
}

/// How strong the colors are.
public enum MakeupIntensity: String, CaseIterable, Identifiable, Sendable {
    case soft, medium, bold

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .soft: return option("Soft")
        case .medium: return option("Medium")
        // Shown as "Vivid": the catalog's "Bold" is a font weight in Text & Stickers.
        case .bold: return option("Vivid")
        }
    }

    var request: String {
        switch self {
        case .soft: return "Keep the colors soft and subtle."
        case .medium: return "Make the colors visible but wearable."
        case .bold: return "Make the colors bold and vivid."
        }
    }
}

/// Everything she picked: one look on a photo.
public struct MakeupRecipe: Hashable, Sendable {
    public var lips: MakeupLips
    public var eyes: MakeupEyes
    public var cheeks: MakeupCheeks
    public var extras: Set<MakeupExtra>
    public var hair: MakeupHair
    public var intensity: MakeupIntensity

    public init(
        lips: MakeupLips = .none, eyes: MakeupEyes = .none, cheeks: MakeupCheeks = .none,
        extras: Set<MakeupExtra> = [], hair: MakeupHair = .none, intensity: MakeupIntensity = .medium
    ) {
        self.lips = lips
        self.eyes = eyes
        self.cheeks = cheeks
        self.extras = extras
        self.hair = hair
        self.intensity = intensity
    }

    /// Any makeup at all (a hair color alone isn't).
    public var hasMakeup: Bool { lips != .none || eyes != .none || cheeks != .none || !extras.isEmpty }

    /// Nothing to try yet.
    public var isEmpty: Bool { !hasMakeup && hair == .none }

    /// The same makeup with another hair choice: picking a look keeps her hair color.
    public func withHair(_ hair: MakeupHair) -> MakeupRecipe {
        var recipe = self
        recipe.hair = hair
        return recipe
    }

    /// Adds or removes one extra.
    public mutating func toggle(_ extra: MakeupExtra) {
        if extras.contains(extra) { extras.remove(extra) } else { extras.insert(extra) }
    }
}

/// A one-tap look: a named recipe with two or three colors for its chip.
public struct MakeupPreset: Identifiable, Hashable, Sendable {
    public let id: String
    /// English name on its chip.
    public let name: String
    /// Never sets a hair color: that stays her own choice.
    public let recipe: MakeupRecipe
    /// "#RRGGBB" colors for the chip's swatch dots.
    public let swatches: [String]
}

public enum MakeupStudio {
    /// The looks, in the order the panel shows them. No brand, celebrity or
    /// platform names.
    public static let presets: [MakeupPreset] = [
        MakeupPreset(id: "softGlam", name: look("Soft Glam"),
                     recipe: MakeupRecipe(lips: .softPink, eyes: .smokyBrown, cheeks: .softBlush, intensity: .soft),
                     swatches: ["#B98068", "#F4A7A3", "#E8A6B4"]),
        MakeupPreset(id: "strawberryGirl", name: look("Strawberry Girl"),
                     recipe: MakeupRecipe(lips: .cherryRed, eyes: .softShimmer, cheeks: .rosyFlush, extras: [.fauxFreckles]),
                     swatches: ["#E2445C", "#F28FA8", "#9C6644"]),
        MakeupPreset(id: "cherryLips", name: look("Cherry Lips"),
                     recipe: MakeupRecipe(lips: .cherryRed, cheeks: .softBlush, intensity: .bold),
                     swatches: ["#C8102E", "#F4A7A3"]),
        MakeupPreset(id: "latte", name: look("Latte"),
                     recipe: MakeupRecipe(lips: .mocha, eyes: .smokyBrown),
                     swatches: ["#7A5240", "#8B5A44", "#E3C9A8"]),
        MakeupPreset(id: "coldGirl", name: look("Cold Girl"),
                     recipe: MakeupRecipe(lips: .clearGloss, eyes: .softShimmer, cheeks: .rosyFlush),
                     swatches: ["#F28FA8", "#DCE6F5", "#F6E3EA"]),
        MakeupPreset(id: "glitterPop", name: look("Glitter Pop"),
                     recipe: MakeupRecipe(lips: .rosy, eyes: .glitterLid, cheeks: .softBlush, extras: [.glitter], intensity: .bold),
                     swatches: ["#FF5CA1", "#E7C4F0", "#FFD45C"]),
        MakeupPreset(id: "y2kFrost", name: look("Y2K Frost"),
                     recipe: MakeupRecipe(lips: .clearGloss, eyes: .pastelWash, extras: [.starStickers, .glitter]),
                     swatches: ["#BFD7FF", "#C9B8F2", "#F6E3EA"]),
        MakeupPreset(id: "graphicLiner", name: look("Graphic Liner"),
                     recipe: MakeupRecipe(lips: .softPink, eyes: .wingedLiner, intensity: .bold),
                     swatches: ["#121212", "#E8A6B4"]),
        MakeupPreset(id: "peachyDoll", name: look("Peachy Doll"),
                     recipe: MakeupRecipe(lips: .coral, eyes: .softShimmer, cheeks: .softBlush, intensity: .soft),
                     swatches: ["#FFB38A", "#FF6F61", "#F4A7A3"]),
        MakeupPreset(id: "festivalGems", name: look("Festival Gems"),
                     recipe: MakeupRecipe(lips: .clearGloss, eyes: .colorLiner, extras: [.faceGems, .glitter], intensity: .bold),
                     swatches: ["#78E1CD", "#A78BFA", "#FF5CA1"]),
        MakeupPreset(id: "balletBlush", name: look("Ballet Blush"),
                     recipe: MakeupRecipe(lips: .softPink, eyes: .softShimmer, cheeks: .drapedBlush, intensity: .soft),
                     swatches: ["#F7C1D9", "#E9799A", "#F8E0EA"]),
        MakeupPreset(id: "gothGlam", name: look("Goth Glam"),
                     recipe: MakeupRecipe(lips: .plum, eyes: .smokyBrown, intensity: .bold),
                     swatches: ["#3C185A", "#5E1B47", "#121212"]),
        MakeupPreset(id: "rainbowLiner", name: look("Rainbow Liner"),
                     recipe: MakeupRecipe(lips: .clearGloss, eyes: .colorLiner, cheeks: .softBlush, extras: [.starStickers]),
                     swatches: ["#FFB3C7", "#BFD7FF", "#C8F0D8"]),
        MakeupPreset(id: "sunsetShimmer", name: look("Sunset Shimmer"),
                     recipe: MakeupRecipe(lips: .clearGloss, eyes: .sunset, cheeks: .sunKissed),
                     swatches: ["#FF9E6D", "#FF6F61", "#FFD45C"]),
    ]

    /// Preselected when the panel opens.
    public static var defaultPreset: MakeupPreset { presets[0] }

    public static func preset(id: String) -> MakeupPreset? {
        presets.first { $0.id == id }
    }

    /// The look this recipe is (her hair color aside), if it is one.
    public static func preset(matching recipe: MakeupRecipe) -> MakeupPreset? {
        presets.first { $0.recipe == recipe.withHair(.none) }
    }

    /// The protective last sentence of every request. The editor's guard
    /// (`PromptBuilder.editGuard`) follows it, so face shape, skin tone, age
    /// and clothing are covered there too. Worded so it passes
    /// `ContentPolicy` itself: the server checks the whole instruction.
    public static let skinGuard = "Keep the same expression and every freckle, pore and mark of the real skin, with no smoothing, contouring or reshaping."

    /// The request for the image model, sent as a Magic Edit (empty when
    /// nothing is chosen). Only adds color, shine and sparkle.
    public static func instruction(for recipe: MakeupRecipe) -> String {
        sentences(for: recipe).joined(separator: " ")
    }

    /// The instruction's sentences in order. Each is long enough that a
    /// policy term can only run across two neighbours (see the tests).
    static func sentences(for recipe: MakeupRecipe) -> [String] {
        guard !recipe.isEmpty else { return [] }
        var sentences: [String] = []
        if recipe.hasMakeup {
            sentences.append("Add makeup to the person in this photo as color, shine and sparkle on the real skin.")
            if let eyes = recipe.eyes.request { sentences.append("Eyes: \(eyes).") }
            if let lips = recipe.lips.request { sentences.append("Lips: \(lips), following the natural lip line.") }
            if let cheeks = recipe.cheeks.request { sentences.append("Cheeks: \(cheeks).") }
            let extras = MakeupExtra.allCases.filter(recipe.extras.contains).map(\.request)
            if !extras.isEmpty { sentences.append("Extras: \(list(extras)).") }
        } else {
            sentences.append("Change only the hair color of the person in this photo.")
        }
        sentences.append(recipe.intensity.request)
        if let hair = recipe.hair.request {
            sentences.append("Hair: \(hair) color with realistic highlights, same hairstyle and cut.")
        }
        sentences.append(skinGuard)
        return sentences
    }

    /// "a, b and c".
    private static func list(_ items: [String]) -> String {
        guard let last = items.last, items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }
}
