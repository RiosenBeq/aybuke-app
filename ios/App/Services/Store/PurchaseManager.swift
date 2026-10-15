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

/// What `PurchaseManager.purchase` ended with.
enum PurchaseOutcome {
    case purchased
    /// Waiting for someone's approval (Ask to Buy, or a payment that needs
    /// action). StoreKit reports only an approval, never a decline.
    case pending
    case cancelled
}

/// A purchase that completed outside `purchase(_:)`: an approved pending
/// purchase or a redeemed offer code, delivered through `Transaction.updates`.
/// The free trial she's in: when it ends, its first payment and whether it
/// renews (cancelling turns that off; the trial itself runs to the end).
struct TrialStatus: Equatable {
    let productID: String
    let endsAt: Date
    let price: String?
    let willRenew: Bool
}

struct LatePurchase {
    let productID: String
    /// The end of a free trial that this purchase started.
    let trialEndsAt: Date?

    var isCreditPack: Bool { StoreProducts.creditPacks[productID] != nil }
}

/// StoreKit 2 subscriptions and credit packs. Entitlements are re-derived from
/// `Transaction.currentEntitlements` so restores, refunds and family changes
/// are picked up automatically.
@MainActor
@Observable
final class PurchaseManager {
    enum LoadState: Equatable {
        case idle, loading, loaded
        /// No answer in time, or an error.
        case unreachable
        /// The App Store answered without some products (say, plans not
        /// attached to this build yet).
        case unavailable
    }

    private(set) var products: [Product] = []
    private(set) var isPro = false
    private(set) var isPurchasing = false
    private(set) var loadState = LoadState.idle
    /// False with Screen Time purchase restrictions or device management:
    /// the buy buttons are then turned off, Restore still works.
    private(set) var canMakePayments = true
    /// A demo-mode build installed from the App Store: its AI only makes
    /// samples, so it never takes real money (see `closeForPreview`).
    private(set) var isClosedForPreview = false
    /// Waiting for approval. Kept in memory only: a decline never arrives,
    /// so the waiting state clears on the next launch.
    private(set) var pendingProductIDs: Set<String> = []
    /// JWS of the active entitlement, forwarded to the backend so it can verify
    /// Pro status with Apple's signature instead of trusting the client.
    private(set) var entitlementJWS: String?
    /// The running free trial, if any (Settings › Membership, the reminder).
    private(set) var trial: TrialStatus?
    /// She has bought Pro or a credit pack: on this Apple Account (StoreKit's
    /// history, `refreshPurchaseHistory()`) or on this device (a pack's
    /// transaction is finished once redeemed, so StoreKit forgets it; kept
    /// here). Settings › Account offers Sign in with Apple in full only then.
    /// Delete my data forgets it (`forgetPurchases()`).
    private(set) var hasPurchased: Bool

