import SwiftUI
import SwiftData
import PhotosUI
import Observation
import AuthenticationServices
import StoreKit
import Network
import AppCore

enum AppTab: Hashable {
    case home, create, edit, library
}

/// What to open in the editor once the user picks a photo.
struct EditorRequest: Equatable {
    var tool: EditorTool?
    var template: PhotoTemplate?
}

struct EditorLaunch: Identifiable {
    let id = UUID()
    let image: UIImage
    var tool: EditorTool?
    var template: PhotoTemplate?
    /// Pre-filled Magic Edit instruction (deep links, screenshots).
    var prompt: String?
    /// An already-applied result to show in compare mode (screenshots).
    var previewResult: UIImage?
    /// An effect to preview right away (screenshots).
    var previewEffect: RetroEffect?
    /// A crop shape and straighten angle to start from (screenshots).
    var cropAspect: CropAspect?
    var cropAngle: Double = 0
    /// How the photo was made (an AI result, or a file that already carries
    /// an AI marking), so saving after a re-edit keeps the marking.
    var provenance = Provenance()
}

struct ConsentRequest: Identifiable {
    let id = UUID()
    let onAccept: () -> Void
}

/// The Pro look or style that opened the paywall, and how to go on with it if
/// she watches an ad for a one-time try (`ProTryCard`): the same request
/// again, through the usual gates.
struct ProTryRequest {
    let item: ProTryItem
    let resume: () -> Void
}

struct PhotosAccessRequest: Identifiable {
    let id = UUID()
    /// Offers "Share instead" when the caller can share what she tried to save.
    let shareInstead: (() -> Void)?

    /// Photos privacy settings: the app's own page on iPhone and iPad,
    /// Privacy & Security › Photos on the Mac.
    static var settingsURL: URL? {
        URL(string: Platform.isMac ? "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos"
                                   : UIApplication.openSettingsURLString)
    }
}

/// Settings › Appearance. Light (the pink "Blush" look) is the default.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case light, dark, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        case .system: return String(localized: "Automatic")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

/// App-wide state, navigation and the gates (consent → Pro → credits) that
/// every AI action passes through.
@MainActor
@Observable
final class AppModel {
    // MARK: Persistent flags
    private(set) var hasCompletedOnboarding: Bool
    /// Cloud AI consent (see `AIConsentRecord` in AppCore); nil until she
    /// taps "Allow AI processing".
    private(set) var consentRecord: AIConsentRecord?
    /// Her age range (band, source, date), only on this device. Nil until
    /// she has answered the age step.
    private(set) var ageRecord: AgeRecord?
    /// The App Store storefront (three-letter code), for consent-age rules.
    private(set) var storefrontCountry: String?
    private(set) var interests: Set<String>
    var appearance: AppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    // MARK: Navigation
    var selectedTab: AppTab = .home {
        // Under 13 there's no Create tab: a button that asks for it (My
        // Works' empty state, say) lands on the free tools instead of a blank.
        didSet { if selectedTab == .create && !allowsCloudAI { selectedTab = .edit } }
    }
    /// Mac: the sidebar shows (View › Show Sidebar, ⌃⌘S) or not.
    var macSidebarVisibility: NavigationSplitViewVisibility = .all
    /// The editor on screen, so Edit › Undo and Redo (⌘Z, ⇧⌘Z) on the Mac
    /// step through its history.
    var activeEditor: EditorViewModel?
    /// The save of the cover on screen (editor, collage, video editor, Retro
    /// Cam review), for File › Save (⌘S). Each registers it while it's up.
    var saveActiveCover: (() -> Void)?
    /// The close of the cover on screen (editor, collage, video editor, Retro
    /// Cam and its shot review), for File › Close (⌘W); each runs its own close
    /// button's path. Unset while one of the app's sheets is over the editor.
    var closeActiveCover: (() -> Void)?
    /// File › New Creation asks Create to put the cursor in its prompt.
    var wantsPromptFocus = false
    /// Settings: the gear on Explore, or Aybuke › Settings… on the Mac.
    var isSettingsPresented = false
    var isPaywallPresented = false
    /// Pro without enough credits: next refill and packs (free members get the paywall).
    var outOfCredits: OutOfCreditsRequest?
    /// Cloud AI rests after repeated safety blocks, or is off for this
    /// install (the server's word, from a balance read or a refused job).
    /// While it lasts, AI actions explain it kindly instead of trying, and
    /// never open the paywall; the free on-device tools work as always.
    private(set) var cloudPause: CloudPause?
    /// Cloud AI rests for everyone: the server's own pause (the owner's
    /// switch, the day's limits or the image provider's balance), from
    /// `GET /credits-redeem`. While it touches her there's no ad for a
    /// credit, and the paywall and the packs say so (`activeAIServicePause`).
    private(set) var aiServicePause: AIServicePause?
    private(set) var paywallSource = "unknown"
    /// What the paywall's Pro look or style was for, while it's up.
    private(set) var pendingProTry: ProTryRequest?
    /// A granted try's request, run once the paywall is gone.
    @ObservationIgnored private var proTryResume: (() -> Void)?
    var isPhotoPickerPresented = false
    var editorLaunch: EditorLaunch? {
        didSet { if editorLaunch?.tool == .textStickers { GlowTips.noteUsed(.textStickers) } }
    }
    var consentRequest: ConsentRequest?
    var shareRequest: SharePayload?
    /// "Your polls" (My Works, a poll link).
    var pollsSheet: PollsSheetRequest?
    /// Two creations from My Works on their way to a poll ("Ask friends").
    var pollDraft: PollDraft?
    /// "Keep your credits on every device": offered after a purchase while
    /// Sign in with Apple is offered (`offersSignIn`).
    var isAccountPromptPresented = false
    /// "Find your best shot" (on-device, by light and focus).
    var isBestShotPresented = false
    /// The collage and photo dump maker (full screen, on-device).
    var isCollagePresented = false {
        didSet { if isCollagePresented { GlowTips.noteUsed(.collage) } else { collageStartFiles = [] } }
    }
    /// Pictures from My Works the collage maker opens with (`openCollage(with:)`).
    @ObservationIgnored private var collageStartFiles: [Data] = []
    /// The simple video editor: picker, then the editor itself.
    var isVideoPickerPresented = false
    var videoSource: VideoSource?
    /// Retro Cam and Photo Booth (full screen, on the device).
    var isRetroCamPresented = false {
        didSet { if isRetroCamPresented { GlowTips.noteUsed(.retroCam) } }
    }
    /// Retro Cam opens in Photo Booth mode (Siri, Shortcuts, a control);
    /// the camera clears it when it starts.
    @ObservationIgnored var retroCamStartsInBooth = false
    var toast: ToastMessage?
    /// "Photos access is off" with Open Settings (and Share instead).
    var photosAccessRequest: PhotosAccessRequest?
    @ObservationIgnored private var pendingEditorRequest: EditorRequest?
    /// How My Works opened at launch; a repair is reported once in `start()`.
    @ObservationIgnored var libraryOutcome: LibraryStore.Outcome = .opened
    /// Library saves that failed while the device was locked, retried after unlock.
    @ObservationIgnored private var deferredSaves: [DeferredSave] = []
    @ObservationIgnored private var unlockWatcher: Task<Void, Never>?
    @ObservationIgnored private var widgetImageTask: Task<Void, Never>?
    private(set) var isOnline = true
    @ObservationIgnored private var pathMonitor: NWPathMonitor?

    // MARK: Services
    let config: AppConfig
    let purchases: PurchaseManager
    let credits: CreditsManager
    let ai: AIImageService
    /// Present only when a backend is configured (production mode).
    private let remote: RemoteAIImageService?
    /// StoreKit's signed AppTransaction: free credits belong to a verified App Store install.
    let appTransactions: AppTransactionProvider
    private let container: ModelContainer
    private let defaults: UserDefaults
    /// Dynamic Island / Lock Screen progress for cloud jobs.
    private let liveActivity = GlowActivityController()
    /// Opt-in local reminders (glow ready, credits back, the weekly look).
    let notifier = GlowNotifier()
    /// The first-run tour ("Next, Next…" through every tab).
    let tour = TourGuide()
    /// Prompt upgrades and ideas from Apple's on-device model (when available).
    let writer = OnDeviceWriter()
    /// Writing help from the server (Claude), when a backend is configured;
    /// asked first while `usesCloudWriter`, with `writer` as the fallback.
    let cloudWriter: CloudWriter?
    /// Create's recent prompts and draft, kept only on this device.
    let prompts: PromptHistory
    /// Adjust's saved filters ("My filters"), kept only on this device.
    let myFilters: MyFiltersStore
    /// Rewarded and interstitial ads for free members 13+ (see `AdCoordinator`).
    let ads: AdCoordinator
    /// "Which vibe?" polls with friends, and what this device keeps of them.
    let polls: PollsModel

    // MARK: Account (optional Sign in with Apple)
    /// A server session exists on this device, anonymous or signed in. Her
    /// first consented cloud job or a purchase makes one; writing help waits
    /// for it and never makes one (`usesCloudWriter`).
    private(set) var hasSession = false
    /// Signed in with Apple: Pro and credits follow her to other iPhones.
    private(set) var isSignedIn = false
    /// The Apple ID email or its private relay address, if she shared it.
    private(set) var accountEmail: String?
    /// "Delete my data" is waiting for the server.
    private(set) var isDeletingData = false
    @ObservationIgnored private var reviewPolicy: ReviewPromptPolicy
    /// "Loving Aybuke? Invite a friend" after a finished save or share.
    @ObservationIgnored private var invitePacing: InviteCardPacing
    /// Her visits (no rating request or invite card in the first).
    @ObservationIgnored private var sessions: EngagementSessions
    /// Goes up when it's the moment to ask for a rating: the root view asks StoreKit.
    private(set) var reviewRequests = 0
    /// The invite card is on screen, above the tab bar (`InvitePromptCard`).
    private(set) var isInviteCardVisible = false
    /// The invite (Glow together), opened from the invite card.
    var isInvitePresented = false
    /// The last finished save or share, until the next natural break decides
    /// whether a rating request or the invite card follows it.
    @ObservationIgnored private var lastExport: Date?
    @ObservationIgnored private var askTask: Task<Void, Never>?
    /// The cold-launch splash covers the first moments (`LaunchSplash`).
    private(set) var isLaunchSplashVisible: Bool
    /// The last paywall or permission prompt; no rating prompt for 30 minutes after.
    @ObservationIgnored private var lastInterruption: Date?
    /// One paywall a session is enough: no onboarding one after another.
    @ObservationIgnored private var paywallShownThisSession = false
    /// When the last full balance read answered, and reads on their way: the
    /// app's own reads at launch and in the foreground wait 15 minutes after
    /// one (`BalanceRefreshPolicy`).
    @ObservationIgnored private var lastBalanceRead: Date?
    @ObservationIgnored private var balanceReadsInFlight = 0
    /// When the server's pause was last asked for: at most once a minute.
    @ObservationIgnored private var lastAIPauseRead: Date?

