import Foundation

/// A visual style for text-to-image generation. Styles are appended to the
/// user's prompt so people get great results without prompt-engineering.
public struct ImageStyle: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let promptSuffix: String
    public let symbolName: String
    /// Two hex colours that tint the offline demo artwork for this style.
    public let swatch: [String]
    public let isPro: Bool

    public init(id: String, name: String, promptSuffix: String, symbolName: String, swatch: [String], isPro: Bool = false) {
        self.id = id
        self.name = name
        self.promptSuffix = promptSuffix
        self.symbolName = symbolName
        self.swatch = swatch
        self.isPro = isPro
    }
}

public enum StyleCatalog {
    public static let auto = ImageStyle(
        id: "auto", name: "Auto", promptSuffix: "",
        symbolName: "sparkles", swatch: ["#FFC25C", "#FF7A3D"]
    )

    public static let all: [ImageStyle] = [
        auto,
        ImageStyle(id: "photo", name: "Photoreal",
                   promptSuffix: "photorealistic, natural light, shot on a 50mm lens, fine detail, true-to-life colors",
                   symbolName: "camera", swatch: ["#3A3A46", "#9CA3AF"]),
        ImageStyle(id: "cinematic", name: "Cinematic",
                   promptSuffix: "cinematic film still, dramatic lighting, shallow depth of field, anamorphic lens, subtle film grain",
                   symbolName: "film", swatch: ["#0F172A", "#F59E0B"]),
        ImageStyle(id: "pastel", name: "Pastel Dream",
                   promptSuffix: "dreamy pastel aesthetic, soft pink and lavender palette, gentle glow, airy and whimsical",
                   symbolName: "cloud", swatch: ["#F7C1D9", "#E9D5FF"]),
        ImageStyle(id: "anime", name: "Anime",
                   promptSuffix: "anime illustration, clean line art, vibrant cel shading, expressive eyes, detailed background",
                   symbolName: "sparkle", swatch: ["#F472B6", "#60A5FA"]),
        ImageStyle(id: "kawaii", name: "Kawaii",
                   promptSuffix: "kawaii illustration, cute rounded shapes, soft pastel colors, tiny sparkles, cheerful and adorable",
                   symbolName: "heart", swatch: ["#FBCFE8", "#FDE68A"]),
        ImageStyle(id: "3d", name: "3D Toon",
                   promptSuffix: "3D animated movie render, soft global illumination, subsurface scattering, playful character design",
                   symbolName: "cube", swatch: ["#22D3EE", "#A78BFA"]),
        ImageStyle(id: "fantasy", name: "Fantasy",
                   promptSuffix: "epic fantasy concept art, volumetric light, intricate detail, painterly, magical atmosphere",
                   symbolName: "wand.and.stars", swatch: ["#7C3AED", "#F0ABFC"], isPro: true),
        ImageStyle(id: "watercolor", name: "Watercolor",
                   promptSuffix: "loose watercolor painting, soft bleeding edges, textured paper, airy pastel palette",
                   symbolName: "drop", swatch: ["#93C5FD", "#FBCFE8"]),
        ImageStyle(id: "oil", name: "Oil Paint",
                   promptSuffix: "classical oil painting, visible brush strokes, rich chiaroscuro, museum quality",
                   symbolName: "paintbrush", swatch: ["#78350F", "#FBBF24"], isPro: true),
        ImageStyle(id: "neon", name: "Neon Noir",
                   promptSuffix: "neon noir, rainy night, glowing pink and teal neon reflections, cinematic haze",
                   symbolName: "bolt", swatch: ["#EC4899", "#06B6D4"], isPro: true),
        ImageStyle(id: "sketch", name: "Sketch",
                   promptSuffix: "detailed graphite pencil sketch, cross-hatching, textured paper",
                   symbolName: "pencil", swatch: ["#E5E7EB", "#6B7280"]),
        ImageStyle(id: "pixel", name: "Pixel Art",
                   promptSuffix: "16-bit pixel art, crisp pixels, limited retro palette",
                   symbolName: "square.grid.3x3", swatch: ["#22C55E", "#3B82F6"]),
        ImageStyle(id: "clay", name: "Claymation",
                   promptSuffix: "handmade claymation, plasticine texture, visible fingerprints, soft stop-motion lighting",
                   symbolName: "hand.raised", swatch: ["#FB923C", "#FDE68A"], isPro: true),
        ImageStyle(id: "vintage", name: "Vintage Film",
                   promptSuffix: "1990s analog film photo, warm color shift, light grain, soft flash",
                   symbolName: "camera.filters", swatch: ["#B45309", "#FCD34D"]),
        ImageStyle(id: "sticker", name: "Sticker",
                   promptSuffix: "cute die-cut sticker illustration, thick white border, glossy vinyl finish, bold clean shapes, plain pastel background",
                   symbolName: "seal", swatch: ["#FFD6E8", "#FF5CA1"]),
        ImageStyle(id: "storybook", name: "Storybook",
                   promptSuffix: "whimsical storybook illustration, soft gouache textures, gentle hand-painted details, cozy warm palette",
                   symbolName: "book", swatch: ["#F5DEB3", "#7FB77E"]),
        ImageStyle(id: "popart", name: "Pop Art",
                   promptSuffix: "bold pop art, halftone dots, thick black outlines, bright flat colors, punchy contrast",
                   symbolName: "circle.grid.3x3.fill", swatch: ["#FDE047", "#EF4444"]),
        ImageStyle(id: "knit", name: "Cozy Knit",
                   promptSuffix: "handmade knitted and crocheted yarn craft, soft wool texture, visible stitches, cozy handmade charm",
                   symbolName: "scribble.variable", swatch: ["#FBCFE8", "#C4B5FD"], isPro: true),
        ImageStyle(id: "papercraft", name: "Paper Craft",
                   promptSuffix: "layered paper cut-out art, handmade paper textures, soft shadows between the layers, playful depth",
                   symbolName: "scissors", swatch: ["#FDBA74", "#A5B4FC"], isPro: true),
        ImageStyle(id: "diorama", name: "Diorama",
                   promptSuffix: "isometric miniature diorama, tiny handcrafted details, tilt-shift depth of field, soft studio lighting",
                   symbolName: "square.stack.3d.up", swatch: ["#BAE6FD", "#86EFAC"]),
    ]

    public static func style(id: String?) -> ImageStyle {
        guard let id else { return auto }
        return all.first { $0.id == id } ?? auto
    }
}
