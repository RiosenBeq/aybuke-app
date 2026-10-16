import Foundation

public enum TemplateCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case trending
    case glowUp
    case aesthetic
    /// Looks for photos with friends (the "Bestie pics" interest).
    case besties
    case dreamy
    case seasonal
    case art
    case pets
    case business

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .trending: return "Trending now"
        case .glowUp: return "Glow-up looks"
        case .aesthetic: return "Aesthetic edits"
        case .besties: return "Bestie pics"
        case .dreamy: return "Dreamy portraits"
        case .seasonal: return "Spooky season"
        case .art: return "Art styles"
        case .pets: return "Pet portraits"
        case .business: return "For your shop & career"
        }
    }
}

extension TemplateCategory {
    /// Row heading on a given day: the seasonal row is named after the season
    /// that is on, so "Spooky season" never shows in spring.
    public func title(on date: Date, for audience: SeasonAudience = .everyone, calendar: Calendar = .current) -> String {
        guard self == .seasonal, let theme = SeasonalTheme.current(on: date, for: audience, calendar: calendar) else { return title }
        return theme.rowTitle
    }
}

/// A yearly date range, inclusive at both ends. A range whose end comes before
/// its start (December to January) wraps the new year.
public struct SeasonWindow: Hashable, Codable, Sendable {
    public let startMonth: Int
    public let startDay: Int
    public let endMonth: Int
    public let endDay: Int

    public init(startMonth: Int, startDay: Int, endMonth: Int, endDay: Int) {
        self.startMonth = startMonth
        self.startDay = startDay
        self.endMonth = endMonth
        self.endDay = endDay
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.month, .day], from: date)
        guard let month = parts.month, let day = parts.day else { return false }
        let key = month * 100 + day
        let start = startMonth * 100 + startDay
        let end = endMonth * 100 + endDay
        return start <= end ? (start...end).contains(key) : key >= start || key <= end
    }
}

/// Seasonal looks are promoted on Home only while their season is on (and,
/// for the local ones, where it's celebrated: `SeasonCalendar.swift`). They
/// stay reachable from the editor all year, so nothing in the app is hidden.
public enum SeasonalTheme: String, Hashable, Codable, Sendable, CaseIterable {
    // Everywhere.
    case halloween
    case winter
    case galentines
    // Where they're celebrated (`regions`).
    case eidAlFitr
    case eidAlAdha
    case lunarNewYear
    case chuseok
    case hanami
    case tanabata
    case carnaval
    case festaJunina
    case diaDeMuertos

    /// Heading of the seasonal row while this season is on.
    public var rowTitle: String {
        switch self {
        case .halloween: return "Spooky season"
        case .winter: return "Cozy winter"
        case .galentines: return "Galentine's"
        case .eidAlFitr: return "Eid al-Fitr"
        case .eidAlAdha: return "Eid al-Adha"
        case .lunarNewYear: return "Lunar New Year"
        case .chuseok: return "Chuseok"
        case .hanami: return "Hanami"
        case .tanabata: return "Tanabata"
        case .carnaval: return "Carnaval"
        case .festaJunina: return "Festa Junina"
        case .diaDeMuertos: return "Día de Muertos"
        }
    }
}

/// A season starting soon, and how many days until its first day (1: tomorrow).
public struct UpcomingSeason: Hashable, Sendable {
    public let theme: SeasonalTheme
    public let daysLeft: Int