    private enum Keys {
        static let onboarding = "onboarding.completed"
        /// The adult soft paywall waits for the first success (the editor
        /// closing); kept so a force-quit there still shows it once.
        static let onboardingPaywallPending = "onboarding.paywallPending"
        /// Older formats that never shipped: read as "no consent" and removed.
        static let legacyConsent = ["ai.consent.v1", "ai.consent.v2"]
        static let consent = "ai.consent.v3"
        static let ageRecord = "age.record.v1"
        static let interests = "onboarding.interests"
        static let successfulSaves = "stats.successfulSaves"
        static let reviewPolicy = "review.policy.v1"
        static let invitePacing = "invite.card.v1"
        static let sessions = "engagement.sessions.v1"
        static let appleUserID = "auth.appleUserID"
        static let appearance = "appearance"
        /// A delete request was sent; a later rejected session means it worked.
        static let deletionRequested = "account.deletionRequested"
        /// What "Delete my data" removes (other owners' keys spelled out here
        /// so the list is complete in one place).
        static let wiped = [
            onboarding, onboardingPaywallPending, consent, ageRecord, interests, successfulSaves, reviewPolicy, invitePacing, sessions,
            appearance, deletionRequested,
            "credits.wallet.v2", "notifications.preferences.v1", "notifications.readyPingDeclined", "tour.seen.v1",
            PromptHistory.recentKey, PromptHistory.draftKey, MyFiltersStore.key, AdCoordinator.pacingKey, AdCoordinator.usedKey,
            PurchaseManager.purchasedKey, AutoEditQuota.key, PollsModel.storageKey, PollsModel.explainerKey,
        ] + legacyConsent
        static let wipedKeychain = [appleUserID, "auth.session", "auth.pendingMerge", "auth.pendingAppleCode"]
    }

    init(container: ModelContainer, config: AppConfig = .current, defaults: UserDefaults = .standard) {
        self.container = container
        self.config = config
        self.defaults = defaults
        #if DEBUG
        // Screenshot scenes never read or keep her prompts, unless
        // `-GLKeepPrompts YES` asks for the stored ones (QA).
        let keepsPrompts = ScreenshotScene.current == nil || UserDefaults.standard.bool(forKey: "GLKeepPrompts")
        self.prompts = PromptHistory(defaults: keepsPrompts ? defaults : nil)
        // `-GLMyFilters YES` shows a few saved filters in Adjust, in memory only.
        let myFilters = MyFiltersStore(defaults: ScreenshotScene.current == nil ? defaults : nil)
        if ScreenshotScene.current != nil, UserDefaults.standard.bool(forKey: "GLMyFilters") { myFilters.seedForScreenshots() }
        self.myFilters = myFilters
        #else
        self.prompts = PromptHistory(defaults: defaults)
        self.myFilters = MyFiltersStore(defaults: defaults)
        #endif
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        self.consentRecord = AIConsentRecord.decode(defaults.data(forKey: Keys.consent))
        for key in Keys.legacyConsent { defaults.removeObject(forKey: key) }
        self.ageRecord = defaults.data(forKey: Keys.ageRecord).flatMap { try? JSONDecoder().decode(AgeRecord.self, from: $0) }
        self.interests = Set(defaults.stringArray(forKey: Keys.interests) ?? [])
        self.appearance = defaults.string(forKey: Keys.appearance).flatMap(AppearancePreference.init(rawValue:)) ?? .light
        if let data = defaults.data(forKey: Keys.reviewPolicy),
           let saved = try? JSONDecoder().decode(ReviewPromptPolicy.self, from: data) {
            self.reviewPolicy = saved
        } else {
            var fresh = ReviewPromptPolicy(firstSeen: Date())
            fresh.happyMoments = defaults.integer(forKey: Keys.successfulSaves)
            self.reviewPolicy = fresh
        }
        self.invitePacing = defaults.data(forKey: Keys.invitePacing)
            .flatMap { try? JSONDecoder().decode(InviteCardPacing.self, from: $0) } ?? InviteCardPacing()
        // Someone who finished onboarding in an earlier version isn't new:
        // this launch is at least her second visit.
        self.sessions = defaults.data(forKey: Keys.sessions)
            .flatMap { try? JSONDecoder().decode(EngagementSessions.self, from: $0) }
            ?? EngagementSessions(count: defaults.bool(forKey: Keys.onboarding) ? 1 : 0)
        self.isLaunchSplashVisible = LaunchSplash.shouldShow

        let purchases = PurchaseManager(defaults: defaults)
        self.purchases = purchases
        let credits = CreditsManager(policy: config.creditPolicy, isServerAuthoritative: config.backend != nil)
        self.credits = credits
        let appTransactions = AppTransactionProvider()
        self.appTransactions = appTransactions

        // Rewarded ads need the backend (and its session) to confirm the credit.
        var adRewards: AdRewardBackend?
        var pollsBackend: PollsBackend?
        var cloudWriter: CloudWriter?
        var sessionChanges: AsyncStream<Bool>?
        switch config.aiMode {
        case .backend(let backend):
            let auth = AuthSessionManager(config: backend)
            cloudWriter = CloudWriter(config: backend, auth: auth, appTransactions: appTransactions)
            pollsBackend = PollsBackend(config: backend, auth: auth, appTransactions: appTransactions)
            hasSession = auth.hadSessionAtLaunch
            sessionChanges = auth.sessionChanges
            adRewards = AdRewardBackend(config: backend, auth: auth, appTransactions: appTransactions) { [weak purchases] in
                purchases?.entitlementJWS
            }
            // The pill shows the charge as soon as a job starts, and the
            // balance (or the refund) as soon as it ends.
            let remote = RemoteAIImageService(
                config: backend,
                auth: auth,
                entitlementProvider: { [weak purchases] in purchases?.entitlementJWS },
                appTransactions: appTransactions,
                balanceObserver: { [weak credits] balance, asOf in credits?.sync(serverBalance: balance, asOf: asOf) }
            )
            self.remote = remote
            self.ai = AIServiceRouter(cloud: remote, onDevice: OnDeviceImageService())
        case .direct(let direct):
            self.remote = nil
            let cloud = DirectAIImageService(config: direct) { [weak purchases] in
                purchases?.isPro ?? false
            }
            self.ai = AIServiceRouter(cloud: cloud, onDevice: OnDeviceImageService())
        case .demo:
            self.remote = nil
            self.ai = AIServiceRouter(cloud: DemoAIImageService(), onDevice: OnDeviceImageService())
        }
        #if DEBUG
        // -GLAssistStub YES|fail|blocked: canned writing help, no server (QA, screenshots).
        if CloudWriter.isStubbed { cloudWriter = CloudWriter.stub() }
        #endif
        self.cloudWriter = cloudWriter
        #if DEBUG
        // Screenshot scenes never read or keep her polls (`-GLPollsFixture` shows some).
        self.polls = PollsModel(backend: pollsBackend, defaults: ScreenshotScene.current == nil ? defaults : nil)
        #else
        self.polls = PollsModel(backend: pollsBackend, defaults: defaults)
        #endif
        self.ads = AdCoordinator(config: config.ads, backend: adRewards)
        ads.app = self
        if let sessionChanges {
            Task { [weak self] in
                for await present in sessionChanges { self?.hasSession = present }
            }
        }

        purchases.creditPackHandler = { [weak self] credits, signedTransaction in
            await self?.grantCreditPack(credits, signedTransaction: signedTransaction) ?? false
        }
        purchases.onProStatusChange = { [weak self] isPro in
            guard let self else { return }
            ads.proStatusChanged(isPro: isPro)
            credits.refresh(isPro: isPro, isTrial: purchases.trial != nil)
            syncWidgets()
            Task { await self.refreshServerBalance() }
        }
        purchases.onLatePurchase = { [weak self] purchase in self?.completeLatePurchase(purchase) }
        purchases.onTrialChange = { trial in
            Task { await Self.syncTrialReminder(trial) }
        }
        notifier.onOpenLink = { [weak self] link in self?.handle(link) }
        polls.onLiveChange = { [weak self] live in
            guard let self else { return }
            Task { await self.notifier.syncPollReminders(live: live) }
        }

        #if DEBUG
        // -GLAgeBand under13|teen13to15|teen16to17|adult|unknown (not saved).
        if let band = UserDefaults.standard.string(forKey: "GLAgeBand").flatMap(AgeBand.init(rawValue:)) {
            ageRecord = AgeRecord(band: band, source: .selfDeclared, setAt: Date())
        }
        if let scene = ScreenshotScene.current {
            applyScreenshotScene(scene)
        }
        // `-GLInviteCard YES`: the invite card on screen (QA, screenshots).
        if UserDefaults.standard.bool(forKey: "GLInviteCard") { isInviteCardVisible = true }
        // QA: `-GLPollsLiveDraft YES` opens Ask friends on two generated
        // pictures without a scene, so the poll is made on the real backend.
        if ScreenshotScene.current == nil, UserDefaults.standard.bool(forKey: "GLPollsLiveDraft") {
            let art = ScreenshotFixtures.generatedArt(count: 2)
            pollDraft = PollDraft(a: art[0], b: art[1], provenanceA: Provenance(operation: .textToImage),
                                  provenanceB: Provenance(operation: .textToImage))
        }
        #endif
    }

    // MARK: Age

    /// What her age range allows: on-device tools only under 13, no
    /// automatic paywall and a guardian step for teens.
    var ageDefaults: AgeDefaults { AgeDefaults(record: ageRecord, storefrontCountry: storefrontCountry) }
    var allowsCloudAI: Bool { ageDefaults.allowsCloudAI }
    /// Purchases, the paywall, accounts and RevenueCat.
    var allowsPurchases: Bool { ageDefaults.allowsPurchases }
    /// People who finished onboarding before the age step get it once.
    var needsAgeStep: Bool { ageRecord == nil }

    /// Stores a new answer when it may replace the current one (see
    /// `AgeRecord.accepts`). Never sent anywhere.
    @discardableResult
    func recordAge(_ record: AgeRecord) -> Bool {
        if let ageRecord, !ageRecord.accepts(record) { return false }
        ageRecord = record
        if let data = try? JSONEncoder().encode(record) { defaults.set(data, forKey: Keys.ageRecord) }
        if !allowsPurchases { isPaywallPresented = false }
        if !allowsCloudAI {
            consentRequest = nil
            if selectedTab == .create { selectedTab = .home }
        }
        // Widgets, controls and reminders follow her age band.
        syncWidgets()
        syncReminders()
        return true
    }

