import Foundation

/// Whose seasons Explore shows: her region, and the app's language for
/// Lunar New Year among Chinese speakers anywhere. Halloween, winter and
/// Galentine's are for everyone; the local seasons only where they're
/// celebrated (`SeasonalTheme.regions`).
public struct SeasonAudience: Hashable, Sendable {
    /// ISO 3166-1 alpha-2 ("TR"), "419" (Latin American Spanish) or nil.
    public let region: String?
    /// The app's language, BCP 47 ("zh-Hans", "pt-BR").
    public let language: String?

    public init(region: String?, language: String? = nil) {
        self.region = region?.uppercased()
        self.language = language
    }

    /// No region known: the global seasons only.
    public static let everyone = SeasonAudience(region: nil)

    /// The device's region first, then the App Store storefront (StoreKit's
    /// three-letter code), then the region her language implies ("pt-BR",
    /// "ja"). A storefront this table doesn't know still decides: an
    /// American storefront isn't a reason to guess from the language.
    public static func resolve(localeRegion: String?, storefront: String?, language: String?) -> SeasonAudience {
        let region = countryCode(localeRegion)
            ?? storefront.flatMap(storefrontRegion)
            ?? language.flatMap(languageRegion)
        return SeasonAudience(region: region, language: language)
    }

    static func countryCode(_ code: String?) -> String? {
        guard let code, code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return code.uppercased()
    }

    static func storefrontRegion(_ alpha3: String) -> String? {
        let code = alpha3.uppercased()
        guard !code.isEmpty else { return nil }
        return storefronts[code] ?? code
    }

    /// The storefronts whose countries have a local season.
    private static let storefronts: [String: String] = [
        "TUR": "TR", "IDN": "ID", "KOR": "KR", "JPN": "JP", "BRA": "BR",
        "CHN": "CN", "TWN": "TW", "HKG": "HK", "MAC": "MO", "SGP": "SG", "MYS": "MY",
        "MEX": "MX", "GTM": "GT", "SLV": "SV", "HND": "HN", "NIC": "NI", "CRI": "CR", "PAN": "PA",
        "CUB": "CU", "DOM": "DO", "PRI": "PR", "COL": "CO", "VEN": "VE", "ECU": "EC", "PER": "PE",
        "BOL": "BO", "CHL": "CL", "ARG": "AR", "URY": "UY", "PRY": "PY",
    ]

    /// "pt-BR" → BR, "es-419" → 419, "zh-Hans-SG" → SG; a bare language
    /// spoken mostly in one country → that country.
    static func languageRegion(_ language: String) -> String? {
        let parts = language.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        if let region = parts.dropFirst().first(where: { ($0.count == 2 && $0.allSatisfy(\.isLetter)) || $0 == "419" }) {
            return region.uppercased()
        }
        switch parts.first?.lowercased() {
        case "tr": return "TR"
        case "id": return "ID"
        case "ja": return "JP"
        case "ko": return "KR"
        default: return nil
        }
    }

    /// Simplified Chinese, however the system spells it.
    var speaksSimplifiedChinese: Bool {
        guard let language = language?.lowercased().replacingOccurrences(of: "_", with: "-") else { return false }
        return ["zh-hans", "zh-cn", "zh-sg", "zh-my"].contains { language == $0 || language.hasPrefix($0 + "-") }
    }
}

/// Calendar days, both ends included, written yyyymmdd (20260319).
public struct DayRange: Hashable, Sendable {
    public let first: Int
    public let last: Int

    public init(_ first: Int, _ last: Int) {
        self.first = first
        self.last = last
    }

    public var year: Int { first / 10_000 }

    func contains(_ day: Int) -> Bool { (first...last).contains(day) }
}

/// When a season is on: the same days every year, or listed year by year
/// for dates that follow the moon or Easter (never computed: each comes
/// from the authority that sets it, see `SeasonalTheme.dates`).
public enum SeasonDates: Hashable, Sendable {
    case yearly(SeasonWindow)
    case dated([DayRange])

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .yearly(let window):
            return window.contains(date, calendar: calendar)
        case .dated(let ranges):
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = parts.year, let month = parts.month, let day = parts.day else { return false }
            let key = year * 10_000 + month * 100 + day
            return ranges.contains { $0.contains(key) }
        }
    }

    /// The last year with dates (nil: every year).
    public var lastYear: Int? {
        if case .dated(let ranges) = self { return ranges.map(\.year).max() }
        return nil
    }
}

extension SeasonalTheme {
    // MARK: Where

