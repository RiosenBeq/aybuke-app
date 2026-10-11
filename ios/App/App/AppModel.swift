import SwiftUI
import SwiftData
import PhotosUI
import Observation
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
}

struct ConsentRequest: Identifiable {
    let id = UUID()
    let onAccept: () -> Void
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

    // MARK: Navigation
    var selectedTab: AppTab = .home
    var isPaywallPresented = false
    private(set) var paywallSource = "unknown"
    var isPhotoPickerPresented = false
    var editorLaunch: EditorLaunch?
    var consentRequest: ConsentRequest?
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

    private enum Keys {
        static let onboarding = "onboarding.completed"
        static let consent = "ai.consent.v1"
        static let interests = "onboarding.interests"
        static let successfulSaves = "stats.successfulSaves"
    }

    init(container: ModelContainer, config: AppConfig = .current, defaults: UserDefaults = .standard) {
        self.container = container
        self.config = config
        self.defaults = defaults
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        self.hasAIConsent = defaults.bool(forKey: Keys.consent)
        self.interests = Set(defaults.stringArray(forKey: Keys.interests) ?? [])

        let purchases = PurchaseManager()
        self.purchases = purchases
        self.credits = CreditsManager(isServerAuthoritative: config.backend != nil)

        if let backend = config.backend {
            let auth = AuthSessionManager(config: backend)
            let remote = RemoteAIImageService(config: backend, auth: auth) { [weak purchases] in
                await purchases?.entitlementJWS
            }
            self.remote = remote
            self.ai = AIServiceRouter(cloud: remote, onDevice: OnDeviceImageService())
        } else {
            self.remote = nil
            self.ai = AIServiceRouter(cloud: DemoAIImageService(), onDevice: OnDeviceImageService())
        }

        purchases.creditPackHandler = { [weak self] credits, signedTransaction in
            await self?.grantCreditPack(credits, signedTransaction: signedTransaction) ?? false
        }

        #if DEBUG
        if let scene = ScreenshotScene.current {
            applyScreenshotScene(scene)
        }
        #endif
    }

    var isDemoMode: Bool { config.isDemoMode }

    /// Called once from the root view's `.task`.
    func start() async {
        await purchases.refreshEntitlements()
        credits.refresh(isPro: purchases.isPro)
        await refreshServerBalance()
        await purchases.loadProducts()
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

    /// Binds purchases to the backend user (StoreKit `appAccountToken`).
    func appAccountToken() async -> UUID? {
        await remote?.currentUserID()
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
        setAIConsent(false)
        TrialReminder.cancel()
        showToast("Your data has been deleted.", style: .success)
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

    func setAIConsent(_ granted: Bool) {
        hasAIConsent = granted
        defaults.set(granted, forKey: Keys.consent)
    }

    // MARK: Paywall

    func presentPaywall(source: String) {
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
                showToast("You've reached today's fair-use limit. Credits refill at midnight.", style: .info)
            } else {
                presentPaywall(source: "out_of_credits")
            }
            return
        }
        action()
    }

    // MARK: Running jobs

    /// Spends credits optimistically, runs the job and refunds on failure.
    func run(_ job: AIJob, saveToLibrary: Bool) async throws -> AIJobResult {
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
                await save(result.images, for: job)
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
    func save(_ images: [UIImage], for job: AIJob) async {
        let context = container.mainContext
        for image in images {
            let stored = await Task.detached(priority: .utility) { () -> (String, PixelSize)? in
                guard let name = try? ImageStore.save(image) else { return nil }
                return (name, ImageUtilities.pixelSize(of: image))
            }.value
            guard let stored else { continue }
            let (name, size) = stored
            context.insert(Creation(
                operation: job.operation,
                title: job.title,
                prompt: job.prompt ?? job.template?.prompt,
                imageFileName: name,
                pixelWidth: size.width,
                pixelHeight: size.height
            ))
        }
        try? context.save()
    }

    func deleteAllCreations() {
        let context = container.mainContext
        try? context.delete(model: Creation.self)
        try? context.save()
        ImageStore.deleteAll()
    }

    /// Counts successful saves; returns true when it's a good moment to ask for a review.
    func registerSuccessfulSave() -> Bool {
        let count = defaults.integer(forKey: Keys.successfulSaves) + 1
        defaults.set(count, forKey: Keys.successfulSaves)
        return count == 2 || count == 10
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

    func handlePickedPhoto(_ item: PhotosPickerItem) async {
        let request = pendingEditorRequest ?? EditorRequest()
        pendingEditorRequest = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw AIServiceError.invalidRequest("Couldn't open that photo.")
            }
            let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let image = UIImage(data: data) else { return nil }
                return ImageUtilities.normalized(image)
            }.value
            guard let image else { throw AIServiceError.invalidRequest("That file isn't a supported photo.") }
            editorLaunch = EditorLaunch(image: image, tool: request.tool, template: request.template)
        } catch {
            showToast("Couldn't open that photo. Try another one.", style: .error)
        }
    }

    // MARK: Feedback

    func showToast(_ text: String, style: ToastMessage.Style = .info) {
        toast = ToastMessage(text: text, style: style)
    }

    /// Maps any error to a friendly toast, opening the paywall when relevant.
    func handle(_ error: Error) {
        if error is CancellationError { return }
        Haptics.error()
        if case AIServiceError.insufficientCredits = error {
            if purchases.isPro {
                showToast("You've reached today's fair-use limit.", style: .info)
            } else {
                presentPaywall(source: "out_of_credits")
            }
            return
        }
        if case CreditError.insufficient = error {
            presentPaywall(source: "out_of_credits")
            return
        }
        if case AIServiceError.consentRequired = error {
            consentRequest = ConsentRequest { [weak self] in self?.setAIConsent(true) }
            return
        }
        let message = (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Please try again."
        showToast(message, style: .error)
    }
}

#if DEBUG
extension AppModel {
    /// Puts the app into a deterministic state for screenshots (DEBUG only).
    func applyScreenshotScene(_ scene: ScreenshotScene) {
        hasCompletedOnboarding = scene != .onboarding
        hasAIConsent = scene != .consent
        switch scene {
        case .onboarding, .home, .settings:
            selectedTab = .home
        case .create, .results:
            selectedTab = .create
        case .edit:
            selectedTab = .edit
        case .library:
            selectedTab = .library
            seedScreenshotLibrary()
        case .editor:
            selectedTab = .home
            editorLaunch = EditorLaunch(image: ScreenshotFixtures.overcastLandscape, tool: .magicEdit, prompt: "Golden hour light")
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
        case .consent:
            selectedTab = .home
            consentRequest = ConsentRequest {}
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
                title: index == 0 ? "Golden hour light" : ScreenshotFixtures.createPrompt,
                prompt: nil,
                imageFileName: name,
                pixelWidth: size.width,
                pixelHeight: size.height
            ))
        }
        try? context.save()
    }
}
#endif