    public init(theme: SeasonalTheme, daysLeft: Int) {
        self.theme = theme
        self.daysLeft = daysLeft
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
    /// Promoted on Home only during this season (nil: all year).
    public let season: SeasonalTheme?
    /// A realistic look of the same person, so the on-device likeness check
    /// runs on the result. False for toys, figurines, art and pets.
    public let keepsLikeness: Bool

    public init(
        id: String, title: String, subtitle: String, category: TemplateCategory,
        prompt: String, symbolName: String,
        isPro: Bool = false, isNew: Bool = false, thumbnailURL: URL? = nil,
        season: SeasonalTheme? = nil, keepsLikeness: Bool? = nil
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
        self.season = season
        self.keepsLikeness = keepsLikeness ?? [.glowUp, .aesthetic, .besties, .dreamy, .business].contains(category)
    }
}

/// Looks made for girls and young women. House rules for every recipe:
/// preserve identity and skin tone, never reshape bodies or faces, keep
/// outfits modest and age-appropriate, and never name real brands.
public enum TemplateCatalog {
    /// Appended to every people-centric template so the model preserves identity
    /// (the #1 complaint about AI photo apps is "it doesn't look like me").
    public static let identityClause = "Keep the person's face, identity, skin tone, body shape and expression exactly the same."
    /// For group looks: friends often pose together.
    public static let groupIdentityClause = "Keep every person's face, identity, skin tone, body shape and expression exactly the same."
    /// For looks that change the outfit.
    public static let modestyClause = "Keep the outfit modest and age-appropriate, with sleeves and a high neckline."
    /// For pet looks: owners often hold their pet in the photo.
    public static let petClause = "Keep the animal's breed, markings, colors and face exactly the same. If a person is in the photo, keep them exactly the same too."
    /// For the local seasons' looks: a headscarf, a hat or a bow stays, and
    /// none is added, so a festive look never dresses her for a faith.
    public static let headClause = "Keep her hair and anything she wears on her head exactly as they are."

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
            prompt: "Restyle the photo with a soft balletcore aesthetic: satin ribbon bows in the hair, a pastel pink wrap cardigan with a flowing tulle skirt, a sunlit dance studio with a barre and tall mirrors, and airy pastel light. \(modestyClause) \(identityClause)",
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
            prompt: "Restyle as an 'old money' editorial portrait: tailored neutral-toned clothing, an elegant estate garden background, golden-hour light and a 35mm film look. \(modestyClause) \(identityClause)",
            symbolName: "building.columns", isPro: true
        ),

        // MARK: Dreamy portraits
        PhotoTemplate(
            id: "fairy", title: "Fairy Princess", subtitle: "Enchanted & ethereal",
            category: .dreamy,
            prompt: "Transform the photo into an ethereal fairy princess portrait: an elegant flowing pastel gown with long sleeves, delicate translucent wings, a flower crown, and a glowing enchanted forest with fireflies and soft sparkles. \(modestyClause) \(identityClause)",
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
            prompt: "Transform this photo into a cinematic Halloween portrait: a moody candle-lit atmosphere, carved glowing pumpkins, light fog, autumn leaves and a subtle gothic costume. \(modestyClause) \(identityClause)",
            symbolName: "moon.stars", isPro: true, isNew: true, season: .halloween
        ),
        PhotoTemplate(
            id: "witchy", title: "Witchy Glam", subtitle: "Cute & a little spooky",
            category: .seasonal,
            prompt: "Restyle the person as a cute, glamorous witch: an elegant black witch hat, a cozy dark knit dress, a little black cat nearby, candles, pumpkins and a soft purple-and-pink glow. \(modestyClause) \(identityClause)",
            symbolName: "wand.and.stars", season: .halloween
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
            prompt: "Turn this into a professional headshot of the same person wearing a tailored blazer, soft studio lighting, a neutral light-gray backdrop, shallow depth of field and natural skin texture. \(modestyClause) \(identityClause)",
            symbolName: "person.crop.square", isPro: true
        ),
        PhotoTemplate(
            id: "golden-sky", title: "Golden Sky", subtitle: "Instant sunset",
            category: .business,
            prompt: "Replace the sky with a dramatic golden-hour sunset and match the lighting, color temperature and reflections of the rest of the scene. Change nothing else.",
            symbolName: "sun.horizon"
        ),
        // MARK: Trend pack (October 2026)
        // Appended after the original looks so their card colours stay put
        // (TemplateCard picks an Aura palette by position in `all`).
        PhotoTemplate(
            id: "80s-studio", title: "80s Studio Portrait", subtitle: "Mall photo-studio glam",
            category: .trending,
            prompt: "Make this a 1980s photo-studio portrait: a mottled blue studio backdrop, big soft curls in her real hair color, a puffy-sleeve blouse, warm studio lighting and a faded film print look. Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "camera.aperture", isNew: true, keepsLikeness: true
        ),
        PhotoTemplate(
            id: "laser-yearbook", title: "Laser Yearbook '86", subtitle: "Retro school-photo lasers",
            category: .trending,
            prompt: "Make this a 1986 school yearbook portrait: a dark backdrop with bright pink and blue laser beams, a head-and-shoulders pose, a crew-neck sweater and a slightly faded print. Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "graduationcap", isPro: true, isNew: true, keepsLikeness: true
        ),
        PhotoTemplate(
            id: "disco-79", title: "Disco '79", subtitle: "Mirror-ball sparkle",
            category: .trending,
            prompt: "Place the person at a 1970s roller-disco party: mirror-ball bokeh, warm colored lights, a sparkly sequin top with long sleeves, and the grain of 1979 film. No alcohol. Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "music.note", isNew: true, keepsLikeness: true
        ),
        PhotoTemplate(
            id: "plushie", title: "Plushie Me", subtitle: "You, as a soft toy",
            category: .trending,
            prompt: "Turn the person into a cute handmade stitched plush toy sitting on a cozy bed: soft fabric with visible seams, yarn hair in her real hair color and hairstyle, fabric in a shade that matches her real skin tone, embroidered features and a little matching outfit. No logos, labels or brand names. \(identityClause)",
            symbolName: "teddybear", isPro: true, isNew: true
        ),
        PhotoTemplate(
            id: "bag-charm", title: "Bag Charm Mini", subtitle: "A tiny vinyl you",
            category: .trending,
            prompt: "Turn the person into a tiny glossy vinyl bag charm figure hanging from a keyring on a canvas tote bag strap, with her real hairstyle, hair color, skin tone and outfit in chibi proportions. Soft daylight product photo. No logos, labels or brand names. \(identityClause)",
            symbolName: "handbag", isNew: true
        ),

