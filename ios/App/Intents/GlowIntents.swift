import AppIntents
import UIKit
import UniformTypeIdentifiers
import AppCore

// Siri, Shortcuts, Spotlight and the Action button. Every intent is a free
// on-device tool or opens the app; none reaches cloud AI by itself, so there
// is no consent or credit step here. "Edit a photo" opens the editor with
// its own age rules: under 13 that's the free effects, never Magic Edit.

enum GlowIntents {
    /// The app's state for the intents that open the app. Set in the app's
    /// initializer, which runs before the system performs any intent. (Not
    /// an `@Dependency`: those exist only inside the system's perform flow,
    /// so QA couldn't perform the intents itself.)
    @MainActor private(set) static weak var app: AppModel?

    @MainActor static func register(_ app: AppModel) {
        self.app = app
        #if DEBUG
        if let name = UserDefaults.standard.string(forKey: "GLIntent") {
            Task { await performForQA(name) }
        }
        #endif
    }

    #if DEBUG
    /// QA with a screenshot scene: `-GLIntent retroCam|photoBooth|collage|edit|effect`
    /// performs that intent after launch, as Siri or Shortcuts would. `edit`
    /// passes the demo photo; `effect` (`-GLEffect <name>`) writes its result
    /// to tmp/glowlit-intent-qa.
    private static func performForQA(_ name: String) async {
        try? await Task.sleep(for: .seconds(1.5))
        let photo = IntentFile(data: ImageUtilities.jpegData(ScreenshotFixtures.goldenLandscape, maxLongEdge: 1500) ?? Data(),
                               filename: "golden-hour.jpg", type: .jpeg)
        switch name {
        case "retroCam": _ = try? await OpenRetroCamIntent().perform()
        case "photoBooth": _ = try? await StartPhotoBoothIntent().perform()
        case "collage": _ = try? await MakeCollageIntent().perform()
        case "edit":
            let intent = EditPhotoIntent()
            intent.photo = photo
            _ = try? await intent.perform()
        case "effect":
            let intent = ApplyRetroEffectIntent()
            intent.photo = photo
            intent.effect = UserDefaults.standard.string(forKey: "GLEffect").flatMap(RetroEffectChoice.init(rawValue:)) ?? .vhs
            guard let file = try? await intent.perform().value else { return }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("glowlit-intent-qa", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? file.data.write(to: folder.appendingPathComponent(file.filename))
        default: break
        }
    }
    #endif
}

// MARK: - Apply a retro effect (in the background, also in automations)

/// The photo effects as Shortcuts lists them. A type of its own, so a new
/// `RetroEffect` never changes what a saved shortcut means.
enum RetroEffectChoice: String, AppEnum {
    case vhs, disposable, kira, digicam, instant, glamour, neon, throwback16, camcorder06, filmStill, tinyWorld, toyCam, rainbow

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Retro Effect"
    // Effect names stay the same in every language, like `RetroEffect.title`.
    static let caseDisplayRepresentations: [RetroEffectChoice: DisplayRepresentation] = [
        .vhs: DisplayRepresentation(title: "VHS '86", subtitle: "80s"),
        .disposable: DisplayRepresentation(title: "Disposable '98", subtitle: "90s"),
        .kira: DisplayRepresentation(title: "Kira Kira", subtitle: "Sparkle"),
        .digicam: DisplayRepresentation(title: "Digicam '04", subtitle: "Y2K"),
        .instant: DisplayRepresentation(title: "Instant '82", subtitle: "80s"),
        .glamour: DisplayRepresentation(title: "Glamour '92", subtitle: "90s"),
        .neon: DisplayRepresentation(title: "Neon '84", subtitle: "80s"),
        .throwback16: DisplayRepresentation(title: "Throwback '16", subtitle: "2010s"),
        .camcorder06: DisplayRepresentation(title: "Camcorder '06", subtitle: "Y2K"),
        .filmStill: DisplayRepresentation(title: "Film Still", subtitle: "Film"),
        .tinyWorld: DisplayRepresentation(title: "Tiny World", subtitle: "Mini"),
        .toyCam: DisplayRepresentation(title: "Toy Cam '09", subtitle: "Y2K"),
        .rainbow: DisplayRepresentation(title: "Rainbow '17", subtitle: "2010s"),
    ]