    /// Under 13, every entry point to an AI tool opens a free on-device one.
    private func permittedTool(_ tool: EditorTool?) -> EditorTool? {
        guard !allowsCloudAI else { return tool }
        if let tool, !tool.usesCloudAI { return tool }
        return .effects
    }

    private func noteUnavailable() {
        showToast("That one isn't available. The free tools in Edit are all yours.", style: .info)
    }

    var isDemoMode: Bool { config.isDemoMode }

    /// Screenshot scenes never read the server (a session left on the
    /// simulator would put its balance and account in the picture): their
    /// numbers and states are the fixtures'. Always false in Release.
    static var staysOffServer: Bool {
        #if DEBUG
        return ScreenshotScene.current != nil
        #else
        return false
        #endif
    }

    /// Cloud AI can't be reached. Demo mode runs without a network, so it
    /// never counts as offline (nor do screenshot scenes).
    var isCloudOffline: Bool {
        #if DEBUG
        if ScreenshotScene.current != nil { return UserDefaults.standard.bool(forKey: "GLOffline") }
        #endif
        return !isOnline && !isDemoMode
    }

    /// Starts once; the first update arrives within moments, so until then
    /// she's assumed online rather than shown a false offline notice.
    private func watchNetwork() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                if self?.isOnline != online { self?.isOnline = online }
            }
        }
        monitor.start(queue: DispatchQueue(label: "app.glowlit.network", qos: .utility))
        pathMonitor = monitor
    }

    /// Banner on Explore explaining simulated (demo) or developer-key results.
    var modeBanner: String? {
        #if DEBUG
        // Marketing and QA screenshots show the app as people will see it.
        if ScreenshotScene.current != nil { return nil }
        #endif
        switch config.aiMode {
        case .backend:
            return nil
        case .direct(let direct):
            return "Developer mode — AI runs directly on \(direct.provider.displayName) with your key from Secrets.xcconfig. Release builds use the backend."
        case .demo:
            return String(localized: "Preview build: AI results are samples")
        }
    }

    /// Called once from the root view's `.task`.
    func start() async {
        sessions.noteLaunch()
        persistEngagement()
        watchNetwork()
        liveActivity.endLeftovers()
        Task { await TemporaryFiles.sweep() }
        Task { await LibraryTrash.purgeExpired(in: container) }
        switch libraryOutcome {
        case .opened: break
        case .rebuilt:
            showToast("We rebuilt My Works. Your images are back; titles and hearts couldn't be restored.", style: .info)
        case .temporary:
            showToast("My Works couldn't open, so new creations won't be kept this time. Free up some space and restart Aybuke.", style: .error)
        }
        libraryOutcome = .opened
        storefrontCountry = await Storefront.current?.countryCode
        // Read on the device only (nothing is sent), so the first cloud job
        // after consent doesn't wait for StoreKit.
        if remote != nil, allowsCloudAI {
            let appTransactions = appTransactions
            Task.detached(priority: .utility) { _ = await appTransactions.jws(waitingAtMost: .seconds(30)) }
        }
        // No account and no RevenueCat here: both wait until she buys or uses
        // a cloud feature (Privacy Policy §5).
        await configureRevenueCatForReturningBuyer()
        await refreshAccount()
        watchAppleCredentialRevocation()
        await purchases.refreshEntitlements()
        // Settings › Account: who bought something gets the sign-in card.
        if allowsPurchases { await purchases.refreshPurchaseHistory() }
        credits.refresh(isPro: purchases.isPro, isTrial: purchases.trial != nil)
        await refreshServerBalanceIfDue()
        syncWidgets()
        syncReminders()
        #if !DEBUG
        if isDemoMode { await purchases.closeForPreviewIfFromAppStore() }
        #endif
        await purchases.loadProducts()
        // She force-quit the editor she opened from onboarding.
        if defaults.bool(forKey: Keys.onboardingPaywallPending), hasCompletedOnboarding, !needsAgeStep, editorLaunch == nil {
            while isLaunchSplashVisible { try? await Task.sleep(for: .milliseconds(100)) }
            offerOnboardingPaywall()
        }
    }

    /// The splash is done (or a link, or leaving the app, cut it short): a
    /// crossfade into the app, and the tour may start once it's gone.
    func endLaunchSplash(animated: Bool = true) {
        guard isLaunchSplashVisible else { return }
        if animated {
            withAnimation(.easeInOut(duration: LaunchSplash.fadeDuration)) { isLaunchSplashVisible = false }
        } else {
            isLaunchSplashVisible = false
        }
        guard hasCompletedOnboarding, !tour.hasSeen else { return }
        Task {
            try? await Task.sleep(for: .seconds(LaunchSplash.fadeDuration + 0.3))
            offerTourIfNeeded()
        }
    }

    /// Back in the foreground: notification permission may have changed.
    func becameActive() {
        sessions.noteForeground(at: Date())
        persistEngagement()
        syncReminders()
        // A trial cancelled in Settings › Subscriptions loses its reminder.
        Task { await purchases.refreshEntitlements() }
        // Refunds can land while she's away (a result that never reached the
        // app); the credits sheet still reads at once when she opens it.
        Task {
            await refreshServerBalanceIfDue()
            syncWidgets()
        }
    }

    /// In the background: half an hour away starts a new session.
    func enteredBackground() {
        sessions.noteBackground(at: Date())
        persistEngagement()
    }

    /// The trial reminder exists only while a trial runs and will renew.
    private static func syncTrialReminder(_ trial: TrialStatus?) async {
        guard let trial, trial.willRenew else {
            TrialReminder.cancel()
            return
        }
        await TrialReminder.schedule(trialEnd: trial.endsAt, price: trial.price, mayAsk: false)
    }

    /// Adds a purchased pack: locally in demo mode, verified by the server in production.
    func grantCreditPack(_ credits: Int, signedTransaction: String) async -> Bool {
        guard let remote else {
            self.credits.addPurchased(credits)
            return true
        }
        do {
            let sent = Date()
            let balance = try await remote.redeemCreditPack(signedTransaction: signedTransaction)
            self.credits.sync(serverBalance: balance, asOf: sent)
            return true
        } catch {
            // The transaction stays unfinished, so StoreKit redelivers it and we retry.
            showToast("We couldn't add your credits yet. We'll retry automatically.", style: .error)
            return false
        }
    }

    /// An approved "Ask to Buy" or a redeemed offer code. No account prompt
    /// here: it could cover an edit in progress (Settings still offers it).
    private func completeLatePurchase(_ purchase: LatePurchase) {
        Haptics.success()
        if purchase.isCreditPack {
            showToast("Credits added ✦", style: .success)
            return
        }
        showToast("Welcome to \(Brand.name) Pro ✦", style: .success)
        // The trial reminder follows from `onTrialChange`.
    }

    /// Binds purchases to the backend user (StoreKit `appAccountToken`) and
    /// starts RevenueCat's observer for this buyer. Called on tap, so the
    /// paywall never waits for it; if sign-up fails the purchase goes ahead.
    func appAccountToken() async -> UUID? {
        guard allowsPurchases else { return nil }
        let userID = await remote?.currentUserID()
        RevenueCatBridge.configure(apiKey: config.revenueCatAPIKey, appUserID: userID?.uuidString)
        if let userID { await RevenueCatBridge.identify(userID.uuidString) }
        return userID
    }

    /// RevenueCat only sees people who buy. At launch that means an Apple
    /// Account that already has our purchases, so observer mode still
    /// records renewals and approved Ask to Buy requests.
    private func configureRevenueCatForReturningBuyer() async {
        // Family Sharing can bring purchases to a child's Apple Account.
        guard let remote, allowsPurchases, !config.revenueCatAPIKey.isEmpty else { return }
        for await _ in Transaction.all {
            RevenueCatBridge.configure(apiKey: config.revenueCatAPIKey, appUserID: await remote.existingUserID()?.uuidString)
            return
        }
    }

    /// Reports go to the backend for review; preview (demo and developer)
    /// builds have no server to send them to.
    var canSendReports: Bool { remote != nil }

    /// Says so instead of pretending a report was kept.
    func noteReportingUnavailable() {
        showToast("Reporting turns on when \(Brand.name) launches. Thanks for looking out.", style: .info)
    }

    /// "Report this image": sent to the backend for review.
    func report(_ reason: ReportReason, requestID: String?) async {
        registerSetback()
        guard let remote else {
            noteReportingUnavailable()
            return
        }
        do {
            try await remote.report(reason, jobID: requestID.flatMap { UUID(uuidString: $0) == nil ? nil : $0 })
            Haptics.success()
            showToast("Thanks — we'll review this image.", style: .success)
        } catch {
            handle(error)
        }
    }

    /// Settings › Delete my data: the server account first, so a failed
    /// request keeps everything; then everything on this device.
    func deleteAccountAndData() async {
        guard !isDeletingData else { return }
        isDeletingData = true
        defer { isDeletingData = false }
        if let remote {
            let previouslyRequested = defaults.bool(forKey: Keys.deletionRequested)
            defaults.set(true, forKey: Keys.deletionRequested)
            do {
                try await deleteServerAccount(remote, previouslyRequested: previouslyRequested)
            } catch AccountDeletionError.appleConfirmationNeeded {
                // She closed Apple's sheet: nothing was deleted, and she can try again.
                showToast("Confirm with Apple to finish deleting your account.", style: .info)
                return
            } catch {
                handle(error)
                return
            }
        }
        await RevenueCatBridge.logOut()
        await wipeLocalData()
        isSettingsPresented = false
        showToast("Your data has been deleted.", style: .success)
    }

    /// A Sign in with Apple account whose Apple token the server never got (the
    /// one-time code expired or Apple refused it at sign-in) needs a fresh code,
    /// so deleting it can revoke the token as Apple requires. Throws
    /// `appleConfirmationNeeded` when she cancels Apple's sheet.
    private func deleteServerAccount(_ remote: RemoteAIImageService, previouslyRequested: Bool) async throws {
        do {
            try await remote.deleteAccount(previouslyRequested: previouslyRequested)
        } catch AccountDeletionError.appleConfirmationNeeded {
            switch await AppleReauthorization.authorizationCode() {
            case .code(let code):
                try await remote.deleteAccount(previouslyRequested: previouslyRequested, authorizationCode: code)
            case .canceled:
                throw AccountDeletionError.appleConfirmationNeeded
            case .unavailable:
                // Apple can't answer here (no Apple ID on this device, an error):
                // deleting her data comes first; the server logs the token it kept none of.
                try await remote.deleteAccount(previouslyRequested: previouslyRequested, skipAppleRevoke: true)
            }
        }
    }

    /// Everything Aybuke keeps on this device, back to a fresh install. The
    /// per-app language choice stays, and so does the trial reminder while a
    /// trial runs: the Apple subscription outlives the deletion.
    private func wipeLocalData() async {
        for key in Keys.wiped { defaults.removeObject(forKey: key) }
        for key in Keys.wipedKeychain { Keychain.delete(key: key) }
        hasCompletedOnboarding = false
        consentRecord = nil
        ageRecord = nil
        interests = []
        appearance = .light
        defaults.removeObject(forKey: Keys.appearance) // the didSet wrote it back
        reviewPolicy = ReviewPromptPolicy(firstSeen: Date())
        invitePacing = InviteCardPacing()
        sessions = EngagementSessions(count: 1)
        isInviteCardVisible = false
        lastExport = nil
        lastInterruption = nil
        isSignedIn = false
        accountEmail = nil
        tour.reset()
        GlowTips.eraseAll()
        prompts.reset()
        myFilters.reset()
        polls.reset()
        pollsSheet = nil
        pollDraft = nil
        ads.reset()
        credits.resetAll()
        purchases.forgetPurchases()
        cloudPause = nil
        await appTransactions.reset()
        credits.refresh(isPro: purchases.isPro, isTrial: purchases.trial != nil)
        deleteAllCreations() // also resets the widgets, after the credits
        deferredSaves = []
        // A library moved aside after damage still holds titles and prompts.
        LibraryStore.removeAllCorruptStores()
        liveActivity.endAll()
        await notifier.reset(keeping: purchases.isPro ? [TrialReminder.identifier] : [])
        URLCache.shared.removeAllCachedResponses()
        // Share exports, the invite card and video copies.
        let temporary = FileManager.default.temporaryDirectory
        for file in (try? FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: Account

    /// A server account exists to delete (anonymous, or signed in): demo and
    /// developer modes have none.
    var canUseAccounts: Bool { remote != nil }

    /// Sign in with Apple is offered: a backend, and `signInWithApple` in
    /// AppConfig.json (on since 1.0; turned off, no entry point shows, and
    /// someone already signed in still sees the account and can sign out).
    var offersSignIn: Bool { remote != nil && config.signInWithApple }

    /// She bought Pro or credits (`PurchaseManager.hasPurchased`): Settings ›
    /// Account offers her the Sign in with Apple card. Everyone else uses the
    /// app without any sign-up and sees one small row for purchases made on
    /// another device; the paywall's Sign in and the prompt after a purchase
    /// stay for all.
    var hasPurchased: Bool { purchases.isPro || purchases.hasPurchased }

    /// Reads the session, finishes a credit merge or code hand-over that failed
    /// earlier, and signs out if the Apple ID stopped using Aybuke.
    func refreshAccount() async {
        guard let remote, !Self.staysOffServer else { return }
        let account = await remote.account()
        isSignedIn = account != nil
        accountEmail = account?.email
        guard isSignedIn else { return }
        try? await remote.linkAccount()
        if let appleUserID = Keychain.load(String.self, key: Keys.appleUserID),
           let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: appleUserID),
           state == .revoked || state == .notFound {
            await signOut(quietly: true)
        }
    }

    func signInWithApple(_ credential: ASAuthorizationAppleIDCredential, nonce: String) async {
        guard let remote else { return }
        guard let tokenData = credential.identityToken, let idToken = String(data: tokenData, encoding: .utf8) else {
            showToast("Apple didn't send a sign-in token. Please try again.", style: .error)
            return
        }
        let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        do {
            try await remote.signInWithApple(idToken: idToken, nonce: nonce, authorizationCode: code)
        } catch {
            handle(error)
            return
        }
        // Signed in from here on, whatever the merge does: requests use the
        // account, so the revoked-Apple-ID check needs the id now.
        Keychain.save(credential.user, key: Keys.appleUserID)
        await refreshAccount() // moves her credits and hands Apple's code over
        if let userID = await remote.existingUserID() { await RevenueCatBridge.identify(userID.uuidString) }
        await purchases.refreshEntitlements()
        credits.refresh(isPro: purchases.isPro, isTrial: purchases.trial != nil)
        await refreshServerBalance()
        syncWidgets()
        if await remote.creditsWaitingToMove() {
            // refreshAccount() tries again at every launch.
            showToast("You're signed in, but your credits haven't moved to your account yet. We'll try again automatically.", style: .info)
            return
        }
        Haptics.success()
        showToast("You're signed in ✨ Your credits now come with you.", style: .success)
    }

    /// Back to an anonymous session on this iPhone. Pro stays tied to the
    /// Apple Account that bought it.
    func signOut(quietly: Bool = false) async {
        await remote?.signOut()
        Keychain.delete(key: Keys.appleUserID)
        isSignedIn = false
        accountEmail = nil
        // No new anonymous user here: one is created when she next needs it.
        await RevenueCatBridge.logOut()
        credits.resetServerBalance()
        await refreshServerBalance()
        syncWidgets()
        if !quietly { showToast("Signed out. Sign in again anytime in Settings.", style: .info) }
    }

    /// After a purchase, offer (never require) an account, so the purchase
    /// isn't stuck on this iPhone.
    func offerAccountAfterPurchase() {
        guard offersSignIn, !isSignedIn else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            isAccountPromptPresented = true
        }
    }

    private func watchAppleCredentialRevocation() {
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: ASAuthorizationAppleIDProvider.credentialRevokedNotification) {
                await self?.signOut(quietly: true)
            }
        }
    }

    /// Reads the balance whenever a session exists, consent or not, so
    /// credits bought before consenting show at launch too. Never creates an
    /// account to read it (the local free allowance shows until one exists),
    /// and never under 13, when the app sends nothing to us.
    func refreshServerBalance() async {
        guard let remote, allowsCloudAI || allowsPurchases, !Self.staysOffServer else { return }
        balanceReadsInFlight += 1
        defer { balanceReadsInFlight -= 1 }
        guard await remote.existingUserID() != nil else { return }
        let sent = Date()
        if let state = try? await remote.fetchBalance() {
            credits.apply(state, asOf: sent)
            cloudPause = CloudPause.from(state)
            lastBalanceRead = Date()
        }
    }

    /// The app's own reads, at launch and back in the foreground: each one is
    /// a server request, so none while one is on its way or within 15 minutes
    /// of the last that answered. Jobs report the balance as they go.
    func refreshServerBalanceIfDue() async {
        guard balanceReadsInFlight == 0, BalanceRefreshPolicy.standard.isDue(lastRead: lastBalanceRead) else { return }
        await refreshServerBalance()
    }

    /// Asks whether cloud AI rests for everyone, where it matters: as the
    /// paywall, the credits sheet or the packs appear, before an ad for a
    /// credit, and after a job was refused with `ai_paused`. It needs no
    /// session (nobody gets an account by opening the paywall) and runs at
    /// most once a minute unless `force`. A failed read changes nothing.
    func refreshAIServicePause(force: Bool = false) async {
        #if DEBUG
        // -GLAIPause all|free: the server's pause, for QA and screenshots.
        if let scope = UserDefaults.standard.string(forKey: "GLAIPause") {
            aiServicePause = AIServicePause(freeOnly: scope == "free", until: .distantFuture)
            return
        }
        #endif
        guard let remote, allowsCloudAI || allowsPurchases, !isCloudOffline, !Self.staysOffServer else { return }
        if !force, let lastAIPauseRead, abs(lastAIPauseRead.timeIntervalSinceNow) < 60 { return }
        lastAIPauseRead = Date()
        do {
            aiServicePause = try await remote.fetchAIPause()
        } catch {
            // Unknown: the last answer stands until its end, and the next look asks again.
            lastAIPauseRead = nil
        }
    }

    /// The server's pause while it lasts and touches her: a pause on free
    /// credits leaves Pro's alone.
    var activeAIServicePause: AIServicePause? {
        guard let aiServicePause, aiServicePause.isActive(), aiServicePause.touches(isPro: purchases.isPro) else { return nil }
        return aiServicePause
    }

    // MARK: Onboarding & consent

    func completeOnboarding(interests: Set<String>) {
        self.interests = interests
        hasCompletedOnboarding = true
        defaults.set(Array(interests), forKey: Keys.interests)
        defaults.set(true, forKey: Keys.onboarding)
    }

    /// The soft paywall after onboarding: adults only, never for Pro, and
    /// not when another paywall was already shown this session. The one
    /// place the age-assurance rules extend.
    var shouldShowOnboardingPaywall: Bool {
        !purchases.isPro && ageDefaults.autoPaywall && !paywallShownThisSession
    }

    /// Onboarding ended (a saved try-it result, or skipped): the paywall now.
    func offerOnboardingPaywall() {
        defaults.removeObject(forKey: Keys.onboardingPaywallPending)
        if shouldShowOnboardingPaywall { presentPaywall(source: "onboarding") }
    }

    /// Onboarding ended in the editor: the paywall waits until she closes it.
    func deferOnboardingPaywall() {
        guard shouldShowOnboardingPaywall else { return }
        defaults.set(true, forKey: Keys.onboardingPaywallPending)
    }

    func toggleMacSidebar() {
        withAnimation(.snappy) {
            macSidebarVisibility = macSidebarVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    /// The editor's full-screen cover closed.
    func editorDidClose() {
        activeEditor = nil
        GlowTips.noteEditorClosed()
        if defaults.bool(forKey: Keys.onboardingPaywallPending) {
            offerOnboardingPaywall()
        }
        presentationEnded()
    }

    /// A paywall, account prompt or editor closed: a moment later (after a
    /// purchase the account prompt comes first), offer the tour.
    func presentationEnded() {
        if let resume = proTryResume {
            // The paywall closed for a try she just got: the look or style
            // starts now (the photo picker, consent or the job itself), so
            // no break and no tour on top of it.
            proTryResume = nil
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                resume()
            }
            return
        }
        // A save in the editor, video editor or collage maker: its break is now.
        naturalBreak()
        guard hasCompletedOnboarding, !tour.hasSeen else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            offerTourIfNeeded()
        }
    }

    /// Shows the tour once, after onboarding, when nothing else is on screen.
    func offerTourIfNeeded() {
        #if DEBUG
        if let scene = ScreenshotScene.current {
            if scene == .tour { startTour() }
            return
        }
        #endif
        guard hasCompletedOnboarding, !needsAgeStep, !tour.hasSeen, !tour.isRunning, !isPresentingSomething,
              !isSettingsPresented, !isPhotoPickerPresented, !isVideoPickerPresented, !isLaunchSplashVisible else { return }
        startTour()
    }

    func startTour() {
        // Under 13 the AI steps (and the Create tab) aren't there.
        let steps = allowsCloudAI ? TourStep.allCases : TourStep.allCases.filter { !$0.isAboutCloudAI }
        selectedTab = steps.first?.tab ?? .home
        tour.start(steps: steps)
    }

    /// The editor, the video editor, Retro Cam or the collage maker fills the
    /// screen. Each shows the app's sheets itself (the root's would open
    /// behind it), and deep links leave it alone: its work may not be saved.
    var isFullScreenCoverPresented: Bool {
        editorLaunch != nil || videoSource != nil || isRetroCamPresented || isCollagePresented
    }

    private var isPresentingSomething: Bool {
        isPaywallPresented || outOfCredits != nil || isFullScreenCoverPresented || consentRequest != nil
            || shareRequest != nil || isAccountPromptPresented || isBestShotPresented || pollsSheet != nil || pollDraft != nil
    }

    /// Mac menu commands and dropped photos only act on the main screens:
    /// never during onboarding or the tour, or over a sheet, a picker or the editor.
    var acceptsCommands: Bool {
        hasCompletedOnboarding && !needsAgeStep && !tour.isRunning && !isPresentingSomething
            && !isSettingsPresented && !isPhotoPickerPresented && !isVideoPickerPresented
    }

    /// File › Close (⌘W) is for what's on screen, in order: a cover that asks
    /// before it discards work, then Settings, the paywall and Best shot. The
    /// others close with Esc or their own buttons, as before.
    var canClosePresented: Bool {
        closeActiveCover != nil || isSettingsPresented || isPaywallPresented || isBestShotPresented
    }

    func closePresented() {
        if let closeActiveCover {
            closeActiveCover()
        } else if isSettingsPresented {
            isSettingsPresented = false
        } else if isPaywallPresented {
            isPaywallPresented = false
        } else if isBestShotPresented {
            isBestShotPresented = false
        }
    }

    /// Consent counts only where cloud AI is offered, for the current
    /// consent version and processors, and only with the guardian answer
    /// when her age range asks for one.
    var hasAIConsent: Bool {
        guard allowsCloudAI, let consentRecord,
              consentRecord.isValid(currentVersion: config.consentVersion,
                                    currentProcessors: config.consentProcessors.map(\.name)) else { return false }
        return !ageDefaults.requiresGuardianStep || consentRecord.guardianConfirmed
    }

    /// Settings: switching it off withdraws consent. Switching it on goes
    /// through the consent sheet (`grantAIConsent`).
    func withdrawAIConsent() {
        saveConsent(nil)
    }

    /// "Allow AI processing" in the consent sheet: records what it showed.
    func grantAIConsent(guardianConfirmed: Bool) {
        saveConsent(AIConsentRecord(version: config.consentVersion, acceptedAt: Date(),
                                    processors: config.consentProcessors.map(\.name), guardianConfirmed: guardianConfirmed))
    }

    private func saveConsent(_ record: AIConsentRecord?) {
        consentRecord = record
        if let record, let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: Keys.consent)
        } else {
            defaults.removeObject(forKey: Keys.consent)
        }
    }

    // MARK: Paywall

    /// `proTry`: a Pro look or style she may try once for an ad instead,
    /// and how to go on with it.
    func presentPaywall(source: String, proTry: ProTryRequest? = nil) {
        // Never under 13; for teens, never by itself after onboarding.
        guard allowsPurchases, source != "onboarding" || ageDefaults.autoPaywall else { return }
        lastInterruption = Date() // never ask for a rating right after a paywall
        paywallShownThisSession = true
        paywallSource = source
        pendingProTry = proTry
        isPaywallPresented = true
    }

    /// She has a try of `item` (an ad just paid for it, or one was waiting):
    /// the paywall closes and what opened it goes on, through the usual
    /// gates; the server spends the try with the job it admits.
    func startProTry(_ item: ProTryItem) {
        guard isPaywallPresented, let pending = pendingProTry, pending.item == item else {
            // The paywall closed while Google confirmed the ad: the try waits for her.
            showToast("Your Pro try is ready ✨ Tap it again to start.", style: .success)
            return
        }
        pendingProTry = nil
        proTryResume = pending.resume
        isPaywallPresented = false
    }

    // MARK: Gates

    /// Runs `action` only when the user may perform `operation`:
    /// Pro-only content → paywall, cloud processing → consent, no credits → paywall.
    /// `proSource` tells the paywall what was Pro (`template_<id>`,
    /// `style_<id>`, `create_count`), so it can say why it opened.
    func requestAccess(
        for operation: AIOperation,
        outputs: Int = 1,
        requiresPro: Bool = false,
        proSource: String = "pro_content",
        then action: @escaping () -> Void
    ) {
        if !operation.runsOnDevice && !allowsCloudAI {
            noteUnavailable()
            return
        }
        if !operation.runsOnDevice && isCloudOffline {
            handle(AIServiceError.offline)
            return
        }
        if !operation.runsOnDevice, let cloudPause, cloudPause.isActive() {
            Haptics.error()
            explain(cloudPause)
            return
        }
        if requiresPro && !purchases.isPro {
            // One Pro look or style, one image: a try she watched an ad for
            // lets it through, and the server spends it on this job.
            let item = outputs == 1 ? ProTryItem(paywallSource: proSource) : nil
            if let item, ads.hasActiveTry(for: item) {
                // On to consent and credits as usual.
            } else {
                presentPaywall(source: proSource, proTry: item.map { item in
                    ProTryRequest(item: item) { [weak self] in
                        self?.requestAccess(for: operation, outputs: outputs, requiresPro: requiresPro, proSource: proSource, then: action)
                    }
                })
                return
            }
        }
        if !operation.runsOnDevice && !hasAIConsent {
            // The sheet records consent (with the guardian answer) before this runs.
            consentRequest = ConsentRequest { [weak self] in
                self?.requestAccess(for: operation, outputs: outputs, requiresPro: requiresPro, proSource: proSource, then: action)
            }
            return
        }
        credits.refresh(isPro: purchases.isPro, isTrial: purchases.trial != nil)
        guard credits.canAfford(operation, outputs: outputs) else {
            if purchases.isPro {
                outOfCredits = OutOfCreditsRequest(needed: credits.cost(of: operation, outputs: outputs), available: credits.balance)
            } else {
                presentPaywall(source: "out_of_credits")
            }
            return
        }
        action()
    }

    // MARK: Running jobs

    /// Spends credits optimistically, runs the job and refunds on failure.
    /// Cloud jobs show a Live Activity and keep running briefly in the
    /// background, so people can switch apps while they wait.
    func run(_ job: AIJob, saveToLibrary: Bool) async throws -> AIJobResult {
        let isCloud = !job.operation.runsOnDevice
        // Also covers the free retry, which skips `requestAccess`.
        if isCloud && isCloudOffline { throw AIServiceError.offline }
        let showsActivity = isCloud && liveActivity.start(
            // Catalog text only: her prompt would show on the Lock Screen.
            title: job.activityTitle.shortened(to: 34),
            symbolName: job.activitySymbol,
            expectedSeconds: GlowActivityController.expectedSeconds(for: job.operation, outputs: job.numOutputs)
        )
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "glowlit.job")
        defer {
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
            syncWidgets()
            syncReminders()
        }
        do {
            let result = try await perform(job, saveToLibrary: saveToLibrary)
            if isCloud { finishCloudJob(success: true, operation: job.operation, showsActivity: showsActivity) }
            return result
        } catch {
            if Self.isCancellation(error) {
                if showsActivity { liveActivity.cancel() }
            } else if isCloud {
                finishCloudJob(success: false, operation: job.operation, showsActivity: showsActivity)
            }
            throw error
        }
    }

    /// The Live Activity shows the outcome; without one (switched off in
    /// Settings, say) a notification does, if she opted in.
    private func finishCloudJob(success: Bool, operation: AIOperation, showsActivity: Bool) {
        let inBackground = UIApplication.shared.applicationState != .active
        if showsActivity {
            liveActivity.finish(success: success, lingers: inBackground)
        } else {
            notifier.notifyJobFinished(success: success, isCreate: operation == .textToImage)
        }
    }

    private func perform(_ job: AIJob, saveToLibrary: Bool) async throws -> AIJobResult {
        let verdict = ContentPolicy.evaluate(
            [job.prompt, job.template?.prompt].compactMap { $0 }.joined(separator: " "),
            operation: job.operation
        )
        if case .blocked(let reason, _) = verdict {
            throw AIServiceError.contentBlocked(reason)
        }

        // A free "Doesn't look like you?" retry costs nothing (the server
        // verifies `retry_of` in production).
        let cost = job.retryOf == nil ? credits.cost(of: job.operation, outputs: job.numOutputs) : 0
        let charge = try credits.charge(cost)
        // A free member's Pro look or style rides on a try she watched an ad for.
        let proTry = purchases.isPro ? nil : job.proTryItem
        do {
            let result = try await ai.perform(job)
            if let proTry { ads.noteTrySpent(proTry) }
            if let remaining = result.creditsRemaining {
                credits.sync(serverBalance: remaining)
            }
            if saveToLibrary {
                await self.saveToLibrary(result.images, operation: job.operation, title: job.title, prompt: job.prompt)
            }
            Haptics.success()
            return result
        } catch {
            // Fair-Price Promise: failed or blocked generations are never charged.
            credits.refund(charge)
            if case AIServiceError.insufficientCredits(let remaining) = error, let remaining {
                credits.sync(serverBalance: remaining)
            }
            // The try ended (or was used) before the server took the job:
            // nothing was booked. A refunded job gives a try back by itself.
            if let proTry, case AIServiceError.server(code: "pro_required", _) = error {
                ads.forgetTry(proTry)
                throw AIServiceError.server(code: "pro_try_ended", message: "")
            }
            throw error
        }
    }

    /// Adds images to the library (SwiftData metadata + files on disk).
    /// `operation == nil` marks a manually adjusted photo (no AI claim).
    func saveToLibrary(_ images: [UIImage], operation: AIOperation?, title: String, prompt: String?, source: String? = nil,
                       inheritedSourceType: DigitalSourceType? = nil) async {
        let context = container.mainContext
        let tag = ImageStore.Tag(operation: operation, source: source, inheritedSourceType: inheritedSourceType)
        var saved: [UIImage] = []
        for image in images {
            let stored = await Task.detached(priority: .utility) { () -> Result<(String, PixelSize), Error> in
                Result { (try ImageStore.save(image, tag: tag), ImageUtilities.pixelSize(of: image)) }
            }.value
            switch stored {
            case .success(let (name, size)):
                context.insert(Creation(
                    operation: operation,
                    title: title,
                    prompt: prompt,
                    imageFileName: name,
                    pixelWidth: size.width,
                    pixelHeight: size.height,
                    source: source,
                    inheritedSourceType: inheritedSourceType
                ))
                saved.append(image)
            case .failure:
                if isDeviceLocked {
                    deferredSaves.append(DeferredSave(image: image, operation: operation, title: title, prompt: prompt,
                                                      source: source, inheritedSourceType: inheritedSourceType))
                    watchForUnlock()
                } else {
                    showToast("Couldn't save to My Works", style: .error)
                }
            }
        }
        guard !saved.isEmpty else { return }
        try? context.save()
        if let newest = saved.last {
            GlowWidgetBridge.updateLatestImage(newest)
        }
        syncWidgets()
    }

    /// Kept in memory only: if the app is closed while locked, it's lost,
    /// which is why files are written "unless open" in the first place.
    private struct DeferredSave {
        let image: UIImage
        let operation: AIOperation?
        let title: String
        let prompt: String?
        let source: String?
        let inheritedSourceType: DigitalSourceType?
    }

    private var isDeviceLocked: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        !UIApplication.shared.isProtectedDataAvailable
        #endif
    }

    private func watchForUnlock() {
        guard unlockWatcher == nil else { return }
        unlockWatcher = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.protectedDataDidBecomeAvailableNotification) {
                guard let self else { return }
                await self.retryDeferredSaves()
                if self.deferredSaves.isEmpty { break }
            }
            self?.unlockWatcher = nil
        }
    }

    private func retryDeferredSaves() async {
        let pending = deferredSaves
        deferredSaves = []
        let before = (try? container.mainContext.fetchCount(FetchDescriptor<Creation>())) ?? 0
        for item in pending {
            await saveToLibrary([item.image], operation: item.operation, title: item.title, prompt: item.prompt,
                                source: item.source, inheritedSourceType: item.inheritedSourceType)
        }
        let after = (try? container.mainContext.fetchCount(FetchDescriptor<Creation>())) ?? 0
        // A failure already showed "Couldn't save to My Works".
        if after > before, deferredSaves.isEmpty {
            showToast("Saved to My Works", style: .success)
        }
    }

    /// Writes credits and the newest creation for the Home Screen widgets.
    func syncWidgets() {
        let context = container.mainContext
        // Creations in Recently deleted are gone as far as the widgets know.
        let kept = #Predicate<Creation> { $0.deletedAt == nil }
        var newest = FetchDescriptor<Creation>(predicate: kept, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        newest.fetchLimit = 1
        let count = (try? context.fetchCount(FetchDescriptor<Creation>(predicate: kept))) ?? 0
        if count == 0 { GlowWidgetBridge.updateLatestImage(nil) }
        GlowWidgetBridge.update(
            credits: credits.balance,
            isPro: purchases.isPro,
            nextRefill: credits.nextFreeRefill,
            latest: (try? context.fetch(newest))?.first,
            creationsCount: count,
            breakdown: credits.breakdown,
            nextGrant: credits.nextSubscriptionGrant,
            cloudAIAllowed: allowsCloudAI,
            allowance: purchases.isPro ? credits.policy.proMonthlyAllowance : credits.policy.freeDailyAllowance
        )
    }

    /// The file of the newest creation that isn't in Recently deleted.
    func newestCreationFile() -> String? {
        var newest = FetchDescriptor<Creation>(predicate: #Predicate { $0.deletedAt == nil },
                                               sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        newest.fetchLimit = 1
        return (try? container.mainContext.fetch(newest))?.first?.imageFileName
    }

    /// After My Works changed without a new result (deleted, restored,
    /// duplicated): the widgets get the counts and, when the newest creation
    /// changed, its picture, made off the main thread.
    func libraryDidChange(newestBefore: String?) {
        syncWidgets()
        let newest = newestCreationFile()
        guard newest != newestBefore else { return }
        widgetImageTask?.cancel()
        widgetImageTask = Task.detached(priority: .utility) {
            let image = newest.flatMap { ImageStore.downsampled($0, maxPixel: 600) }
            guard !Task.isCancelled else { return }
            GlowWidgetBridge.updateLatestImage(image)
        }
    }

    func deleteAllCreations() {
        let context = container.mainContext
        // Every row, Recently deleted included.
        try? context.delete(model: Creation.self)
        try? context.save()
        ImageStore.deleteAll()
        widgetImageTask?.cancel()
        GlowWidgetBridge.updateLatestImage(nil)
        syncWidgets()
    }

    // MARK: Ratings, the invite card and reminders

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// A finished save or share (the editor, Create, the collage maker, the
    /// video editor, the share composer, Retro Cam, My Works). It counts toward
    /// the rating request and the invite card; at the next natural break one of
    /// them may follow, or an ad (`allowsAd`: only after the saves and shares
    /// listed for interstitials), never more than one.
    func noteFinishedExport(allowsAd: Bool = true) {
        reviewPolicy.recordExport()
        invitePacing.noteExport()
        persistEngagement()
        if allowsAd { ads.noteFinishedExport() }
        lastExport = Date()
        // After the success toast has had its moment, a little before an ad would.
        scheduleAsk(after: 1.5)
    }

    /// A screen closed (the editor, video editor, collage maker, Retro Cam,
    /// share composer): if a save just happened there, this is its break.
    func naturalBreak() {
        if lastExport != nil { scheduleAsk(after: 0.6) }
        ads.naturalBreak()
    }

    /// A failed job, a report or a "doesn't look like you" retry: no rating
    /// request or invite card for a few days.
    func registerSetback() {
        reviewPolicy.recordSetback(at: Date())
        persistEngagement()
    }

    /// The card's "Invite a friend": the invite opens, and the card's job is done.
    func openInviteFromCard() {
        invitePacing.retire()
        persistEngagement()
        hideInviteCard()
        isInvitePresented = true
    }

    /// The card's close button, or "Don't show again" (`forGood`).
    func dismissInviteCard(forGood: Bool) {
        if forGood {
            invitePacing.retire()
            persistEngagement()
        }
        hideInviteCard()
    }

    private func hideInviteCard() {
        withAnimation(Motion.appear) { isInviteCardVisible = false }
    }

    private func scheduleAsk(after seconds: Double) {
        askTask?.cancel()
        askTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.askIfDue()
        }
    }

    /// The rating request or the invite card, if one is due, at a natural
    /// break: nothing else on screen (no sheet, cover, picker, tour or
    /// splash), and the app in front. Still in the editor: it waits for it to
    /// close; three minutes later the moment has passed.
    private func askIfDue() {
        guard let exportedAt = lastExport else { return }
        let now = Date()
        guard now.timeIntervalSince(exportedAt) < 180 else {
            lastExport = nil
            return
        }
        guard acceptsCommands, tour.hasSeen, !isSettingsPresented, !isLaunchSplashVisible, !isInviteCardVisible,
              !UIApplication.shared.isPresentingAnything, UIApplication.shared.applicationState == .active else { return }
        lastExport = nil
        #if DEBUG
        if ScreenshotScene.current != nil { return }
        #endif
        let interrupted = lastInterruption.map { now.timeIntervalSince($0) < 1800 } ?? false
        if !interrupted, reviewPolicy.shouldPrompt(now: now, appVersion: Self.appVersion, isFirstSession: sessions.isFirstSession) {
            reviewPolicy.notePrompted(at: now, appVersion: Self.appVersion)
            persistEngagement()
            ads.yieldBreak()
            reviewRequests += 1
        } else if invitePacing.isDue(at: now, isFirstSession: sessions.isFirstSession, lastSetback: reviewPolicy.lastSetback) {
            invitePacing.noteShown(at: now)
            persistEngagement()
            ads.yieldBreak()
            withAnimation(Motion.appear) { isInviteCardVisible = true }
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Loving \(Brand.name)?"))
        }
    }

    private func persistEngagement() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(reviewPolicy) { defaults.set(data, forKey: Keys.reviewPolicy) }
        if let data = try? encoder.encode(invitePacing) { defaults.set(data, forKey: Keys.invitePacing) }
        if let data = try? encoder.encode(sessions) { defaults.set(data, forKey: Keys.sessions) }
    }

    /// Reschedules the opt-in reminders for the current credits.
    func syncReminders() {
        Task {
            await notifier.reschedule(
                credits: credits.balance,
                isPro: purchases.isPro,
                nextRefill: credits.nextFreeRefill,
                dailyCredits: credits.policy.freeDailyAllowance,
                cloudAIAllowed: allowsCloudAI
            )
            await notifier.syncPollReminders(live: offersPolls ? polls.shelf.live(at: Date()) : [])
        }
    }

    // MARK: Editor routing

    func startEditing(tool: EditorTool? = nil, template: PhotoTemplate? = nil) {
        let template = allowsCloudAI ? template : nil
        let tool = permittedTool(tool)
        if let template, template.isPro, !purchases.isPro, !ads.hasActiveTry(for: .template(template.id)) {
            // With a try, the photo picker opens next and the editor runs the look.
            presentPaywall(source: "template_\(template.id)", proTry: ProTryRequest(item: .template(template.id)) { [weak self] in
                self?.startEditing(tool: tool, template: template)
            })
            return
        }
        pendingEditorRequest = EditorRequest(tool: tool, template: template)
        isPhotoPickerPresented = true
    }

    func openEditor(with image: UIImage, tool: EditorTool? = nil, template: PhotoTemplate? = nil, provenance: Provenance = .none,
                    previewEffect: RetroEffect? = nil) {
        editorLaunch = EditorLaunch(image: ImageUtilities.normalized(image), tool: permittedTool(tool),
                                    template: allowsCloudAI ? template : nil, previewEffect: previewEffect, provenance: provenance)
    }

    /// Copies a picked video to a temporary file and opens the video editor.
    func handlePickedVideo(_ item: PhotosPickerItem) async {
        do {
            guard let file = try await item.loadTransferable(type: VideoFile.self) else {
                throw AIServiceError.invalidRequest(String(localized: "Couldn't open that video."))
            }
            // Let the picker finish dismissing first, so the editor is laid out
            // inside the screen's safe area.
            try? await Task.sleep(for: .milliseconds(450))
            videoSource = VideoSource(url: file.url)
        } catch {
            showToast("Couldn't open that video. Try another one.", style: .error)
        }
    }

    func handlePickedPhoto(_ item: PhotosPickerItem) async {
        let request = pendingEditorRequest ?? EditorRequest()
        pendingEditorRequest = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw AIServiceError.invalidRequest(String(localized: "Couldn't open that photo."))
            }
            try await openPhoto(data, request: request)
        } catch {
            showToast("Couldn't open that photo. Try another one.", style: .error)
        }
    }

    /// A photo file dropped on the window (Mac): opens in Magic Edit, like a
    /// photo picked from Explore's hero card.
    func openDroppedPhoto(_ data: Data) async {
        guard acceptsCommands else { return }
        do {
            try await openPhoto(data, request: EditorRequest(tool: .magicEdit))
        } catch {
            showToast("Couldn't open that photo. Try another one.", style: .error)
        }
    }

    private func openPhoto(_ data: Data, request: EditorRequest) async throws {
        guard let (image, isRAW, sourceType) = await PhotoDecoder.decode(data) else {
            throw AIServiceError.invalidRequest(String(localized: "That file isn't a supported photo."))
        }
        editorLaunch = EditorLaunch(image: image, tool: permittedTool(request.tool), template: allowsCloudAI ? request.template : nil,
                                    provenance: Provenance(inheritedSourceType: sourceType))
        if isRAW {
            showToast("RAW photo developed with the best settings ✨", style: .success)
        }
    }

    // MARK: Deep links (widgets, controls, Live Activities, Siri and Shortcuts)

    func handle(_ link: GlowDeepLink) {
        // A link (a widget, a notification, Siri) goes straight where it points.
        endLaunchSplash()
        guard hasCompletedOnboarding, !needsAgeStep, !isFullScreenCoverPresented else { return }
        isPaywallPresented = false
        outOfCredits = nil
        if !allowsCloudAI {
            switch link {
            case .magicEdit:
                selectedTab = .edit
                startEditing(tool: .effects)
                return
            case .template, .create:
                selectedTab = .edit
                return
            default:
                break
            }
        }
        switch link {
        case .magicEdit:
            selectedTab = .home
            startEditing(tool: .magicEdit)
        case .removeBackground:
            selectedTab = .edit
            startEditing(tool: .removeBackground)
        case .template(let id):
            selectedTab = .home
            startEditing(tool: .styles, template: TemplateCatalog.template(id: id))
        case .create:
            selectedTab = .create
        case .effects:
            selectedTab = .edit
            startEditing(tool: .effects)
        case .video:
            selectedTab = .edit
            isVideoPickerPresented = true
        case .library:
            selectedTab = .library
        case .retroCam, .photoBooth:
            // A Mac without a camera has no Retro Cam.
            guard RetroCam.isAvailable else {
                noteUnavailable()
                return
            }
            selectedTab = .edit
            retroCamStartsInBooth = link == .photoBooth
            isRetroCamPresented = true
        case .collage:
            selectedTab = .edit
            isCollagePresented = true
        case .poll(let id):
            // Never under 13, and only her own polls.
            guard offersPolls else { return }
            selectedTab = .library
            // One sheet at a time: the link takes the place of what was open.
            shareRequest = nil
            pollDraft = nil
            Task { await openPoll(id) }
        }
    }

    // MARK: Sharing

    func share(_ payload: SharePayload) {
        shareRequest = payload
    }

    /// The collage maker with these pictures, in this order, instead of the
    /// photo picker. They're encoded like exports, so each keeps its marking.
    func openCollage(with files: [Data]) {
        collageStartFiles = files
        isCollagePresented = true
    }

    /// What `openCollage(with:)` sent, handed over once.
    func takeCollageStartFiles() -> [Data] {
        defer { collageStartFiles = [] }
        return collageStartFiles
    }

    // MARK: Feedback

    func showToast(_ text: LocalizedStringResource, style: ToastMessage.Style = .info) {
        toast = ToastMessage(text: String(localized: text), style: style)
    }

    /// For text that's already localized (or comes from the server).
    func showToast(verbatim text: String, style: ToastMessage.Style = .info) {
        toast = ToastMessage(text: text, style: style)
    }

    /// Maps any error to a friendly toast, opening the paywall when relevant.
    static func isCancellation(_ error: Error) -> Bool {
        if case StoreKitError.userCancelled = error { return true }
        return error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    /// Saving to Photos without access: an alert that can open Settings, and
    /// share the image instead when the caller has it at hand.
    func handleSaveError(_ error: Error, shareInstead: SharePayload?) {
        handleSaveError(error, onShareInstead: shareInstead.map { payload in { [weak self] in self?.share(payload) } })
    }

    /// The same for things that aren't an image, like a video export.
    func handleSaveError(_ error: Error, onShareInstead: (() -> Void)?) {
        if case PhotoLibrarySaver.SaveError.denied = error {
            Haptics.error()
            photosAccessRequest = PhotosAccessRequest(shareInstead: onShareInstead)
            return
        }
        handle(error)
    }

    func handle(_ error: Error) {
        if Self.isCancellation(error) { return }
        if case PhotoLibrarySaver.SaveError.denied = error {
            handleSaveError(error, shareInstead: nil)
            return
        }
        Haptics.error()
        // Only a job that failed is a setback: a rest, a limit or a consent prompt isn't.
        if Self.isFailedJob(error) { registerSetback() }
        // Resting or off: say so kindly; never the paywall.
        if case AIServiceError.cooldown(let retryAfter) = error {
            let pause = CloudPause.cooldown(until: Date().addingTimeInterval(retryAfter ?? 24 * 3600))
            cloudPause = pause
            explain(pause)
            return
        }
        if case AIServiceError.cloudBlocked = error {
            cloudPause = .blocked
            explain(.blocked)
            return
        }
        if case AIServiceError.insufficientCredits(let remaining) = error {
            if purchases.isPro {
                outOfCredits = OutOfCreditsRequest(available: remaining)
            } else {
                presentPaywall(source: "out_of_credits")
            }
            return
        }
        if case CreditError.insufficient(let needed, let available) = error {
            if purchases.isPro {
                outOfCredits = OutOfCreditsRequest(needed: needed, available: available)
            } else {
                presentPaywall(source: "out_of_credits")
            }
            return
        }
        if case AIServiceError.consentRequired = error {
            if allowsCloudAI { consentRequest = ConsentRequest {} }
            return
        }
        if case AIServiceError.aiPaused = error {
            // Resting for everyone? Then no ad for a credit, and the paywall says so.
            Task { await refreshAIServicePause(force: true) }
        }
        showToast(verbatim: Self.localizedMessage(for: error), style: .error)
    }

    /// A job the server ran and failed (its error code, or the content check on it).
    private static func isFailedJob(_ error: Error) -> Bool {
        if case AIServiceError.server = error { return true }
        if case AIServiceError.contentBlocked = error { return true }
        return false
    }

    /// Why cloud AI isn't available right now, never as blame (the members
    /// are teens), with the free tools that still work.
    func explain(_ pause: CloudPause) {
        showToast(verbatim: message(for: pause), style: .info)
    }

    func message(for pause: CloudPause) -> String {
        switch pause {
        case .cooldown(let until):
            let time = until.formatted(date: Calendar.current.isDateInToday(until) ? .omitted : .abbreviated,
                                       time: .shortened)
            return String(localized: "Cloud AI is taking a little break until \(time). Effects, Retro Cam, Cut out and your other free tools still work.")
        case .blocked:
            return String(localized: "Cloud AI is turned off here for now. Effects, Retro Cam, Cut out and your other free tools still work. If you think this is a mistake, write to us at \(config.supportEmail).")
        }
    }

    /// One honest line where credits are explained or sold while the server
    /// rests AI: what rests, and that what she buys waits for her. Never a
    /// date: the owner can end a pause sooner.
    func message(for pause: AIServicePause) -> String {
        pause.freeOnly
            ? String(localized: "Free AI credits are taking a short break. Your free tools still work.",
                     comment: "Note on the paywall and the credits sheet while the server pauses AI on free daily credits")
            : String(localized: "AI is taking a short break. Credits you buy stay safe until it's back.",
                     comment: "Note on the paywall, the credits sheet and the credit packs while the server pauses all cloud AI")
    }

    /// The user's language for any error: known server codes get their own
    /// sentence, AppCore's English messages are looked up in the catalog.
    static func localizedMessage(for error: Error) -> String {
        if case AIServiceError.server(let code, let message) = error {
            return serverMessages[code] ?? L10n.core(message)
        }
        if let message = storeMessage(for: error) {
            return message
        }
        if let text = (error as? LocalizedError)?.errorDescription {
            return L10n.core(text)
        }
        return String(localized: "Something went wrong. Please try again.")
    }

    /// StoreKit's own texts would otherwise pass through untranslated.
    private static func storeMessage(for error: Error) -> String? {
        if let error = error as? StoreKitError {
            switch error {
            case .networkError:
                return String(localized: "Couldn't reach the App Store. Check your connection.")
            case .notAvailableInStorefront:
                return String(localized: "This purchase isn't available in your country or region.")
            default:
                return nil
            }
        }
        if let error = error as? Product.PurchaseError {
            switch error {
            case .purchaseNotAllowed:
                return String(localized: "Purchases are turned off on this device.")
            case .productUnavailable:
                return String(localized: "This purchase isn't available right now.")
            default:
                return nil
            }
        }
        return nil
    }

    private static let serverMessages: [String: String] = [
        "provider_unavailable": String(localized: "The AI service is busy. Your credit was refunded."),
        "provider_busy": String(localized: "The AI service is busy. Your credit was refunded. Please try again in a minute."),
        "provider_failed": String(localized: "This creation failed. Your credit was refunded."),
        "job_failed": String(localized: "This creation failed. Your credit was refunded."),
        "empty_result": String(localized: "The AI returned no image. Your credit was refunded."),
        "timeout": String(localized: "This took too long. Your credit was refunded."),
        // The app stopped waiting through a lost connection; the server refunds a
        // result that never reached the app, so nothing more is promised.
        "result_not_received": String(localized: "The connection dropped before your result arrived. If it never reaches you, your credit comes back automatically within about an hour."),
        "rate_limited": String(localized: "Too many requests. Please wait a moment."),
        "pro_required": String(localized: "This is part of Pro."),
        "pro_try_ended": String(localized: "Your Pro try ended before this could start, so no credit was used."),
        "retry_unavailable": String(localized: "This result can't be retried for free anymore."),
        "too_large": String(localized: "That photo is too large. Try a smaller one."),
        "image_invalid": String(localized: "This photo couldn't be read. Try another one."),
        "prompt_too_long": String(localized: "That's a long description. Try a shorter one."),
        // The optional photo check (XAI_SAFETY_MODEL on the server). When it
        // can't run, nothing has been made yet, so it isn't the output check's sentence.
        "input_blocked": String(localized: "This photo can't be edited. Try another one. Your credit was refunded."),
        "photo_check_failed": String(localized: "We couldn't check this photo just now, so nothing was made and no credit was used. Try again in a moment."),
        "content_blocked": String(localized: "This was blocked by our safety filters. Your credit was refunded."),
        // The output check fails closed: no verdict, no result.
        "safety_check_failed": String(localized: "Our safety check couldn't run, so this result wasn't shown. Your credit was refunded."),
        "misconfigured": String(localized: "AI features aren't configured yet."),
        "internal": String(localized: "Something went wrong. Please try again."),
    ]
}

