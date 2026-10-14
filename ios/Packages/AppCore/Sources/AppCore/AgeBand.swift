import Foundation

/// An age range, never a birthdate: Apple's Declared Age Range answer or the
/// neutral month-and-year question, mapped to the gates that change what the
/// app offers (13, 16, 18). It stays on the device.
public enum AgeBand: String, Codable, CaseIterable, Sendable {
    case under13
    case teen13to15
    case teen16to17
    case adult
    /// Not answered yet, or the answer can't be relied on.
    case unknown

    /// The youngest age in the band; nil when unknown.
    public var minimumAge: Int? {
        switch self {
        case .under13: return 0
        case .teen13to15: return 13
        case .teen16to17: return 16
        case .adult: return 18
        case .unknown: return nil
        }
    }

    public init(age: Int) {
        switch age {
        case ..<13: self = .under13
        case 13..<16: self = .teen13to15
        case 16..<18: self = .teen16to17
        default: self = .adult
        }
    }

    /// Apple's answer, mapped by its lower bound. Apple may return ranges
    /// other than the gates asked for, so when unsure this picks the younger
    /// band; no lower bound means under 13.
    public init(appleLowerBound lowerBound: Int?) {
        self = lowerBound.map(AgeBand.init(age:)) ?? .under13
    }

    /// From a birth month (1–12) and year, assuming the birthday is as late as
    /// possible (the youngest possible age), so a birthday later this month
    /// hasn't happened yet. The date itself is never kept.
    public init(birthMonth: Int, birthYear: Int, now: Date, calendar: Calendar = Calendar(identifier: .gregorian)) {
        let today = calendar.dateComponents([.year, .month], from: now)
        var age = (today.year ?? birthYear) - birthYear
        if (today.month ?? 1) <= birthMonth { age -= 1 }
        self.init(age: age)
    }

    /// Bands in order, youngest first (unknown has no place in it).
    var rank: Int? {
        switch self {
        case .under13: return 0
        case .teen13to15: return 1
        case .teen16to17: return 2
        case .adult: return 3
        case .unknown: return nil
        }
    }
}

/// Where an age band came from.
public enum AgeSource: String, Codable, Sendable {
    /// Apple's Declared Age Range, confirmed or declared by a guardian.
    case apple
    /// Apple's Declared Age Range, declared by the person herself.
    case appleSelfDeclared
    /// The app's own month-and-year question.
    case selfDeclared
    /// She declined to share her age range where the law requires it.
    case declined

    public var isSelfDeclared: Bool { self == .appleSelfDeclared || self == .selfDeclared }
    public var isApple: Bool { self == .apple || self == .appleSelfDeclared }
}

/// The stored answer: band, source and when it was set. Nothing else.
public struct AgeRecord: Codable, Equatable, Sendable {
    public var band: AgeBand
    public var source: AgeSource
    public var setAt: Date

    public init(band: AgeBand, source: AgeSource, setAt: Date) {
        self.band = band
        self.source = source
        self.setAt = setAt
    }

    /// How long a self-declared band stays before it may be raised again.
    public static let raiseInterval: TimeInterval = 365 * 24 * 3600

    /// Whether `new` may replace this answer. A younger band and Apple's
    /// answer always may; a self-declared older band only after a year, so the
    /// question can't simply be answered again until it unlocks more.
    public func accepts(_ new: AgeRecord) -> Bool {
        guard let newRank = new.band.rank else { return band == .unknown }
        guard let rank = band.rank else { return true }
        if new.source.isApple || newRank <= rank { return true }
        return new.setAt.timeIntervalSince(setAt) >= Self.raiseInterval
    }
}

/// What the app offers for an age band.
public struct AgeDefaults: Equatable, Sendable {
    /// Cloud AI features (and so their consent sheet).
    public var allowsCloudAI: Bool
    /// Purchases, the paywall, accounts and subscription analytics.
    public var allowsPurchases: Bool
    /// The paywall opens by itself after onboarding (adults only).
    public var autoPaywall: Bool
    /// The consent sheet asks her to read it with a parent or guardian.
    public var requiresGuardianStep: Bool

    /// Age of digital consent where it's above 13 (GDPR Art. 8 and similar
    /// laws; Türkiye per our policy), by StoreKit's three-letter storefront
    /// code. To be completed with counsel.
    public static let digitalConsentAge: [String: Int] = [
        "DEU": 16, "NLD": 16, "IRL": 16, "POL": 16,
        "FRA": 15,
        "ESP": 14, "ITA": 14, "AUT": 14, "KOR": 14,
        "TUR": 18,
    ]

    /// Storefronts where a self-declared age isn't enough for anything beyond
    /// the protective defaults (Brazil's ECA Digital). Counsel to confirm.
    public static let selfDeclarationNotAccepted: Set<String> = ["BRA"]

    public init(allowsCloudAI: Bool, allowsPurchases: Bool, autoPaywall: Bool, requiresGuardianStep: Bool) {
        self.allowsCloudAI = allowsCloudAI
        self.allowsPurchases = allowsPurchases
        self.autoPaywall = autoPaywall
        self.requiresGuardianStep = requiresGuardianStep
    }

    /// `record` nil means the question hasn't been answered yet: protective
    /// defaults until it is.
    public init(record: AgeRecord?, storefrontCountry: String?) {
        let country = storefrontCountry?.uppercased()
        var band = record?.band ?? .unknown
        if let record, let country, Self.selfDeclarationNotAccepted.contains(country),
           record.source.isSelfDeclared, band != .under13 {
            band = .unknown
        }
        if record?.source == .declined {
            self.init(allowsCloudAI: false, allowsPurchases: false, autoPaywall: false, requiresGuardianStep: true)
            return
        }
        let consentAge = country.flatMap { Self.digitalConsentAge[$0] } ?? 13
        switch band {
        case .under13:
            self.init(allowsCloudAI: false, allowsPurchases: false, autoPaywall: false, requiresGuardianStep: true)
        case .teen13to15, .teen16to17:
            let guardian = band == .teen13to15 || (band.minimumAge ?? 0) < consentAge
            self.init(allowsCloudAI: true, allowsPurchases: true, autoPaywall: false, requiresGuardianStep: guardian)
        case .adult:
            self.init(allowsCloudAI: true, allowsPurchases: true, autoPaywall: true, requiresGuardianStep: false)
        case .unknown:
            self.init(allowsCloudAI: true, allowsPurchases: true, autoPaywall: false, requiresGuardianStep: true)
        }
    }
}
