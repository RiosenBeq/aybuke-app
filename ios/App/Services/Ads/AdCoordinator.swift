import SwiftUI
import Observation
import AppCore

/// Ads for free members 13+, in two kinds, and nothing at all for Pro, under
/// 13, on the Mac or in preview builds.
///
/// - **Rewarded** ("Watch a short ad · +1 credit"): offered only when she's out
///   of credits, at most three a day. The credit comes from the server once
///   AdMob confirms the ad (`functions/v1/ad-reward`); the app only shows the
///   ad with a single-use token, and polls until the credit lands.
/// - **Interstitial**: may follow a finished save or share at a natural break
///   (nothing else on screen, never during onboarding or the tour), within
///   `InterstitialPacing`. It's loaded quietly ahead of time and skipped when
///   it isn't ready: a save never waits for an ad.
///
/// Google's SDK starts on first use, never at launch. Consent (Google's form,
/// in the EEA, UK and Switzerland) is only ever asked after she taps "Watch".
@MainActor
@Observable
final class AdCoordinator {
    enum RewardState: Equatable {
        /// Ready; `remaining` ads left today once the server has said.
        case available(remaining: Int?)
        /// Consent, the ad itself or the server's token is on its way.
        case loading
        /// She watched it: waiting for Google to confirm it to the server.
        case pending
        /// Today's ads are used up.
        case capped
        /// Something to tell her; the button stays.
        case notice(Notice)
    }

    enum Notice: Equatable {
        case offline, noFill, consent, closedEarly, delayed, failed
    }

    private(set) var rewardState: RewardState = .available(remaining: nil)
    /// Goes up each time an ad credit lands, so the sheet showing the ad can close.
    private(set) var rewardsLanded = 0
    /// Settings › Ad privacy choices, where Google's privacy options apply.
    private(set) var showsPrivacyChoices = false

    @ObservationIgnored weak var app: AppModel?
    private let config: AdsConfig
    private let backend: AdRewardBackend?
    private let provider: AdProvider
    private let defaults: UserDefaults
    private let rewardPolicy: AdRewardPolicy
    @ObservationIgnored private var pacing: InterstitialPacing
    @ObservationIgnored private var pacingRules = InterstitialPacing.Rules.standard
    /// The last finished save or share, until the next natural break decides.
    @ObservationIgnored private var lastExport: Date?
    @ObservationIgnored private var breakTask: Task<Void, Never>?
    @ObservationIgnored private var preloadTask: Task<Void, Never>?
    @ObservationIgnored private var lastOverview: Date?
    /// Google's SDKs have run on this device (consent checked or an ad asked
    /// for): Settings may offer its privacy options, and Delete my data resets
    /// its consent record. Held in memory too, since Delete my data clears
    /// the stored flag before `reset()` runs.
    @ObservationIgnored private var hasUsedAds: Bool

    /// Interstitial pacing (saves, last ads, today's count).
    nonisolated static let pacingKey = "ads.pacing.v1"
    /// She has asked for an ad before, so Settings may check Google's privacy options.
    nonisolated static let usedKey = "ads.used.v1"
    /// An interstitial only right after the save: at the first natural break
    /// within this time, or not at all.
    private static let breakWindow: TimeInterval = 3 * 60
    /// How long to wait for Google's confirmation before saying it's late.
    private static let confirmationWait: TimeInterval = 60

    init(config: AdsConfig, backend: AdRewardBackend?, defaults: UserDefaults = .standard) {
        self.config = config
        self.backend = backend
        self.defaults = defaults
        self.provider = AdProviders.make()
        self.rewardPolicy = AdRewardPolicy(dailyCap: config.dailyCap)
        self.hasUsedAds = defaults.bool(forKey: Self.usedKey)
        if let data = defaults.data(forKey: Self.pacingKey),
           let saved = try? JSONDecoder().decode(InterstitialPacing.self, from: data) {
            pacing = saved
        } else {
            // The first launch with ads: the 24-hour grace starts now.
            let fresh = InterstitialPacing(firstLaunch: Date())
            if let data = try? JSONEncoder().encode(fresh) { defaults.set(data, forKey: Self.pacingKey) }
            pacing = fresh
        }
        #if DEBUG
        if let state = Self.screenshotState { rewardState = state }
        // `-GLAdPacing off`: interstitials after every save (QA only).
        if UserDefaults.standard.string(forKey: "GLAdPacing") == "off" {
            pacingRules = InterstitialPacing.Rules(grace: 0, minimumSaves: 1, spacing: 0, dailyCap: 1000, afterRewarded: 0)
        }
        #endif
    }

