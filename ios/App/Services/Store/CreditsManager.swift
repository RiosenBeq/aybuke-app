import Foundation
import Observation
import AppCore

/// The user's credit balance as shown in the UI.
///
/// - Demo mode: this local wallet is the ledger (daily free credits, Pro
///   monthly allowance with rollover, purchased packs, exact refunds).
/// - Backend mode: the server is authoritative. We display the last
///   `credits_remaining` it reported and let it accept or reject each job.
@MainActor
@Observable
final class CreditsManager {
    let policy: CreditPolicy
    let isServerAuthoritative: Bool
    private(set) var wallet: CreditWallet
    private(set) var serverBalance: Int?
    private let defaults: UserDefaults
    private static let storageKey = "credits.wallet.v2"

    init(policy: CreditPolicy = .standard, isServerAuthoritative: Bool, defaults: UserDefaults = .standard) {
        self.policy = policy
        self.isServerAuthoritative = isServerAuthoritative
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(CreditWallet.self, from: data) {
            wallet = saved
        } else {
            wallet = .fresh(now: Date(), policy: policy)
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

    func refresh(isPro: Bool, now: Date = Date()) {
        wallet.refresh(now: now, isPro: isPro, policy: policy)
        persist()
    }

    func canAfford(_ operation: AIOperation, outputs: Int = 1) -> Bool {
        let cost = cost(of: operation, outputs: outputs)
        if isServerAuthoritative {
            // Unknown balance: let the server decide (it answers 402 if empty).
            guard let serverBalance else { return true }
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

    func sync(serverBalance: Int) {
        self.serverBalance = max(0, serverBalance)
    }

    /// Demo-mode grant for a purchased pack (the backend grants it in production).
    func addPurchased(_ amount: Int) {
        wallet.addPurchased(amount)
        persist()
    }

    /// Signed out: the account's balance isn't hers on this device anymore.
    func resetServerBalance() {
        serverBalance = nil
    }

    /// "Delete my data": a fresh day's free credits, and no server balance
    /// until a new session reports one.
    func resetAll() {
        serverBalance = nil
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