        // MARK: Pet portraits
        PhotoTemplate(
            id: "royal-pet", title: "Royal Pet Portrait", subtitle: "Painted like royalty",
            category: .pets,
            prompt: "Repaint the pet in this photo as a regal classical oil portrait: a velvet cape with gold trim, a small jeweled crown, a carved gold frame and a rich dark background. \(petClause) \(identityClause)",
            symbolName: "crown", isNew: true
        ),
        PhotoTemplate(
            id: "pet-figurine", title: "Pet Figurine", subtitle: "Collectible desk toy",
            category: .pets,
            prompt: "Turn the pet in this photo into a cute collectible vinyl figurine on a round clear base on a tidy desk, with its matching toy box behind it. No logos or brand names. \(petClause) \(identityClause)",
            symbolName: "cat", isNew: true
        ),
        PhotoTemplate(
            id: "pet-astronaut", title: "Pet Astronaut", subtitle: "One small step for paws",
            category: .pets,
            prompt: "Show the pet in this photo as a brave astronaut in a little white space suit with a clear helmet, floating in front of a glowing planet and soft pink stars. \(petClause) \(identityClause)",
            symbolName: "dog", isNew: true
        ),

        // MARK: Winter (Dec 1 – Jan 6)
        PhotoTemplate(
            id: "snow-globe", title: "Snow Globe Me", subtitle: "A tiny winter figurine",
            category: .seasonal,
            prompt: "Turn the person into a small hand-painted figurine standing inside a glass snow globe, with drifting snowflakes, a tiny snowy pine tree and a wooden base, on a windowsill with warm fairy lights. She wears a cozy winter coat and scarf. \(identityClause)",
            symbolName: "snowflake", isPro: true, season: .winter
        ),
        PhotoTemplate(
            id: "cozy-sweater", title: "Cozy Sweater Digicam", subtitle: "Snowy-night flash photo",
            category: .seasonal,
            prompt: "Make this a 2000s digital-camera photo on a snowy winter evening: a chunky knit sweater and a knit hat, falling snow caught in the direct flash, warm string lights behind and an orange date stamp. Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "mug", season: .winter, keepsLikeness: true
        ),
        PhotoTemplate(
            id: "new-year", title: "New Year Confetti", subtitle: "Midnight flash & confetti",
            category: .seasonal,
            prompt: "Turn this into a New Year's Eve digital-camera photo: bright on-camera flash, gold and pink confetti in the air, a sparkly party hat, sparklers and a 00:00 time stamp in the corner. No alcohol. Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "party.popper", season: .winter, keepsLikeness: true
        ),

