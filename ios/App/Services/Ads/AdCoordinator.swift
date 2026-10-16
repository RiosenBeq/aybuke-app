import SwiftUI
import Observation
import AppCore

/// Ads for free members 13+, in two kinds, and nothing at all for Pro, under
/// 13, on the Mac or in preview builds.
///
/// - **Rewarded** ("Watch a short ad · +1 credit"): offered only when she's out
///   of credits, at most two a day (per user and per App Store install, on
///   the server). The credit comes from the server once
///   AdMob confirms the ad (`functions/v1/ad-reward`); the app only shows the
///   ad with a single-use token, and polls until the credit lands.
/// - **Pro try** ("Try this look once · watch a short ad"): on the paywall a
///   Pro look or style opened, one a day, only with a credit to spend (the
///   look's job costs one as usual). Same unit, same token and polling; once
///   the server has the try, the paywall closes and the look or style starts
///   through the usual gates (`AppModel.startProTry`).
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

    /// Where the ad for a Pro try is (`ProTryCard`).
    enum TryPhase: Equatable {
        /// Nothing under way: the card shows the offer.
        case idle
        /// Consent, the ad itself or the server's token is on its way.
        case loading
        /// She watched it: waiting for Google to confirm it to the server.
        case pending
        /// The server has the try: the paywall closes and the look starts.
        case granted
        case notice(TryNotice)
    }

    enum TryNotice: Equatable {
        case offline, noFill, consent, closedEarly, delayed, failed
        /// The server won't offer a try right now (a block, a cool-down, AI resting).
        case unavailable
    }

    private(set) var rewardState: RewardState = .available(remaining: nil)
    /// Goes up each time an ad credit lands, so the sheet showing the ad can close.
    private(set) var rewardsLanded = 0
    /// Settings › Ad privacy choices, where Google's privacy options apply.
    private(set) var showsPrivacyChoices = false
    /// The Pro try's ad, for `tryItem`.
    private(set) var tryPhase: TryPhase = .idle
    private(set) var tryItem: ProTryItem?
    /// `GET /ad-reward`'s `unlock`: today's tries, nil until the server has said.
    private(set) var tryOverview: ProTryOverview?
    /// Tries she watched an ad for and hasn't used, until each ends (the
    /// server's list after each overview, plus the one just granted).
    private(set) var activeTries: [ProTry] = []

    @ObservationIgnored weak var app: AppModel?
    private let config: AdsConfig
    private let backend: AdRewardBackend?
    private let provider: AdProvider
    private let defaults: UserDefaults
    /// Its cap follows the server's last `daily_cap` (see `noteServerCap`).
    private var rewardPolicy: AdRewardPolicy
    @ObservationIgnored private var pacing: InterstitialPacing
    @ObservationIgnored private var pacingRules = InterstitialPacing.Rules.standard
    /// The last finished save or share, until the next natural break decides.
    @ObservationIgnored private var lastExport: Date?
    @ObservationIgnored private var breakTask: Task<Void, Never>?
    @ObservationIgnored private var preloadTask: Task<Void, Never>?
    @ObservationIgnored private var lastOverview: Date?
    @ObservationIgnored private var lastTryOverview: Date?
    /// A watched try's token while Google's confirmation is late ("delayed"):
    /// tapping the card asks again.
    @ObservationIgnored private var lateTry: (token: String, item: ProTryItem)?
    private let tryPolicy = ProTryPolicy.standard
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
    /// session and AI consent who's out of credits, while the server takes
    /// jobs on free credits (the ad's credit lands among them).
    var offersRewardedAd: Bool {
        // Before the screenshot override, which would otherwise show it on the Mac.
        guard !Platform.isMac else { return false }
        #if DEBUG
        if Self.screenshotState != nil { return true }
        #endif
        guard adsPossible, let app, backend != nil, config.activeRewardedUnitID != nil, app.hasAIConsent else { return false }
        return rewardPolicy.offersAd(isPro: app.purchases.isPro, audience: audience, balance: app.credits.balance,
                                     pause: app.aiServicePause)
    }

    /// The server's cap, as it last said so; the bundled one until it has.
    var dailyCap: Int { rewardPolicy.dailyCap }

    /// The server sends `daily_cap` with its answers (null when its policy call
    /// failed, then the last value stays). The copy must match what it enforces.
    private func noteServerCap(_ cap: Int?) {
        guard let cap, (0...10_000).contains(cap) else { return }
        rewardPolicy.dailyCap = cap
    }

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

    /// A rewarded ad (for a credit or a try) is loading, on screen or waiting
    /// for Google: no other ad, and no interstitial, meanwhile.
    private var isRewardFlowActive: Bool {
        rewardState == .loading || rewardState == .pending
            || tryPhase == .loading || tryPhase == .pending || tryPhase == .granted
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
            noteServerCap(overview.dailyCap)
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
        // AI may have gone on a break since the card appeared: its credit would wait unused.
        await app.refreshAIServicePause()
        guard offersRewardedAd else {
            rewardState = .available(remaining: nil)
            return
        }
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
            noteServerCap(token.dailyCap)
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
        case .noCredits, .notUnlockable, .aiPaused:
            // A try's answers; a credit ad never gets them.
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
            noteServerCap(status.dailyCap)
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

    // MARK: Pro tries

    /// Everything a try needs but the server's word: a free member 13+ on
    /// iPhone or iPad who can see ads, with AI consent and a session (asked
    /// for with the overview), and a paywall opened by exactly this Pro look
    /// or style with a job waiting to go on (`AppModel.pendingProTry`).
    func canOfferProTry(for item: ProTryItem) -> Bool {
        guard !Platform.isMac else { return false }
        #if DEBUG
        if Self.screenshotTry != nil { return true }
        #endif
        guard adsPossible, let app, backend != nil, config.activeRewardedUnitID != nil, app.hasAIConsent else { return false }
        return app.pendingProTry?.item == item
    }

    /// The try card belongs on the paywall: an ad for this look under way, or
    /// something to offer or explain.
    func offersProTry(for item: ProTryItem) -> Bool {
        guard canOfferProTry(for: item) else { return false }
        return tryPhase(for: item) != .idle || proTryOffer(for: item) != .none
    }

    func proTryOffer(for item: ProTryItem) -> ProTryOffer {
        #if DEBUG
        if let pinned = Self.screenshotTry { return pinned.offer }
        #endif
        guard let app else { return .none }
        return tryPolicy.offer(for: item, isPro: app.purchases.isPro, audience: audience, balance: app.credits.balance,
                               cost: app.credits.cost(of: item.operation), overview: tryOverview, active: activeTries,
                               pause: app.aiServicePause)
    }

    func tryPhase(for item: ProTryItem) -> TryPhase {
        #if DEBUG
        if let pinned = Self.screenshotTry { return pinned.phase }
        #endif
        return tryItem == item ? tryPhase : .idle
    }

    /// The server's tries today (`GET /ad-reward`): how many are left, whether
    /// she may, and the tries she already has.
    func refreshProTryOverview(force: Bool = false) async {
        #if DEBUG
        if Self.screenshotTry != nil { return }
        #endif
        guard let backend, let app, !app.purchases.isPro, adsPossible, app.hasAIConsent, !isRewardFlowActive else { return }
        if !force, let lastTryOverview, Date().timeIntervalSince(lastTryOverview) < 20, tryOverview != nil { return }
        guard app.isOnline, !app.isCloudOffline else { return }
        let asked = Date()
        guard let overview = try? await backend.overview() else { return }
        noteServerCap(overview.dailyCap)
        lastTryOverview = Date()
        if let balance = overview.creditsRemaining { app.credits.sync(serverBalance: balance, asOf: asked) }
        tryOverview = overview.unlock
        // The server's list of her live tries is the one that counts.
        activeTries = overview.unlock?.active ?? []
    }

    /// Her try of exactly this look or style can still start a job.
    func hasActiveTry(for item: ProTryItem) -> Bool {
        guard let app, !app.purchases.isPro else { return false }
        return tryPolicy.liveTry(for: item, in: activeTries) != nil
    }

    /// The card's tap: an ad for a try, Google's late confirmation asked
    /// again, or a try she already has started.
    func tapProTry(_ item: ProTryItem) async {
        #if DEBUG
        if Self.screenshotTry != nil { return }
        #endif
        if case .notice(.delayed) = tryPhase(for: item), let lateTry, lateTry.item == item {
            setTry(.pending, for: item)
            await waitForTry(token: lateTry.token, item: item)
            return
        }
        if case .ready = proTryOffer(for: item) {
            app?.startProTry(item)
            return
        }
        await watchProTryAd(for: item)
    }

    /// "Try this look once · watch a short ad": consent where it's needed
    /// (only now, after her tap), the ad, a token for the try, the ad on
    /// screen with only that token, then the wait for the server's try.
    private func watchProTryAd(for item: ProTryItem) async {
        guard canOfferProTry(for: item), !isRewardFlowActive, let app, let audience, let backend,
              let unitID = config.activeRewardedUnitID, case .available = proTryOffer(for: item) else { return }
        guard app.isOnline, !app.isCloudOffline else {
            setTry(.notice(.offline), for: item)
            return
        }
        setTry(.loading, for: item)
        // AI may have gone on a break since the card appeared: the try couldn't start its job.
        await app.refreshAIServicePause()
        guard case .available = proTryOffer(for: item) else {
            setTry(.idle, for: item)
            return
        }
        markAdsUsed()
        guard await provider.gatherConsent(audience: audience) else {
            setTry(.notice(.consent), for: item)
            return
        }
        showsPrivacyChoices = provider.privacyOptionsRequired
        // Pro, her age or her balance may have changed while Google's form was up.
        guard canOfferProTry(for: item), case .available = proTryOffer(for: item), self.audience == audience else {
            setTry(.idle, for: item)
            return
        }
        do {
            try await provider.loadRewarded(unitID: unitID, audience: audience)
        } catch {
            setTry(.notice(app.isOnline ? .noFill : .offline), for: item)
            return
        }
        let token: AdRewardToken
        do {
            token = try await backend.issueUnlockToken(for: item)
        } catch let error as AdRewardError {
            await refusedTry(error, item: item)
            return
        } catch {
            setTry(.notice(NetworkFailure.isTransient(error) ? .offline : .failed), for: item)
            return
        }
        let outcome = await provider.showRewarded(token: token.token)
        // Like the credit ad: no interstitial within 4 minutes of this one.
        pacing.noteRewardedAd(at: Date())
        savePacing()
        switch outcome {
        case .earned:
            setTry(.pending, for: item)
            await waitForTry(token: token.token, item: item)
        case .closedEarly:
            await backend.release(token: token.token)
            setTry(.notice(.closedEarly), for: item)
            await refreshProTryOverview(force: true)
        case .failed:
            await backend.release(token: token.token)
            setTry(.notice(.failed), for: item)
            await refreshProTryOverview(force: true)
        }
    }

    private func refusedTry(_ error: AdRewardError, item: ProTryItem) async {
        switch error {
        case .dailyCap:
            // The card says so: today's try is used.
            tryOverview = ProTryOverview(remainingToday: 0, dailyCap: tryOverview?.dailyCap, eligible: false,
                                         active: tryOverview?.active ?? [])
            setTry(.idle, for: item)
        case .noCredits:
            app?.credits.sync(serverBalance: 0)
            setTry(.idle, for: item)
        case .aiPaused:
            await app?.refreshAIServicePause(force: true)
            setTry(.notice(.unavailable), for: item)
        case .notEligible, .notUnlockable:
            setTry(.notice(.unavailable), for: item)
        case .hasCredits, .unauthorized, .server:
            setTry(.notice(.failed), for: item)
        }
    }

    /// AdMob tells the server, usually within seconds; the app asks until the
    /// try is there, then the paywall closes and the look or style starts.
    private func waitForTry(token: String, item: ProTryItem) async {
        guard let backend else { return }
        lateTry = nil
        let started = Date()
        var delay: Double = 1.5
        while Date().timeIntervalSince(started) < Self.confirmationWait {
            try? await Task.sleep(for: .seconds(delay))
            delay = min(delay + 0.5, 4)
            let asked = Date()
            guard let status = try? await backend.status(token: token) else { continue }
            switch status.status {
            case .granted:
                if let balance = status.creditsRemaining { app?.credits.sync(serverBalance: balance, asOf: asked) }
                if var overview = tryOverview {
                    overview.remainingToday = status.remainingToday
                    tryOverview = overview
                }
                let expiresAt = status.expiresAt ?? Date().addingTimeInterval(tryPolicy.fallbackLength)
                activeTries.removeAll { $0.item == item }
                activeTries.append(ProTry(item: item, expiresAt: expiresAt))
                setTry(.granted, for: item)
                Haptics.success()
                // A moment for "Your try is ready", then on to the look.
                try? await Task.sleep(for: .milliseconds(700))
                setTry(.idle, for: item)
                app?.startProTry(item)
                return
            case .capped:
                tryOverview = ProTryOverview(remainingToday: 0, dailyCap: tryOverview?.dailyCap, eligible: false,
                                             active: tryOverview?.active ?? [])
                setTry(.idle, for: item)
                return
            case .expired, .unknown:
                setTry(.notice(.failed), for: item)
                return
            case .pending, nil:
                continue
            }
        }
        lateTry = (token, item)
        setTry(.notice(.delayed), for: item)
    }

    /// The try's job was admitted and finished: it's spent.
    func noteTrySpent(_ item: ProTryItem) {
        activeTries.removeAll { $0.item == item }
        lastTryOverview = nil
    }

    /// The server says the try is gone (ended or spent): the card asks again.
    func forgetTry(_ item: ProTryItem) {
        activeTries.removeAll { $0.item == item }
        lastTryOverview = nil
    }

    private func setTry(_ phase: TryPhase, for item: ProTryItem) {
        tryItem = item
        tryPhase = phase
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

    /// The rating request or the invite card took this break: no ad on top
    /// of it (this save's chance is gone; the pacing is unchanged).
    func yieldBreak() {
        breakTask?.cancel()
        lastExport = nil
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
        tryPhase = .idle
        lateTry = nil
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
        tryPhase = .idle
        tryItem = nil
        tryOverview = nil
        activeTries = []
        lastTryOverview = nil
        lateTry = nil
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

    /// `-GLUnlockState available|loading|pending|granted|capped|nocredits|nofill`
    /// (also `ready`, `closed`, `delayed`, `offline`, `unavailable`) pins the
    /// Pro try card, with `paywall -GLPaywallSource template_<id>|style_<id>`
    /// of a Pro look or style.
    static let screenshotTry: (offer: ProTryOffer, phase: TryPhase)? = {
        let open = ProTryOffer.available(remaining: 1)
        switch UserDefaults.standard.string(forKey: "GLUnlockState") {
        case "available": return (open, .idle)
        case "loading": return (open, .loading)
        case "pending": return (open, .pending)
        case "granted": return (open, .granted)
        case "ready": return (.ready(expiresAt: Date().addingTimeInterval(24 * 60)), .idle)
        case "capped": return (.capped, .idle)
        case "nocredits": return (.needsCredit, .idle)
        case "nofill": return (open, .notice(.noFill))
        case "closed": return (open, .notice(.closedEarly))
        case "delayed": return (open, .notice(.delayed))
        case "offline": return (open, .notice(.offline))
        case "unavailable": return (open, .notice(.unavailable))
        default: return nil
        }
    }()
    #endif
}