    /// Grants credits for a verified consumable transaction (locally in demo
    /// mode, via the backend in production). Return `true` once granted; the
    /// transaction is only finished after that, so nothing is lost on failure.
    @ObservationIgnored var creditPackHandler: ((_ credits: Int, _ jws: String) async -> Bool)?
    /// Pro switched on or off (purchase, renewal, expiry, refund, offer code).
    @ObservationIgnored var onProStatusChange: ((Bool) -> Void)?
    /// A purchase completed in the background (see `LatePurchase`).
    @ObservationIgnored var onLatePurchase: ((LatePurchase) -> Void)?
    /// The trial started, ended or was cancelled (or not, re-checked).
    @ObservationIgnored var onTrialChange: ((TrialStatus?) -> Void)?
    @ObservationIgnored private var statusTask: Task<Void, Never>?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var hasCheckedEntitlements = false
    @ObservationIgnored private var isRequestInFlight = false
    @ObservationIgnored private var loadTimeout: Task<Void, Never>?
    private let defaults: UserDefaults
    nonisolated static let purchasedKey = "purchases.hasPurchased.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasPurchased = defaults.bool(forKey: Self.purchasedKey)
        #if DEBUG
        if Self.debugPro { isPro = true }
        if Self.debugPro || UserDefaults.standard.bool(forKey: "GLPurchased") { hasPurchased = true }
        #endif
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update, isUpdate: true)
            }
        }
        // Cancelling in Settings › Subscriptions arrives here, not as a transaction.
        statusTask = Task { [weak self] in
            for await _ in Product.SubscriptionInfo.Status.updates {
                await self?.refreshEntitlements()
            }
        }
    }

    var monthly: Product? { products.first { $0.id == StoreProducts.monthly } }
    var yearly: Product? { products.first { $0.id == StoreProducts.yearly } }
    var creditPacks: [Product] {
        products.filter { StoreProducts.creditPacks[$0.id] != nil }.sorted { $0.price < $1.price }
    }

    /// The buy buttons work (Restore and Manage always do).
    var canBuy: Bool { canMakePayments && !isClosedForPreview }

    /// Both plans share one subscription group, so one waiting plan blocks both.
    var isSubscriptionPending: Bool { !pendingProductIDs.isDisjoint(with: StoreProducts.subscriptions) }

    /// Loads every product. Shows a failure after 10 seconds without waiting
    /// for StoreKit (it may ignore cancellation); a late answer still lands.
    func loadProducts() async {
        canMakePayments = AppStore.canMakePayments
        guard loadState != .loaded else { return }
        loadState = .loading
        loadTimeout?.cancel()
        loadTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.loadState == .loading else { return }
            self.loadState = .unreachable
        }
        // "Try again" during a slow request restarts the timer, not the request.
        guard !isRequestInFlight else { return }
        isRequestInFlight = true
        defer { isRequestInFlight = false }
        do {
            let loaded = try await Product.products(for: StoreProducts.all)
            if !loaded.isEmpty { products = loaded }
            loadTimeout?.cancel()
            // A partial answer (say, packs without the plans) counts as a failure, so it can be retried.
            loadState = Set(loaded.map(\.id)).isSuperset(of: StoreProducts.all)
                ? .loaded
                : .unavailable
        } catch {
            loadTimeout?.cancel()
            loadState = .unreachable
        }
    }

    func purchase(_ product: Product, appAccountToken: UUID? = nil) async throws -> PurchaseOutcome {
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
            return await handle(verification, isUpdate: false) ? .purchased : .cancelled
        case .pending:
            pendingProductIDs.insert(product.id)
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// Throws when the App Store can't be reached (or the sign-in prompt was
    /// cancelled, see `AppModel.isCancellation`), so "nothing to restore" is
    /// only said when that's true.
    func restore() async throws {
        do {
            try await AppStore.sync()
        } catch {
            await refreshEntitlements()
            throw error
        }
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
        #if DEBUG
        if Self.debugPro { active = true }
        #endif
        let changed = active != isPro
        isPro = active
        entitlementJWS = jws
        if active {
            pendingProductIDs.subtract(StoreProducts.subscriptions)
            notePurchase()
        }
        hasCheckedEntitlements = true
        if changed { onProStatusChange?(active) }
        await refreshTrial()
    }

    /// Once at launch: anything bought on this Apple Account that StoreKit
    /// still lists (a subscription, even expired, or a pack not redeemed yet).
    func refreshPurchaseHistory() async {
        guard !hasPurchased else { return }
        for await result in Transaction.all {
            guard case .verified(let transaction) = result, StoreProducts.all.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            notePurchase()
            return
        }
    }

    /// "Delete my data": her account and its credits are gone, so she's
    /// asked like someone who never bought (Pro still counts while it lasts).
    func forgetPurchases() {
        hasPurchased = false
        defaults.removeObject(forKey: Self.purchasedKey)
    }

    private func notePurchase() {
        guard !hasPurchased else { return }
        hasPurchased = true
        defaults.set(true, forKey: Self.purchasedKey)
    }

    #if DEBUG
    /// `-GLPro YES`: Pro without a purchase, for screenshots and QA (DEBUG only).
    static var debugPro: Bool { UserDefaults.standard.bool(forKey: "GLPro") }
    #endif

    private func refreshTrial() async {
        var found: TrialStatus?
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  StoreProducts.subscriptions.contains(transaction.productID),
                  transaction.revocationDate == nil, transaction.ownershipType == .purchased,
                  let end = Self.trialEnd(of: transaction), end > Date() else { continue }
            var willRenew = true
            if let status = await transaction.subscriptionStatus, case .verified(let renewal) = status.renewalInfo {
                willRenew = renewal.willAutoRenew
            }
            var product = products.first { $0.id == transaction.productID }
            if product == nil { product = try? await Product.products(for: [transaction.productID]).first }
            found = TrialStatus(productID: transaction.productID, endsAt: end, price: product?.displayPrice, willRenew: willRenew)
        }
        trial = found
        onTrialChange?(found)
    }

    /// Turns purchases off when a demo-mode build runs from the App Store
    /// itself. Xcode, TestFlight (sandbox) and the screenshots keep working.
    func closeForPreviewIfFromAppStore() async {
        guard case .verified(let transaction)? = try? await AppTransaction.shared,
              transaction.environment == .production else { return }
        isClosedForPreview = true
    }

    func isEligibleForTrial(_ product: Product) async -> Bool {
        guard let subscription = product.subscription, subscription.introductoryOffer != nil else { return false }
        return await subscription.isEligibleForIntroOffer
    }

    @discardableResult
    private func handle(_ verification: VerificationResult<Transaction>, isUpdate: Bool) async -> Bool {
        guard case .verified(let transaction) = verification else { return false }
        let wasPending = pendingProductIDs.remove(transaction.productID) != nil
        if let credits = StoreProducts.creditPacks[transaction.productID] {
            guard transaction.revocationDate == nil else {
                await transaction.finish()
                return false
            }
            let granted = await creditPackHandler?(credits, verification.jwsRepresentation) ?? false
            if granted {
                notePurchase()
                await transaction.finish()
                if isUpdate, wasPending {
                    onLatePurchase?(LatePurchase(productID: transaction.productID, trialEndsAt: nil))
                }
            }
            return granted
        }
        let wasPro = isPro
        let couldTell = hasCheckedEntitlements
        await transaction.finish()
        await refreshEntitlements()
        // Renewals and unfinished transactions also arrive here at launch:
        // only an approval or a new subscription (offer code) is news.
        if isUpdate, isPro, transaction.reason == .purchase, wasPending || (couldTell && !wasPro) {
            onLatePurchase?(LatePurchase(productID: transaction.productID, trialEndsAt: Self.trialEnd(of: transaction)))
        }
        return isPro
    }

    private static func trialEnd(of transaction: Transaction) -> Date? {
        let isTrial: Bool
        if #available(iOS 17.2, *) {
            isTrial = transaction.offer?.paymentMode == .freeTrial
        } else {
            isTrial = transaction.offerType == .introductory && transaction.productID == StoreProducts.yearly
        }
        return isTrial ? transaction.expirationDate : nil
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

    /// "≈ $0.10 per credit" for a credit pack; always shown below the billed price.
    var perCreditPrice: String? {
        guard let credits = StoreProducts.creditPacks[id], credits > 0 else { return nil }
        return (price / Decimal(credits)).formatted(priceFormatStyle)
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
