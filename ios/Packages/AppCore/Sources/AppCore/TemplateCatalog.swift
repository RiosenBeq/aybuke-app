import Foundation

public enum TemplateCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case trending
    case glowUp
    case aesthetic
    case dreamy
    case seasonal
    case art
    case business

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .trending: return "Trending now"
        case .glowUp: return "Glow-up looks"
        case .aesthetic: return "Aesthetic edits"
        case .dreamy: return "Dreamy portraits"
        case .seasonal: return "Spooky season"
        case .art: return "Art styles"
        case .business: return "For your shop & career"
        }
    }
}

/// A one-tap transformation: the user picks a photo, we send it to the edit
/// model together with a carefully written instruction.
public struct PhotoTemplate: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let category: TemplateCategory
    /// Instruction sent to the image-edit model.
    public let prompt: String
    public let symbolName: String
    public let isPro: Bool
    public let isNew: Bool
    /// Optional remote thumbnail (from the remote catalog).
    public let thumbnailURL: URL?

    public init(
        id: String, title: String, subtitle: String, category: TemplateCategory,
        prompt: String, symbolName: String,
        isPro: Bool = false, isNew: Bool = false, thumbnailURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.prompt = prompt
        self.symbolName = symbolName
        self.isPro = isPro
        self.isNew = isNew
        self.thumbnailURL = thumbnailURL
    }
}

/// Looks made for girls and young women. House rules for every recipe:
/// preserve identity and skin tone, never reshape bodies or faces, keep
/// outfits modest and age-appropriate, and never name real brands.
public enum TemplateCatalog {
    /// Appended to every people-centric template so the model preserves identity
    /// (the #1 complaint about AI photo apps is "it doesn't look like me").
    public static let identityClause = "Keep the person's face, identity, skin tone, body shape and expression exactly the same."

