import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Ads for free members 13+ (Pro has none): an optional rewarded ad for one
// credit when she's out of credits, at most two a day, one for a one-time try
// of a Pro look or style (a day, with a credit to spend), and now and then an
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
    /// When the token stops being accepted (30 minutes to show the ad).
    public var expiresAt: String?
    /// Ads of this kind left today, this one counted.
    public var remainingToday: Int
    public var dailyCap: Int?
    /// `credit` or `unlock` (a Pro try); older servers send none (a credit).
    public var kind: String?
    /// A try's look or style.
    public var item: ProTryItem?

    enum CodingKeys: String, CodingKey {
        case token, kind
        case expiresAt = "expires_at"
        case remainingToday = "remaining_today"
        case dailyCap = "daily_cap"
    }

    public init(token: String, expiresAt: String? = nil, remainingToday: Int, dailyCap: Int? = nil, kind: String? = nil,
                item: ProTryItem? = nil) {
        self.token = token
        self.expiresAt = expiresAt
        self.remainingToday = remainingToday
        self.dailyCap = dailyCap
        self.kind = kind
        self.item = item
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decode(String.self, forKey: .token)
        expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt)
        remainingToday = try container.decodeIfPresent(Int.self, forKey: .remainingToday) ?? 0
        dailyCap = try container.decodeIfPresent(Int.self, forKey: .dailyCap)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        item = try ProTryItem.decodeIfPresent(from: decoder)
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
    /// Ads of the token's kind left today (the overview: credit ads).
    public var remainingToday: Int
    public var dailyCap: Int?
    public var creditsRemaining: Int?
    /// Overview only: free, out of credits and under today's cap.
    public var eligible: Bool?
    /// `credit` or `unlock` (a Pro try); older servers send none.
    public var kind: String?
    /// A try's look or style.
    public var item: ProTryItem?
    /// A granted try: when it can no longer start a job.
    public var expiresAt: Date?
    /// Overview only: today's Pro tries (nil from servers before them).
    public var unlock: ProTryOverview?

    enum CodingKeys: String, CodingKey {
        case status, eligible, kind, unlock
        case remainingToday = "remaining_today"
        case dailyCap = "daily_cap"
        case creditsRemaining = "credits_remaining"
        case expiresAt = "expires_at"
    }

    public init(status: Outcome? = nil, remainingToday: Int, dailyCap: Int? = nil, creditsRemaining: Int? = nil, eligible: Bool? = nil,
                kind: String? = nil, item: ProTryItem? = nil, expiresAt: Date? = nil, unlock: ProTryOverview? = nil) {
        self.status = status
        self.remainingToday = remainingToday
        self.dailyCap = dailyCap
        self.creditsRemaining = creditsRemaining
        self.eligible = eligible
        self.kind = kind
        self.item = item
        self.expiresAt = expiresAt
        self.unlock = unlock
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A status the app doesn't know yet reads as "not confirmed".
        status = (try? container.decodeIfPresent(String.self, forKey: .status)).flatMap { Outcome(rawValue: $0) }
        remainingToday = try container.decodeIfPresent(Int.self, forKey: .remainingToday) ?? 0
        dailyCap = try container.decodeIfPresent(Int.self, forKey: .dailyCap)
        creditsRemaining = try container.decodeIfPresent(Int.self, forKey: .creditsRemaining)
        eligible = try container.decodeIfPresent(Bool.self, forKey: .eligible)
        kind = try? container.decodeIfPresent(String.self, forKey: .kind)
        item = try ProTryItem.decodeIfPresent(from: decoder)
        expiresAt = (try? container.decodeIfPresent(String.self, forKey: .expiresAt)).flatMap { ServerDate.parse($0) }
        // A tries block this version can't read leaves the credit ads working.
        unlock = try? container.decodeIfPresent(ProTryOverview.self, forKey: .unlock)
    }
}

/// Why the server wouldn't hand out a token (or answer at all).
public enum AdRewardError: Error, Equatable, Sendable {
    /// Pro (or anyone the server won't show ads to).
    case notEligible
    /// She isn't out of credits; the server's balance comes along.
    case hasCredits(Int?)
    /// Today's ads (or today's Pro try) are used up.
    case dailyCap
    /// A Pro try: its job costs a credit, and she has none.
    case noCredits
    /// A Pro try of something that isn't a Pro look or style (or a malformed ask).
    case notUnlockable
    /// AI rests for everyone, so a try couldn't start its job.
    case aiPaused
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

