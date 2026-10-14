import Foundation
import Observation
import AppCore

/// The user's credit balance as shown in the UI.
///
/// - Demo mode: this local wallet is the ledger (daily free credits, Pro
///   monthly allowance with rollover, purchased packs, exact refunds).
/// - Backend mode: the server is authoritative. We display the last
///   `credits_remaining` it reported (the charge when a job starts, the
///   balance when it finishes or is refunded) and let it accept or reject
///   each job.
///
/// `policy` holds the numbers the copy shows (free credits a day, Pro's
/// month, the trial's credits, free retries a day): the server's last ones
/// (`credit_policy()`), kept between launches, else AppConfig.json's.
@MainActor
@Observable
final class CreditsManager {
    private(set) var policy: CreditPolicy
    let isServerAuthoritative: Bool
    private(set) var wallet: CreditWallet
    private(set) var serverBalance: Int?
    /// The server couldn't verify this App Store install on the last read, so
    /// the free part of the balance is unknown: let the server decide each
    /// job (it says why if it can't), never open the paywall on a guess.
    private(set) var freeCreditsUnverified = false
    /// When the request behind `serverBalance` was sent.
    @ObservationIgnored private var serverBalanceAsOf: Date?
    private let defaults: UserDefaults
    private static let storageKey = "credits.wallet.v2"
    static let policyKey = "credits.policy.v1"

    init(policy: CreditPolicy = .standard, isServerAuthoritative: Bool, defaults: UserDefaults = .standard) {
        let cached = defaults.data(forKey: Self.policyKey).flatMap { try? JSONDecoder().decode(CreditPolicy.self, from: $0) }
            ?? policy
        self.policy = cached
        self.isServerAuthoritative = isServerAuthoritative
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(CreditWallet.self, from: data) {
            wallet = saved
        } else {
            // The server's last policy, not the bundled one, after "Delete my data".
            wallet = .fresh(now: Date(), policy: cached)
        }
    }

    var balance: Int {
        if isServerAuthoritative, let serverBalance { return serverBalance }
        return wallet.balance
    }

    /// When the free daily credits come back: midnight UTC on the server,
    /// local midnight in demo mode.
    var nextFreeRefill: Date {
        guard isServerAuthoritative else { return wallet.nextDailyRefill() }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        return utc.date(byAdding: .day, value: 1, to: utc.startOfDay(for: Date())) ?? Date().addingTimeInterval(86_400)
    }

    /// When Pro's monthly credits arrive next. Known in demo mode only: the
    /// server's month can start elsewhere (for example after a sign-in merge).
    var nextSubscriptionGrant: Date? {
        isServerAuthoritative ? nil : wallet.nextSubscriptionGrant()
    }

    /// Where the balance comes from; nil in backend mode, where only the server knows.
    var breakdown: CreditBreakdown? {
        guard !isServerAuthoritative else { return nil }
        return CreditBreakdown(daily: wallet.daily, monthly: wallet.subscription, packs: wallet.purchased)
    }

    func cost(of operation: AIOperation, outputs: Int = 1) -> Int {
        policy.cost(of: operation, outputs: outputs)
    }

    /// `isTrial`: the subscription is in its free trial week (`PurchaseManager.trial`).
    func refresh(isPro: Bool, isTrial: Bool = false, now: Date = Date()) {
        wallet.refresh(now: now, isPro: isPro, isTrial: isTrial, policy: policy)
        persist()
    }

    func canAfford(_ operation: AIOperation, outputs: Int = 1) -> Bool {
        let cost = cost(of: operation, outputs: outputs)
        if isServerAuthoritative {
            // Unknown balance: let the server decide (it answers 402 if empty).
            guard let serverBalance, !freeCreditsUnverified else { return true }
            return cost <= serverBalance
        }
        return wallet.canAfford(cost)
    }

    /// Reserves credits for a job. In backend mode the server charges instead.
    func charge(_ cost: Int) throws -> CreditCharge {
        guard !isServerAuthoritative, cost > 0 else { return .none }
        let charge = try wallet.spend(cost)
        persist()
        return charge
    }

    func refund(_ charge: CreditCharge) {
        guard !isServerAuthoritative, charge.total > 0 else { return }
        wallet.refund(charge, policy: policy)
        persist()
    }

    /// `asOf`: when the request that reported it was sent. An older answer
    /// that arrives late (a cancel's refund after the next job's charge)
    /// never overwrites a newer one. Absolute numbers only, so nothing is
    /// counted twice.
    func sync(serverBalance: Int, asOf: Date = Date()) {
        if let serverBalanceAsOf, asOf < serverBalanceAsOf { return }
        self.serverBalance = max(0, serverBalance)
        serverBalanceAsOf = asOf
    }

    /// A full balance read (`GET /ai-image`): the numbers, the balance and
    /// whether its free part is known. An unverified read keeps the last
    /// known balance on screen rather than a number without free credits.
    func apply(_ state: BalanceState, asOf: Date = Date()) {
        if let server = state.policy {
            let updated = CreditPolicy(server: server, fallback: policy)
            if updated != policy {
                policy = updated
                if let data = try? JSONEncoder().encode(updated) { defaults.set(data, forKey: Self.policyKey) }
            }
        }
        freeCreditsUnverified = state.freeCredits == .unverified
        if !freeCreditsUnverified || serverBalance == nil || state.creditsRemaining > (serverBalance ?? 0) {
            sync(serverBalance: state.creditsRemaining, asOf: asOf)
        }
    }

    /// Demo-mode grant for a purchased pack (the backend grants it in production).
    func addPurchased(_ amount: Int) {
        wallet.addPurchased(amount)
        persist()
    }

    /// Signed out: the account's balance isn't hers on this device anymore.
    func resetServerBalance() {
        serverBalance = nil
        serverBalanceAsOf = nil
    }

    /// "Delete my data": a fresh day's free credits, and no server balance
    /// until a new session reports one.
    func resetAll() {
        serverBalance = nil
        serverBalanceAsOf = nil
        freeCreditsUnverified = false
        wallet = .fresh(now: Date(), policy: policy)
        defaults.removeObject(forKey: Self.storageKey)
    }

    #if DEBUG
    /// Screenshots always show a fresh day's free credits.
    func resetForScreenshots() {
        wallet = .fresh(now: Date(), policy: policy)
    }
    #endif

    private func persist() {
        if let data = try? JSONEncoder().encode(wallet) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

struct CreditBreakdown: Equatable {
    var daily: Int
    var monthly: Int
    var packs: Int
}
