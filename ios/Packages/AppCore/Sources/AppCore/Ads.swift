import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Ads for free members 13+ (Pro has none): an optional rewarded ad for one
// credit when she's out of credits, at most two a day, and now and then an
// interstitial after a finished save or share. The rules that decide who and
// when live here so they're tested on Linux; the app only shows the ads.

// MARK: - Who may see ads

/// The protections an ad request carries, from her age range. Every request
/// is non-personalised, whoever she is.
public enum AdAudience: String, Codable, Sendable {
    /// 13 to 17, and ages not known: tagged as under the age of consent,
    /// general-audience (G) ads only, and no consent form.
    case teen
    /// 18 and over: up to PG ads; Google's consent form where the law asks for one.
    case adult

    public var isUnderAgeOfConsent: Bool { self == .teen }
}

extension AgeDefaults {
    /// Nil (no ads, and no ad SDK at all) under 13 and after declining to
    /// share an age where the law asks for it; teen protections for teens and
    /// unknown ages, including a self-declared age where it isn't accepted.
    public static func adAudience(record: AgeRecord?, storefrontCountry: String?) -> AdAudience? {
        let defaults = AgeDefaults(record: record, storefrontCountry: storefrontCountry)
        guard defaults.allowsCloudAI, defaults.allowsPurchases else { return nil }
        return effectiveBand(record: record, storefrontCountry: storefrontCountry) == .adult ? .adult : .teen
    }
}

// MARK: - Rewarded ads

/// One credit per rewarded ad, at most `dailyCap` a day (UTC), only for free
/// members who are out of credits. The server enforces the same numbers
/// (`ad_reward_policy()` in the backend, per user and per App Store
/// install); this decides what the app offers.
public struct AdRewardPolicy: Equatable, Sendable {
    public var dailyCap: Int
    public var creditsPerAd: Int

    public init(dailyCap: Int = 2, creditsPerAd: Int = 1) {
        self.dailyCap = dailyCap
        self.creditsPerAd = creditsPerAd
    }

    public static let standard = AdRewardPolicy()

    /// Whether "Watch a short ad" belongs on screen: never for Pro (their
    /// credits come every month), never without an audience, only once the
    /// balance is empty, and never while the server rests free AI (`pause`):
    /// the ad's credit lands among the free credits, so she couldn't use it.
    public func offersAd(isPro: Bool, audience: AdAudience?, balance: Int, pause: AIServicePause? = nil,
                         now: Date = Date()) -> Bool {
        if let pause, pause.isActive(at: now) { return false }
        return !isPro && audience != nil && balance <= 0
    }
}