    var effect: RetroEffect {
        switch self {
        case .vhs: return .vhs
        case .disposable: return .disposable
        case .kira: return .kira
        case .digicam: return .digicam
        case .instant: return .instant
        case .glamour: return .glamour
        case .neon: return .neon
        case .throwback16: return .throwback16
        case .camcorder06: return .camcorder06
        case .filmStill: return .filmStill
        case .tinyWorld: return .tinyWorld
        case .toyCam: return .toyCam
        case .rainbow: return .rainbow
        }
    }
}

struct ApplyRetroEffectIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply a Retro Effect"
    static let description = IntentDescription(
        "Gives a photo an 80s, 90s or Y2K look and returns the new image. Free and made on your device: the photo isn't uploaded."
    )

    @Parameter(title: "Photo", supportedTypeIdentifiers: ["public.image"], inputConnectionBehavior: .connectToPreviousIntentResult)
    var photo: IntentFile

    @Parameter(title: "Effect", default: .vhs)
    var effect: RetroEffectChoice

    static var parameterSummary: some ParameterSummary {
        Summary("Apply \(\.$effect) to \(\.$photo)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let photo = photo
        let effect = effect.effect
        guard let encoded = await Task.detached(priority: .userInitiated, operation: {
            RetroEffectFile.render(photo.data, effect: effect)
        }).value else {
            throw GlowIntentError.notAPhoto
        }
        let base = (photo.filename as NSString).deletingPathExtension
        let name = "\(base.isEmpty ? "Aybuke" : base)-\(effect.rawValue).\(encoded.fileExtension)"
        return .result(value: IntentFile(data: encoded.data, filename: name, type: encoded.fileExtension == "png" ? .png : .jpeg))
    }
}

/// The effect on a whole file, like the editor's: RAW is developed with
/// Auto first, the result is at most 4096 px, and the file is encoded like a
/// save, so an AI marking the photo already had stays and its EXIF and
/// location don't. Call it off the main actor.
enum RetroEffectFile {
    static func render(_ data: Data, effect: RetroEffect) -> (data: Data, fileExtension: String)? {
        let isRAW = AutoDevelop.isRAW(data)
        let image = isRAW ? AutoDevelop.developRAW(data) : ImageUtilities.decodedImage(from: data, maxPixel: 4096)
        guard let image else { return nil }
        let options = RetroEffect.Options(extra: effect.option?.isOnByDefault ?? true)
        var output = effect.apply(to: image, options: options)
        // Core Image can hand back a developed RAW with an alpha channel, which
        // would make the photo a big PNG; only a transparent source keeps one.
        if isRAW || !ImageUtilities.hasAlpha(image) {
            output = ImageUtilities.opaque(output)
        }
        return ImageExporter.encode(output, sourceType: ImageExporter.digitalSourceType(in: data))
    }
}

enum GlowIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notAPhoto

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notAPhoto: return "That file isn't a supported photo."
        }
    }
}

// MARK: - Open the app at a tool

struct OpenRetroCamIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Retro Cam"
    static let description = IntentDescription("Opens the camera with live 80s, 90s and Y2K effects. Free, on your device.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await GlowIntents.app?.openFromIntent(.retroCam)
        return .result()
    }
}

struct StartPhotoBoothIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Retro Booth"
    static let description = IntentDescription(
        "Opens Retro Booth in Retro Cam: four shots with a 3-2-1 countdown, printed as a strip or a grid. Free, on your device."
    )
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await GlowIntents.app?.openFromIntent(.photoBooth)
        return .result()
    }
}

struct MakeCollageIntent: AppIntent {
    static let title: LocalizedStringResource = "Make a Collage"
    static let description = IntentDescription("Opens the collage maker for photo dumps, moodboards and carousels. Free, on your device.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await GlowIntents.app?.openFromIntent(.collage)
        return .result()
    }
}

