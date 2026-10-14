import Foundation

/// Credit rules ("Fair-Price Promise", see docs/03-product-spec.md):
/// - Free users get a small daily allowance that refills every day.
/// - Pro subscribers get a monthly allowance; unused credits roll over up to a cap.
/// - Purchased credit packs never expire.
/// - Failed generations are refunded automatically.
///
/// The backend is the source of truth in production (`credit_policy()` in
/// SQL): `GET /ai-image` returns these numbers with the balance, the app
/// keeps the last ones it saw and shows them in its copy, with bundled
/// defaults in AppConfig.json. The app mirrors the same rules for instant UI
/// feedback and for the offline demo mode.
public struct CreditPolicy: Equatable, Sendable, Codable {
    /// Free credits per App Store install per day (UTC on the server).
    public var freeDailyAllowance: Int
    public var proMonthlyAllowance: Int
    /// Maximum subscription credits that can be banked (allowance + rollover).
    public var proRolloverCap: Int
    /// What the yearly plan's 7-day free trial brings, instead of a month's
    /// credits; the full month starts with the first paid period.
    public var trialCredits: Int
    /// Likeness Lock: still one free retry per result, at most this many a day.
    public var freeRetriesPerDay: Int

    public init(
        freeDailyAllowance: Int, proMonthlyAllowance: Int, proRolloverCap: Int,
        trialCredits: Int = CreditPolicy.standard.trialCredits,
        freeRetriesPerDay: Int = CreditPolicy.standard.freeRetriesPerDay
    ) {
        self.freeDailyAllowance = freeDailyAllowance
        self.proMonthlyAllowance = proMonthlyAllowance
        self.proRolloverCap = proRolloverCap
        self.trialCredits = trialCredits
        self.freeRetriesPerDay = freeRetriesPerDay
    }

    /// Sized from the unit economics in docs/03-product-spec.md (low quality
    /// $0.04 and medium $0.06 per image, about $0.01 more per edited photo):
    /// 2 free creations a day, 80 a month on Pro with one month of rollover,
    /// 20 in the yearly plan's trial week. The server can change all of these
    /// without an app update.
    public static let standard = CreditPolicy(
        freeDailyAllowance: 2, proMonthlyAllowance: 80, proRolloverCap: 160, trialCredits: 20, freeRetriesPerDay: 3
    )

    /// The server's numbers over `fallback`, each one only when it's sane, so
    /// a missing or broken value never reaches the copy.
    public init(server: ServerCreditPolicy, fallback: CreditPolicy) {
        func pick(_ value: Int?, _ fallback: Int) -> Int {
            guard let value, (0...10_000).contains(value) else { return fallback }
            return value
        }
        self.init(
            freeDailyAllowance: pick(server.freeDaily, fallback.freeDailyAllowance),
            proMonthlyAllowance: pick(server.proMonthly, fallback.proMonthlyAllowance),
            proRolloverCap: pick(server.rolloverCap, fallback.proRolloverCap),
            trialCredits: pick(server.trialCredits, fallback.trialCredits),
            freeRetriesPerDay: pick(server.freeRetriesDaily, fallback.freeRetriesPerDay)
        )
    }

    /// The keys of AppConfig.json's `creditPolicy` and of the app's cache.
    enum CodingKeys: String, CodingKey {
        case freeDailyAllowance = "freeDaily"
        case proMonthlyAllowance = "proMonthly"
        case proRolloverCap = "rolloverCap"
        case trialCredits
        case freeRetriesPerDay = "freeRetriesDaily"
    }

    /// Missing keys keep `standard`'s numbers.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let base = CreditPolicy.standard
        self.init(server: ServerCreditPolicy(
            freeDaily: try container.decodeIfPresent(Int.self, forKey: .freeDailyAllowance),
            proMonthly: try container.decodeIfPresent(Int.self, forKey: .proMonthlyAllowance),
            rolloverCap: try container.decodeIfPresent(Int.self, forKey: .proRolloverCap),
            trialCredits: try container.decodeIfPresent(Int.self, forKey: .trialCredits),
            freeRetriesDaily: try container.decodeIfPresent(Int.self, forKey: .freeRetriesPerDay)
        ), fallback: base)
    }

    public func cost(of operation: AIOperation, outputs: Int = 1) -> Int {
        let unitCost: Int
        switch operation {
        case .removeBackground:
            unitCost = 0 // on-device, free forever
        case .textToImage, .magicEdit, .enhance, .eraseObject, .restyle:
            unitCost = 1
        }
        return unitCost * max(1, outputs)
    }
}

public enum CreditError: Error, Equatable, Sendable {
    case insufficient(needed: Int, available: Int)
    case invalidAmount
}

