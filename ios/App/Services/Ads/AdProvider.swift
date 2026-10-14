import UIKit
import AppCore

/// How a rewarded ad ended.
enum RewardedAdOutcome: Equatable {
    /// She watched it to the reward; the credit comes once AdMob tells the server.
    case earned
    /// She closed it before the reward.
    case closedEarly
    /// It couldn't be shown.
    case failed
}

/// What `AdCoordinator` needs from an ad SDK. The Mac app, and any build
/// without Google's SDK, gets `NoAdProvider`, so no ad code runs there.
/// Nothing here touches the SDK until it's called, and nothing calls it
/// for Pro members or under 13.
@MainActor
protocol AdProvider: AnyObject {
    var isAvailable: Bool { get }
    /// Consent allows requesting ads (or none is needed where she is).
    var canRequestAds: Bool { get }
    /// Google's privacy options form applies to her (EEA, UK, Switzerland).
    var privacyOptionsRequired: Bool { get }
    var hasRewardedAd: Bool { get }
    var hasInterstitial: Bool { get }

    /// Updates consent information quietly, never showing a form. Returns
    /// whether ads may be requested.
    func refreshConsent(audience: AdAudience) async -> Bool
    /// The same, then Google's consent form if an adult in the EEA, UK or
    /// Switzerland hasn't answered it yet. Only after she asked for an ad.
    func gatherConsent(audience: AdAudience) async -> Bool
    func presentPrivacyOptions() async
    func loadRewarded(unitID: String, audience: AdAudience) async throws
    /// Shows the loaded rewarded ad with `token` as its server-side
    /// verification custom data (never her user id).
    func showRewarded(token: String) async -> RewardedAdOutcome
    /// Loads an interstitial quietly; a failure (no fill) is simply no ad.
    func loadInterstitial(unitID: String, audience: AdAudience) async
    /// Shows the loaded interstitial; false when there was none to show.
    func showInterstitial() async -> Bool
    /// Drops loaded ads (she became Pro, or deleted her data).
    func discardAll()
    /// "Delete my data": forgets Google's consent choices on this device.
    func resetConsent()
}

/// No ads: the Mac app and builds without Google Mobile Ads.
@MainActor
final class NoAdProvider: AdProvider {
    var isAvailable: Bool { false }
    var canRequestAds: Bool { false }
    var privacyOptionsRequired: Bool { false }
    var hasRewardedAd: Bool { false }
    var hasInterstitial: Bool { false }

    func refreshConsent(audience: AdAudience) async -> Bool { false }
    func gatherConsent(audience: AdAudience) async -> Bool { false }
    func presentPrivacyOptions() async {}
    func loadRewarded(unitID: String, audience: AdAudience) async throws { throw CancellationError() }
    func showRewarded(token: String) async -> RewardedAdOutcome { .failed }
    func loadInterstitial(unitID: String, audience: AdAudience) async {}
    func showInterstitial() async -> Bool { false }
    func discardAll() {}
    func resetConsent() {}
}

enum AdProviders {
    @MainActor
    static func make() -> AdProvider {
        #if canImport(GoogleMobileAds) && !targetEnvironment(macCatalyst)
        return GoogleAdProvider()
        #else
        return NoAdProvider()
        #endif
    }
}

extension UIApplication {
    /// The view controller on top of everything, sheets included: where an
    /// SDK has to present its own screens.
    var topViewController: UIViewController? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    /// A sheet, cover, alert or share sheet is on screen (or on its way out).
    var isPresentingAnything: Bool {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.rootViewController?.presentedViewController != nil }
    }
}