        // MARK: Galentine's (Feb 1 – 14)
        PhotoTemplate(
            id: "galentines-brunch", title: "Galentine's Brunch", subtitle: "Besties at a pink café",
            category: .seasonal,
            prompt: "Place the people in this photo at a daytime brunch in a pink café: heart-shaped pancakes, strawberries, pink lemonade, paper hearts and soft window light. No alcohol. Match the lighting naturally. \(modestyClause) \(groupIdentityClause)",
            symbolName: "fork.knife", season: .galentines, keepsLikeness: true
        ),
        PhotoTemplate(
            id: "heart-booth", title: "Heart Booth", subtitle: "Bestie booth strip",
            category: .seasonal,
            prompt: "Turn this into a retro photo-booth picture: a pink curtain with paper hearts, heart-shaped sunglasses as props, bright even flash and a light film grain. \(modestyClause) \(groupIdentityClause)",
            symbolName: "heart.square", season: .galentines, keepsLikeness: true
        ),

        // MARK: Content pack (October 2026)
        // Appended, like the trend pack, and ordered so that neighbours in
        // each Home row get different card colours (palette = index % 6).
        PhotoTemplate(
            id: "concert-night", title: "Concert Night", subtitle: "Stage lights & confetti",
            category: .besties,
            prompt: "Place the people in this photo in the crowd at an outdoor evening concert: colorful stage lights and light beams, floating confetti, glow sticks and a soft haze. Give everyone a sparkly sequin jacket over their outfit. No alcohol, no band names, logos or readable text. Keep natural skin texture, no skin smoothing. \(modestyClause) \(groupIdentityClause)",
            symbolName: "music.mic", isPro: true, isNew: true
        ),
        PhotoTemplate(
            id: "pet-studio", title: "Pet & Me Studio", subtitle: "Studio portrait, together",
            category: .pets,
            prompt: "Turn this into a soft studio portrait by a pet photographer: a seamless pastel backdrop, gentle studio lighting and a soft shadow on the floor. Change only the background and the light. \(petClause) \(identityClause)",
            symbolName: "camera.on.rectangle", isNew: true
        ),
        PhotoTemplate(
            id: "sticker-sheet", title: "Sticker Sheet", subtitle: "Die-cut stickers of you",
            category: .trending,
            prompt: "Turn the person in this photo into a sheet of six glossy die-cut vinyl stickers on a pastel backing sheet: cute illustrated versions of her in cheerful poses, each with a small prop such as a heart, a star, a bubble tea, a camera, a flower or a rainbow. Thick white sticker borders, soft shadows and no text, logos or brand names. Keep her real hairstyle, hair color, skin tone and outfit in every sticker. \(identityClause)",
            symbolName: "star.square.on.square", isNew: true
        ),
        PhotoTemplate(
            id: "tennis-club", title: "Tennis Club", subtitle: "Sunny court, sporty fit",
            category: .aesthetic,
            prompt: "Restyle the photo as a sunny tennis-club moment: a white sleeved tennis polo with a pastel sweater tied over the shoulders, a knee-length pleated tennis skirt, a racket and tennis balls, a green court with crisp white lines and bright midday light. No logos or brand names. Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "tennis.racket", isPro: true, isNew: true
        ),
        PhotoTemplate(
            id: "grad-day", title: "Grad Day", subtitle: "Cap, gown & confetti",
            category: .dreamy,
            prompt: "Turn this into a graduation-day photo: a classic graduation cap and gown over her outfit, a sunny campus lawn with leafy trees, golden confetti and tossed caps in the air, and warm afternoon light. Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "graduationcap.fill", isNew: true
        ),
        PhotoTemplate(
            id: "bracelet-club", title: "Bracelet Club", subtitle: "Beads, besties & sunshine",
            category: .besties,
            prompt: "Turn this into a sunny friendship-bracelet afternoon: colorful beaded friendship bracelets on everyone's wrists, a picnic blanket with little boxes of beads and string, wildflowers and soft golden light. Keep everyone's outfits from the photo. Match the lighting naturally. \(groupIdentityClause)",
            symbolName: "hands.and.sparkles", isNew: true
        ),
        PhotoTemplate(
            id: "trading-card", title: "Holo Card", subtitle: "A shiny holo card of you",
            category: .trending,
            prompt: "Turn the person in this photo into a shiny holographic collectible trading card: her portrait as glossy card art inside an ornate pastel frame with a rainbow foil shimmer and sparkles, the card standing on a desk in soft light. No text, numbers, logos or brand names. \(identityClause)",
            symbolName: "rectangle.portrait.on.rectangle.portrait.angled", isPro: true, isNew: true
        ),
        PhotoTemplate(
            id: "twinning", title: "Twinning", subtitle: "Matching fits, same vibe",
            category: .besties,
            prompt: "Give everyone in this photo matching outfits: cozy pastel-pink zip hoodies, with a soft pastel color grade and light film grain. Keep the background and each person's hairstyle and hair color. No logos or brand names. Keep natural skin texture, no skin smoothing. \(modestyClause) \(groupIdentityClause)",
            symbolName: "tshirt", isNew: true
        ),
        PhotoTemplate(
            id: "pet-party", title: "Pawty Time", subtitle: "Party hats & balloons",
            category: .pets,
            prompt: "Turn this into a cute birthday party for the pet: a tiny striped party hat, pastel balloons, paper bunting, confetti and a small pet-safe cake with one candle on the table. \(petClause) \(identityClause)",
            symbolName: "balloon.2", isNew: true
        ),
        PhotoTemplate(
            id: "manga", title: "Manga Panel", subtitle: "Ink, sparkles & screentone",
            category: .art,
            prompt: "Redraw this photo as a classic black-and-white manga panel with clean ink lines, soft screentone shading, sparkles and floating flowers around the people, and gentle speed lines in the background. Keep the composition and each person's recognizable features.",
            symbolName: "book.pages", isNew: true
        ),
        PhotoTemplate(
            id: "postcard", title: "Travel Postcard", subtitle: "Greetings from the seaside",
            category: .aesthetic,
            prompt: "Turn this photo into a vintage travel postcard: place the person on a sunny seaside promenade with pastel houses, a lighthouse and sailboats, inside a white deckled postcard border with a decorative stamp and a round postmark in the corner. No readable text. Match the lighting naturally. \(identityClause)",
            symbolName: "sailboat", isPro: true, isNew: true
        ),
        PhotoTemplate(
            id: "bow-era", title: "Bow Era", subtitle: "Ribbons, lace & pearls",
            category: .aesthetic,
            prompt: "Restyle the photo with a soft bow aesthetic: pink satin ribbon bows in her hair, a cream knit cardigan with a lace collar and pearl buttons, a pastel pink backdrop with little bows, soft daylight and light film grain. Keep her hairstyle and hair color; just add the bows. \(modestyClause) \(identityClause)",
            symbolName: "gift.fill", isNew: true
        ),
        PhotoTemplate(
            id: "sleepover", title: "Sleepover", subtitle: "Pillow fort & fairy lights",
            category: .besties,
            prompt: "Turn this into a cozy sleepover photo: a pillow fort with fairy lights, soft blankets, popcorn bowls, instant photos pinned to a string and a warm movie-night glow. Everyone wears matching long-sleeve pastel pajamas. Keep natural skin texture, no skin smoothing. \(modestyClause) \(groupIdentityClause)",
            symbolName: "tent", isNew: true
        ),
        PhotoTemplate(
            id: "plushie-pet", title: "Plushie Pet", subtitle: "Your pet, as a soft toy",
            category: .pets,
            prompt: "Turn the pet in this photo into a cute handmade stitched plush toy sitting on a cozy knitted blanket: soft fabric in the pet's real colors and markings, visible seams, embroidered details and a little ribbon collar. No logos, labels or brand names. \(petClause) \(identityClause)",
            symbolName: "pawprint.fill", isPro: true, isNew: true
        ),
        PhotoTemplate(
            id: "soft-film", title: "Soft Film", subtitle: "Dreamy 35mm snapshot",
            category: .aesthetic,
            prompt: "Make this look like a dreamy 35mm film snapshot: soft window light, a pastel color grade, gentle halation around the highlights, a faint light leak at the edge and fine grain. Keep the scene and the outfit unchanged. Keep natural skin texture, no skin smoothing. \(identityClause)",
            symbolName: "film", isNew: true
        ),
        // MARK: 1.1
        PhotoTemplate(
            id: "dslr-portrait", title: "DSLR Portrait", subtitle: "85mm lens, creamy bokeh",
            category: .dreamy,
            prompt: "Re-render this photo as if it was taken with a full-frame DSLR camera and an 85mm f/1.4 portrait lens: a creamy, softly blurred background with round bokeh, soft natural window light or gentle studio light, crisp focus on the eyes and natural skin texture, no skin smoothing. Keep the pose, framing, age and outfit unchanged. \(modestyClause) \(identityClause)",
            symbolName: "camera.fill", isNew: true
        ),

