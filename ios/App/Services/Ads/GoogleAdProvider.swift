#if canImport(GoogleMobileAds) && !targetEnvironment(macCatalyst)
import UIKit
import AppCore
import GoogleMobileAds
import UserMessagingPlatform

/// Google Mobile Ads and Google's User Messaging Platform (consent), on
/// iPhone and iPad only. The SDK starts on first use, never at launch, and
/// every request is non-personalised, without the advertising identifier
/// (the app never asks for tracking permission), with Google's restricted
/// data processing, and with an age treatment and content rating from her
/// age range: teens and unknown ages get child treatment (what "under the age
/// of consent" maps to) and G-rated ads, adults up to PG.
@MainActor
final class GoogleAdProvider: NSObject, AdProvider {
    private var started = false
    private var configuredAudience: AdAudience?
    private var rewarded: RewardedAd?
    private var rewardedLoadedAt: Date?
    private var interstitial: InterstitialAd?
    private var interstitialLoadedAt: Date?
    /// The ad on screen; resumed when it's dismissed or fails to present.
    private var presentation: CheckedContinuation<Void, Never>?
    private var presentationFailed = false

    /// Loaded ads go stale after an hour; drop them a little earlier.
    private static let freshness: TimeInterval = 50 * 60

    var isAvailable: Bool { true }
    var canRequestAds: Bool { ConsentInformation.shared.canRequestAds }
    var privacyOptionsRequired: Bool { ConsentInformation.shared.privacyOptionsRequirementStatus == .required }
    var hasRewardedAd: Bool { rewarded != nil && Self.isFresh(rewardedLoadedAt) }
    var hasInterstitial: Bool { interstitial != nil && Self.isFresh(interstitialLoadedAt) }

    // MARK: Consent

    func refreshConsent(audience: AdAudience) async -> Bool {
        let parameters = RequestParameters()
        parameters.isTaggedForUnderAgeOfConsent = audience.isUnderAgeOfConsent
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: parameters)
        } catch {
            // Offline or unreachable: the SDK keeps the last session's answer.
        }
        return ConsentInformation.shared.canRequestAds
    }

    func gatherConsent(audience: AdAudience) async -> Bool {
        guard !(await refreshConsent(audience: audience)) else { return true }
        // Teens are tagged as under the age of consent and never see a form.
        guard audience == .adult else { return false }
        do {
            try await ConsentForm.loadAndPresentIfRequired(from: UIApplication.shared.topViewController)
        } catch {
            return false
        }
        return ConsentInformation.shared.canRequestAds
    }

    func presentPrivacyOptions() async {
        try? await ConsentForm.presentPrivacyOptionsForm(from: UIApplication.shared.topViewController)
    }

    func resetConsent() {
        ConsentInformation.shared.reset()
    }

    // MARK: Rewarded

    func loadRewarded(unitID: String, audience: AdAudience) async throws {
        await startIfNeeded(audience: audience)
        if hasRewardedAd { return }
        rewarded = nil
        let ad = try await RewardedAd.load(with: unitID, request: Request())
        ad.fullScreenContentDelegate = self
        rewarded = ad
        rewardedLoadedAt = Date()
    }

    func showRewarded(token: String) async -> RewardedAdOutcome {
        guard presentation == nil, hasRewardedAd, let ad = rewarded else { return .failed }
        rewarded = nil
        let options = ServerSideVerificationOptions()
        options.customRewardText = token
        ad.serverSideVerificationOptions = options
        let root = UIApplication.shared.topViewController
        do {
            try ad.canPresent(from: root)
        } catch {
            return .failed
        }
        let reward = RewardFlag()
        presentationFailed = false
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            presentation = continuation
            ad.present(from: root) {
                reward.earned = true
            }
        }
        if presentationFailed { return .failed }
        return reward.earned ? .earned : .closedEarly
    }

    // MARK: Interstitials

    func loadInterstitial(unitID: String, audience: AdAudience) async {
        await startIfNeeded(audience: audience)
        if hasInterstitial { return }
        interstitial = nil
        guard let ad = try? await InterstitialAd.load(with: unitID, request: Request()) else { return }
        ad.fullScreenContentDelegate = self
        interstitial = ad
        interstitialLoadedAt = Date()
    }

    func showInterstitial() async -> Bool {
        guard presentation == nil, hasInterstitial, let ad = interstitial else {
            interstitial = nil
            return false
        }
        interstitial = nil
        let root = UIApplication.shared.topViewController
        do {
            try ad.canPresent(from: root)
        } catch {
            return false
        }
        presentationFailed = false
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            presentation = continuation
            ad.present(from: root)
        }
        return !presentationFailed
    }

    func discardAll() {
        rewarded = nil
        interstitial = nil
    }

    // MARK: Setup

    /// Sets the request configuration for her audience (it applies to every
    /// later request) and starts the SDK the first time it's needed.
    private func startIfNeeded(audience: AdAudience) async {
        configure(for: audience)
        guard !started else { return }
        started = true
        MobileAds.shared.disableSDKCrashReporting()
        _ = await MobileAds.shared.start()
    }

    private func configure(for audience: AdAudience) {
        guard configuredAudience != audience else { return }
        configuredAudience = audience
        // A different audience (her age range changed): ads loaded for the
        // old one never show.
        discardAll()
        let configuration = MobileAds.shared.requestConfiguration
        switch audience {
        case .teen:
            configuration.ageRestrictedTreatment = .child
            configuration.maxAdContentRating = .general
        case .adult:
            configuration.ageRestrictedTreatment = .unspecified
            configuration.maxAdContentRating = .parentalGuidance
        }
        configuration.publisherPrivacyPersonalizationState = .disabled
        configuration.setPublisherFirstPartyIDEnabled(false)
        // US state privacy laws: Google's restricted data processing for every request.
        UserDefaults.standard.set(true, forKey: "gad_rdp")
    }

    private static func isFresh(_ loadedAt: Date?) -> Bool {
        guard let loadedAt else { return false }
        return Date().timeIntervalSince(loadedAt) < freshness
    }

    private func finishPresentation(failed: Bool) {
        if failed { presentationFailed = true }
        presentation?.resume()
        presentation = nil
    }
}

extension GoogleAdProvider: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        finishPresentation(failed: false)
    }

    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        finishPresentation(failed: true)
    }
}

/// Set by the reward handler, read after the ad closes (both on the main thread).
private final class RewardFlag: @unchecked Sendable {
    var earned = false
}
#endif