/// Which buckets a job was paid from, so a failure can be refunded exactly.
public struct CreditCharge: Equatable, Sendable, Codable {
    public var daily: Int
    public var subscription: Int
    public var purchased: Int

    public init(daily: Int = 0, subscription: Int = 0, purchased: Int = 0) {
        self.daily = daily
        self.subscription = subscription
        self.purchased = purchased
    }

    public var total: Int { daily + subscription + purchased }

    public static let none = CreditCharge()
}

public struct CreditWallet: Equatable, Sendable, Codable {
    public private(set) var daily: Int
    public private(set) var dailyPeriodStart: Date
    public private(set) var subscription: Int
    /// Start of the current subscription month; `nil` while not subscribed.
    public private(set) var subscriptionPeriodStart: Date?
    public private(set) var purchased: Int

    public init(daily: Int, dailyPeriodStart: Date, subscription: Int = 0, subscriptionPeriodStart: Date? = nil, purchased: Int = 0) {
        self.daily = daily
        self.dailyPeriodStart = dailyPeriodStart
        self.subscription = subscription
        self.subscriptionPeriodStart = subscriptionPeriodStart
        self.purchased = purchased
    }

    public static func fresh(now: Date, policy: CreditPolicy) -> CreditWallet {
        CreditWallet(daily: policy.freeDailyAllowance, dailyPeriodStart: now)
    }

    public var balance: Int { daily + subscription + purchased }

    public var isSubscribed: Bool { subscriptionPeriodStart != nil }

    /// Applies refills and expiries for the given moment.
    public mutating func refresh(now: Date, isPro: Bool, policy: CreditPolicy, calendar: Calendar = .current) {
        if !calendar.isDate(now, inSameDayAs: dailyPeriodStart) {
            // Daily credits are a free-tier perk and never accumulate.
            daily = isPro ? 0 : policy.freeDailyAllowance
            dailyPeriodStart = now
        }

        if isPro {
            if let start = subscriptionPeriodStart {
                let elapsedMonths = calendar.dateComponents([.month], from: start, to: now).month ?? 0
                if elapsedMonths > 0 {
                    subscription = min(subscription + elapsedMonths * policy.proMonthlyAllowance, policy.proRolloverCap)
                    subscriptionPeriodStart = calendar.date(byAdding: .month, value: elapsedMonths, to: start) ?? now
                }
            } else {
                subscription = min(subscription + policy.proMonthlyAllowance, policy.proRolloverCap)
                subscriptionPeriodStart = now
            }
        } else if subscriptionPeriodStart != nil {
            // Subscription credits end with the subscription; purchased packs stay.
            subscription = 0
            subscriptionPeriodStart = nil
            daily = policy.freeDailyAllowance
            dailyPeriodStart = now
        }
    }

    public func canAfford(_ cost: Int) -> Bool {
        cost >= 0 && cost <= balance
    }

    /// Spends expiring credits first: daily → subscription → purchased.
    @discardableResult
    public mutating func spend(_ cost: Int) throws -> CreditCharge {
        guard cost >= 0 else { throw CreditError.invalidAmount }
        guard cost <= balance else { throw CreditError.insufficient(needed: cost, available: balance) }
        var remaining = cost
        let fromDaily = min(daily, remaining)
        daily -= fromDaily
        remaining -= fromDaily
        let fromSubscription = min(subscription, remaining)
        subscription -= fromSubscription
        remaining -= fromSubscription
        let fromPurchased = min(purchased, remaining)
        purchased -= fromPurchased
        return CreditCharge(daily: fromDaily, subscription: fromSubscription, purchased: fromPurchased)
    }

    /// Gives back exactly what a failed job was charged (never above the caps).
    public mutating func refund(_ charge: CreditCharge, policy: CreditPolicy) {
        daily = min(daily + max(0, charge.daily), policy.freeDailyAllowance)
        subscription = min(subscription + max(0, charge.subscription), policy.proRolloverCap)
        purchased += max(0, charge.purchased)
    }

    /// Credits bought as a one-off pack. They never expire.
    public mutating func addPurchased(_ amount: Int) {
        guard amount > 0 else { return }
        purchased += amount
    }

    public func nextDailyRefill(calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: dailyPeriodStart)
        return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? dailyPeriodStart.addingTimeInterval(86_400)
    }

    /// The first moment `refresh` grants the next monthly Pro allowance;
    /// nil without a subscription. Uses the same month arithmetic as `refresh`.
    public func nextSubscriptionGrant(calendar: Calendar = .current) -> Date? {
        guard let start = subscriptionPeriodStart else { return nil }
        return calendar.date(byAdding: .month, value: 1, to: start)
    }
}