    // MARK: Who gets ads

    /// Her ad protections, or nil (no ads) under 13 and after declining to share an age.
    var audience: AdAudience? {
        guard let app else { return nil }
        return AgeDefaults.adAudience(record: app.ageRecord, storefrontCountry: app.storefrontCountry)
    }

    /// This build can show her ads at all: Google's SDK is here (not on the
    /// Mac), she's 13+ and not Pro, and the app id is the one the units belong to.
    private var adsPossible: Bool {
        guard let app, config.enabled, provider.isAvailable, !Platform.isMac, !app.purchases.isPro, audience != nil else {
            return false
        }
        #if DEBUG
        return true
        #else
        // Preview builds (no backend) show no ads.
        return !app.isDemoMode
        #endif
    }

    /// "Watch a short ad · +1 credit" belongs on screen: a free member with a
    /// session and AI consent who's out of credits.
    var offersRewardedAd: Bool {
        // Before the screenshot override, which would otherwise show it on the Mac.
        guard !Platform.isMac else { return false }
        #if DEBUG
        if Self.screenshotState != nil { return true }
        #endif
        guard adsPossible, let app, backend != nil, config.activeRewardedUnitID != nil, app.hasAIConsent else { return false }
        return rewardPolicy.offersAd(isPro: app.purchases.isPro, audience: audience, balance: app.credits.balance)
    }

    var dailyCap: Int { rewardPolicy.dailyCap }

    /// Free members here can see ads, so "No ads" is a real Pro benefit (it
    /// isn't on the Mac, where nobody sees any).
    var freeMembersSeeAds: Bool {
        guard config.enabled, provider.isAvailable, !Platform.isMac, audience != nil else { return false }
        return config.activeRewardedUnitID != nil || config.activeInterstitialUnitID != nil
    }

    private var interstitialsPossible: Bool {
        guard adsPossible, let app, config.activeInterstitialUnitID != nil else { return false }
        return app.isOnline && !app.isCloudOffline
    }

    private var isRewardFlowActive: Bool {
        rewardState == .loading || rewardState == .pending
    }

    // MARK: Rewarded

    /// Today's count from the server, when the card appears.
    func refreshRewardOverview() async {
        #if DEBUG
        if Self.screenshotState != nil { return }
        #endif
        guard offersRewardedAd, let backend, let app, !isRewardFlowActive else { return }
        if let lastOverview, Date().timeIntervalSince(lastOverview) < 20, case .available(remaining: .some(_)) = rewardState { return }
        guard app.isOnline, !app.isCloudOffline else {
            rewardState = .notice(.offline)
            return
        }
        do {
            let overview = try await backend.overview()
            lastOverview = Date()
            if let balance = overview.creditsRemaining, balance > 0 {
                // She has credits after all (a new day, say): the card goes.
                app.credits.sync(serverBalance: balance)
            }
            rewardState = overview.remainingToday > 0 ? .available(remaining: overview.remainingToday) : .capped
        } catch {
            // The count stays unknown; the button still works and the server decides.
            if case .notice(.offline) = rewardState { rewardState = .available(remaining: nil) }
        }
    }