#if DEBUG
extension AppModel {
    /// Puts the app into a deterministic state for screenshots (DEBUG only).
    func applyScreenshotScene(_ scene: ScreenshotScene) {
        credits.resetForScreenshots()
        // `-GLPollsFixture live|results|ended|takendown|empty|limit|blocked`
        // with any scene: her polls without the server (My Works' row too).
        if let fixture = UserDefaults.standard.string(forKey: "GLPollsFixture") ?? (scene == .polls ? "results" : nil) {
            polls.seedFixture(fixture, pictures: [ScreenshotFixtures.portraitPinkHair, ScreenshotFixtures.portraitSoftGlam,
                                                  ScreenshotFixtures.beachPhoto, ScreenshotFixtures.goldenLandscape,
                                                  ScreenshotFixtures.editorPhoto, ScreenshotFixtures.overcastLandscape])
        }
        hasCompletedOnboarding = scene != .onboarding
        consentRecord = scene == .consent ? nil : AIConsentRecord(
            version: config.consentVersion, acceptedAt: Date(),
            processors: config.consentProcessors.map(\.name), guardianConfirmed: true
        )
        if scene == .age {
            ageRecord = nil
        } else if ageRecord == nil {
            ageRecord = AgeRecord(band: .adult, source: .apple, setAt: Date())
        }
        switch scene {
        case .onboarding, .home, .settings, .legal, .invite, .tour, .collection, .feelGood, .age, .tips:
            selectedTab = .home
        case .bestShot:
            selectedTab = .home
            isBestShotPresented = true
        case .collage:
            selectedTab = .home
            isCollagePresented = true
        case .effects:
            selectedTab = .home
            // `-GLEffectsPhoto <sample>` picks another sample photo.
            let photo = UserDefaults.standard.string(forKey: "GLEffectsPhoto").flatMap(ScreenshotFixtures.sample)
            editorLaunch = EditorLaunch(image: photo ?? ScreenshotFixtures.effectsPhoto, tool: .effects,
                                        previewEffect: UserDefaults.standard.string(forKey: "GLEffect").flatMap(RetroEffect.init(rawValue:)) ?? .vhs)
        case .ideas:
            selectedTab = .home
            editorLaunch = EditorLaunch(image: ScreenshotFixtures.overcastLandscape, tool: .magicEdit)
        case .crop:
            selectedTab = .home
            editorLaunch = EditorLaunch(image: ScreenshotFixtures.beachPhoto, tool: .crop, cropAspect: .story, cropAngle: 4)
        case .hideFaces:
            selectedTab = .home
            editorLaunch = EditorLaunch(image: ScreenshotFixtures.groupPhoto, tool: .hideFaces)
        case .cutout:
            selectedTab = .home
            // `-GLCutoutPhoto <sample>`: a sample photo (with `-GLVisionFixtures`) instead of the cartoon.
            let photo = UserDefaults.standard.string(forKey: "GLCutoutPhoto").flatMap(ScreenshotFixtures.sample)
            editorLaunch = EditorLaunch(image: photo ?? ScreenshotFixtures.cutoutPhoto, tool: .removeBackground)
        case .erase:
            selectedTab = .home
            // `-GLErasePhoto <sample>` erases on a sample photo instead.
            let photo = UserDefaults.standard.string(forKey: "GLErasePhoto").flatMap(ScreenshotFixtures.sample)
            editorLaunch = EditorLaunch(image: photo ?? ScreenshotFixtures.goldenLandscape, tool: .erase)
        case .textStickers:
            selectedTab = .home
            editorLaunch = EditorLaunch(image: ScreenshotFixtures.beachPhoto, tool: .textStickers)
        case .video:
            selectedTab = .home
            let defaults = UserDefaults.standard
            let seconds = defaults.double(forKey: "GLVideoSeconds")
            Task {
                if let url = try? await ScreenshotFixtures.sampleVideo(seconds: seconds > 0 ? seconds : 8,
                                                                       broken: defaults.bool(forKey: "GLVideoBroken")) {
                    videoSource = VideoSource(url: url)
                }
            }
        case .create, .results:
            selectedTab = .create
        case .recentPrompts:
            selectedTab = .create
            if !UserDefaults.standard.bool(forKey: "GLKeepPrompts") {
                prompts.seedForScreenshots(ScreenshotFixtures.recentPrompts)
            }
        case .edit:
            selectedTab = .edit
        case .camera:
            selectedTab = .home
            isRetroCamPresented = true
        case .library, .librarySelect, .libraryTrash:
            selectedTab = .library
            seedScreenshotLibrary(trash: scene == .libraryTrash)
        case .polls:
            selectedTab = .library
            seedScreenshotLibrary()
            // `-GLPollsCreate explainer|form|send|ready` (and the `limit` and
            // `blocked` fixtures) show Ask friends instead of Your polls.
            let create = UserDefaults.standard.string(forKey: "GLPollsCreate")
            if create != nil || PollsModel.fixtureError(polls.fixture ?? "") != nil {
                polls.hasSeenExplainer = create != "explainer"
                // Two looks from one photo, as the share composer's "Which vibe?" pairs them.
                pollDraft = PollDraft(a: ScreenshotFixtures.portraitPinkHair, b: ScreenshotFixtures.portraitSoftGlam,
                                      provenanceA: Provenance(operation: .magicEdit), provenanceB: Provenance(operation: .magicEdit))
            } else {
                pollsSheet = PollsSheetRequest()
            }
        case .editor:
            selectedTab = .home
            // `-GLEditorTool <tool>` opens another tool's panel (layout QA).
            let tool = UserDefaults.standard.string(forKey: "GLEditorTool").flatMap(EditorTool.init(rawValue:)) ?? .magicEdit
            editorLaunch = EditorLaunch(image: tool == .makeup ? ScreenshotFixtures.portraitBefore : ScreenshotFixtures.editorPhoto,
                                        tool: tool,
                                        prompt: tool == .magicEdit ? String(localized: "Golden hour light") : nil)
        case .result:
            selectedTab = .home
            // `-GLResultLook makeup`: Makeup Studio's Soft Glam instead of
            // Magic Edit's pink hair.
            if UserDefaults.standard.string(forKey: "GLResultLook") == "makeup" {
                editorLaunch = EditorLaunch(image: ScreenshotFixtures.portraitBefore, tool: .makeup,
                                            previewResult: ScreenshotFixtures.portraitSoftGlam)
            } else {
                editorLaunch = EditorLaunch(image: ScreenshotFixtures.portraitBefore, tool: .magicEdit,
                                            prompt: String(localized: "Give me pink hair"),
                                            previewResult: ScreenshotFixtures.portraitPinkHair)
            }
        case .paywall:
            selectedTab = .home
            // `-GLPaywallSource out_of_credits|template_<id>|style_<id>|create_count|share_watermark`
            // shows the line that says why it opened.
            paywallSource = UserDefaults.standard.string(forKey: "GLPaywallSource") ?? "screenshot"
            isPaywallPresented = true
        case .outOfCredits:
            selectedTab = .home
            outOfCredits = OutOfCreditsRequest(needed: 1, available: 0)
        case .outOfCreditsMulti:
            selectedTab = .create
            outOfCredits = OutOfCreditsRequest(needed: 4, available: 2)
        case .consent:
            selectedTab = .home
            consentRequest = ConsentRequest {}
        case .share where UserDefaults.standard.bool(forKey: "GLShareHideFaces"):
            // A group shared from My Works, with "Hide other faces" switched on.
            selectedTab = .home
            shareRequest = SharePayload(image: ScreenshotFixtures.groupPhoto, operation: nil, offersHidingFaces: true)
        case .share:
            selectedTab = .home
            shareRequest = SharePayload(
                image: ScreenshotFixtures.portraitPinkHair,
                original: ScreenshotFixtures.portraitBefore,
                // `-GLShareOnDevice YES`: an effects-only photo (no mark, no AI tags).
                operation: UserDefaults.standard.bool(forKey: "GLShareOnDevice") ? nil : .magicEdit,
                // A second look, so `-GLShareFormat pick` can show "Which vibe?".
                alternatives: ScreenshotFixtures.generatedArt(count: 1)
            )
        }
    }

