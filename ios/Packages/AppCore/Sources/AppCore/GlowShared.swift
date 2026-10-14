import Foundation
#if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

// Types shared by the app and the GlowlitWidgets extension (Home and Lock
// Screen widgets, the generation Live Activity in the Dynamic Island).

// MARK: - Deep links

/// `glowlit://…` links opened from widgets, Control Center controls and
/// Live Activities.
public enum GlowDeepLink: Equatable, Sendable {
    case magicEdit
    case create
    case removeBackground
    case effects
    case video
    case template(String)
    case library
    /// Retro Cam, and Retro Cam already in Photo Booth mode.
    case retroCam
    case photoBooth
    case collage

    public static let scheme = "glowlit"

    public var url: URL {
        switch self {
        case .magicEdit: return URL(string: "\(Self.scheme)://edit/magic")!
        case .create: return URL(string: "\(Self.scheme)://create")!
        case .removeBackground: return URL(string: "\(Self.scheme)://edit/remove-background")!
        case .effects: return URL(string: "\(Self.scheme)://edit/effects")!
        case .video: return URL(string: "\(Self.scheme)://video")!
        case .template(let id): return URL(string: "\(Self.scheme)://template/\(id)")!
        case .library: return URL(string: "\(Self.scheme)://library")!
        case .retroCam: return URL(string: "\(Self.scheme)://camera")!
        case .photoBooth: return URL(string: "\(Self.scheme)://camera/booth")!
        case .collage: return URL(string: "\(Self.scheme)://collage")!
        }
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host?.lowercased() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        switch (host, path.first) {
        case ("edit", "magic"?): self = .magicEdit
        case ("edit", "remove-background"?): self = .removeBackground
        case ("edit", "effects"?): self = .effects
        case ("video", nil): self = .video
        case ("create", nil): self = .create
        case ("library", nil): self = .library
        case ("camera", nil): self = .retroCam
        case ("camera", "booth"?): self = .photoBooth
        case ("collage", nil): self = .collage
        case ("template", let id?) where TemplateCatalog.template(id: id) != nil: self = .template(id)
        default: return nil
        }
    }
}

// MARK: - Trend of the day

extension TemplateCatalog {
    /// Looks the trend widget and the Friday push may feature: trending,
    /// aesthetic and art looks, never makeup "glow-ups" or out-of-season
    /// ones, and only free looks unless she's Pro (a push shouldn't lead to
    /// the paywall).
    public static func pushPool(isPro: Bool) -> [PhotoTemplate] {
        all.filter {
            [.trending, .aesthetic, .art].contains($0.category) && $0.season == nil && (isPro || !$0.isPro)
        }
    }

    /// One look per calendar day from `pushPool`, so the widget and the app
    /// agree on "today's" trend without any network call.
    public static func trendOfTheDay(on date: Date = Date(), isPro: Bool = false, calendar: Calendar = .current) -> PhotoTemplate {
        let pool = pushPool(isPro: isPro)
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return pool[day % pool.count]
    }
}

// MARK: - Widget snapshot (written by the app, read by the widgets)

public struct GlowWidgetSnapshot: Codable, Equatable, Sendable {
    public var credits: Int
    public var isPro: Bool
    /// When free daily credits refill next (nil for Pro).
    public var nextRefill: Date?
    public var latestTitle: String?
    public var latestIsFavorite: Bool
    public var creationsCount: Int
    public var updatedAt: Date
    /// Where `credits` comes from. Optional, so snapshots written by older
    /// versions still decode; nil when unknown (the server keeps the split).
    public var daily: Int?
    public var monthly: Int?
    public var packs: Int?
    /// When Pro's monthly credits arrive next, when known.
    public var nextGrant: Date?
    /// False under 13 (her age band): widgets and controls offer only the
    /// free on-device tools. Nil in older snapshots, read as allowed.
    public var cloudAIAllowed: Bool?

    /// Widgets and controls show cloud AI entry points (and credits).
    public var showsCloudAI: Bool { cloudAIAllowed ?? true }

    public init(
        credits: Int, isPro: Bool, nextRefill: Date?, latestTitle: String?,
        latestIsFavorite: Bool = false, creationsCount: Int, updatedAt: Date = Date(),
        daily: Int? = nil, monthly: Int? = nil, packs: Int? = nil, nextGrant: Date? = nil,
        cloudAIAllowed: Bool? = nil
    ) {
        self.credits = credits
        self.isPro = isPro
        self.nextRefill = nextRefill
        self.latestTitle = latestTitle
        self.latestIsFavorite = latestIsFavorite
        self.creationsCount = creationsCount
        self.updatedAt = updatedAt
        self.daily = daily
        self.monthly = monthly
        self.packs = packs
        self.nextGrant = nextGrant
        self.cloudAIAllowed = cloudAIAllowed
    }