    /// "Watch a short ad": consent where it's needed, the ad, a token from
    /// the server, the ad on screen, then the wait for the credit.
    func watchRewardedAd() async {
        #if DEBUG
        if Self.screenshotState != nil { return }
        #endif
        guard offersRewardedAd, !isRewardFlowActive, let app, let audience, let backend,
              let unitID = config.activeRewardedUnitID else { return }
        guard app.isOnline, !app.isCloudOffline else {
            rewardState = .notice(.offline)
            return
        }
        rewardState = .loading
        markAdsUsed()
        guard await provider.gatherConsent(audience: audience) else {
            rewardState = .notice(.consent)
            return
        }
        showsPrivacyChoices = provider.privacyOptionsRequired
        // Pro, her age or her balance may have changed while Google's form was up.
        guard offersRewardedAd, self.audience == audience else {
            rewardState = .available(remaining: nil)
            return
        }
        do {
            try await provider.loadRewarded(unitID: unitID, audience: audience)
        } catch {
            rewardState = .notice(app.isOnline ? .noFill : .offline)
            return
        }
        let token: AdRewardToken
        do {
            token = try await backend.issueToken()
        } catch let error as AdRewardError {
            refused(error)
            return
        } catch {
            rewardState = .notice(NetworkFailure.isTransient(error) ? .offline : .failed)
            return
        }
        let outcome = await provider.showRewarded(token: token.token)
        pacing.noteRewardedAd(at: Date())
        savePacing()
        switch outcome {
        case .earned:
            rewardState = .pending
            await waitForCredit(token: token.token)
        case .closedEarly:
            await backend.release(token: token.token)
            rewardState = .notice(.closedEarly)
            lastOverview = nil
        case .failed:
            await backend.release(token: token.token)
            rewardState = .notice(.failed)
            lastOverview = nil
        }
    }

    private func refused(_ error: AdRewardError) {
        switch error {
        case .dailyCap:
            rewardState = .capped
        case .hasCredits(let balance):
            if let balance { app?.credits.sync(serverBalance: balance) }
            rewardState = .available(remaining: nil)
        case .notEligible, .unauthorized, .server:
            rewardState = .notice(.failed)
        }
    }

    /// AdMob tells the server, usually within seconds; the app asks until it has.
    private func waitForCredit(token: String) async {
        guard let backend else { return }
        let started = Date()
        var delay: Double = 1.5
        while Date().timeIntervalSince(started) < Self.confirmationWait {
            try? await Task.sleep(for: .seconds(delay))
            delay = min(delay + 0.5, 4)
            guard let status = try? await backend.status(token: token) else { continue }
            switch status.status {
            case .granted:
                if let balance = status.creditsRemaining { app?.credits.sync(serverBalance: balance) }
                rewardState = status.remainingToday > 0 ? .available(remaining: status.remainingToday) : .capped
                rewardsLanded += 1
                Haptics.success()
                app?.showToast("You earned 1 credit ✨", style: .success)
                app?.syncWidgets()
                return
            case .capped:
                rewardState = .capped
                return
            case .expired, .unknown:
                rewardState = .notice(.failed)
                return
            case .pending, nil:
                continue
            }
        }
        rewardState = .notice(.delayed)
    }

    // MARK: Interstitials

    /// A finished edit, collage or video was saved or shared. Counts toward
    /// the third-save rule, loads the next ad quietly when one could be due,
    /// and shows one at the next natural break if everything allows it.
    func noteFinishedExport() {
        pacing.noteSave()
        savePacing()
        guard interstitialsPossible else { return }
        lastExport = Date()
        preloadInterstitialIfWorthIt()
        // After the success toast has had its moment.
        scheduleBreak(after: 1.8)
    }

    /// A screen closed (the editor, video editor, collage maker, share
    /// composer): if a save just happened there, this is its break.
    func naturalBreak() {
        guard lastExport != nil else { return }
        scheduleBreak(after: 0.8)
    }