    public static let all: [PhotoTemplate] = [
        // MARK: Trending
        PhotoTemplate(
            id: "doll-box", title: "Doll Box", subtitle: "You, as a collectible doll",
            category: .trending,
            prompt: "Turn the person in this photo into a collectible fashion doll standing inside a pink cardboard toy box with a clear plastic window. Next to the doll, show three small matching accessories in their own compartments: a handbag, sunglasses and a phone. Glossy toy-packaging design with an empty header area and no text or logos. Keep the outfit modest and age-appropriate. \(identityClause)",
            symbolName: "gift", isPro: true, isNew: true
        ),
        PhotoTemplate(
            id: "figurine", title: "3D Figurine", subtitle: "Collectible desk toy",
            category: .trending,
            prompt: "Create a 1/7 scale commercialized collectible figure of the person in this photo, realistic style, standing on a round transparent acrylic base on a computer desk. Behind it, show the figure's colorful retail packaging box with matching artwork, and a monitor displaying the figure's 3D modeling process. \(identityClause)",
            symbolName: "figure.stand", isPro: true
        ),
        PhotoTemplate(
            id: "y2k", title: "Y2K Digicam", subtitle: "2000s point-and-shoot",
            category: .trending,
            prompt: "Make this look like an authentic early-2000s digital camera photo: direct on-camera flash, slightly bright highlights, a cool tint, soft focus, light noise and an orange date stamp in the bottom corner. \(identityClause)",
            symbolName: "camera.viewfinder", isNew: true
        ),
        PhotoTemplate(
            id: "anime-film", title: "Anime Film", subtitle: "Hand-painted movie still",
            category: .trending,
            prompt: "Redraw this photo as a hand-painted anime film still with soft pastel colors, warm sunlight, painterly clouds and lush backgrounds. Keep the composition and each person's recognizable features.",
            symbolName: "cloud.sun"
        ),
        PhotoTemplate(
            id: "polaroid", title: "Bestie Polaroid", subtitle: "90s instant film",
            category: .trending,
            prompt: "Make this look like an authentic 1990s instant-film photo: direct on-camera flash, soft focus, warm color shift, light grain and a white instant-film border. \(identityClause)",
            symbolName: "heart.text.square"
        ),

        // MARK: Glow-up looks
        PhotoTemplate(
            id: "soft-glam", title: "Soft Glam", subtitle: "Pretty, natural makeup",
            category: .glowUp,
            prompt: "Add soft, natural-looking glam makeup: a light dewy base that keeps the real skin texture, rosy blush, soft brown eyeshadow, defined lashes and a glossy pink lip. Change only the makeup. \(identityClause)",
            symbolName: "sparkles", isNew: true
        ),
        PhotoTemplate(
            id: "pink-hair", title: "Pink Hair", subtitle: "Try pastel pink",
            category: .glowUp,
            prompt: "Change only the hair color to a soft pastel pink with natural highlights and realistic strands. Keep the hairstyle, haircut and everything else in the photo unchanged. \(identityClause)",
            symbolName: "paintbrush.pointed", isNew: true
        ),
        PhotoTemplate(
            id: "glam", title: "Glam Studio", subtitle: "Beauty-campaign lighting",
            category: .glowUp,
            prompt: "Create a studio beauty portrait with soft glam makeup, glossy hair, rim lighting and a seamless pastel pink backdrop. Preserve the natural skin texture. \(identityClause)",
            symbolName: "camera.aperture"
        ),
        PhotoTemplate(
            id: "curls", title: "Bouncy Curls", subtitle: "Salon-fresh volume",
            category: .glowUp,
            prompt: "Restyle the hair into voluminous, bouncy salon curls with a healthy shine, keeping the original hair color and length. Keep everything else in the photo unchanged. \(identityClause)",
            symbolName: "wind", isPro: true
        ),
        PhotoTemplate(
            id: "clean-girl", title: "Clean Girl", subtitle: "Fresh, dewy & effortless",
            category: .glowUp,
            prompt: "Give the photo a fresh 'clean girl' look: dewy skin that keeps its natural texture, brushed-up brows, a hint of tinted lip balm, small gold hoop earrings, a sleek low bun and soft morning daylight. \(identityClause)",
            symbolName: "drop", isPro: true
        ),

        // MARK: Aesthetic edits
        PhotoTemplate(
            id: "ballet", title: "Ballet Core", subtitle: "Satin bows & tulle",
            category: .aesthetic,
            prompt: "Restyle the photo with a soft balletcore aesthetic: satin ribbon bows in the hair, a pastel pink wrap cardigan with a flowing tulle skirt, a sunlit dance studio with a barre and tall mirrors, and airy pastel light. \(identityClause)",
            symbolName: "figure.dance", isNew: true
        ),
        PhotoTemplate(
            id: "cherry-blossom", title: "Cherry Blossom", subtitle: "Spring in full bloom",
            category: .aesthetic,
            prompt: "Place the person under blooming pink cherry blossom trees on a sunny spring day, with soft petals drifting in the air and dreamy bokeh. Match the lighting naturally. \(identityClause)",
            symbolName: "leaf"
        ),
        PhotoTemplate(
            id: "cafe", title: "Café Date", subtitle: "Cozy latte vibes",
            category: .aesthetic,
            prompt: "Place the person in a cozy, aesthetic café with warm fairy lights, a latte with heart latte art and a pastry on the table, and soft afternoon light. Match the lighting naturally. \(identityClause)",
            symbolName: "cup.and.saucer"
        ),
        PhotoTemplate(
            id: "paris", title: "Paris Trip", subtitle: "Sunny city getaway",
            category: .aesthetic,
            prompt: "Place the person on a charming Paris street on a sunny day, with the Eiffel Tower in the soft-focus background, flower boxes on the balconies and warm golden light. Match the lighting naturally. \(identityClause)",
            symbolName: "airplane", isPro: true, isNew: true
        ),
        PhotoTemplate(
            id: "old-money", title: "Old Money", subtitle: "Quiet-luxury editorial",
            category: .aesthetic,
            prompt: "Restyle as an 'old money' editorial portrait: tailored neutral-toned clothing, an elegant estate garden background, golden-hour light and a 35mm film look. \(identityClause)",
            symbolName: "building.columns", isPro: true
        ),

        // MARK: Dreamy portraits
        PhotoTemplate(
            id: "fairy", title: "Fairy Princess", subtitle: "Enchanted & ethereal",
            category: .dreamy,
            prompt: "Transform the photo into an ethereal fairy princess portrait: an elegant flowing pastel gown with long sleeves, delicate translucent wings, a flower crown, and a glowing enchanted forest with fireflies and soft sparkles. \(identityClause)",
            symbolName: "crown", isPro: true
        ),
        PhotoTemplate(
            id: "golden-glow", title: "Golden Hour Glow", subtitle: "Warm sunset light",
            category: .dreamy,
            prompt: "Relight this photo with warm golden-hour sunlight: a soft glowing backlight in the hair, a gentle lens flare and a warm, flattering color grade. Keep the scene unchanged. \(identityClause)",
            symbolName: "sun.max"
        ),
        PhotoTemplate(
            id: "birthday", title: "Birthday Glam", subtitle: "Balloons & confetti",
            category: .dreamy,
            prompt: "Turn this into a festive birthday photoshoot: pastel pink and silver balloons, a sparkly backdrop, floating confetti and a birthday cake with sparkler candles nearby. \(identityClause)",
            symbolName: "birthday.cake"
        ),
        PhotoTemplate(
            id: "restore", title: "Restore Old Photo", subtitle: "Bring memories back",
            category: .dreamy,
            prompt: "Restore this old photograph: remove scratches, dust, stains and creases, fix fading, sharpen faces naturally and colorize with realistic, period-accurate colors. Do not change anyone's features.",
            symbolName: "clock.arrow.circlepath", isPro: true
        ),

        // MARK: Seasonal
        PhotoTemplate(
            id: "spooky", title: "Spooky Portrait", subtitle: "Candle-lit Halloween",
            category: .seasonal,
            prompt: "Transform this photo into a cinematic Halloween portrait: a moody candle-lit atmosphere, carved glowing pumpkins, light fog, autumn leaves and a subtle gothic costume. \(identityClause)",
            symbolName: "moon.stars", isPro: true, isNew: true
        ),
        PhotoTemplate(
            id: "witchy", title: "Witchy Glam", subtitle: "Cute & a little spooky",
            category: .seasonal,
            prompt: "Restyle the person as a cute, glamorous witch: an elegant black witch hat, a cozy dark knit dress, a little black cat nearby, candles, pumpkins and a soft purple-and-pink glow. \(identityClause)",
            symbolName: "wand.and.stars"
        ),

        // MARK: Art styles
        PhotoTemplate(
            id: "watercolor", title: "Watercolor", subtitle: "Soft & dreamy",
            category: .art,
            prompt: "Turn this photo into a loose watercolor illustration with soft bleeding edges, paper texture and a light pastel palette. Keep the composition.",
            symbolName: "drop.circle"
        ),
        PhotoTemplate(
            id: "3d-cartoon", title: "3D Cartoon", subtitle: "Animated-movie you",
            category: .art,
            prompt: "Turn the person into a cute 3D animated movie character with big expressive eyes, soft subsurface lighting and a colorful background. Keep their hairstyle, outfit and recognizable features.",
            symbolName: "face.smiling"
        ),
        PhotoTemplate(
            id: "oil-painting", title: "Oil Painting", subtitle: "Museum masterpiece",
            category: .art,
            prompt: "Repaint this photo as a classical oil painting with visible brush strokes, rich chiaroscuro lighting and a museum-quality finish. Keep the composition and likeness.",
            symbolName: "paintpalette"
        ),
        PhotoTemplate(
            id: "comic", title: "Comic Book", subtitle: "Ink & halftone",
            category: .art,
            prompt: "Redraw this photo as a bold comic book panel with confident ink outlines, halftone shading and vibrant flat colors. Keep the composition and likeness.",
            symbolName: "text.bubble"
        ),
        PhotoTemplate(
            id: "claymation", title: "Claymation", subtitle: "Stop-motion charm",
            category: .art,
            prompt: "Recreate this photo as a handmade claymation scene with plasticine textures, visible fingerprints and soft stop-motion lighting. Keep the composition.",
            symbolName: "hand.raised"
        ),
        PhotoTemplate(
            id: "neon-city", title: "Neon City", subtitle: "Pink neon nights",
            category: .art,
            prompt: "Restyle this photo with a neon-noir look: a rainy night street, glowing pink and teal neon reflections and cinematic haze. \(identityClause)",
            symbolName: "building.2", isPro: true
        ),

        // MARK: For your shop & career
        PhotoTemplate(
            id: "product-studio", title: "Product Studio", subtitle: "Shop-ready product shots",
            category: .business,
            prompt: "Place the main product from this photo on a clean seamless pastel studio background with soft natural shadows and premium e-commerce lighting. Keep the product's shape, label, text and colors exactly the same.",
            symbolName: "bag", isPro: true
        ),
        PhotoTemplate(
            id: "headshot", title: "Pro Headshot", subtitle: "LinkedIn-ready in seconds",
            category: .business,
            prompt: "Turn this into a professional headshot of the same person wearing a tailored blazer, soft studio lighting, a neutral light-gray backdrop, shallow depth of field and natural skin texture. \(identityClause)",
            symbolName: "person.crop.square", isPro: true
        ),
        PhotoTemplate(
            id: "golden-sky", title: "Golden Sky", subtitle: "Instant sunset",
            category: .business,
            prompt: "Replace the sky with a dramatic golden-hour sunset and match the lighting, color temperature and reflections of the rest of the scene. Change nothing else.",
            symbolName: "sun.horizon"
        ),
    ]

    public static func templates(in category: TemplateCategory) -> [PhotoTemplate] {
        all.filter { $0.category == category }
    }

    public static func template(id: String) -> PhotoTemplate? {
        all.first { $0.id == id }
    }

    /// Categories in display order, skipping empty ones.
    public static var categories: [TemplateCategory] {
        TemplateCategory.allCases.filter { category in all.contains { $0.category == category } }
    }
}