    static let eidRegions: Set<String> = ["TR", "ID"]
    /// Korea, and Chinese-speaking places (mainland China isn't a storefront,
    /// but a Chinese region setting can be on any device).
    static let lunarNewYearRegions: Set<String> = ["KR", "CN", "TW", "HK", "MO", "SG", "MY"]
    /// Mexico and the other Spanish-speaking countries of Latin America.
    static let latinAmerica: Set<String> = [
        "MX", "GT", "SV", "HN", "NI", "CR", "PA", "CU", "DO", "PR",
        "CO", "VE", "EC", "PE", "BO", "CL", "AR", "UY", "PY", "419",
    ]

    /// Where the season is on; nil: everywhere.
    public var regions: Set<String>? {
        switch self {
        case .halloween, .winter, .galentines: return nil
        case .eidAlFitr, .eidAlAdha: return Self.eidRegions
        case .lunarNewYear: return Self.lunarNewYearRegions
        case .chuseok: return ["KR"]
        case .hanami, .tanabata: return ["JP"]
        case .carnaval, .festaJunina: return ["BR"]
        case .diaDeMuertos: return Self.latinAmerica
        }
    }

    /// Where it leads Explore ahead of the global seasons. Día de Muertos
    /// leads in Mexico; elsewhere in Latin America it follows Halloween.
    var homeRegions: Set<String>? {
        self == .diaDeMuertos ? ["MX"] : regions
    }

    public var isLocal: Bool { regions != nil }

    public func isShown(to audience: SeasonAudience) -> Bool {
        guard let regions else { return true }
        if self == .lunarNewYear, audience.speaksSimplifiedChinese { return true }
        guard let region = audience.region else { return false }
        return regions.contains(region)
    }

    /// Who comes first when several are on: a local season at home (2), the
    /// global ones (1), a local season away from home (0).
    func rank(for audience: SeasonAudience) -> Int {
        guard isLocal else { return 1 }
        if self == .lunarNewYear, audience.speaksSimplifiedChinese { return 2 }
        guard let region = audience.region, homeRegions?.contains(region) == true else { return 0 }
        return 2
    }

    /// The local seasons for this audience, in catalog order.
    public static func local(for audience: SeasonAudience) -> [SeasonalTheme] {
        allCases.filter { $0.isLocal && $0.isShown(to: audience) }
    }

    // MARK: When

    /// Inclusive. Dates that move are listed per year from the authority
    /// that sets them; past the last year, the season is off until someone
    /// adds the next one (CatalogTests reminds a year ahead).
    public var dates: SeasonDates {
        switch self {
        case .halloween: return .yearly(SeasonWindow(startMonth: 10, startDay: 1, endMonth: 11, endDay: 2))
        case .winter: return .yearly(SeasonWindow(startMonth: 12, startDay: 1, endMonth: 1, endDay: 6))
        case .galentines: return .yearly(SeasonWindow(startMonth: 2, startDay: 1, endMonth: 2, endDay: 14))
        case .eidAlFitr:
            // Türkiye: Diyanet's religious days and public holidays, eve
            // (arefe) to the third day. Indonesia: the SKB 3 Menteri holidays
            // and cuti bersama. 2026: TR 19 (eve), 20–22; ID 21–22 (Kemenag's
            // isbat: 21), cuti bersama 20, 23, 24. 2027: TR 8 (eve), 9–11;
            // ID 10–11, cuti bersama 9, 12, 15. 2028: TR 25 (eve), 26–28;
            // Indonesia's 2028 SKB isn't out yet (autumn 2027), so the window
            // runs one more day.
            return .dated([DayRange(2026_03_19, 2026_03_24), DayRange(2027_03_08, 2027_03_15), DayRange(2028_02_25, 2028_02_29)])
        case .eidAlAdha:
            // Same sources. 2026: TR 26 (eve), 27–30; ID 27, cuti bersama 28.
            // 2027: TR 15 (eve), 16–19; ID 17, cuti bersama 18. 2028: TR 4
            // (eve), 5–8 (Indonesia: SKB not out yet).
            return .dated([DayRange(2026_05_26, 2026_05_30), DayRange(2027_05_15, 2027_05_19), DayRange(2028_05_04, 2028_05_08)])
        case .lunarNewYear:
            // New Year's Eve to the fifth day. First days from the Hong Kong
            // Observatory's calendar: 2026-02-17, 2027-02-06, 2028-01-26.
            // Korea's Seollal can fall a day later, on Korean time: 2027-02-07
            // (KASA's 2027 calendar: holidays 6–9) and 2028-01-27 (new moon
            // 15:12 UT, 00:12 in Seoul, per the US Naval Observatory).
            return .dated([DayRange(2026_02_16, 2026_02_21), DayRange(2027_02_05, 2027_02_10), DayRange(2028_01_25, 2028_01_30)])
        case .chuseok:
            // The three days around the 15th of the 8th lunar month: 2026-09-25,
            // 2027-09-15 (KASA: holidays 14–16), 2028-10-03 (HKO), which is
            // also National Foundation Day, so a substitute day follows.
            return .dated([DayRange(2026_09_24, 2026_09_26), DayRange(2027_09_14, 2027_09_16), DayRange(2028_10_02, 2028_10_05)])
        case .hanami:
            // The Japan Meteorological Agency's 1991–2020 normals: blossoms
            // open around Mar 22–27 from Fukuoka to Tokyo and Kyoto, and are
            // in full bloom until mid-April in Sendai.
            return .yearly(SeasonWindow(startMonth: 3, startDay: 20, endMonth: 4, endDay: 15))
        case .tanabata:
            // July 7; wishes go up on the bamboo in the days before.
            return .yearly(SeasonWindow(startMonth: 7, startDay: 1, endMonth: 7, endDay: 7))
        case .carnaval:
            // Saturday to Ash Wednesday around the Monday and Tuesday of
            // Carnaval in ANBIMA's national holidays: 2026-02-16/17,
            // 2027-02-08/09, 2028-02-28/29.
            return .dated([DayRange(2026_02_14, 2026_02_18), DayRange(2027_02_06, 2027_02_10), DayRange(2028_02_26, 2028_03_01)])
        case .festaJunina:
            // The June saints: Santo Antônio (13), São João (24), São Pedro (29).
            return .yearly(SeasonWindow(startMonth: 6, startDay: 1, endMonth: 6, endDay: 30))
        case .diaDeMuertos:
            // November 1 and 2, from the night of October 31.
            return .yearly(SeasonWindow(startMonth: 10, startDay: 31, endMonth: 11, endDay: 2))
        }
    }

