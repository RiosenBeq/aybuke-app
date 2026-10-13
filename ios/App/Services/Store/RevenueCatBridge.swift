import StoreKit
import RevenueCat

/// RevenueCat in observer mode: StoreKit 2 and our backend still sell and
/// verify everything (PurchaseManager); RevenueCat only records purchases
/// for its dashboard (revenue, trials, churn, refunds). Off until a public
/// SDK key is set in AppConfig.json (`revenueCatAPIKey`, "appl_…").
enum RevenueCatBridge {
    static func configure(apiKey: String, appUserID: String?) {
        guard !apiKey.isEmpty, !Purchases.isConfigured else { return }
        Purchases.logLevel = .warn
        Purchases.configure(
            with: Configuration.Builder(withAPIKey: apiKey)
                .with(purchasesAreCompletedBy: .myApp, storeKitVersion: .storeKit2)
                .with(appUserID: appUserID)
                .build()
        )
    }

    /// Records a purchase made with StoreKit 2 directly.
    static func record(_ result: Product.PurchaseResult) async {
        guard Purchases.isConfigured else { return }
        _ = try? await Purchases.shared.recordPurchase(result)
    }

    /// Ties RevenueCat's customer to our account id (anonymous or Apple).
    static func identify(_ userID: String) async {
        guard Purchases.isConfigured, Purchases.shared.appUserID != userID else { return }
        _ = try? await Purchases.shared.logIn(userID)
    }
}
