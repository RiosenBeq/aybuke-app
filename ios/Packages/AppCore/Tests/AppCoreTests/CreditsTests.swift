import XCTest
@testable import AppCore

final class CreditsTests: XCTestCase {
    private let policy = CreditPolicy.standard
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    func testCosts() {
        XCTAssertEqual(policy.cost(of: .removeBackground), 0)
        XCTAssertEqual(policy.cost(of: .textToImage, outputs: 4), 4)
        XCTAssertEqual(policy.cost(of: .magicEdit, outputs: 0), 1)
    }

    func testFreeDailyAllowanceRefillsWithoutAccumulating() throws {
        var wallet = CreditWallet.fresh(now: date(10, 11), policy: policy)
        XCTAssertEqual(wallet.balance, 2)
        try wallet.spend(2)
        wallet.refresh(now: date(10, 11, 23), isPro: false, policy: policy, calendar: calendar)
        XCTAssertEqual(wallet.balance, 0, "same day: no refill")
        wallet.refresh(now: date(10, 12, 1), isPro: false, policy: policy, calendar: calendar)
        XCTAssertEqual(wallet.balance, 2)
        wallet.refresh(now: date(10, 15, 1), isPro: false, policy: policy, calendar: calendar)
        XCTAssertEqual(wallet.balance, 2, "unused daily credits don't roll over")
    }

    func testInsufficientAndInvalidAmounts() throws {
        var wallet = CreditWallet.fresh(now: date(10, 11), policy: policy)
        try wallet.spend(1)
        XCTAssertThrowsError(try wallet.spend(2)) { error in
            XCTAssertEqual(error as? CreditError, .insufficient(needed: 2, available: 1))
        }
        XCTAssertThrowsError(try wallet.spend(-1)) { error in
            XCTAssertEqual(error as? CreditError, .invalidAmount)
        }
    }

    func testSubscribingGrantsMonthlyAllowanceThatRollsOverUpToCap() {
        var wallet = CreditWallet.fresh(now: date(10, 11), policy: policy)
        wallet.refresh(now: date(10, 11, 10), isPro: true, policy: policy, calendar: calendar)
        XCTAssertEqual(wallet.subscription, 80)
        XCTAssertEqual(wallet.balance, 82, "today's free credits stay until midnight")

        wallet.refresh(now: date(10, 12), isPro: true, policy: policy, calendar: calendar)
        XCTAssertEqual(wallet.daily, 0, "Pro doesn't also accrue free daily credits")

        wallet.refresh(now: date(11, 12), isPro: true, policy: policy, calendar: calendar)
        XCTAssertEqual(wallet.subscription, 160, "one month of rollover")

        wallet.refresh(now: date(12, 13), isPro: true, policy: policy, calendar: calendar)
        XCTAssertEqual(wallet.subscription, 160, "capped at allowance + one month")
    }

    func testLosingProExpiresSubscriptionCreditsButKeepsPurchased() {
        var wallet = CreditWallet.fresh(now: date(10, 11), policy: policy)
        wallet.addPurchased(30)
        wallet.refresh(now: date(10, 11, 10), isPro: true, policy: policy, calendar: calendar)
        wallet.refresh(now: date(10, 20), isPro: false, policy: policy, calendar: calendar)
        XCTAssertEqual(wallet.subscription, 0)
        XCTAssertFalse(wallet.isSubscribed)
        XCTAssertEqual(wallet.purchased, 30)
        XCTAssertEqual(wallet.daily, 2, "back on the free daily allowance")
    }

    func testSpendsExpiringCreditsFirstAndRefundsExactly() throws {
        var wallet = CreditWallet(daily: 2, dailyPeriodStart: date(10, 11), subscription: 1, subscriptionPeriodStart: date(10, 1), purchased: 10)
        let charge = try wallet.spend(4)
        XCTAssertEqual(charge, CreditCharge(daily: 2, subscription: 1, purchased: 1))
        XCTAssertEqual(wallet.balance, 9)
        wallet.refund(charge, policy: policy)
        XCTAssertEqual(wallet, CreditWallet(daily: 2, dailyPeriodStart: date(10, 11), subscription: 1, subscriptionPeriodStart: date(10, 1), purchased: 10))
    }

    func testRefundNeverExceedsDailyAllowance() throws {
        var wallet = CreditWallet.fresh(now: date(10, 11), policy: policy)
        let charge = try wallet.spend(1)
        wallet.refresh(now: date(10, 12), isPro: false, policy: policy, calendar: calendar)
        wallet.refund(charge, policy: policy)
        XCTAssertEqual(wallet.daily, 2)
    }