    /// Its dates are on, wherever that is.
    public func isOn(_ date: Date, calendar: Calendar = .current) -> Bool {
        dates.contains(date, calendar: calendar)
    }

    /// On, and celebrated where she is.
    public func isActive(on date: Date, for audience: SeasonAudience = .everyone, calendar: Calendar = .current) -> Bool {
        isShown(to: audience) && isOn(date, calendar: calendar)
    }

    /// Every season on for her today, the one Explore leads with first.
    public static func active(on date: Date, for audience: SeasonAudience = .everyone, calendar: Calendar = .current) -> [SeasonalTheme] {
        let on = allCases.filter { $0.isActive(on: date, for: audience, calendar: calendar) }
        // Stable: catalog order within a rank.
        return on.enumerated()
            .sorted { lhs, rhs in
                let (left, right) = (lhs.element.rank(for: audience), rhs.element.rank(for: audience))
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    public static func current(on date: Date, for audience: SeasonAudience = .everyone, calendar: Calendar = .current) -> SeasonalTheme? {
        active(on: date, for: audience, calendar: calendar).first
    }

    /// The season Home teases ("Coming soon") in the `days` before its first
    /// day: one that will lead Explore when it starts, so nothing is on yet
    /// or it outranks what is (her local season during Halloween). On its
    /// first day its own banner and row take over. A local season goes
    /// before a global one, then the sooner.
    public static func upcoming(
        on date: Date, within days: Int = 14, for audience: SeasonAudience = .everyone, calendar: Calendar = .current
    ) -> UpcomingSeason? {
        guard days >= 1 else { return nil }
        let active = active(on: date, for: audience, calendar: calendar)
        let leading = active.first?.rank(for: audience)
        var best: (season: UpcomingSeason, rank: Int)?
        for theme in allCases where theme.isShown(to: audience) && !active.contains(theme) {
            let rank = theme.rank(for: audience)
            if let leading, rank <= leading { continue }
            for ahead in 1...days {
                guard let day = calendar.date(byAdding: .day, value: ahead, to: date) else { break }
                guard theme.isOn(day, calendar: calendar) else { continue }
                // It's off today, so the first day it's on is its first day.
                let beaten = best.map { rank < $0.rank || (rank == $0.rank && ahead >= $0.season.daysLeft) } ?? false
                if !beaten { best = (UpcomingSeason(theme: theme, daysLeft: ahead), rank) }
                break
            }
        }
        return best?.season
    }
}
