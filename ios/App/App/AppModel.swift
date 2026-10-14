import SwiftUI
import SwiftData
import PhotosUI
import Observation
import AuthenticationServices
import StoreKit
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
}

struct ConsentRequest: Identifiable {
    let id = UUID()
    let onAccept: () -> Void
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
    private(set) var hasAIConsent: Bool
    private(set) var interests: Set<String>
    var appearance: AppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    // MARK: Navigation
    var selectedTab: AppTab = .home
    /// Settings: the gear on Explore, or Glowlit › Settings… on the Mac.
    var isSettingsPresented = false
    var isPaywallPresented = false
    /// Pro without enough credits: next refill and packs (free members get the paywall).
    var outOfCredits: OutOfCreditsRequest?
    private(set) var paywallSource = "unknown"
    var isPhotoPickerPresented = false
    var editorLaunch: EditorLaunch?
    var consentRequest: ConsentRequest?
    var shareRequest: SharePayload?
    /// "Keep your glow on every iPhone": offered after a purchase.
    var isAccountPromptPresented = false
    /// "Find your best shot" (on-device selfie ranking).
    var isBestShotPresented = false
    /// The simple video editor: picker, then the editor itself.
    var isVideoPickerPresented = false
    var videoSource: VideoSource?
    var toast: ToastMessage?
    @ObservationIgnored private var pendingEditorRequest: EditorRequest?

    // MARK: Services
    let config: AppConfig
    let purchases: PurchaseManager
    let credits: CreditsManager
    let ai: AIImageService
    /// Present only when a backend is configured (production mode).
    private let remote: RemoteAIImageService?
    private let container: ModelContainer
    private let defaults: UserDefaults
    /// Dynamic Island / Lock Screen progress for cloud jobs.
    private let liveActivity = GlowActivityController()
    /// Opt-in local reminders (glow ready, credits back, the weekly look).
    let notifier = GlowNotifier()
    /// The first-run tour ("Next, Next…" through every tab).
    let tour = TourGuide()

    // MARK: Account (optional Sign in with Apple)
    /// Signed in with Apple: Pro and credits follow her to other iPhones.
    private(set) var isSignedIn = false
    /// The Apple ID email or its private relay address, if she shared it.
    private(set) var accountEmail: String?
    @ObservationIgnored private var reviewPolicy: ReviewPromptPolicy
    /// The last paywall or permission prompt; no rating prompt for 30 minutes after.
    @ObservationIgnored private var lastInterruption: Date?

    private enum Keys {
        static let onboarding = "onboarding.completed"
        static let consent = "ai.consent.v1"
        static let interests = "onboarding.interests"
        static let successfulSaves = "stats.successfulSaves"
        static let reviewPolicy = "review.policy.v1"
        static let appleUserID = "auth.appleUserID"
        static let appearance = "appearance"
    }