        // MARK: Local seasons (1.1)
        // Shown on Explore where each is celebrated (SeasonCalendar.swift).
        // Decorations, light and food only: she keeps her own outfit (or a
        // modest festive one), her hair and head covering, and her face.

        // Eid al-Fitr: Ramazan Bayramı, Lebaran
        PhotoTemplate(
            id: "eid-lanterns", title: "Lantern Glow", subtitle: "Festive lights & soft gold",
            category: .seasonal,
            prompt: "Turn this into a festive holiday-evening portrait: glowing brass lanterns with delicate geometric cutouts hanging around her, warm gold string lights, soft bokeh and a gentle golden glow. No writing. Keep her own outfit. \(headClause) Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "lamp.ceiling.fill", isNew: true, season: .eidAlFitr, keepsLikeness: true
        ),
        PhotoTemplate(
            id: "eid-sweets", title: "Festive Sweets", subtitle: "Cookies, candy & flowers",
            category: .seasonal,
            prompt: "Turn this into a bright festive-morning photo: a table with glass jars of holiday cookies, a bowl of colorful wrapped candies, a teapot with small tea glasses, fresh tulips and roses, and soft sunlight through lace curtains. Keep her own outfit. \(headClause) Match the lighting naturally. Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "cup.and.saucer.fill", isPro: true, isNew: true, season: .eidAlFitr, keepsLikeness: true
        ),

