import Foundation

// Explore's "Describe your vibe": she says the occasion or the mood ("birthday
// picnic by the sea"), and up to three things the app already has come back,
// each opening in one tap. Aybik (the server's writing help, task `looks`)
// picks them by id from catalog.json's "finder" when she may use it; on the
// device, and under 13, a keyword match over the catalog's names in her
// language does. Nothing here ranks or talks about how anyone looks.

public enum LookFinder {
    /// What a pick is, as the contract spells it.
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// A one-tap look (`PhotoTemplate`).
        case look
        /// A Create style (`ImageStyle`, never Auto).
        case style
        /// A free retro effect in the editor (the app's `RetroEffect`).
        case effect
        /// An Enhance option (`EnhanceOption`).
        case enhance
        /// A Glow look in Retro Cam (Natural or one of `GlowCam.vibeIDs`).
        case glow
    }

    /// One pick: what it is, and a line in her language about why.
    public struct Pick: Decodable, Equatable, Sendable {
        public var kind: Kind
        public var id: String
        public var reason: String

        public init(kind: Kind, id: String, reason: String) {
            self.kind = kind
            self.id = id
            self.reason = reason
        }

        /// `kind:id`, unique across kinds (a look and a style can share an id).
        public var key: String { "\(kind.rawValue):\(id)" }
    }

    /// `{ "picks": [...] }`, leaving out picks this version can't read.
    struct Reply: Decodable {
        let picks: [Pick]

        private struct Lossy: Decodable {
            let pick: Pick?

            init(from decoder: Decoder) throws {
                pick = try? Pick(from: decoder)
            }
        }

        enum CodingKeys: String, CodingKey { case picks }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            picks = try container.decode([Lossy].self, forKey: .picks).compactMap(\.pick)
        }
    }

    /// The most picks she sees.
    public static let maxPicks = 3
    /// A reason's length, in characters (the server's limit).
    public static let maxReasonLength = 100

    // MARK: The catalog

    /// The editor's retro effects the finder knows (catalog.json's
    /// `finder.effects`; `RetroEffect` itself lives in the app). Glamour '92
    /// is left out, as "Ideas for this photo" leaves it out.
    public static let effects: [(id: String, about: String)] = [
        ("vhs", about("An 80s home-video tape look with a date stamp")),
        ("disposable", about("A 90s disposable film camera with flash and a date stamp")),
        ("kira", about("Sparkles and glints over your photo")),
        ("digicam", about("A Y2K pocket digital camera with a date stamp")),
        ("instant", about("An 80s instant film print")),
        ("neon", about("An 80s neon glow for nights and city lights")),
        ("throwback16", about("A 2016 phone photo with an optional white border")),
        ("camcorder06", about("A 2006 camcorder with its REC display")),
        ("toyCam", about("A 2009 toy camera with cross-processed color")),
        ("rainbow", about("2017's rainbow prism light")),
        ("dslr12", about("A 2012 DSLR look with soft, round bokeh behind you")),
        ("filmStill", about("A movie frame with letterbox bars and a subtitle")),
        ("tinyWorld", about("Tilt-shift that turns wide views into a tiny model world")),
    ]

    /// Retro Cam's Glow looks: Natural, then `GlowCam.vibeIDs`.
    public static let glowLooks: [(id: String, about: String)] = [
        ("natural", about("Clean, natural light in Retro Cam")),
        ("dreamy", about("A soft, dreamy glow in Retro Cam")),
        ("golden", about("Warm golden-hour light in Retro Cam")),
        ("analog", about("Faded film color with grain in Retro Cam")),
        ("moody", about("Deeper shadows and a moody grade in Retro Cam")),
    ]

    /// The line under a Create style found on the device.
    public static let styleAbout = about("A style for a new picture made from your words")

    /// Ids of `kind` this version can open.
    public static func ids(of kind: Kind) -> Set<String> {
        switch kind {
        case .look: return Set(TemplateCatalog.all.map(\.id))
        case .style: return Set(StyleCatalog.all.filter { $0 != StyleCatalog.auto }.map(\.id))
        case .effect: return Set(effects.map(\.id))
        case .enhance: return Set(EnhanceOption.allCases.map(\.rawValue))
        case .glow: return Set(glowLooks.map(\.id))
        }
    }

    /// The server's picks the app can show: of the kinds she can use and
    /// that `isAvailable` allows (an effect this build has), known ids only,
    /// each once, with a reason that passes the photo rules on the device
    /// too (a pick whose reason doesn't is dropped, as the server drops it),
    /// at most `maxPicks`.
    public static func usable(_ picks: [Pick], kinds: Set<Kind>, isAvailable: (Pick) -> Bool = { _ in true }) -> [Pick] {
        var seen = Set<String>()
        var kept: [Pick] = []
        for pick in picks where kept.count < maxPicks {
            guard kinds.contains(pick.kind), ids(of: pick.kind).contains(pick.id), isAvailable(pick),
                  let reason = Assist.screenedShown([pick.reason], maxLength: maxReasonLength, limit: 1).first,
                  seen.insert(pick.key).inserted else { continue }
            kept.append(Pick(kind: pick.kind, id: pick.id, reason: reason))
        }
        return kept
    }

    // MARK: On the device

    /// One thing the device can match her words against.
    public struct Item: Equatable, Sendable {
        public var kind: Kind
        public var id: String
        /// Its name, as the app shows it.
        public var name: String
        /// One line about it, as the app shows it: the reason when it's picked here.
        public var about: String
        /// More words to match: its English name and line, its collection.
        public var words: [String]
        public var isPro: Bool

        public init(kind: Kind, id: String, name: String, about: String, words: [String] = [], isPro: Bool = false) {
            self.kind = kind
            self.id = id
            self.name = name
            self.about = about
            self.words = words
            self.isPro = isPro
        }

        public var key: String { "\(kind.rawValue):\(id)" }

        public var pick: Pick { Pick(kind: kind, id: id, reason: about) }
    }

    /// The catalog she can use, named in her language: `localize` translates
    /// AppCore's English (`L10n.core` in the app), `effectName` names an
    /// effect this build has (nil leaves it out), and `enhance` names an
    /// Enhance option she may use, with its line.
    public static func items(
        kinds: Set<Kind>, localize: (String) -> String, effectName: (String) -> String?,
        enhance: (EnhanceOption) -> (name: String, about: String)?, on date: Date = Date()
    ) -> [Item] {
        var items: [Item] = []
        if kinds.contains(.look) {
            for template in TemplateCatalog.all {
                let collection = template.category.title
                items.append(Item(kind: .look, id: template.id, name: localize(template.title), about: localize(template.subtitle),
                                  words: [template.title, template.subtitle, collection, localize(collection)], isPro: template.isPro))
            }
        }
        if kinds.contains(.style) {
            for style in StyleCatalog.all where style != StyleCatalog.auto {
                items.append(Item(kind: .style, id: style.id, name: localize(style.name), about: localize(styleAbout),
                                  words: [style.name], isPro: style.isPro))
            }
        }
        if kinds.contains(.effect) {
            for effect in effects {
                guard let name = effectName(effect.id) else { continue }
                items.append(Item(kind: .effect, id: effect.id, name: name, about: localize(effect.about), words: [effect.about]))
            }
        }
        if kinds.contains(.enhance) {
            for option in EnhanceOption.allCases {
                guard let words = enhance(option) else { continue }
                items.append(Item(kind: .enhance, id: option.rawValue, name: words.name, about: words.about))
            }
        }
        if kinds.contains(.glow) {
            for look in glowLooks {
                let english = look.id == "natural" ? "Natural" : AdjustVibes.preset(id: look.id)?.name ?? look.id
                items.append(Item(kind: .glow, id: look.id, name: localize(english), about: localize(look.about),
                                  words: [english, look.about, "Glow"]))
            }
        }
        return items
    }

    /// Up to `limit` items whose words match hers, best first: a word of hers
    /// that is (or starts, or shares a stem with) a word of the item's name
    /// counts most, one in its line or collection less; in Chinese, Japanese
    /// and Korean, shared pairs of characters count. At most `perKind` of a
    /// kind, so a vibe gets a mix; free before Pro on a tie. Empty when nothing matches.
    public static func localMatches(for text: String, in items: [Item], limit: Int = maxPicks, perKind: Int = 2) -> [Item] {
        let hers = Words(fold(text))
        guard !hers.isEmpty else { return [] }
        let folded = fold(text)
        var scored: [(item: Item, score: Int, index: Int)] = []
        for (index, item) in items.enumerated() {
            let name = Words(fold(item.name))
            let other = Words(fold(([item.about] + item.words).joined(separator: " ")))
            var score = 0
            for word in hers.tokens {
                if name.tokens.contains(where: { matches(word, $0) }) {
                    score += 3
                } else if other.tokens.contains(where: { matches(word, $0) }) {
                    score += 1
                }
            }
            score += min(6, 2 * hers.pairs.intersection(name.pairs).count + hers.pairs.intersection(other.pairs).count)
            let wholeName = fold(item.name).trimmingCharacters(in: .whitespaces)
            if wholeName.count >= 3, folded.contains(wholeName) { score += 3 }
            if score > 0 { scored.append((item, score, index)) }
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.item.isPro != rhs.item.isPro { return !lhs.item.isPro }
            return lhs.index < rhs.index
        }
        var kinds: [Kind: Int] = [:]
        var kept: [Item] = []
        for entry in scored where kept.count < limit {
            guard kinds[entry.item.kind, default: 0] < perKind else { continue }
            kinds[entry.item.kind, default: 0] += 1
            kept.append(entry.item)
        }
        return kept
    }

    /// Favorites to start with when nothing matched: the first free look,
    /// Disposable '98, Dreamy in Retro Cam, Digicam '04 and Quick fix,
    /// whichever she can use, `limit` at most.
    public static func favorites(in items: [Item], limit: Int = maxPicks) -> [Item] {
        let firstLook = items.first { $0.kind == .look && !$0.isPro }?.key
        let order = [firstLook, "effect:disposable", "glow:dreamy", "effect:digicam", "enhance:quickFix"].compactMap { $0 }
        return order.compactMap { key in items.first { $0.key == key } }.prefix(limit).map { $0 }
    }

    // MARK: Words

    /// Case, accents and width folded, so "Café" and "cafe" match.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
    }

    /// Her word and a catalog word are the same word: equal, hers starts
    /// theirs ("sea" in "seaside"), or they share a stem of four letters
    /// or more that leaves at most two letters of the shorter one ("pikniği", "piknik").
    static func matches(_ hers: String, _ theirs: String) -> Bool {
        if hers == theirs { return true }
        if hers.count >= 3, theirs.hasPrefix(hers) { return true }
        let shorter = min(hers.count, theirs.count)
        guard shorter >= 4 else { return false }
        let shared = zip(hers, theirs).prefix { $0 == $1 }.count
        return shared >= max(4, shorter - 2)
    }

    /// Words with spaces between them, and pairs of characters for scripts written without.
    struct Words {
        var tokens: [String] = []
        var pairs: Set<String> = []

        init(_ folded: String) {
            var current = ""
            var dense: [Character] = []
            func endWord() {
                if !current.isEmpty, current.count >= 3 || current.contains(where: \.isNumber) && current.count >= 2,
                   !LookFinder.stopWords.contains(current) {
                    tokens.append(current)
                }
                current = ""
            }
            func endDense() {
                if dense.count >= 2 {
                    for index in 0..<(dense.count - 1) {
                        let pair = [dense[index], dense[index + 1]]
                        // A kana particle (の, に, を…) doesn't make a word.
                        if pair.contains(where: LookFinder.isHiragana) { continue }
                        pairs.insert(String(pair))
                    }
                }
                dense = []
            }
            for character in folded {
                if LookFinder.isDense(character) {
                    endWord()
                    dense.append(character)
                } else if character.isLetter || character.isNumber {
                    endDense()
                    current.append(character)
                } else {
                    endWord()
                    endDense()
                }
            }
            endWord()
            endDense()
        }

        var isEmpty: Bool { tokens.isEmpty && pairs.isEmpty }
    }

    /// Han, kana and Hangul: matched by pairs of characters.
    static func isDense(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F:
            return true
        default:
            return false
        }
    }

    static func isHiragana(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return (0x3040...0x309F).contains(scalar.value)
    }

    /// Small words that say nothing about a vibe, in the app's languages.
    static let stopWords: Set<String> = [
        "the", "and", "with", "for", "you", "your", "this", "that", "from", "into", "like", "look", "looks", "photo",
        "picture", "pic", "vibe", "vibes", "style", "some", "very", "just", "want", "make", "something",
        "bir", "ile", "icin", "gibi", "olan", "cok", "biraz",
        "con", "para", "una", "uno", "del", "los", "las", "por", "que", "como", "muy",
        "com", "uma", "dos", "das", "num", "numa", "pra",
        "avec", "pour", "une", "des", "les", "dans", "sur", "aux",
        "mit", "und", "fur", "ein", "eine", "einem", "einen", "der", "die", "das", "den", "dem", "auf", "zum", "zur",
        "per", "della", "delle", "degli", "nel", "nella", "alla",
        "для", "как", "это", "или", "мне", "под", "при",
        "dan", "yang", "untuk", "dengan", "saya", "di", "ke",
    ]

    /// Marks a line for scripts/export-core-strings.py.
    static func about(_ english: String) -> String { english }
}