    public enum BalanceKind: Sendable {
        /// Only today's free credits.
        case daily
        /// Only Pro's monthly credits.
        case monthly
        /// Packs, a mix, or an unknown split: say just "credits".
        case mixed
    }

    public var balanceKind: BalanceKind {
        guard let daily, let monthly, let packs, packs == 0 else { return .mixed }
        if !isPro, monthly == 0 { return .daily }
        if isPro, daily == 0 { return .monthly }
        return .mixed
    }

    /// The gauge's range: one day's or one month's allowance (never "∞").
    /// Rollover and packs can exceed it, so clamp the value with `gaugeValue`.
    public func gaugeRange(policy: CreditPolicy = .standard) -> ClosedRange<Int> {
        0...max(1, isPro ? policy.proMonthlyAllowance : policy.freeDailyAllowance)
    }

    public func gaugeValue(policy: CreditPolicy = .standard) -> Int {
        min(max(0, credits), gaugeRange(policy: policy).upperBound)
    }

    public static let placeholder = GlowWidgetSnapshot(
        credits: 3, isPro: false, nextRefill: nil, latestTitle: nil, creationsCount: 0
    )
}

/// The App Group container both targets can read. Without the entitlement
/// (e.g. unsigned CI builds) every call degrades to "no data".
public enum GlowSharedStore {
    public static let appGroup = "group.app.glowlit.shared"
    static let snapshotFile = "widget-snapshot.json"
    static let latestImageFile = "latest-creation.jpg"

    public static var containerURL: URL? {
        #if canImport(Darwin)
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        #else
        return nil
        #endif
    }

    public static var latestImageURL: URL? {
        containerURL?.appendingPathComponent(latestImageFile)
    }

    public static func save(_ snapshot: GlowWidgetSnapshot, in directory: URL? = containerURL) {
        guard let directory, let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: directory.appendingPathComponent(snapshotFile), options: .atomic)
    }

    public static func load(from directory: URL? = containerURL) -> GlowWidgetSnapshot? {
        guard let directory, let data = try? Data(contentsOf: directory.appendingPathComponent(snapshotFile)) else { return nil }
        return try? decoder.decode(GlowWidgetSnapshot.self, from: data)
    }

    /// Small JPEG of the newest creation for the "My glow" widget (nil removes it).
    public static func saveLatestImage(_ jpeg: Data?, in directory: URL? = containerURL) {
        guard let directory else { return }
        let url = directory.appendingPathComponent(latestImageFile)
        if let jpeg {
            try? jpeg.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Live Activity (Dynamic Island)

/// Progress of one cloud AI job, shown in the Dynamic Island and on the Lock
/// Screen while the user waits (or switches apps). The text is English; the
/// widget extension translates it with `L10n.core(_:)` (registered by
/// `scripts/export-core-strings.py`).
public enum GlowJobStage: String, Codable, Hashable, Sendable {
    case creating
    case finishing
    case ready
    case failed

    public var headline: String {
        switch self {
        case .creating: return "Creating your glow…"
        case .finishing: return "Adding the final sparkle…"
        case .ready: return "Your glow-up is ready"
        case .failed: return "That one didn't work"
        }
    }

    public var detail: String {
        switch self {
        case .creating, .finishing: return "You can leave the app — we'll keep going."
        case .ready: return "Tap to see it ✨"
        // True whether the server refunded at once or will refund a result
        // that never reached the app.
        case .failed: return "Failed creations are refunded automatically. Tap to try again."
        }
    }
}

extension String {
    /// Shortens text to at most `limit` characters at a word boundary, ending
    /// with "…" — for Live Activity titles, where a prompt is often too long.
    public func shortened(to limit: Int) -> String {
        let text = components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard limit > 1, text.count > limit else { return text }
        let head = text.prefix(limit - 1)
        var cut = head
        if let space = head.lastIndex(of: " "), head.distance(from: head.startIndex, to: space) >= limit / 2 {
            cut = head[..<space]
        }
        while let last = cut.last, last.isWhitespace || last.isPunctuation {
            cut = cut.dropLast()
        }
        return (cut.isEmpty ? head : cut) + "…"
    }
}

// Live Activities are iPhone and iPad only: ActivityKit is unavailable in Mac Catalyst.
#if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
public struct GlowActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var stage: GlowJobStage
        public var startedAt: Date
        /// Expected finish time, used for the self-animating progress bar.
        public var expectedEnd: Date

        public init(stage: GlowJobStage, startedAt: Date, expectedEnd: Date) {
            self.stage = stage
            self.startedAt = startedAt
            self.expectedEnd = expectedEnd
        }
    }

    /// "Pink Hair", "Magic Edit"…
    public var title: String
    /// SF Symbol of the tool or template.
    public var symbolName: String

    public init(title: String, symbolName: String) {
        self.title = title
        self.symbolName = symbolName
    }
}
#endif