    /// A single-use token for an ad that pays a one-time try of `item`
    /// (`{ "kind": "unlock", "template_id" | "style_id" }`); the credit ad
    /// sends no body.
    public static func adRewardUnlockToken(
        for item: ProTryItem, config: BackendConfiguration, accessToken: String?, entitlementJWS: String? = nil,
        appTransactionJWS: String? = nil
    ) throws -> URLRequest {
        var request = try adRewardRequest(method: "POST", query: [], config: config, accessToken: accessToken,
                                          entitlementJWS: entitlementJWS, appTransactionJWS: appTransactionJWS)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["kind": "unlock", item.field: item.id], options: [.sortedKeys])
        return request
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
        case (_, "no_credits"):
            return .noCredits
        case (_, "not_unlockable"), (_, "bad_request"):
            return .notUnlockable
        case (_, "ai_paused"):
            return .aiPaused
        case (401, _):
            return .unauthorized
        default:
            return .server(code: body?.code ?? "http_\(statusCode)", message: body?.message ?? "")
        }
    }
}

// MARK: - Pro tries (backend README, "Rewarded unlock")

/// A Pro look (a one-tap template) or Pro Create style that a free member can
/// try once by watching a rewarded ad. One try covers one job with exactly
/// this look or style and one image, costs a credit like any job, and ends 30
/// minutes after Google confirms the ad; the server decides all of it.
public enum ProTryItem: Hashable, Sendable {
    case template(String)
    case style(String)

    public var id: String {
        switch self {
        case .template(let id), .style(let id): return id
        }
    }

    /// The paywall's reason for it (`template_<id>`, `style_<id>`).
    public var paywallSource: String {
        switch self {
        case .template(let id): return "template_\(id)"
        case .style(let id): return "style_\(id)"
        }
    }

    /// The job a try pays for.
    public var operation: AIOperation {
        switch self {
        case .template: return .restyle
        case .style: return .textToImage
        }
    }

    /// The field that names it in requests and answers.
    var field: String {
        switch self {
        case .template: return "template_id"
        case .style: return "style_id"
        }
    }

    /// The Pro look or style a paywall reason names, if it's one in the
    /// catalog: free ones, unknown ids and other reasons have no try.
    public init?(paywallSource source: String) {
        if source.hasPrefix("template_") {
            let id = String(source.dropFirst("template_".count))
            guard TemplateCatalog.template(id: id)?.isPro == true else { return nil }
            self = .template(id)
        } else if source.hasPrefix("style_") {
            let id = String(source.dropFirst("style_".count))
            guard StyleCatalog.all.contains(where: { $0.id == id && $0.isPro }) else { return nil }
            self = .style(id)
        } else {
            return nil
        }
    }

    private enum Keys: String, CodingKey {
        case templateID = "template_id"
        case styleID = "style_id"
    }

    /// `template_id` or `style_id` in an answer, when exactly one is there.
    static func decodeIfPresent(from decoder: Decoder) throws -> ProTryItem? {
        let container = try decoder.container(keyedBy: Keys.self)
        let template = try? container.decodeIfPresent(String.self, forKey: .templateID)
        let style = try? container.decodeIfPresent(String.self, forKey: .styleID)
        switch (template ?? nil, style ?? nil) {
        case (let id?, nil) where !id.isEmpty: return .template(id)
        case (nil, let id?) where !id.isEmpty: return .style(id)
        default: return nil
        }
    }
}

/// A try she watched an ad for and hasn't used yet.
public struct ProTry: Equatable, Sendable, Decodable {
    public var item: ProTryItem
    /// When it can no longer start a job.
    public var expiresAt: Date

    public init(item: ProTryItem, expiresAt: Date) {
        self.item = item
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case expiresAt = "expires_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let item = try ProTryItem.decodeIfPresent(from: decoder),
              let expiresAt = ServerDate.parse(try container.decode(String.self, forKey: .expiresAt)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a Pro try"))
        }
        self.item = item
        self.expiresAt = expiresAt
    }
}

/// `GET /ad-reward`'s `unlock`: today's Pro tries.
public struct ProTryOverview: Decodable, Equatable, Sendable {
    public var remainingToday: Int
    /// Nil when the server couldn't read its policy; 0 turns tries off.
    public var dailyCap: Int?
    /// A free member with a verified install, a credit, under today's cap,
    /// and AI not paused.
    public var eligible: Bool
    /// Her unused, live tries (after a relaunch, say).
    public var active: [ProTry]