/// AdMob ids, checked before any request so a typo turns ads off instead of
/// sending requests for someone else's app.
public enum AdMobID {
    /// `ca-app-pub-<publisher>~<app>`, as in Info.plist's GADApplicationIdentifier.
    public static func isAppID(_ value: String) -> Bool {
        value.range(of: #"^ca-app-pub-\d{10,20}~\d{6,14}$"#, options: .regularExpression) != nil
    }

    /// `ca-app-pub-<publisher>/<unit>`.
    public static func isUnitID(_ value: String) -> Bool {
        value.range(of: #"^ca-app-pub-\d{10,20}/\d{6,14}$"#, options: .regularExpression) != nil
    }

    /// The publisher part both share, so a unit can be matched to its app.
    public static func publisher(of value: String) -> String? {
        guard isAppID(value) || isUnitID(value) else { return nil }
        let rest = value.dropFirst("ca-app-pub-".count)
        return rest.split(whereSeparator: { $0 == "~" || $0 == "/" }).first.map(String.init)
    }
}

// MARK: - Interstitials

/// When an interstitial may follow a finished save or share, kept on the
/// device: never in the first day after the first launch or before her third
/// successful save, at most one every 4 minutes and 3 a day, and never within
/// 4 minutes of a rewarded ad. Whether one is loaded, and whether the moment
/// is a natural break, is the app's part.
public struct InterstitialPacing: Codable, Equatable, Sendable {
    public struct Rules: Equatable, Sendable {
        public var grace: TimeInterval
        public var minimumSaves: Int
        public var spacing: TimeInterval
        public var dailyCap: Int
        public var afterRewarded: TimeInterval

        public init(grace: TimeInterval, minimumSaves: Int, spacing: TimeInterval, dailyCap: Int, afterRewarded: TimeInterval) {
            self.grace = grace
            self.minimumSaves = minimumSaves
            self.spacing = spacing
            self.dailyCap = dailyCap
            self.afterRewarded = afterRewarded
        }

        public static let standard = Rules(grace: 24 * 3600, minimumSaves: 3, spacing: 4 * 60, dailyCap: 3, afterRewarded: 4 * 60)
    }

    public var firstLaunch: Date
    public var successfulSaves: Int
    public var lastShown: Date?
    public var lastRewarded: Date?
    /// The start of the (local) day `shownThatDay` counts.
    public var shownDay: Date?
    public var shownThatDay: Int

    public init(firstLaunch: Date, successfulSaves: Int = 0, lastShown: Date? = nil, lastRewarded: Date? = nil,
                shownDay: Date? = nil, shownThatDay: Int = 0) {
        self.firstLaunch = firstLaunch
        self.successfulSaves = successfulSaves
        self.lastShown = lastShown
        self.lastRewarded = lastRewarded
        self.shownDay = shownDay
        self.shownThatDay = shownThatDay
    }

    public mutating func noteSave() {
        successfulSaves += 1
    }

    public mutating func noteShown(at date: Date, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        shownThatDay = shownDay == day ? shownThatDay + 1 : 1
        shownDay = day
        lastShown = date
    }

    public mutating func noteRewardedAd(at date: Date) {
        lastRewarded = date
    }

    public func shownCount(on date: Date, calendar: Calendar = .current) -> Int {
        shownDay == calendar.startOfDay(for: date) ? shownThatDay : 0
    }

    /// Whether an interstitial may show right after the save just counted.
    /// A clock set back counts as "too soon", never as "long ago".
    public func allowsInterstitial(at date: Date, rules: Rules = .standard, calendar: Calendar = .current) -> Bool {
        guard date.timeIntervalSince(firstLaunch) >= rules.grace, successfulSaves >= rules.minimumSaves else { return false }
        if let lastShown, date.timeIntervalSince(lastShown) < rules.spacing { return false }
        if let lastRewarded, date.timeIntervalSince(lastRewarded) < rules.afterRewarded { return false }
        return shownCount(on: date, calendar: calendar) < rules.dailyCap
    }

    /// Worth loading one now, quietly, so a later save can show it at once:
    /// past the grace period, the next save would be the third or later, and
    /// today's cap isn't reached.
    public func worthPreloading(at date: Date, rules: Rules = .standard, calendar: Calendar = .current) -> Bool {
        date.timeIntervalSince(firstLaunch) >= rules.grace
            && successfulSaves + 1 >= rules.minimumSaves
            && shownCount(on: date, calendar: calendar) < rules.dailyCap
    }
}

// MARK: - Wire models (shared contract with backend/supabase/functions/ad-reward)

/// `POST /ad-reward`: the single-use token for the next rewarded ad.
public struct AdRewardToken: Decodable, Equatable, Sendable {
    public var token: String
    public var expiresAt: String?
    public var remainingToday: Int
    public var dailyCap: Int?

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
        case remainingToday = "remaining_today"
        case dailyCap = "daily_cap"
    }

    public init(token: String, expiresAt: String? = nil, remainingToday: Int, dailyCap: Int? = nil) {
        self.token = token
        self.expiresAt = expiresAt
        self.remainingToday = remainingToday
        self.dailyCap = dailyCap
    }
}

/// `GET /ad-reward` (today's ads) and `GET /ad-reward?token=` (one ad's reward).
public struct AdRewardStatus: Decodable, Equatable, Sendable {
    public enum Outcome: String, Decodable, Sendable {
        /// AdMob hasn't called back yet.
        case pending
        case granted
        /// Today's ad credits were already paid.
        case capped
        /// The token timed out before AdMob confirmed the ad.
        case expired
        /// Not a token of hers.
        case unknown
    }

    public var status: Outcome?
    public var remainingToday: Int
    public var dailyCap: Int?
    public var creditsRemaining: Int?
    /// Overview only: free, out of credits and under today's cap.
    public var eligible: Bool?

    enum CodingKeys: String, CodingKey {
        case status, eligible
        case remainingToday = "remaining_today"
        case dailyCap = "daily_cap"
        case creditsRemaining = "credits_remaining"
    }