        // Eid al-Adha: Kurban Bayramı, Iduladha
        PhotoTemplate(
            id: "eid-courtyard", title: "Courtyard Lanterns", subtitle: "A golden-hour garden",
            category: .seasonal,
            prompt: "Place the person in an elegant courtyard at golden hour: hanging lanterns, patterned tiles, a small fountain, potted roses and jasmine, and warm, soft light. Keep her own outfit. \(headClause) Match the lighting naturally. Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "sun.horizon.fill", isNew: true, season: .eidAlAdha, keepsLikeness: true
        ),
        PhotoTemplate(
            id: "eid-florals", title: "Festive Florals", subtitle: "Fresh flowers & soft gold",
            category: .seasonal,
            prompt: "Turn this into a soft festive portrait framed by fresh flowers in cream, soft pink and gold, with gentle golden light, a few floating sparkles and a warm, elegant color grade. Keep her own outfit. \(headClause) Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "camera.macro", isPro: true, isNew: true, season: .eidAlAdha, keepsLikeness: true
        ),

        // Lunar New Year: Seollal, Spring Festival
        PhotoTemplate(
            id: "lunar-lanterns", title: "Lantern Night", subtitle: "Red & gold lanterns",
            category: .seasonal,
            prompt: "Turn this into a festive Lunar New Year evening photo: rows of glowing red-and-gold paper lanterns overhead, soft fireworks in the night sky, warm bokeh and a rich red-and-gold color grade. No writing on the lanterns. Keep her own outfit, or give her a modest festive outfit in red and gold. \(headClause) Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "fireworks", isNew: true, season: .lunarNewYear, keepsLikeness: true
        ),
        PhotoTemplate(
            id: "plum-blossom", title: "Plum Blossom", subtitle: "Spring blooms in red & gold",
            category: .seasonal,
            prompt: "Place the person beside branches of blooming pink and white plum blossoms on a bright, crisp morning, with red paper-cut decorations and gold sparkles softly out of focus and gentle light. No writing. Keep her own outfit. \(headClause) Match the lighting naturally. Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "camera.macro", isPro: true, isNew: true, season: .lunarNewYear, keepsLikeness: true
        ),

