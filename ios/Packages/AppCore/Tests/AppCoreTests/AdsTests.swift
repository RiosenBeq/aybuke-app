import XCTest
@testable import AppCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class AdsTests: XCTestCase {
    private let config = BackendConfiguration(baseURL: URL(string: "https://demo.supabase.co")!, anonKey: "anon-key")

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: Audience

    func testNoAdsUnder13OrAfterDecliningTheAgeStep() {
        func audience(_ band: AgeBand, _ source: AgeSource = .selfDeclared, _ country: String? = "USA") -> AdAudience? {
            AgeDefaults.adAudience(record: AgeRecord(band: band, source: source, setAt: .distantPast), storefrontCountry: country)
        }
        XCTAssertNil(audience(.under13), "under 13 never gets ads, or the SDK")
        XCTAssertNil(audience(.unknown, .declined), "declining keeps the device ad-free")
        XCTAssertEqual(audience(.teen13to15), .teen)
        XCTAssertEqual(audience(.teen16to17), .teen)
        XCTAssertEqual(audience(.adult), .adult)
        XCTAssertEqual(AgeDefaults.adAudience(record: nil, storefrontCountry: nil), .teen, "unknown ages get teen protections")
        XCTAssertEqual(audience(.adult, .selfDeclared, "BRA"), .teen, "a self-declared adult in Brazil stays protected")
        XCTAssertEqual(audience(.adult, .apple, "BRA"), .adult)
        XCTAssertTrue(AdAudience.teen.isUnderAgeOfConsent)
        XCTAssertFalse(AdAudience.adult.isUnderAgeOfConsent)
    }

    func testRewardedAdsOnlyForFreeMembersWhoAreOut() {
        let policy = AdRewardPolicy.standard
        XCTAssertEqual(policy.dailyCap, 2)
        XCTAssertEqual(policy.creditsPerAd, 1)
        XCTAssertTrue(policy.offersAd(isPro: false, audience: .teen, balance: 0))
        XCTAssertFalse(policy.offersAd(isPro: false, audience: .adult, balance: 1), "not while she has credits")
        XCTAssertFalse(policy.offersAd(isPro: true, audience: .adult, balance: 0), "never for Pro")
        XCTAssertFalse(policy.offersAd(isPro: false, audience: nil, balance: 0), "never under 13")
    }

    /// The ad's credit lands among the free credits, so no ad while the
    /// server rests free AI or all of it: she couldn't use the credit today.
    func testNoRewardedAdWhileTheServerRestsAI() {
        let policy = AdRewardPolicy.standard
        let now = Date(timeIntervalSince1970: 1_000_000)
        let free = AIServicePause(freeOnly: true, until: now.addingTimeInterval(3600))
        let all = AIServicePause(freeOnly: false, until: now.addingTimeInterval(3600))
        XCTAssertFalse(policy.offersAd(isPro: false, audience: .teen, balance: 0, pause: free, now: now))
        XCTAssertFalse(policy.offersAd(isPro: false, audience: .adult, balance: 0, pause: all, now: now))
        XCTAssertTrue(policy.offersAd(isPro: false, audience: .teen, balance: 0, pause: free, now: now.addingTimeInterval(3600)),
                      "back once the pause is over")
        XCTAssertTrue(policy.offersAd(isPro: false, audience: .teen, balance: 0, pause: nil, now: now))
    }

    func testAdMobIDs() {
        XCTAssertTrue(AdMobID.isAppID("ca-app-pub-2292230772061554~5236020895"))
        XCTAssertTrue(AdMobID.isAppID("ca-app-pub-3940256099942544~1458002511"), "Google's test app id")
        XCTAssertTrue(AdMobID.isUnitID("ca-app-pub-2292230772061554/1406702504"))
        XCTAssertTrue(AdMobID.isUnitID("ca-app-pub-3940256099942544/4411468910"))
        XCTAssertFalse(AdMobID.isUnitID(""), "an empty unit means off")
        XCTAssertFalse(AdMobID.isUnitID("ca-app-pub-2292230772061554~5236020895"), "an app id isn't a unit")
        XCTAssertFalse(AdMobID.isAppID("REPLACE_ME"))
        XCTAssertEqual(AdMobID.publisher(of: "ca-app-pub-2292230772061554/1406702504"), "2292230772061554")
        XCTAssertEqual(AdMobID.publisher(of: "ca-app-pub-2292230772061554~5236020895"), "2292230772061554")
        XCTAssertNil(AdMobID.publisher(of: "nope"))
    }

    /// A unit from another account, or a typo, quietly turns that format off
    /// in Release builds (`AdsConfig`; check-release-config.py says the same).
    /// An empty interstitial unit is allowed: it means no interstitials.
    func testBundledAdUnitsBelongToTheApp() throws {
        struct Ads: Decodable { let enabled: Bool; let appID, rewardedUnitID, interstitialUnitID: String }
        struct Config: Decodable { let ads: Ads }
        let ads = try JSONDecoder().decode(
            Config.self, from: Data(contentsOf: RepositoryFile.url("ios/App/Resources/AppConfig.json"))).ads
        guard ads.enabled else { return }
        XCTAssertTrue(AdMobID.isAppID(ads.appID), ads.appID)
        let units = [ads.rewardedUnitID] + (ads.interstitialUnitID.isEmpty ? [] : [ads.interstitialUnitID])
        for unit in units {
            XCTAssertTrue(AdMobID.isUnitID(unit), "not an ad unit: \(unit)")
            XCTAssertEqual(AdMobID.publisher(of: unit), AdMobID.publisher(of: ads.appID), "another account's unit: \(unit)")
        }
    }

    // MARK: Interstitial pacing

    func testNoInterstitialsInTheFirstDayOrBeforeTheThirdSave() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var pacing = InterstitialPacing(firstLaunch: start)
        pacing.noteSave()
        pacing.noteSave()
        pacing.noteSave()
        XCTAssertFalse(pacing.allowsInterstitial(at: start.addingTimeInterval(23 * 3600), calendar: utc), "grace period")

        var fresh = InterstitialPacing(firstLaunch: start)
        let later = start.addingTimeInterval(25 * 3600)
        fresh.noteSave()
        fresh.noteSave()
        XCTAssertFalse(fresh.allowsInterstitial(at: later, calendar: utc), "not before the third save")
        XCTAssertTrue(fresh.worthPreloading(at: later, calendar: utc), "so the third save can show one at once")
        fresh.noteSave()
        XCTAssertTrue(fresh.allowsInterstitial(at: later, calendar: utc))

        var early = InterstitialPacing(firstLaunch: start)
        early.noteSave()
        XCTAssertFalse(early.worthPreloading(at: later, calendar: utc), "nothing is loaded two saves ahead")
        XCTAssertFalse(pacing.worthPreloading(at: start.addingTimeInterval(3600), calendar: utc), "or in the first day")
    }

    func testSpacingDailyCapAndRewardedAds() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var pacing = InterstitialPacing(firstLaunch: start, successfulSaves: 10)
        var now = utc.startOfDay(for: start.addingTimeInterval(3 * 24 * 3600)).addingTimeInterval(9 * 3600)
        XCTAssertTrue(pacing.allowsInterstitial(at: now, calendar: utc))
        pacing.noteShown(at: now, calendar: utc)
        XCTAssertFalse(pacing.allowsInterstitial(at: now.addingTimeInterval(3 * 60), calendar: utc), "at most one every 4 minutes")
        now.addTimeInterval(5 * 60)
        XCTAssertTrue(pacing.allowsInterstitial(at: now, calendar: utc))
        pacing.noteShown(at: now, calendar: utc)
        now.addTimeInterval(5 * 60)
        pacing.noteShown(at: now, calendar: utc)
        XCTAssertEqual(pacing.shownCount(on: now, calendar: utc), 3)
        now.addTimeInterval(60 * 60)
        XCTAssertFalse(pacing.allowsInterstitial(at: now, calendar: utc), "at most 3 a day")
        XCTAssertFalse(pacing.worthPreloading(at: now, calendar: utc), "and nothing more is loaded today")

        let tomorrow = utc.startOfDay(for: now).addingTimeInterval(24 * 3600 + 10 * 3600)
        XCTAssertTrue(pacing.allowsInterstitial(at: tomorrow, calendar: utc), "a new day")
        XCTAssertEqual(pacing.shownCount(on: tomorrow, calendar: utc), 0)

        pacing.noteRewardedAd(at: tomorrow)
        XCTAssertFalse(pacing.allowsInterstitial(at: tomorrow.addingTimeInterval(3 * 60), calendar: utc), "never within 4 minutes of a rewarded ad")
        XCTAssertTrue(pacing.allowsInterstitial(at: tomorrow.addingTimeInterval(5 * 60), calendar: utc))

        XCTAssertFalse(pacing.allowsInterstitial(at: tomorrow.addingTimeInterval(-3600), calendar: utc),
                       "a clock set back is too soon, not long ago")
    }

    func testPacingRoundTrips() throws {
        var pacing = InterstitialPacing(firstLaunch: Date(timeIntervalSince1970: 1_800_000_000), successfulSaves: 4)
        pacing.noteShown(at: Date(timeIntervalSince1970: 1_800_100_000), calendar: utc)
        pacing.noteRewardedAd(at: Date(timeIntervalSince1970: 1_800_100_500))
        let decoded = try JSONDecoder().decode(InterstitialPacing.self, from: JSONEncoder().encode(pacing))
        XCTAssertEqual(decoded, pacing)
    }

    // MARK: Wire format

    func testAdRewardRequests() throws {
        let token = try RequestFactory.adRewardToken(config: config, accessToken: "user-jwt", entitlementJWS: "jws")
        XCTAssertEqual(token.url?.absoluteString, "https://demo.supabase.co/functions/v1/ad-reward")
        XCTAssertEqual(token.httpMethod, "POST")
        XCTAssertEqual(token.value(forHTTPHeaderField: "Authorization"), "Bearer user-jwt")
        XCTAssertEqual(token.value(forHTTPHeaderField: RequestFactory.entitlementHeader), "jws")
        XCTAssertNil(token.httpBody, "the app sends nothing but its session")

        let status = try RequestFactory.adRewardStatus(token: "3f9a1c2e-5b7d-4e8f-9a0b-1c2d3e4f5a6b", config: config, accessToken: "user-jwt")
        XCTAssertEqual(status.url?.absoluteString,
                       "https://demo.supabase.co/functions/v1/ad-reward?token=3f9a1c2e-5b7d-4e8f-9a0b-1c2d3e4f5a6b")
        XCTAssertEqual(status.httpMethod, "GET")

        let release = try RequestFactory.releaseAdRewardToken(token: "t1", config: config, accessToken: "user-jwt")
        XCTAssertEqual(release.httpMethod, "DELETE")
        XCTAssertEqual(release.url?.query, "token=t1")

        let overview = try RequestFactory.adRewardOverview(config: config, accessToken: "user-jwt", appTransactionJWS: "app.jws")
        XCTAssertEqual(overview.httpMethod, "GET")
        XCTAssertNil(overview.url?.query)
        XCTAssertEqual(overview.value(forHTTPHeaderField: "X-App-Transaction"), "app.jws",
                       "ad credits belong to the App Store install, like the free ones")
        let tokenRequest = try RequestFactory.adRewardToken(config: config, accessToken: "user-jwt", appTransactionJWS: "app.jws")
        XCTAssertEqual(tokenRequest.value(forHTTPHeaderField: "X-App-Transaction"), "app.jws")
    }

    func testDecodesTokensAndStatuses() throws {
        let token = try ResponseDecoder.decodeAdRewardToken(data: Data("""
        {"token":"3f9a1c2e-5b7d-4e8f-9a0b-1c2d3e4f5a6b","expires_at":"2026-10-14T12:30:00Z","remaining_today":1,"daily_cap":2}
        """.utf8), statusCode: 201)
        XCTAssertEqual(token, AdRewardToken(token: "3f9a1c2e-5b7d-4e8f-9a0b-1c2d3e4f5a6b", expiresAt: "2026-10-14T12:30:00Z",
                                            remainingToday: 1, dailyCap: 2))

        let granted = try ResponseDecoder.decodeAdRewardStatus(data: Data("""
        {"token":"t","status":"granted","remaining_today":1,"daily_cap":2,"credits_remaining":1}
        """.utf8), statusCode: 200)
        XCTAssertEqual(granted.status, .granted)
        XCTAssertEqual(granted.creditsRemaining, 1)
        XCTAssertEqual(granted.remainingToday, 1)

        let overview = try ResponseDecoder.decodeAdRewardStatus(data: Data("""
        {"remaining_today":2,"daily_cap":2,"credits_remaining":0,"eligible":true}
        """.utf8), statusCode: 200)
        XCTAssertNil(overview.status)
        XCTAssertEqual(overview.eligible, true)

        let future = try ResponseDecoder.decodeAdRewardStatus(data: Data(#"{"status":"reviewing","remaining_today":0}"#.utf8), statusCode: 200)
        XCTAssertNil(future.status, "a status this version doesn't know reads as unconfirmed")

        XCTAssertThrowsError(try ResponseDecoder.decodeAdRewardToken(data: Data("{}".utf8), statusCode: 201))
    }

    func testDailyCapDecodesWhenNullOrNumber() throws {
        // The server sends null when its policy call failed: the app keeps its last cap.
        let nullToken = try ResponseDecoder.decodeAdRewardToken(data: Data(#"{"token":"t","remaining_today":1,"daily_cap":null}"#.utf8),
                                                                statusCode: 201)
        XCTAssertNil(nullToken.dailyCap)
        let nullStatus = try ResponseDecoder.decodeAdRewardStatus(data: Data(#"{"remaining_today":1,"daily_cap":null}"#.utf8),
                                                                  statusCode: 200)
        XCTAssertNil(nullStatus.dailyCap)
        let numberStatus = try ResponseDecoder.decodeAdRewardStatus(data: Data(#"{"remaining_today":1,"daily_cap":3}"#.utf8),
                                                                    statusCode: 200)
        XCTAssertEqual(numberStatus.dailyCap, 3)
        let missing = try ResponseDecoder.decodeAdRewardToken(data: Data(#"{"token":"t","remaining_today":1}"#.utf8), statusCode: 201)
        XCTAssertNil(missing.dailyCap)
    }

    func testMapsAdRewardErrors() {
        func error(_ status: Int, _ body: String) -> AdRewardError {
            ResponseDecoder.adRewardError(from: Data(body.utf8), statusCode: status)
        }
        XCTAssertEqual(error(403, #"{"error":{"code":"not_eligible","message":"Pro has no ads"}}"#), .notEligible)
        XCTAssertEqual(error(409, #"{"error":{"code":"has_credits","message":"x","credits_remaining":3}}"#), .hasCredits(3))
        XCTAssertEqual(error(409, #"{"error":{"code":"daily_cap","message":"x"}}"#), .dailyCap)
        XCTAssertEqual(error(401, #"{"error":{"code":"unauthorized","message":"x"}}"#), .unauthorized)
        XCTAssertEqual(error(500, "oops"), .server(code: "http_500", message: ""))
        XCTAssertThrowsError(try ResponseDecoder.decodeAdRewardToken(data: Data(#"{"error":{"code":"daily_cap","message":"x"}}"#.utf8),
                                                                     statusCode: 409)) { thrown in
            XCTAssertEqual(thrown as? AdRewardError, .dailyCap)
        }
    }

    // MARK: Pro tries (one Pro look or style for a rewarded ad)

    func testProTryItemsComeOnlyFromProLooksAndStyles() {
        XCTAssertEqual(ProTryItem(paywallSource: "template_doll-box"), .template("doll-box"))
        XCTAssertEqual(ProTryItem(paywallSource: "style_fantasy"), .style("fantasy"))
        let free = TemplateCatalog.all.first { !$0.isPro }!
        XCTAssertNil(ProTryItem(paywallSource: "template_\(free.id)"), "a free look needs no try")
        let freeStyle = StyleCatalog.all.first { !$0.isPro }!
        XCTAssertNil(ProTryItem(paywallSource: "style_\(freeStyle.id)"))
        XCTAssertNil(ProTryItem(paywallSource: "style_nope"), "an unknown style isn't the default one")
        XCTAssertNil(ProTryItem(paywallSource: "template_nope"))
        for source in ["create_count", "out_of_credits", "share_watermark", "settings", "template_", "style_"] {
            XCTAssertNil(ProTryItem(paywallSource: source), source)
        }
        for template in TemplateCatalog.all where template.isPro {
            let item = ProTryItem(paywallSource: "template_\(template.id)")
            XCTAssertEqual(item?.paywallSource, "template_\(template.id)")
            XCTAssertEqual(item?.operation, .restyle)
        }
        for style in StyleCatalog.all where style.isPro {
            XCTAssertEqual(ProTryItem(paywallSource: "style_\(style.id)")?.operation, .textToImage)
        }
    }

    func testProTryOfferRules() {
        let policy = ProTryPolicy.standard
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let item = ProTryItem.template("doll-box")
        let open = ProTryOverview(remainingToday: 1, dailyCap: 1, eligible: true)
        func offer(isPro: Bool = false, audience: AdAudience? = .teen, outputs: Int = 1, balance: Int = 2,
                   overview: ProTryOverview? = open, active: [ProTry] = [], pause: AIServicePause? = nil) -> ProTryOffer {
            policy.offer(for: item, isPro: isPro, audience: audience, outputs: outputs, balance: balance, cost: 1,
                         overview: overview, active: active, pause: pause, now: now)
        }

        XCTAssertEqual(offer(), .available(remaining: 1))
        XCTAssertEqual(offer(audience: .adult), .available(remaining: 1))
        XCTAssertEqual(offer(isPro: true), .none, "Pro has every look already, and no ads")
        XCTAssertEqual(offer(audience: nil), .none, "never under 13 (no ad audience)")
        XCTAssertEqual(offer(outputs: 4), .none, "several images at once stays Pro-only, even with a try")
        XCTAssertEqual(offer(overview: nil), .none, "only once the server has said")
        XCTAssertEqual(offer(pause: AIServicePause(freeOnly: true, until: now.addingTimeInterval(600))), .none,
                       "AI resting: the try couldn't start its job")
        XCTAssertEqual(offer(pause: AIServicePause(freeOnly: false, until: now.addingTimeInterval(-1))), .available(remaining: 1),
                       "a pause that ended is no pause")
        XCTAssertEqual(offer(balance: 0), .needsCredit, "the try's job costs a credit")
        XCTAssertEqual(offer(overview: ProTryOverview(remainingToday: 0, dailyCap: 1, eligible: false)), .capped)
        XCTAssertEqual(offer(balance: 0, overview: ProTryOverview(remainingToday: 0, dailyCap: 1, eligible: false)), .capped,
                       "a credit wouldn't help today")
        XCTAssertEqual(offer(overview: ProTryOverview(remainingToday: 0, dailyCap: 0, eligible: false)), .none,
                       "a cap of 0 turns tries off; nothing to explain")
        XCTAssertEqual(offer(overview: ProTryOverview(remainingToday: 1, dailyCap: 1, eligible: false)), .none,
                       "the server says no (a block, a cool-down, no verified install)")
        XCTAssertEqual(offer(overview: ProTryOverview(remainingToday: 1, dailyCap: nil, eligible: true)), .available(remaining: 1),
                       "an unread cap isn't a cap of 0")

        // A try she already has comes first, as long as it can still start a job.
        let live = ProTry(item: item, expiresAt: now.addingTimeInterval(20 * 60))
        XCTAssertEqual(offer(active: [live]), .ready(expiresAt: live.expiresAt))
        XCTAssertEqual(offer(overview: nil, active: [live]), .ready(expiresAt: live.expiresAt), "known before the server answers")
        XCTAssertEqual(offer(overview: ProTryOverview(remainingToday: 0, dailyCap: 1, eligible: false), active: [live]),
                       .ready(expiresAt: live.expiresAt), "today's try is this one")
        XCTAssertEqual(offer(balance: 0, active: [live]), .needsCredit)
        XCTAssertEqual(offer(isPro: true, active: [live]), .none)
        XCTAssertEqual(offer(active: [ProTry(item: .template("figurine"), expiresAt: live.expiresAt)]), .available(remaining: 1),
                       "a try covers exactly one look")
        XCTAssertEqual(offer(active: [ProTry(item: .style("doll-box"), expiresAt: live.expiresAt)]), .available(remaining: 1),
                       "a style's id isn't a look's")
        let ending = ProTry(item: item, expiresAt: now.addingTimeInterval(10))
        XCTAssertNil(policy.liveTry(for: item, in: [ending], at: now), "ending within the margin")
        XCTAssertNil(policy.liveTry(for: item, in: [ProTry(item: item, expiresAt: now.addingTimeInterval(-60))], at: now))
        XCTAssertEqual(policy.liveTry(for: item, in: [ending, live], at: now), live)
    }

    func testUnlockTokenRequests() throws {
        let look = try RequestFactory.adRewardUnlockToken(for: .template("doll-box"), config: config, accessToken: "user-jwt",
                                                          entitlementJWS: "jws", appTransactionJWS: "app.jws")
        XCTAssertEqual(look.url?.absoluteString, "https://demo.supabase.co/functions/v1/ad-reward")
        XCTAssertEqual(look.httpMethod, "POST")
        XCTAssertEqual(look.value(forHTTPHeaderField: "Authorization"), "Bearer user-jwt")
        XCTAssertEqual(look.value(forHTTPHeaderField: RequestFactory.entitlementHeader), "jws")
        XCTAssertEqual(look.value(forHTTPHeaderField: "X-App-Transaction"), "app.jws", "tries are counted per App Store install too")
        XCTAssertEqual(look.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(String(data: try XCTUnwrap(look.httpBody), encoding: .utf8), #"{"kind":"unlock","template_id":"doll-box"}"#)

        let style = try RequestFactory.adRewardUnlockToken(for: .style("fantasy"), config: config, accessToken: "user-jwt")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(style.httpBody)) as? [String: String])
        XCTAssertEqual(body, ["kind": "unlock", "style_id": "fantasy"], "her user id never goes along")
    }

    func testDecodesUnlockAnswers() throws {
        let token = try ResponseDecoder.decodeAdRewardToken(data: Data("""
        {"token":"t1","kind":"unlock","template_id":"doll-box","expires_at":"2026-10-16T12:30:00.123456+00:00",
         "remaining_today":0,"daily_cap":1}
        """.utf8), statusCode: 201)
        XCTAssertEqual(token.kind, "unlock")
        XCTAssertEqual(token.item, .template("doll-box"))
        XCTAssertEqual(token.remainingToday, 0)
        XCTAssertEqual(token.dailyCap, 1)
        let credit = try ResponseDecoder.decodeAdRewardToken(data: Data(#"{"token":"t","kind":"credit","remaining_today":1}"#.utf8),
                                                             statusCode: 201)
        XCTAssertNil(credit.item)

        let granted = try ResponseDecoder.decodeAdRewardStatus(data: Data("""
        {"token":"t1","kind":"unlock","status":"granted","style_id":"fantasy","remaining_today":0,"daily_cap":1,
         "credits_remaining":2,"expires_at":"2026-10-16T12:30:00.123456+00:00"}
        """.utf8), statusCode: 200)
        XCTAssertEqual(granted.status, .granted)
        XCTAssertEqual(granted.item, .style("fantasy"))
        XCTAssertEqual(granted.creditsRemaining, 2)
        let end = try XCTUnwrap(granted.expiresAt)
        XCTAssertEqual(end.timeIntervalSince1970, 1_792_153_800.123, accuracy: 0.001)

        let pending = try ResponseDecoder.decodeAdRewardStatus(data: Data("""
        {"token":"t1","kind":"unlock","status":"pending","template_id":"doll-box","remaining_today":0,"daily_cap":1}
        """.utf8), statusCode: 200)
        XCTAssertNil(pending.expiresAt, "a try's end comes with the grant")

        let overview = try ResponseDecoder.decodeAdRewardStatus(data: Data("""
        {"remaining_today":2,"daily_cap":2,"credits_remaining":1,"eligible":false,
         "unlock":{"remaining_today":0,"daily_cap":1,"eligible":false,
                   "active":[{"template_id":"doll-box","expires_at":"2026-10-16T12:30:00Z"},
                             {"style_id":"fantasy","expires_at":"2026-10-16T12:31:00.5+00:00"},
                             {"template_id":"doll-box","expires_at":"soon"},
                             {"expires_at":"2026-10-16T12:30:00Z"}]}}
        """.utf8), statusCode: 200)
        XCTAssertEqual(overview.remainingToday, 2, "the top level stays the credit ads")
        let unlock = try XCTUnwrap(overview.unlock)
        XCTAssertEqual(unlock.remainingToday, 0)
        XCTAssertEqual(unlock.dailyCap, 1)
        XCTAssertFalse(unlock.eligible)
        XCTAssertEqual(unlock.active.map(\.item), [.template("doll-box"), .style("fantasy")], "unreadable entries are skipped")

        let older = try ResponseDecoder.decodeAdRewardStatus(data: Data(#"{"remaining_today":2,"daily_cap":2,"eligible":true}"#.utf8),
                                                             statusCode: 200)
        XCTAssertNil(older.unlock, "a server before tries: no try card")
        let odd = try ResponseDecoder.decodeAdRewardStatus(data: Data(#"{"remaining_today":2,"unlock":"soon"}"#.utf8), statusCode: 200)
        XCTAssertNil(odd.unlock, "an unreadable block leaves the credit ads working")
        XCTAssertEqual(odd.remainingToday, 2)
    }

    func testServerDates() {
        XCTAssertEqual(ServerDate.parse("2026-10-16T12:30:00Z")?.timeIntervalSince1970, 1_792_153_800)
        XCTAssertEqual(ServerDate.parse("2026-10-16T12:30:00.250Z")?.timeIntervalSince1970 ?? 0, 1_792_153_800.25, accuracy: 0.001)
        XCTAssertEqual(ServerDate.parse("2026-10-16T15:30:00.123456+03:00")?.timeIntervalSince1970 ?? 0, 1_792_153_800.123, accuracy: 0.001)
        XCTAssertNil(ServerDate.parse("tomorrow"))
    }

    func testMapsUnlockErrors() {
        func error(_ status: Int, _ body: String) -> AdRewardError {
            ResponseDecoder.adRewardError(from: Data(body.utf8), statusCode: status)
        }
        XCTAssertEqual(error(409, #"{"error":{"code":"no_credits","message":"x","credits_remaining":0}}"#), .noCredits)
        XCTAssertEqual(error(409, #"{"error":{"code":"daily_cap","message":"x"}}"#), .dailyCap)
        XCTAssertEqual(error(400, #"{"error":{"code":"not_unlockable","message":"x"}}"#), .notUnlockable)
        XCTAssertEqual(error(400, #"{"error":{"code":"bad_request","message":"x"}}"#), .notUnlockable)
        XCTAssertEqual(error(503, #"{"error":{"code":"ai_paused","message":"x"}}"#), .aiPaused)
        XCTAssertEqual(error(403, #"{"error":{"code":"not_eligible","message":"x"}}"#), .notEligible)
    }
}