    /// `trash`: four creations in Recently deleted (30, 19, 4 and 1 days
    /// left) and one past 30 days for the launch purge.
    private func seedScreenshotLibrary(trash: Bool = false) {
        // `-GLKeepLibrary YES`: show the library already on disk (migration QA).
        if UserDefaults.standard.bool(forKey: "GLKeepLibrary") { return }
        deleteAllCreations()
        let images = ScreenshotFixtures.samplePool.map { Array($0.prefix(trash ? 14 : 9)) }
            ?? [ScreenshotFixtures.goldenLandscape] + ScreenshotFixtures.generatedArt(count: trash ? 13 : 8)
        let context = container.mainContext
        let day: TimeInterval = 24 * 3600
        let deletedAgo: [Int: TimeInterval] = trash ? [9: 0.5 * day, 10: 11.5 * day, 11: 26.5 * day, 12: 29.5 * day, 13: 31 * day] : [:]
        for (index, image) in images.enumerated() {
            guard let name = try? ImageStore.save(image, tag: ImageStore.Tag(operation: index == 0 ? .magicEdit : .textToImage)) else { continue }
            let size = ImageUtilities.pixelSize(of: image)
            let creation = Creation(
                createdAt: Date().addingTimeInterval(TimeInterval(-index * 3600)),
                operation: index == 0 ? .magicEdit : .textToImage,
                title: index == 0 ? String(localized: "Golden hour light") : ScreenshotFixtures.createPrompt,
                prompt: nil,
                imageFileName: name,
                pixelWidth: size.width,
                pixelHeight: size.height
            )
            creation.deletedAt = deletedAgo[index].map { Date().addingTimeInterval(-$0) }
            context.insert(creation)
        }
        if UserDefaults.standard.bool(forKey: "GLLibraryMissing") {
            // A row whose file is gone, second in the grid.
            context.insert(Creation(createdAt: Date().addingTimeInterval(-1800), operation: .textToImage,
                                    title: ScreenshotFixtures.createPrompt, prompt: nil,
                                    imageFileName: "missing-\(UUID().uuidString).jpg", pixelWidth: 1024, pixelHeight: 1536))
        }
        try? context.save()
        GlowWidgetBridge.updateLatestImage(images.first)
        syncWidgets()
    }
}
#endif