        // Chuseok
        PhotoTemplate(
            id: "harvest-moon", title: "Harvest Moon", subtitle: "A big glowing full moon",
            category: .seasonal,
            prompt: "Turn this into an autumn evening photo under a huge glowing full moon over soft hills, with warm paper lanterns, silver grass and a soft palette of jade green, coral pink and golden yellow. Keep her own outfit. \(headClause) Match the lighting naturally. Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "moon.fill", isNew: true, season: .chuseok, keepsLikeness: true
        ),
        PhotoTemplate(
            id: "persimmon", title: "Persimmon Autumn", subtitle: "Ripe fruit & warm light",
            category: .seasonal,
            prompt: "Place the person in a sunny autumn courtyard beside a persimmon tree heavy with ripe orange fruit, with a plate of colorful half-moon rice cakes on a low wooden table and warm afternoon light. Keep her own outfit. \(headClause) Match the lighting naturally. Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "leaf.fill", isPro: true, isNew: true, season: .chuseok, keepsLikeness: true
        ),

        // Hanami
        PhotoTemplate(
            id: "hanami-picnic", title: "Hanami Picnic", subtitle: "A picnic under the blossoms",
            category: .seasonal,
            prompt: "Turn this into a sunny hanami picnic under blooming cherry blossom trees: a picnic blanket, a bento box, pink, white and green sweet dumplings on skewers, a flask of tea and petals drifting in the air. No alcohol. Keep her own outfit. \(headClause) Match the lighting naturally. Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "basket.fill", isNew: true, season: .hanami, keepsLikeness: true
        ),
        PhotoTemplate(
            id: "sakura-night", title: "Sakura Night", subtitle: "Blossoms by lantern light",
            category: .seasonal,
            prompt: "Turn this into a night cherry-blossom photo: blossoms lit by soft paper lanterns, petals drifting in the air, glowing reflections on a quiet river and a dreamy pink-and-navy color grade. No writing on the lanterns. Keep her own outfit. \(headClause) Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "moon.stars.fill", isPro: true, isNew: true, season: .hanami, keepsLikeness: true
        ),

        // Tanabata
        PhotoTemplate(
            id: "tanabata-wishes", title: "Star Wishes", subtitle: "Bamboo & paper wishes",
            category: .seasonal,
            prompt: "Turn this into a summer-evening Tanabata photo: tall bamboo branches hung with colorful paper wish strips and paper streamers, a starry sky with the Milky Way and soft lantern light. No readable writing. Keep her own outfit. \(headClause) Match the lighting naturally. Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "star.fill", isNew: true, season: .tanabata, keepsLikeness: true
        ),
        PhotoTemplate(
            id: "milky-way", title: "Milky Way", subtitle: "Under a river of stars",
            category: .seasonal,
            prompt: "Turn this into a dreamy night portrait under a bright Milky Way: twinkling stars, a few soft shooting stars, a gentle blue-violet glow and tiny star sparkles in the air. Keep her own outfit and pose. \(headClause) Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "sparkles", isPro: true, isNew: true, season: .tanabata, keepsLikeness: true
        ),

        // Carnaval
        PhotoTemplate(
            id: "carnaval-confetti", title: "Carnaval Confetti", subtitle: "Streamers & street party",
            category: .seasonal,
            prompt: "Place the person at a sunny daytime street carnival: clouds of colorful confetti and paper streamers, bright flags and balloons, glitter sparkling in the air and a joyful, vivid color grade. Keep her own outfit, or give her a modest, colorful festival outfit. No alcohol. \(headClause) Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "party.popper.fill", isNew: true, season: .carnaval, keepsLikeness: true
        ),
        PhotoTemplate(
            id: "carnaval-mask", title: "Mask & Glitter", subtitle: "A sparkly carnival mask",
            category: .seasonal,
            prompt: "Turn this into a festive carnival portrait: she holds a sparkly, colorful feathered carnival mask beside her face, with confetti, glitter and bright party lights behind her. Her face stays fully visible. Keep her own outfit. \(headClause) Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "theatermasks.fill", isPro: true, isNew: true, season: .carnaval, keepsLikeness: true
        ),

