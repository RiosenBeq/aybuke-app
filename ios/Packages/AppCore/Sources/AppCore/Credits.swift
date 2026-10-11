import Foundation

/// Credit rules ("Fair-Price Promise", see docs/03-product-spec.md):
/// - Free users get a small daily allowance that refills every day.
/// - Pro subscribers get a monthly allowance; unused credits roll over up to a cap.
/// - Purchased credit packs never expire.
/// - Failed generations are refunded automatically.
///
/// The backend is the source of truth in production; the app mirrors the same
/// rules for instant UI feedback and for the offline demo mode.
public struct CreditPolicy: Equatable, Sendable {
    public var freeDailyAllowance: Int
    public var proMonthlyAllowance: Int
    /// Maximum subscription credits that can be banked (allowance + rollover).
    public var proRolloverCap: Int

    public init(freeDailyAllowance: Int, proMonthlyAllowance: Int, proRolloverCap: Int) {
        self.freeDailyAllowance = freeDailyAllowance
        self.proMonthlyAllowance = proMonthlyAllowance
        self.proRolloverCap = proRolloverCap
    }

    /// Sized from the unit economics in docs/03-product-spec.md (~$0.06 per
    /// cloud operation): 3 free creations a day, 100 a month on Pro with one
    /// month of rollover. The server can change these without an app update.
    public static let standard = CreditPolicy(freeDailyAllowance: 3, proMonthlyAllowance: 100, proRolloverCap: 200)

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
}