    private func scheduleBreak(after seconds: Double) {
        breakTask?.cancel()
        breakTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.showInterstitialIfDue()
        }
    }

    /// Nothing else on screen: no sheet, cover, picker, tour or onboarding,
    /// and the app in front.
    private var isNaturalBreak: Bool {
        guard let app else { return false }
        return app.acceptsCommands && app.tour.hasSeen && !app.isSettingsPresented
            && !UIApplication.shared.isPresentingAnything
            && UIApplication.shared.applicationState == .active
    }

    private func showInterstitialIfDue() async {
        guard let exportedAt = lastExport else { return }
        guard Date().timeIntervalSince(exportedAt) < Self.breakWindow else {
            lastExport = nil
            return
        }
        // Still in the editor (or a sheet): wait for it to close.
        guard isNaturalBreak, !isRewardFlowActive else { return }
        // This break decides: shown now, or not for this save.
        lastExport = nil
        guard interstitialsPossible, provider.canRequestAds, provider.hasInterstitial,
              pacing.allowsInterstitial(at: Date(), rules: pacingRules) else { return }
        if await provider.showInterstitial() {
            pacing.noteShown(at: Date())
            savePacing()
        }
    }

    private func preloadInterstitialIfWorthIt() {
        guard preloadTask == nil, interstitialsPossible, !provider.hasInterstitial, let audience,
              let unitID = config.activeInterstitialUnitID, pacing.worthPreloading(at: Date(), rules: pacingRules) else { return }
        preloadTask = Task { [weak self] in
            await self?.preload(unitID: unitID, audience: audience)
            self?.preloadTask = nil
        }
    }

    private func preload(unitID: String, audience: AdAudience) async {
        // Quietly: consent information is refreshed, never asked for here.
        // Where a form is needed and she hasn't answered it, there's no ad.
        markAdsUsed()
        guard await provider.refreshConsent(audience: audience) else { return }
        guard interstitialsPossible, self.audience == audience else { return }
        await provider.loadInterstitial(unitID: unitID, audience: audience)
    }

    // MARK: Pro, privacy choices and deletion

    /// Pro removes every ad, including one already loaded.
    func proStatusChanged(isPro: Bool) {
        guard isPro else { return }
        cancelPending()
        provider.discardAll()
        rewardState = .available(remaining: nil)
    }

    /// Settings: whether to offer Google's privacy options. Asks Google only
    /// if she has asked for an ad on this device before, and never for Pro
    /// (no ads, so nothing ad-related loads; Delete my data still resets it).
    func refreshPrivacyChoices() async {
        guard hasUsedAds, provider.isAvailable, let audience, let app, !app.purchases.isPro else {
            showsPrivacyChoices = false
            return
        }
        _ = await provider.refreshConsent(audience: audience)
        showsPrivacyChoices = provider.privacyOptionsRequired
    }

    func presentPrivacyChoices() async {
        await provider.presentPrivacyOptions()
        showsPrivacyChoices = provider.privacyOptionsRequired
    }

    /// "Delete my data": pacing, Google's consent choices and loaded ads go;
    /// the first-day grace starts again.
    func reset() {
        cancelPending()
        provider.discardAll()
        if hasUsedAds { provider.resetConsent() }
        hasUsedAds = false
        defaults.removeObject(forKey: Self.usedKey)
        defaults.removeObject(forKey: "gad_rdp")
        pacing = InterstitialPacing(firstLaunch: Date())
        savePacing()
        rewardState = .available(remaining: nil)
        showsPrivacyChoices = false
        lastOverview = nil
    }

    private func markAdsUsed() {
        guard !hasUsedAds else { return }
        hasUsedAds = true
        defaults.set(true, forKey: Self.usedKey)
    }

    private func cancelPending() {
        breakTask?.cancel()
        preloadTask?.cancel()
        preloadTask = nil
        lastExport = nil
    }

    private func savePacing() {
        if let data = try? JSONEncoder().encode(pacing) { defaults.set(data, forKey: Self.pacingKey) }
    }

    #if DEBUG
    /// `-GLAdRewardState available|loading|pending|capped` (also `offline`,
    /// `nofill`, `closed`, `delayed`) pins the rewarded-ad card for QA, with
    /// any scene that shows it (`paywall -GLPaywallSource out_of_credits`,
    /// `home -GLCreditsSheet YES`).
    static let screenshotState: RewardState? = {
        switch UserDefaults.standard.string(forKey: "GLAdRewardState") {
        case "available": return .available(remaining: 2)
        case "loading": return .loading
        case "pending": return .pending
        case "capped": return .capped
        case "offline": return .notice(.offline)
        case "nofill": return .notice(.noFill)
        case "closed": return .notice(.closedEarly)
        case "delayed": return .notice(.delayed)
        default: return nil
        }
    }()
    #endif
}