        // Festa Junina
        PhotoTemplate(
            id: "festa-junina", title: "Arraiá Night", subtitle: "Paper flags & bonfire glow",
            category: .seasonal,
            prompt: "Turn this into a festa junina night: strings of colorful little paper flags overhead, warm string lights, a glowing bonfire at a safe distance in the background and a cheerful country-fair feel. Keep her own outfit. \(headClause) Match the lighting naturally. Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "flame.fill", isNew: true, season: .festaJunina, keepsLikeness: true
        ),
        PhotoTemplate(
            id: "junina-sweets", title: "June Sweets", subtitle: "Corn cake, popcorn & candy apples",
            category: .seasonal,
            prompt: "Place the person at a cozy festa junina sweets stand: corn cake, popcorn in paper cones, shiny red candy apples, peanut sweets, colorful little paper flags and warm string lights. No alcohol. Keep her own outfit. \(headClause) Match the lighting naturally. Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "popcorn.fill", isPro: true, isNew: true, season: .festaJunina, keepsLikeness: true
        ),

        // Día de Muertos: decorations only, never skull face paint
        PhotoTemplate(
            id: "marigold-glow", title: "Marigold Glow", subtitle: "Cempasúchil & candlelight",
            category: .seasonal,
            prompt: "Turn this into a warm Día de Muertos evening portrait: bright orange marigold flowers all around, glowing candles, rows of colorful papel picado banners overhead and soft golden light. Decorations only: her face stays exactly as it is, with no face paint. No readable writing. Keep her own outfit. \(headClause) Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "camera.macro", isNew: true, season: .diaDeMuertos, keepsLikeness: true
        ),
        PhotoTemplate(
            id: "papel-picado", title: "Papel Picado", subtitle: "Paper banners & marigolds",
            category: .seasonal,
            prompt: "Place the person on a sunny festive street decorated with rows of colorful papel picado banners, marigold garlands and brightly painted walls. Decorations only: her face stays exactly as it is, with no face paint. No readable writing. Keep her own outfit. \(headClause) Match the lighting naturally. Keep natural skin texture, no skin smoothing. \(modestyClause) \(identityClause)",
            symbolName: "flag.fill", isPro: true, isNew: true, season: .diaDeMuertos, keepsLikeness: true
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

    // MARK: Seasons

    /// Seasonal looks are available during their season where she is; every
    /// other look all year.
    public static func isAvailable(
        _ template: PhotoTemplate, on date: Date, for audience: SeasonAudience = .everyone, calendar: Calendar = .current
    ) -> Bool {
        template.season?.isActive(on: date, for: audience, calendar: calendar) ?? true
    }

    public static func available(on date: Date, for audience: SeasonAudience = .everyone, calendar: Calendar = .current) -> [PhotoTemplate] {
        all.filter { isAvailable($0, on: date, for: audience, calendar: calendar) }
    }

    /// The looks a Home row shows on a given day.
    public static func templates(
        in category: TemplateCategory, on date: Date, for audience: SeasonAudience = .everyone, calendar: Calendar = .current
    ) -> [PhotoTemplate] {
        templates(in: category).filter { isAvailable($0, on: date, for: audience, calendar: calendar) }
    }

    /// Home rows on a given day, skipping empty ones (the seasonal row is off
    /// between seasons).
    public static func categories(on date: Date, for audience: SeasonAudience = .everyone, calendar: Calendar = .current) -> [TemplateCategory] {
        TemplateCategory.allCases.filter { !templates(in: $0, on: date, for: audience, calendar: calendar).isEmpty }
    }

    /// Every look for the editor: the looks of the seasons on for her come
    /// first (the leading season's first), and every other seasonal look
    /// last, but none is ever locked away.
    public static func editorOrder(on date: Date, for audience: SeasonAudience = .everyone, calendar: Calendar = .current) -> [PhotoTemplate] {
        let active = SeasonalTheme.active(on: date, for: audience, calendar: calendar)
        let inSeason = active.flatMap { theme in all.filter { $0.season == theme } }
        let yearRound = all.filter { $0.season == nil }
        let outOfSeason = all.filter { $0.season.map { !active.contains($0) } ?? false }
        return inSeason + yearRound + outOfSeason
    }
}
