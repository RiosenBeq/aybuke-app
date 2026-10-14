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
        XCTAssertEqual(policy.dailyCap, 3)
        XCTAssertEqual(policy.creditsPerAd, 1)
        XCTAssertTrue(policy.offersAd(isPro: false, audience: .teen, balance: 0))
        XCTAssertFalse(policy.offersAd(isPro: false, audience: .adult, balance: 1), "not while she has credits")
        XCTAssertFalse(policy.offersAd(isPro: true, audience: .adult, balance: 0), "never for Pro")
        XCTAssertFalse(policy.offersAd(isPro: false, audience: nil, balance: 0), "never under 13")
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

        let overview = try RequestFactory.adRewardOverview(config: config, accessToken: "user-jwt")
        XCTAssertEqual(overview.httpMethod, "GET")
        XCTAssertNil(overview.url?.query)
    }

    func testDecodesTokensAndStatuses() throws {
        let token = try ResponseDecoder.decodeAdRewardToken(data: Data("""
        {"token":"3f9a1c2e-5b7d-4e8f-9a0b-1c2d3e4f5a6b","expires_at":"2026-10-14T12:30:00Z","remaining_today":2,"daily_cap":3}
        """.utf8), statusCode: 201)
        XCTAssertEqual(token, AdRewardToken(token: "3f9a1c2e-5b7d-4e8f-9a0b-1c2d3e4f5a6b", expiresAt: "2026-10-14T12:30:00Z",
                                            remainingToday: 2, dailyCap: 3))

        let granted = try ResponseDecoder.decodeAdRewardStatus(data: Data("""
        {"token":"t","status":"granted","remaining_today":1,"daily_cap":3,"credits_remaining":1}
        """.utf8), statusCode: 200)
        XCTAssertEqual(granted.status, .granted)
        XCTAssertEqual(granted.creditsRemaining, 1)
        XCTAssertEqual(granted.remainingToday, 1)

        let overview = try ResponseDecoder.decodeAdRewardStatus(data: Data("""
        {"remaining_today":3,"daily_cap":3,"credits_remaining":0,"eligible":true}
        """.utf8), statusCode: 200)
        XCTAssertNil(overview.status)
        XCTAssertEqual(overview.eligible, true)

        let future = try ResponseDecoder.decodeAdRewardStatus(data: Data(#"{"status":"reviewing","remaining_today":0}"#.utf8), statusCode: 200)
        XCTAssertNil(future.status, "a status this version doesn't know reads as unconfirmed")

        XCTAssertThrowsError(try ResponseDecoder.decodeAdRewardToken(data: Data("{}".utf8), statusCode: 201))
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
}
