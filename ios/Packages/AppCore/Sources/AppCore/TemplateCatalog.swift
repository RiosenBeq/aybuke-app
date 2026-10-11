import Foundation

public enum TemplateCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case trending
    case seasonal
    case portrait
    case fun
    case art
    case business

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .trending: return "Trending now"
        case .seasonal: return "Spooky season"
        case .portrait: return "Portraits"
        case .fun: return "Just for fun"
        case .art: return "Art styles"
        case .business: return "For business"
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
    /// Hex gradient stops used for the card artwork until real thumbnails ship.
    public let gradient: [String]
    public let isPro: Bool
    public let isNew: Bool
    /// Optional remote thumbnail (from the remote catalog).
    public let thumbnailURL: URL?

    public init(
        id: String, title: String, subtitle: String, category: TemplateCategory,
        prompt: String, symbolName: String, gradient: [String],
        isPro: Bool = false, isNew: Bool = false, thumbnailURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.prompt = prompt
        self.symbolName = symbolName
        self.gradient = gradient
        self.isPro = isPro
        self.isNew = isNew
        self.thumbnailURL = thumbnailURL
    }
}

public enum TemplateCatalog {
    /// Appended to every people-centric template so the model preserves identity
    /// (the #1 complaint about AI photo apps is "it doesn't look like me").
    public static let identityClause = "Keep the person's face, identity, skin tone and expression exactly the same."

