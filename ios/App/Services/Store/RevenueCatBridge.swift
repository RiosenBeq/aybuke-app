import StoreKit
import RevenueCat

/// RevenueCat in observer mode: StoreKit 2 and our backend still sell and
/// verify everything (PurchaseManager); RevenueCat only records purchases
/// for its dashboard (revenue, trials, churn, refunds). Off until a public
/// SDK key is set in AppConfig.json (`revenueCatAPIKey`, "appl_…"), and
/// configured only for people who buy (AppModel), never at first launch.
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

    /// After "Delete my data" or signing out. RevenueCat advises against
    /// logging out custom ids, but the SDK refreshes customer info on every
    /// foreground, and that "get or create" call would bring back a customer
    /// the server just deleted. Anonymous customers can't log out (the SDK
    /// returns an error), and there is nothing to bring back for them.
    static func logOut() async {
        guard Purchases.isConfigured, !Purchases.shared.isAnonymous else { return }
        _ = try? await Purchases.shared.logOut()
    }
}