struct EditPhotoIntent: AppIntent {
    static let title: LocalizedStringResource = "Edit a Photo"
    static let description = IntentDescription("Opens a photo in Aybuke's editor, or lets you pick one.")
    static let openAppWhenRun = true

    @Parameter(title: "Photo", supportedTypeIdentifiers: ["public.image"])
    var photo: IntentFile?

    static var parameterSummary: some ParameterSummary {
        Summary("Edit \(\.$photo)")
    }

    func perform() async throws -> some IntentResult {
        // Read here, off the main actor: a shared file may be large.
        let data = photo?.data
        await GlowIntents.app?.editFromIntent(data)
        return .result()
    }
}

// MARK: - App Shortcuts (Siri, Spotlight, the Action button)

struct GlowShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenRetroCamIntent(),
            phrases: [
                "Open Retro Cam in \(.applicationName)",
                "Take a retro photo with \(.applicationName)",
                "Open the \(.applicationName) camera",
            ],
            shortTitle: "Retro Cam",
            systemImageName: "camera.fill"
        )
        AppShortcut(
            intent: StartPhotoBoothIntent(),
            phrases: [
                "Start Retro Booth in \(.applicationName)",
                "Open Retro Booth in \(.applicationName)",
                "Take Retro Booth pictures with \(.applicationName)",
            ],
            shortTitle: "Retro Booth",
            systemImageName: "square.grid.2x2"
        )
        AppShortcut(
            intent: MakeCollageIntent(),
            phrases: [
                "Make a collage in \(.applicationName)",
                "Make a collage with \(.applicationName)",
                "Make a photo dump in \(.applicationName)",
            ],
            shortTitle: "Collage",
            systemImageName: "rectangle.3.offgrid.fill"
        )
        AppShortcut(
            intent: EditPhotoIntent(),
            phrases: [
                "Edit a photo with \(.applicationName)",
                "Edit a photo in \(.applicationName)",
                "Edit my photo in \(.applicationName)",
            ],
            shortTitle: "Edit a Photo",
            systemImageName: "photo.badge.plus"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .pink
}

// MARK: - Routing

extension AppModel {
    /// Opens a tool for Siri, Shortcuts or Spotlight, through the same route
    /// as deep links and controls.
    func openFromIntent(_ link: GlowDeepLink) async {
        guard await clearForIntent() else { return }
        handle(link)
    }

    /// "Edit a photo": the photo a shortcut passed, or the photo picker.
    func editFromIntent(_ data: Data?) async {
        guard await clearForIntent() else { return }
        selectedTab = .edit
        guard let data else {
            startEditing()
            return
        }
        guard let (image, isRAW, sourceType) = await PhotoDecoder.decode(data) else {
            showToast("That file isn't a supported photo.", style: .error)
            return
        }
        openEditor(with: image, provenance: Provenance(inheritedSourceType: sourceType))
        if isRAW {
            showToast("RAW photo developed with the best settings ✨", style: .success)
        }
    }

    /// Like a deep link, an intent never interrupts onboarding, a deletion or
    /// a full-screen tool (its work may not be saved). Sheets and pickers
    /// close first, since a cover can't open over them.
    private func clearForIntent() async -> Bool {
        guard hasCompletedOnboarding, !needsAgeStep, !isDeletingData, !isFullScreenCoverPresented else { return false }
        let hasSheet = isSettingsPresented || isPaywallPresented || outOfCredits != nil || consentRequest != nil
            || shareRequest != nil || isAccountPromptPresented || isBestShotPresented || photosAccessRequest != nil
            || isPhotoPickerPresented || isVideoPickerPresented
        guard hasSheet else { return true }
        isSettingsPresented = false
        isPaywallPresented = false
        outOfCredits = nil
        consentRequest = nil
        shareRequest = nil
        isAccountPromptPresented = false
        isBestShotPresented = false
        photosAccessRequest = nil
        isPhotoPickerPresented = false
        isVideoPickerPresented = false
        try? await Task.sleep(for: .milliseconds(500))
        return !isFullScreenCoverPresented
    }
}
