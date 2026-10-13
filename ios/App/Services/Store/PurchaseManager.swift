import Foundation
import StoreKit
import Observation

enum StoreProducts {
    static let monthly = "app.glowlit.pro.monthly"
    static let yearly = "app.glowlit.pro.yearly"
    static let credits30 = "app.glowlit.credits.30"
    static let credits100 = "app.glowlit.credits.100"

    static let subscriptions: Set<String> = [monthly, yearly]
    /// Consumable packs → number of credits they grant (never expire).
    static let creditPacks: [String: Int] = [credits30: 30, credits100: 100]
    static var all: Set<String> { subscriptions.union(creditPacks.keys) }
}

/// StoreKit 2 subscriptions and credit packs. Entitlements are re-derived from
/// `Transaction.currentEntitlements` so restores, refunds and family changes
/// are picked up automatically.
@MainActor
@Observable
final class PurchaseManager {
    private(set) var products: [Product] = []
    private(set) var isPro = false
    private(set) var isPurchasing = false
    private(set) var loadError: String?
    /// JWS of the active entitlement, forwarded to the backend so it can verify
    /// Pro status with Apple's signature instead of trusting the client.
    private(set) var entitlementJWS: String?

    /// Grants credits for a verified consumable transaction (locally in demo
    /// mode, via the backend in production). Return `true` once granted; the
    /// transaction is only finished after that, so nothing is lost on failure.
    @ObservationIgnored var creditPackHandler: ((_ credits: Int, _ jws: String) async -> Bool)?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
    }

    var monthly: Product? { products.first { $0.id == StoreProducts.monthly } }
    var yearly: Product? { products.first { $0.id == StoreProducts.yearly } }
    var creditPacks: [Product] {
        products.filter { StoreProducts.creditPacks[$0.id] != nil }.sorted { $0.price < $1.price }
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            products = try await Product.products(for: StoreProducts.all)
            loadError = products.isEmpty ? String(localized: "Subscriptions are unavailable right now.") : nil
        } catch {
            loadError = String(localized: "Couldn't reach the App Store. Check your connection.")
        }
    }

    /// Returns `true` when the purchase completed (Pro unlocked or credits added).
    @discardableResult
    func purchase(_ product: Product, appAccountToken: UUID? = nil) async throws -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }

        var options: Set<Product.PurchaseOption> = []
        if let appAccountToken {
            options.insert(.appAccountToken(appAccountToken))
        }
        let result = try await product.purchase(options: options)
        await RevenueCatBridge.record(result)
        switch result {
        case .success(let verification):
            return await handle(verification)
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var active = false
        var jws: String?
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if StoreProducts.subscriptions.contains(transaction.productID), transaction.revocationDate == nil {
                active = true
                jws = entitlement.jwsRepresentation
            }
        }
        isPro = active
        entitlementJWS = jws
    }

    func isEligibleForTrial(_ product: Product) async -> Bool {
        guard let subscription = product.subscription, subscription.introductoryOffer != nil else { return false }
        return await subscription.isEligibleForIntroOffer
    }

    @discardableResult
    private func handle(_ verification: VerificationResult<Transaction>) async -> Bool {
        guard case .verified(let transaction) = verification else { return false }
        if let credits = StoreProducts.creditPacks[transaction.productID] {
            guard transaction.revocationDate == nil else {
                await transaction.finish()
                return false
            }
            let granted = await creditPackHandler?(credits, verification.jwsRepresentation) ?? false
            if granted {
                await transaction.finish()
            }
            return granted
        }
        await transaction.finish()
        await refreshEntitlements()
        return isPro
    }
}

extension Product {
    /// "7-day free trial" when the product has a free introductory offer.
    var freeTrialDescription: String? {
        guard let offer = subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        return String(localized: "\(offer.period.dayCount)-day free trial")
    }

    var freeTrialDays: Int? {
        guard let offer = subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        return offer.period.dayCount
    }

    /// Monthly equivalent of a yearly price ("just $3.33/month").
    var monthlyEquivalentPrice: String? {
        guard let period = subscription?.subscriptionPeriod, period.unit == .year else { return nil }
        return (price / Decimal(12 * period.value)).formatted(priceFormatStyle)
    }

    /// A paid introductory offer ("First month $1.99"), when there is one.
    var introOfferText: String? {
        guard let offer = subscription?.introductoryOffer, offer.paymentMode != .freeTrial else { return nil }
        let count = offer.period.value * max(offer.periodCount, 1)
        let price = offer.displayPrice
        // Whole sentences per period, so every language can phrase them naturally.
        switch (offer.period.unit, count == 1) {
        case (.day, true): return String(localized: "First day \(price)")
        case (.day, false): return String(localized: "First \(count) days \(price) each")
        case (.week, true): return String(localized: "First week \(price)")
        case (.week, false): return String(localized: "First \(count) weeks \(price) each")
        case (.month, true): return String(localized: "First month \(price)")
        case (.month, false): return String(localized: "First \(count) months \(price) each")
        case (.year, true): return String(localized: "First year \(price)")
        case (.year, false): return String(localized: "First \(count) years \(price) each")
        @unknown default: return nil
        }
    }

    /// Weekly equivalent of the price, for "just $0.96/week" anchoring.
    var weeklyEquivalentPrice: String? {
        guard let period = subscription?.subscriptionPeriod else { return nil }
        let weeks: Decimal
        switch period.unit {
        case .day: weeks = Decimal(period.value) / 7
        case .week: weeks = Decimal(period.value)
        case .month: weeks = Decimal(period.value) * 52 / 12
        case .year: weeks = Decimal(period.value) * 52
        @unknown default: return nil
        }
        guard weeks > 0 else { return nil }
        return (price / weeks).formatted(priceFormatStyle)
    }

    var periodLabel: String {
        guard let period = subscription?.subscriptionPeriod else { return "" }
        switch period.unit {
        case .day: return period.value == 7 ? "week" : "day"
        case .week: return "week"
        case .month: return period.value == 12 ? "year" : "month"
        case .year: return "year"
        @unknown default: return ""
        }
    }
}

extension Product.SubscriptionPeriod {
    var dayCount: Int {
        switch unit {
        case .day: return value
        case .week: return value * 7
        case .month: return value * 30
        case .year: return value * 365
        @unknown default: return value
        }
    }
}