    public static let all: [PhotoTemplate] = [
        // MARK: Trending
        PhotoTemplate(
            id: "figurine", title: "3D Figurine", subtitle: "Collectible desk toy",
            category: .trending,
            prompt: "Create a 1/7 scale commercialized collectible figure of the person in this photo, realistic style, standing on a round transparent acrylic base on a computer desk. Behind it, show the figure's colorful retail packaging box with matching artwork, and a monitor displaying the figure's 3D modeling process. \(identityClause)",
            symbolName: "figure.stand", gradient: ["#FF5A36", "#FFB547"], isPro: true, isNew: true
        ),
        PhotoTemplate(
            id: "action-figure", title: "Action Figure", subtitle: "Boxed hero starter pack",
            category: .trending,
            prompt: "Turn the person in this photo into a realistic action figure sealed in a clear blister-pack toy box, with three small accessories that match their personal style placed beside the figure. Bold toy-brand header at the top of the box. \(identityClause)",
            symbolName: "shippingbox", gradient: ["#2E6BFF", "#00D1FF"], isPro: true
        ),
        PhotoTemplate(
            id: "anime-film", title: "Anime Film", subtitle: "Hand-painted movie still",
            category: .trending,
            prompt: "Redraw this photo as a hand-painted anime film still with soft pastel colors, warm sunlight, painterly clouds and lush backgrounds. Keep the composition and each person's recognizable features.",
            symbolName: "cloud.sun", gradient: ["#7DD3FC", "#F9A8D4"]
        ),
        PhotoTemplate(
            id: "polaroid", title: "Retro Polaroid", subtitle: "90s instant film",
            category: .trending,
            prompt: "Make this look like an authentic 1990s instant-film photo: direct on-camera flash, soft focus, warm color shift, light grain and a white instant-film border. \(identityClause)",
            symbolName: "camera.viewfinder", gradient: ["#F5D0A9", "#C084FC"]
        ),

        // MARK: Seasonal
        PhotoTemplate(
            id: "spooky", title: "Spooky Portrait", subtitle: "Candle-lit Halloween",
            category: .seasonal,
            prompt: "Transform this photo into a cinematic Halloween portrait: moody candle-lit atmosphere, carved glowing pumpkins, light fog, autumn leaves and a subtle gothic costume. \(identityClause)",
            symbolName: "moon.stars", gradient: ["#F97316", "#4C1D95"], isPro: true, isNew: true
        ),
        PhotoTemplate(
            id: "vampire", title: "Vampire Glam", subtitle: "Elegant & eerie",
            category: .seasonal,
            prompt: "Restyle the person as an elegant vampire in a dark velvet outfit inside a candle-lit gothic castle hall, cinematic lighting, dramatic shadows. \(identityClause)",
            symbolName: "drop.halffull", gradient: ["#7F1D1D", "#111827"], isPro: true
        ),

        // MARK: Portraits
        PhotoTemplate(
            id: "headshot", title: "Pro Headshot", subtitle: "LinkedIn-ready in seconds",
            category: .portrait,
            prompt: "Turn this into a professional corporate headshot of the same person wearing a tailored navy blazer, soft studio lighting, neutral gray backdrop, shallow depth of field, natural skin texture. \(identityClause)",
            symbolName: "person.crop.square", gradient: ["#334155", "#94A3B8"], isPro: true
        ),
        PhotoTemplate(
            id: "old-money", title: "Old Money", subtitle: "Quiet-luxury editorial",
            category: .portrait,
            prompt: "Restyle as an 'old money' editorial portrait: tailored neutral-toned clothing, elegant estate garden background, golden-hour light, 35mm film look. \(identityClause)",
            symbolName: "leaf", gradient: ["#365314", "#D9F99D"], isPro: true
        ),
        PhotoTemplate(
            id: "glam", title: "Glam Studio", subtitle: "Beauty-campaign lighting",
            category: .portrait,
            prompt: "Create a studio beauty portrait with soft glam makeup, glossy hair, rim lighting and a seamless pastel backdrop. Preserve natural skin texture. \(identityClause)",
            symbolName: "sparkles", gradient: ["#FF2E93", "#FFC2D1"]
        ),
        PhotoTemplate(
            id: "restore", title: "Restore Old Photo", subtitle: "Fix, sharpen & colorize",
            category: .portrait,
            prompt: "Restore this old photograph: remove scratches, dust, stains and creases, fix fading, sharpen faces naturally and colorize with realistic, period-accurate colors. Do not change anyone's features.",
            symbolName: "clock.arrow.circlepath", gradient: ["#A16207", "#FDE68A"], isPro: true
        ),

        // MARK: Fun
        PhotoTemplate(
            id: "3d-cartoon", title: "3D Cartoon", subtitle: "Animated-movie you",
            category: .fun,
            prompt: "Turn the person into a cute 3D animated movie character with big expressive eyes, soft subsurface lighting and a colorful background. Keep their hairstyle, outfit and recognizable features.",
            symbolName: "face.smiling", gradient: ["#22D3EE", "#A78BFA"]
        ),
        PhotoTemplate(
            id: "superhero", title: "Superhero", subtitle: "Your origin story",
            category: .fun,
            prompt: "Turn the person into a cinematic superhero with an original suit design, a dramatic city skyline at dusk behind them and dynamic rim lighting. \(identityClause)",
            symbolName: "bolt.shield", gradient: ["#DC2626", "#1D4ED8"], isPro: true
        ),
        PhotoTemplate(
            id: "claymation", title: "Claymation", subtitle: "Stop-motion charm",
            category: .fun,
            prompt: "Recreate this photo as a handmade claymation scene with plasticine textures, visible fingerprints and soft stop-motion lighting. Keep the composition.",
            symbolName: "hand.raised", gradient: ["#FB923C", "#FDE68A"]
        ),

        // MARK: Art
        PhotoTemplate(
            id: "oil-painting", title: "Oil Painting", subtitle: "Museum masterpiece",
            category: .art,
            prompt: "Repaint this photo as a classical oil painting with visible brush strokes, rich chiaroscuro lighting and a museum-quality finish. Keep the composition and likeness.",
            symbolName: "paintbrush.pointed", gradient: ["#78350F", "#FBBF24"]
        ),
        PhotoTemplate(
            id: "watercolor", title: "Watercolor", subtitle: "Soft & dreamy",
            category: .art,
            prompt: "Turn this photo into a loose watercolor illustration with soft bleeding edges, paper texture and a light pastel palette. Keep the composition.",
            symbolName: "drop", gradient: ["#93C5FD", "#FBCFE8"]
        ),
        PhotoTemplate(
            id: "comic", title: "Comic Book", subtitle: "Ink & halftone",
            category: .art,
            prompt: "Redraw this photo as a bold comic book panel with confident ink outlines, halftone shading and vibrant flat colors. Keep the composition and likeness.",
            symbolName: "text.bubble", gradient: ["#FACC15", "#EF4444"]
        ),
        PhotoTemplate(
            id: "neon-city", title: "Neon City", subtitle: "Cyberpunk night",
            category: .art,
            prompt: "Restyle this photo with a neon-noir cyberpunk look: rainy night street, glowing pink and teal neon reflections and cinematic haze. \(identityClause)",
            symbolName: "building.2", gradient: ["#EC4899", "#06B6D4"], isPro: true
        ),

        // MARK: Business
        PhotoTemplate(
            id: "product-studio", title: "Product Studio", subtitle: "E-commerce ready",
            category: .business,
            prompt: "Place the main product from this photo on a clean seamless studio background with soft natural shadows and premium e-commerce lighting. Keep the product's shape, label, text and colors exactly the same.",
            symbolName: "bag", gradient: ["#E5E7EB", "#9CA3AF"], isPro: true
        ),
        PhotoTemplate(
            id: "golden-sky", title: "Golden Sky", subtitle: "Instant sunset",
            category: .business,
            prompt: "Replace the sky with a dramatic golden-hour sunset and match the lighting, color temperature and reflections of the rest of the scene. Change nothing else.",
            symbolName: "sun.horizon", gradient: ["#F97316", "#FDE047"]
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