    enum CodingKeys: String, CodingKey {
        case eligible, active
        case remainingToday = "remaining_today"
        case dailyCap = "daily_cap"
    }

    public init(remainingToday: Int, dailyCap: Int? = 1, eligible: Bool, active: [ProTry] = []) {
        self.remainingToday = remainingToday
        self.dailyCap = dailyCap
        self.eligible = eligible
        self.active = active
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        remainingToday = try container.decodeIfPresent(Int.self, forKey: .remainingToday) ?? 0
        dailyCap = try container.decodeIfPresent(Int.self, forKey: .dailyCap)
        eligible = try container.decodeIfPresent(Bool.self, forKey: .eligible) ?? false
        // One entry this version can't read doesn't hide the others.
        active = (try container.decodeIfPresent([Lossy<ProTry>].self, forKey: .active) ?? []).compactMap(\.value)
    }
}

/// What the paywall that a Pro look or style opened offers besides Pro.
public enum ProTryOffer: Equatable, Sendable {
    /// No try card: Pro, under 13, several images, AI resting, tries off, or
    /// the server hasn't said (or says she can't).
    case none
    /// "Try this look once · watch a short ad", with `remaining` tries left today.
    case available(remaining: Int)
    /// She already watched an ad for this one: it's ready until `expiresAt`.
    case ready(expiresAt: Date)
    /// The try's job costs a credit and she has none: the ways to get one.
    case needsCredit
    /// Today's try is used.
    case capped
}

/// Who gets the try card, and in which state. The server checks everything
/// again (`issue_ad_unlock_token()`, `admit_unlocked_job()`); this decides
/// what the app offers.
public struct ProTryPolicy: Equatable, Sendable {
    /// A try that ends sooner than this can't be counted on to start its job.
    public var margin: TimeInterval
    /// How long a granted try lasts when the server didn't say (it does: 30 minutes from Google's confirmation).
    public var fallbackLength: TimeInterval

    public init(margin: TimeInterval = 15, fallbackLength: TimeInterval = 20 * 60) {
        self.margin = margin
        self.fallbackLength = fallbackLength
    }

    public static let standard = ProTryPolicy()

    /// Never for Pro (every look is theirs), without an ad audience (under
    /// 13) or for several images at once (Pro only, even with a try), and
    /// never while the server rests AI (the try couldn't start its job). A
    /// try she already has comes first; then, once the server has answered:
    /// today's try used, no credit to spend, or the offer if it says she may.
    public func offer(
        for item: ProTryItem, isPro: Bool, audience: AdAudience?, outputs: Int = 1, balance: Int, cost: Int = 1,
        overview: ProTryOverview?, active: [ProTry], pause: AIServicePause? = nil, now: Date = Date()
    ) -> ProTryOffer {
        guard !isPro, audience != nil, outputs == 1 else { return .none }
        if let pause, pause.isActive(at: now) { return .none }
        let needed = max(1, cost)
        if let live = liveTry(for: item, in: active, at: now) {
            return balance >= needed ? .ready(expiresAt: live.expiresAt) : .needsCredit
        }
        guard let overview, overview.dailyCap != 0 else { return .none }
        if overview.remainingToday <= 0 { return .capped }
        if balance < needed { return .needsCredit }
        return overview.eligible ? .available(remaining: overview.remainingToday) : .none
    }

    /// Her try of exactly this look or style that can still start a job.
    public func liveTry(for item: ProTryItem, in active: [ProTry], at now: Date = Date()) -> ProTry? {
        active
            .filter { $0.item == item && $0.expiresAt.timeIntervalSince(now) > margin }
            .max { $0.expiresAt < $1.expiresAt }
    }
}

/// Decodes what it can and leaves the rest nil.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// The server's timestamps: ISO 8601 with or without a fraction of a second
/// (Postgres sends microseconds and `+00:00`).
enum ServerDate {
    static func parse(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        // More digits than milliseconds: keep three.
        guard let fraction = string.range(of: #"\.\d+"#, options: .regularExpression) else { return nil }
        let trimmed = string.replacingCharacters(in: fraction, with: String(string[fraction].prefix(4)))
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: trimmed)
    }
}