    public init(status: Outcome? = nil, remainingToday: Int, dailyCap: Int? = nil, creditsRemaining: Int? = nil, eligible: Bool? = nil) {
        self.status = status
        self.remainingToday = remainingToday
        self.dailyCap = dailyCap
        self.creditsRemaining = creditsRemaining
        self.eligible = eligible
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A status the app doesn't know yet reads as "not confirmed".
        status = (try? container.decodeIfPresent(String.self, forKey: .status)).flatMap { Outcome(rawValue: $0) }
        remainingToday = try container.decodeIfPresent(Int.self, forKey: .remainingToday) ?? 0
        dailyCap = try container.decodeIfPresent(Int.self, forKey: .dailyCap)
        creditsRemaining = try container.decodeIfPresent(Int.self, forKey: .creditsRemaining)
        eligible = try container.decodeIfPresent(Bool.self, forKey: .eligible)
    }
}

/// Why the server wouldn't hand out a token (or answer at all).
public enum AdRewardError: Error, Equatable, Sendable {
    /// Pro (or anyone the server won't show ads to).
    case notEligible
    /// She isn't out of credits; the server's balance comes along.
    case hasCredits(Int?)
    /// Today's ads are used up.
    case dailyCap
    case unauthorized
    case server(code: String, message: String)
}

extension RequestFactory {
    static let adRewardPath = "functions/v1/ad-reward"

    /// Today's ads: how many are left, and the balance. Like a job, it
    /// carries the AppTransaction: ad credits belong to the App Store install.
    public static func adRewardOverview(
        config: BackendConfiguration, accessToken: String?, entitlementJWS: String? = nil, appTransactionJWS: String? = nil
    ) throws -> URLRequest {
        try adRewardRequest(method: "GET", query: [], config: config, accessToken: accessToken,
                            entitlementJWS: entitlementJWS, appTransactionJWS: appTransactionJWS)
    }

    /// A single-use token for the next ad; the app passes only this to AdMob.
    public static func adRewardToken(
        config: BackendConfiguration, accessToken: String?, entitlementJWS: String? = nil, appTransactionJWS: String? = nil
    ) throws -> URLRequest {
        try adRewardRequest(method: "POST", query: [], config: config, accessToken: accessToken,
                            entitlementJWS: entitlementJWS, appTransactionJWS: appTransactionJWS)
    }

    /// Whether AdMob has confirmed the ad that carried `token`.
    public static func adRewardStatus(token: String, config: BackendConfiguration, accessToken: String?, entitlementJWS: String? = nil) throws -> URLRequest {
        try adRewardRequest(method: "GET", query: [URLQueryItem(name: "token", value: token)], config: config,
                            accessToken: accessToken, entitlementJWS: entitlementJWS, appTransactionJWS: nil)
    }

    /// The ad closed before its reward: gives the token's place back.
    public static func releaseAdRewardToken(token: String, config: BackendConfiguration, accessToken: String?) throws -> URLRequest {
        try adRewardRequest(method: "DELETE", query: [URLQueryItem(name: "token", value: token)], config: config,
                            accessToken: accessToken, entitlementJWS: nil, appTransactionJWS: nil)
    }

    private static func adRewardRequest(
        method: String, query: [URLQueryItem], config: BackendConfiguration, accessToken: String?,
        entitlementJWS: String?, appTransactionJWS: String?
    ) throws -> URLRequest {
        var request = try authorized(config: config, path: adRewardPath, method: method, query: query, accessToken: accessToken)
        attach(entitlementJWS: entitlementJWS, appTransactionJWS: appTransactionJWS, to: &request)
        return request
    }
}

extension ResponseDecoder {
    public static func decodeAdRewardToken(data: Data, statusCode: Int) throws -> AdRewardToken {
        guard (200..<300).contains(statusCode) else { throw adRewardError(from: data, statusCode: statusCode) }
        guard let token = try? JSONDecoder().decode(AdRewardToken.self, from: data), !token.token.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return token
    }

    public static func decodeAdRewardStatus(data: Data, statusCode: Int) throws -> AdRewardStatus {
        guard (200..<300).contains(statusCode) else { throw adRewardError(from: data, statusCode: statusCode) }
        guard let status = try? JSONDecoder().decode(AdRewardStatus.self, from: data) else {
            throw AIServiceError.invalidResponse
        }
        return status
    }

    public static func adRewardError(from data: Data, statusCode: Int) -> AdRewardError {
        let body = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error
        switch (statusCode, body?.code) {
        case (_, "not_eligible"):
            return .notEligible
        case (_, "has_credits"):
            return .hasCredits(body?.creditsRemaining)
        case (_, "daily_cap"):
            return .dailyCap
        case (401, _):
            return .unauthorized
        default:
            return .server(code: body?.code ?? "http_\(statusCode)", message: body?.message ?? "")
        }
    }
}