    init(container: ModelContainer, config: AppConfig = .current, defaults: UserDefaults = .standard) {
        self.container = container
        self.config = config
        self.defaults = defaults
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        self.hasAIConsent = defaults.bool(forKey: Keys.consent)
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

        let purchases = PurchaseManager()
        self.purchases = purchases
        self.credits = CreditsManager(isServerAuthoritative: config.backend != nil)

        switch config.aiMode {
        case .backend(let backend):
            let auth = AuthSessionManager(config: backend)
            let remote = RemoteAIImageService(config: backend, auth: auth) { [weak purchases] in
                purchases?.entitlementJWS
            }
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

        purchases.creditPackHandler = { [weak self] credits, signedTransaction in
            await self?.grantCreditPack(credits, signedTransaction: signedTransaction) ?? false
        }
        purchases.onProStatusChange = { [weak self] isPro in
            guard let self else { return }
            credits.refresh(isPro: isPro)
            syncWidgets()
            Task { await self.refreshServerBalance() }
        }
        purchases.onLatePurchase = { [weak self] purchase in self?.completeLatePurchase(purchase) }
        notifier.onOpenLink = { [weak self] link in self?.handle(link) }

        #if DEBUG
        if let scene = ScreenshotScene.current {
            applyScreenshotScene(scene)
        }
        #endif
    }

    var isDemoMode: Bool { config.isDemoMode }

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
            return "Demo mode — AI results are simulated on device. Add an AI key (see README → “Connect an AI provider”) to see real results."
        }
    }

    /// Called once from the root view's `.task`.
    func start() async {
        liveActivity.endLeftovers()
        // Subscription analytics (observer mode), keyed to our account id.
        RevenueCatBridge.configure(apiKey: config.revenueCatAPIKey, appUserID: await remote?.currentUserID()?.uuidString)
        await refreshAccount()
        watchAppleCredentialRevocation()
        await purchases.refreshEntitlements()
        credits.refresh(isPro: purchases.isPro)
        await refreshServerBalance()
        syncWidgets()
        syncReminders()
        await purchases.loadProducts()
    }

    /// Back in the foreground: notification permission may have changed.
    func becameActive() {
        syncReminders()
    }

    /// Adds a purchased pack: locally in demo mode, verified by the server in production.
    func grantCreditPack(_ credits: Int, signedTransaction: String) async -> Bool {
        guard let remote else {
            self.credits.addPurchased(credits)
            return true
        }
        do {
            let balance = try await remote.redeemCreditPack(signedTransaction: signedTransaction)
            self.credits.sync(serverBalance: balance)
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
        // Keep the paywall's "We'll remind you before your trial ends" promise.
        if let trialEnd = purchase.trialEndsAt,
           let price = purchases.products.first(where: { $0.id == purchase.productID })?.displayPrice {
            Task { await TrialReminder.schedule(billingDate: trialEnd, price: price, mayAsk: false) }
        }
    }

    /// Binds purchases to the backend user (StoreKit `appAccountToken`).
    func appAccountToken() async -> UUID? {
        await remote?.currentUserID()
    }

    /// "Report this image": sent to the backend for review; logged locally in
    /// demo and developer mode, where there is no server.
    func report(_ reason: ReportReason, requestID: String?) async {
        registerSetback()
        guard let remote else {
            showToast("Thanks — your report was noted.", style: .success)
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

    /// Settings › Delete my data: local library, server account and credits.
    func deleteAccountAndData() async {
        deleteAllCreations()
        if let remote {
            do {
                try await remote.deleteAccount()
            } catch {
                handle(error)
                return
            }
        }
        Keychain.delete(key: Keys.appleUserID)
        isSignedIn = false
        accountEmail = nil
        setAIConsent(false)
        TrialReminder.cancel()
        showToast("Your data has been deleted.", style: .success)
    }

    // MARK: Account

    /// Accounts live on the backend, so demo and developer modes can't offer them.
    var canUseAccounts: Bool { remote != nil }

    /// Reads the session, finishes a credit merge that failed earlier, and
    /// signs out if the Apple ID stopped using Glowlit.
    func refreshAccount() async {
        guard let remote else { return }
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
        Keychain.save(credential.user, key: Keys.appleUserID)
        await refreshAccount()
        if let userID = await remote.currentUserID() { await RevenueCatBridge.identify(userID.uuidString) }
        await purchases.refreshEntitlements()
        credits.refresh(isPro: purchases.isPro)
        await refreshServerBalance()
        syncWidgets()
        Haptics.success()
        showToast("You're signed in ✨ Pro and your credits now come with you.", style: .success)
    }

    /// Back to an anonymous session on this iPhone. Pro stays tied to the
    /// Apple Account that bought it.
    func signOut(quietly: Bool = false) async {
        await remote?.signOut()
        Keychain.delete(key: Keys.appleUserID)
        isSignedIn = false
        accountEmail = nil
        if let userID = await remote?.currentUserID() { await RevenueCatBridge.identify(userID.uuidString) }
        await refreshServerBalance()
        syncWidgets()
        if !quietly { showToast("Signed out. Sign in again anytime in Settings.", style: .info) }
    }

    /// After a purchase, offer (never require) an account, so the purchase
    /// isn't stuck on this iPhone.
    func offerAccountAfterPurchase() {
        guard canUseAccounts, !isSignedIn else { return }
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

    func refreshServerBalance() async {
        guard let remote, hasAIConsent else { return }
        if let balance = try? await remote.fetchBalance() {
            credits.sync(serverBalance: balance)
        }
    }

    // MARK: Onboarding & consent

    func completeOnboarding(interests: Set<String>) {
        self.interests = interests
        hasCompletedOnboarding = true
        defaults.set(Array(interests), forKey: Keys.interests)
        defaults.set(true, forKey: Keys.onboarding)
    }

    /// Shows the tour once, after onboarding, when nothing else is on screen.
    func offerTourIfNeeded() {
        #if DEBUG
        if let scene = ScreenshotScene.current {
            if scene == .tour { startTour() }
            return
        }
        #endif
        guard hasCompletedOnboarding, !tour.hasSeen, !tour.isRunning, !isPresentingSomething else { return }
        startTour()
    }

    func startTour() {
        selectedTab = TourStep.allCases.first?.tab ?? .home
        tour.start()
    }

    private var isPresentingSomething: Bool {
        isPaywallPresented || outOfCredits != nil || editorLaunch != nil || videoSource != nil || consentRequest != nil
            || shareRequest != nil || isAccountPromptPresented || isBestShotPresented
    }

    /// Mac menu commands and dropped photos only act on the main screens:
    /// never during onboarding or the tour, or over a sheet, a picker or the editor.
    var acceptsCommands: Bool {
        hasCompletedOnboarding && !tour.isRunning && !isPresentingSomething
            && !isSettingsPresented && !isPhotoPickerPresented && !isVideoPickerPresented
    }

    func setAIConsent(_ granted: Bool) {
        hasAIConsent = granted
        defaults.set(granted, forKey: Keys.consent)
    }

    // MARK: Paywall

    func presentPaywall(source: String) {
        lastInterruption = Date() // never ask for a rating right after a paywall
        paywallSource = source
        isPaywallPresented = true
    }

    // MARK: Gates

    /// Runs `action` only when the user may perform `operation`:
    /// Pro-only content → paywall, cloud processing → consent, no credits → paywall.
    func requestAccess(
        for operation: AIOperation,
        outputs: Int = 1,
        requiresPro: Bool = false,
        then action: @escaping () -> Void
    ) {
        if requiresPro && !purchases.isPro {
            presentPaywall(source: "pro_content")
            return
        }
        if !operation.runsOnDevice && !hasAIConsent {
            consentRequest = ConsentRequest { [weak self] in
                self?.setAIConsent(true)
                self?.requestAccess(for: operation, outputs: outputs, requiresPro: requiresPro, then: action)
            }
            return
        }
        credits.refresh(isPro: purchases.isPro)
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
        let showsActivity = isCloud && liveActivity.start(
            title: job.title.shortened(to: 34),
            symbolName: job.template?.symbolName ?? job.operation.symbolName,
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
            if isCloud { finishCloudJob(success: true, title: job.title, showsActivity: showsActivity) }
            return result
        } catch {
            if Self.isCancellation(error) {
                if showsActivity { liveActivity.cancel() }
            } else if isCloud {
                finishCloudJob(success: false, title: job.title, showsActivity: showsActivity)
            }
            throw error
        }
    }

    /// The Live Activity shows the outcome; without one (switched off in
    /// Settings, say) a notification does, if she opted in.
    private func finishCloudJob(success: Bool, title: String, showsActivity: Bool) {
        let inBackground = UIApplication.shared.applicationState != .active
        if showsActivity {
            liveActivity.finish(success: success, lingers: inBackground)
        } else {
            notifier.notifyJobFinished(success: success, title: title)
        }
    }

    private func perform(_ job: AIJob, saveToLibrary: Bool) async throws -> AIJobResult {
        let verdict = ContentPolicy.evaluate([job.prompt, job.template?.prompt].compactMap { $0 }.joined(separator: " "))
        if case .blocked(let reason) = verdict {
            throw AIServiceError.contentBlocked(reason)
        }

        // A free "Doesn't look like you?" retry costs nothing (the server
        // verifies `retry_of` in production).
        let cost = job.retryOf == nil ? credits.cost(of: job.operation, outputs: job.numOutputs) : 0
        let charge = try credits.charge(cost)
        do {
            let result = try await ai.perform(job)
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
            throw error
        }
    }

    /// Adds images to the library (SwiftData metadata + files on disk).
    /// `operation == nil` marks a manually adjusted photo (no AI claim).
    func saveToLibrary(_ images: [UIImage], operation: AIOperation?, title: String, prompt: String?) async {
        let context = container.mainContext
        for image in images {
            let stored = await Task.detached(priority: .utility) { () -> (String, PixelSize)? in
                guard let name = try? ImageStore.save(image) else { return nil }
                return (name, ImageUtilities.pixelSize(of: image))
            }.value
            guard let stored else { continue }
            let (name, size) = stored
            context.insert(Creation(
                operation: operation,
                title: title,
                prompt: prompt,
                imageFileName: name,
                pixelWidth: size.width,
                pixelHeight: size.height
            ))
        }
        try? context.save()
        if let newest = images.last {
            GlowWidgetBridge.updateLatestImage(newest)
        }
        syncWidgets()
    }

    /// Writes credits and the newest creation for the Home Screen widgets.
    func syncWidgets() {
        let context = container.mainContext
        var newest = FetchDescriptor<Creation>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        newest.fetchLimit = 1
        let count = (try? context.fetchCount(FetchDescriptor<Creation>())) ?? 0
        if count == 0 { GlowWidgetBridge.updateLatestImage(nil) }
        GlowWidgetBridge.update(
            credits: credits.balance,
            isPro: purchases.isPro,
            nextRefill: credits.nextFreeRefill,
            latest: (try? context.fetch(newest))?.first,
            creationsCount: count,
            breakdown: credits.breakdown,
            nextGrant: credits.nextSubscriptionGrant
        )
    }

    func deleteAllCreations() {
        let context = container.mainContext
        try? context.delete(model: Creation.self)
        try? context.save()
        ImageStore.deleteAll()
        GlowWidgetBridge.updateLatestImage(nil)
        syncWidgets()
    }

    // MARK: Ratings and reminders

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Saving or hearting a creation. Returns true when it's a good moment to
    /// ask for a rating (see `ReviewPromptPolicy`).
    func registerHappyMoment() -> Bool {
        if let lastInterruption, Date().timeIntervalSince(lastInterruption) < 1800 {
            countHappyMoment()
            return false
        }
        let ask = reviewPolicy.recordHappyMoment(at: Date(), appVersion: Self.appVersion)
        persistReviewPolicy()
        return ask
    }

    /// Sharing counts as a happy moment too, but a share is never interrupted.
    func countHappyMoment() {
        reviewPolicy.happyMoments += 1
        persistReviewPolicy()
    }

    /// A failed job, a report or a "doesn't look like you" retry: no rating
    /// prompts for a few days.
    func registerSetback() {
        reviewPolicy.recordSetback(at: Date())
        persistReviewPolicy()
    }

    private func persistReviewPolicy() {
        if let data = try? JSONEncoder().encode(reviewPolicy) {
            defaults.set(data, forKey: Keys.reviewPolicy)
        }
    }

    /// Reschedules the opt-in reminders for the current credits.
    func syncReminders() {
        Task {
            await notifier.reschedule(
                credits: credits.balance,
                isPro: purchases.isPro,
                nextRefill: credits.nextFreeRefill,
                dailyCredits: credits.policy.freeDailyAllowance
            )
        }
    }

    // MARK: Editor routing

    func startEditing(tool: EditorTool? = nil, template: PhotoTemplate? = nil) {
        if let template, template.isPro, !purchases.isPro {
            presentPaywall(source: "template_\(template.id)")
            return
        }
        pendingEditorRequest = EditorRequest(tool: tool, template: template)
        isPhotoPickerPresented = true
    }

    func openEditor(with image: UIImage, tool: EditorTool? = nil, template: PhotoTemplate? = nil) {
        editorLaunch = EditorLaunch(image: ImageUtilities.normalized(image), tool: tool, template: template)
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
        // RAW (ProRAW, DNG) is developed with Auto, since it looks flat out of the camera.
        let isRAW = AutoDevelop.isRAW(data)
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            if isRAW, let developed = AutoDevelop.developRAW(data) {
                return ImageUtilities.normalized(developed)
            }
            guard let image = UIImage(data: data) else { return nil }
            return ImageUtilities.normalized(image)
        }.value
        guard let image else { throw AIServiceError.invalidRequest(String(localized: "That file isn't a supported photo.")) }
        editorLaunch = EditorLaunch(image: image, tool: request.tool, template: request.template)
        if isRAW {
            showToast("RAW photo developed with the best settings ✨", style: .success)
        }
    }

    // MARK: Deep links (widgets, Live Activities)

    func handle(_ link: GlowDeepLink) {
        guard hasCompletedOnboarding, editorLaunch == nil else { return }
        isPaywallPresented = false
        outOfCredits = nil
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
        }
    }

    // MARK: Sharing

    func share(_ payload: SharePayload) {
        shareRequest = payload
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

    func handle(_ error: Error) {
        if Self.isCancellation(error) { return }
        Haptics.error()
        registerSetback()
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
            consentRequest = ConsentRequest { [weak self] in self?.setAIConsent(true) }
            return
        }
        showToast(verbatim: Self.localizedMessage(for: error), style: .error)
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
        "rate_limited": String(localized: "Too many requests. Please wait a moment."),
        "pro_required": String(localized: "This is part of Pro."),
        "retry_unavailable": String(localized: "This result can't be retried for free anymore."),
        "too_large": String(localized: "That photo is too large. Try a smaller one."),
        "content_blocked": String(localized: "This was blocked by our safety filters. Your credit was refunded."),
        "misconfigured": String(localized: "AI features aren't configured yet."),
        "internal": String(localized: "Something went wrong. Please try again."),
    ]
}

#if DEBUG
extension AppModel {
    /// Puts the app into a deterministic state for screenshots (DEBUG only).
    func applyScreenshotScene(_ scene: ScreenshotScene) {
        credits.resetForScreenshots()
        hasCompletedOnboarding = scene != .onboarding
        hasAIConsent = scene != .consent
        switch scene {
        case .onboarding, .home, .settings, .legal, .invite, .tour:
            selectedTab = .home
        case .effects:
            selectedTab = .home
            editorLaunch = EditorLaunch(image: ScreenshotFixtures.goldenLandscape, tool: .effects, previewEffect: .vhs)
        case .create, .results:
            selectedTab = .create
        case .edit:
            selectedTab = .edit
        case .library:
            selectedTab = .library
            seedScreenshotLibrary()
        case .editor:
            selectedTab = .home
            editorLaunch = EditorLaunch(image: ScreenshotFixtures.overcastLandscape, tool: .magicEdit, prompt: String(localized: "Golden hour light"))
        case .result:
            selectedTab = .home
            editorLaunch = EditorLaunch(
                image: ScreenshotFixtures.overcastLandscape,
                tool: .magicEdit,
                previewResult: ScreenshotFixtures.goldenLandscape
            )
        case .paywall:
            selectedTab = .home
            paywallSource = "screenshot"
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
        case .share:
            selectedTab = .home
            shareRequest = SharePayload(
                image: ScreenshotFixtures.goldenLandscape,
                original: ScreenshotFixtures.overcastLandscape,
                operation: .magicEdit
            )
        }
    }

    private func seedScreenshotLibrary() {
        deleteAllCreations()
        let images = [ScreenshotFixtures.goldenLandscape] + ScreenshotFixtures.generatedArt(count: 8)
        let context = container.mainContext
        for (index, image) in images.enumerated() {
            guard let name = try? ImageStore.save(image) else { continue }
            let size = ImageUtilities.pixelSize(of: image)
            context.insert(Creation(
                createdAt: Date().addingTimeInterval(TimeInterval(-index * 3600)),
                operation: index == 0 ? .magicEdit : .textToImage,
                title: index == 0 ? String(localized: "Golden hour light") : ScreenshotFixtures.createPrompt,
                prompt: nil,
                imageFileName: name,
                pixelWidth: size.width,
                pixelHeight: size.height
            ))
        }
        try? context.save()
        GlowWidgetBridge.updateLatestImage(images.first)
        syncWidgets()
    }
}
#endif