    /// The bundled numbers match the server's credit_policy() (backend
    /// migration 20261020) and AppConfig.json's creditPolicy.
    func testStandardPolicyMatchesTheServer() throws {
        XCTAssertEqual(policy, CreditPolicy(freeDailyAllowance: 2, proMonthlyAllowance: 80, proRolloverCap: 160,
                                            trialCredits: 20, freeRetriesPerDay: 3))
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let config = root.appendingPathComponent("ios/App/Resources/AppConfig.json")
        guard FileManager.default.fileExists(atPath: config.path) else { throw XCTSkip("AppConfig.json not found") }
        struct Config: Decodable { let creditPolicy: CreditPolicy }
        XCTAssertEqual(try JSONDecoder().decode(Config.self, from: Data(contentsOf: config)).creditPolicy, policy,
                       "AppConfig.json's creditPolicy is the bundled default")
        let migration = root.appendingPathComponent("backend/supabase/migrations/20261020000000_credit_policy_v2.sql")
        guard let sql = try? String(contentsOf: migration, encoding: .utf8) else { throw XCTSkip("migration not found") }
        for (number, name) in [(2, "free_daily"), (80, "pro_monthly"), (160, "pro_rollover_cap"), (20, "trial_credits"),
                               (3, "free_retries_daily")] {
            XCTAssertTrue(sql.contains("\(number),") && sql.contains("-- \(name)"), "credit_policy() says \(number) for \(name)")
            let line = sql.split(separator: "\n").first { $0.hasSuffix("-- \(name)") }
            XCTAssertEqual(line?.trimmingCharacters(in: .whitespaces).hasPrefix("\(number),"), true, name)
        }
    }

    func testServerPolicyWinsWhenSane() throws {
        let server = try JSONDecoder().decode(BalanceState.self, from: Data("""
        {"credits_remaining": 4, "policy": {"free_daily": 1, "pro_monthly": 60, "rollover_cap": -5, "trial_credits": 15}}
        """.utf8))
        let merged = CreditPolicy(server: try XCTUnwrap(server.policy), fallback: .standard)
        XCTAssertEqual(merged, CreditPolicy(freeDailyAllowance: 1, proMonthlyAllowance: 60, proRolloverCap: 160,
                                            trialCredits: 15, freeRetriesPerDay: 3), "a broken number keeps the fallback's")
        // The app's cache and AppConfig.json use the same keys; missing ones keep the standard numbers.
        let partial = try JSONDecoder().decode(CreditPolicy.self, from: Data(#"{"freeDaily": 5}"#.utf8))
        XCTAssertEqual(partial.freeDailyAllowance, 5)
        XCTAssertEqual(partial.proMonthlyAllowance, 80)
        let roundTrip = try JSONDecoder().decode(CreditPolicy.self, from: JSONEncoder().encode(merged))
        XCTAssertEqual(roundTrip, merged)
    }

    func testNextDailyRefillIsNextMidnight() {
        let wallet = CreditWallet.fresh(now: date(10, 11, 15), policy: policy)
        XCTAssertEqual(wallet.nextDailyRefill(calendar: calendar), date(10, 12, 0))
    }

    func testWalletRoundTripsThroughCodable() throws {
        var wallet = CreditWallet.fresh(now: date(10, 11), policy: policy)
        wallet.refresh(now: date(10, 11, 10), isPro: true, policy: policy, calendar: calendar)
        wallet.addPurchased(5)
        let decoded = try JSONDecoder().decode(CreditWallet.self, from: JSONEncoder().encode(wallet))
        XCTAssertEqual(decoded, wallet)
    }

    func testNextSubscriptionGrantIsTheFirstMomentRefreshGrants() throws {
        var wallet = CreditWallet.fresh(now: date(1, 31, 10), policy: policy)
        XCTAssertNil(wallet.nextSubscriptionGrant(calendar: calendar), "no subscription yet")
        wallet.refresh(now: date(1, 31, 10), isPro: true, policy: policy, calendar: calendar)
        let grant = try XCTUnwrap(wallet.nextSubscriptionGrant(calendar: calendar))

        var justBefore = wallet
        justBefore.refresh(now: grant.addingTimeInterval(-1), isPro: true, policy: policy, calendar: calendar)
        XCTAssertEqual(justBefore.subscription, wallet.subscription)
        var atGrant = wallet
        atGrant.refresh(now: grant, isPro: true, policy: policy, calendar: calendar)
        XCTAssertEqual(atGrant.subscription, wallet.subscription + policy.proMonthlyAllowance)
        XCTAssertEqual(atGrant.nextSubscriptionGrant(calendar: calendar).map { $0 > grant }, true)

        atGrant.refresh(now: date(4, 1), isPro: false, policy: policy, calendar: calendar)
        XCTAssertNil(atGrant.nextSubscriptionGrant(calendar: calendar), "none after Pro ends")
    }
}

final class SizingTests: XCTestCase {
    func testAspectRatioPixelSizesAreMultiplesOf64() {
        for ratio in AspectRatio.allCases {
            let size = ratio.pixelSize()
            XCTAssertEqual(size.width % 64, 0, ratio.rawValue)
            XCTAssertEqual(size.height % 64, 0, ratio.rawValue)
            XCTAssertEqual(size.longEdge, 1536, ratio.rawValue)
        }
        XCTAssertEqual(AspectRatio.story.pixelSize(), PixelSize(width: 896, height: 1536)) // 864 → nearest multiple of 64
    }

    func testFitNeverUpscales() {
        XCTAssertEqual(ImageSizing.fit(PixelSize(width: 800, height: 600), maxLongEdge: 1536), PixelSize(width: 800, height: 600))
        XCTAssertEqual(ImageSizing.fit(PixelSize(width: 4032, height: 3024), maxLongEdge: 1536), PixelSize(width: 1536, height: 1152))
        XCTAssertEqual(ImageSizing.fit(PixelSize(width: 3024, height: 4032), maxLongEdge: 1024), PixelSize(width: 768, height: 1024))
    }
}
