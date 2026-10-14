import SwiftUI
import AVFoundation
import AppCore

/// A Retro Cam result waiting for Save, Edit or Share.
struct RetroCamShot: Identifiable {
    enum Content {
        /// A photo with the effect applied at full size.
        case photo(UIImage)
        /// The booth's four frames with the effect's colour, grain and light.
        case booth([UIImage])
    }

    let id = UUID()
    let content: Content
    let effect: RetroEffect
}

/// Retro Cam and Photo Booth: the live effect preview, the self-timer, the
/// 3-2-1 booth countdown and the shots. Free and on the device; nothing is
/// uploaded and no credits are used.
@MainActor
@Observable
final class RetroCamModel {
    enum Phase: Equatable {
        case starting, needsPermission, denied, unavailable, live
    }

    enum Mode: String, CaseIterable, Identifiable {
        case photo, booth

        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .photo: return LocalizedStringResource("Photo", comment: "Retro Cam mode: one photo")
            case .booth: return LocalizedStringResource("Booth", comment: "Retro Cam mode: four shots printed like a photo booth strip")
            }
        }
    }

    /// Colour, grain and light only: no beauty filters, nothing reshapes a
    /// face or body. Glamour's soft focus is left out for that reason, and
    /// Kira Kira because its sparkles are placed per photo, not live.
    static let effects: [RetroEffect] = [.disposable, .vhs, .digicam, .toyCam, .instant, .throwback16, .rainbow, .filmStill, .camcorder06, .neon]

    private(set) var phase: Phase = .starting
    var mode: Mode = .photo {
        didSet { renderer.update(look) }
    }
    private(set) var effect: RetroEffect = .disposable
    /// The effect's switch (date stamp, letterbox or camcorder display).
    private(set) var showsExtra = true
    /// Self-timer in seconds (0 = off).
    private(set) var timer = 0
    var isFlashOn = false
    private(set) var features = RetroCamFeatures()
    private(set) var pause: RetroCamPause?
    /// The frames' width over height, so the preview has the photo's shape.
    private(set) var aspect: CGFloat = 3.0 / 4.0
    /// "3, 2, 1" before a shot.
    private(set) var countdown: Int?
    /// A photo or the booth is under way (the shutter stops it).
    private(set) var isShooting = false
    /// Booth frames taken so far.
    private(set) var boothCount = 0
    /// The full-size effect is being applied.
    private(set) var isDeveloping = false
    /// Counts shots, for the shutter flash.
    private(set) var shutterCount = 0
    private(set) var shot: RetroCamShot?

    let previewView = RetroCamPreviewView()
    @ObservationIgnored private let renderer: RetroCamRenderer
    @ObservationIgnored private var source: RetroCamSource?
    @ObservationIgnored private var isRunning = false
    /// Closed for good: nothing may start the camera again.
    @ObservationIgnored private var isClosed = false
    @ObservationIgnored private var sequence: Task<Void, Never>?
    @ObservationIgnored private var sequenceID: UUID?

    init() {
        renderer = RetroCamRenderer(view: previewView, look: RetroCamRenderer.Look(effect: .disposable, showsExtra: true))
        renderer.onAspectChange = { [weak self] aspect in self?.aspect = aspect }
    }

    /// The effect's switch, when it also works live (not 2016's border).
    /// Booth frames get the effect's colour only: the print has the date.
    var extraOption: RetroEffect.Option? {
        guard mode == .photo else { return nil }
        return effect.option.flatMap { $0.worksOnVideo ? $0 : nil }
    }

    /// What the preview shows: exactly what the shot will get.
    private var look: RetroCamRenderer.Look {
        RetroCamRenderer.Look(effect: effect, showsExtra: showsExtra && mode == .photo)
    }

    // MARK: Camera

    /// Finds the camera, then starts it or asks for access first.
    func prepare() async {
        guard source == nil else { return }
        #if DEBUG
        // `-GLCameraPermission ask|denied` shows those screens in screenshots.
        if let forced = UserDefaults.standard.string(forKey: "GLCameraPermission") {
            phase = forced == "denied" ? .denied : .needsPermission
            return
        }
        #endif
        guard let source = await RetroCam.makeSource() else {
            phase = .unavailable
            return
        }
        self.source = source
        let renderer = renderer
        source.frameHandler = { frame, seconds in renderer.draw(frame, seconds: seconds) }
        source.pauseHandler = { [weak self] pause in self?.pause = pause }
        guard RetroCam.needsPermission(source) else { return await run() }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: await run()
        case .notDetermined: phase = .needsPermission
        default: phase = .denied
        }
    }

    /// After the friendly explanation, the system's own prompt.
    func requestAccess() async {
        guard source != nil else { return }
        if await AVCaptureDevice.requestAccess(for: .video) {
            await run()
        } else {
            phase = .denied
        }
    }

    /// Starts the camera, unless a shot is waiting for review.
    func run() async {
        guard let source, shot == nil, !isRunning, !isClosed else { return }
        isRunning = true
        renderer.setActive(true)
        guard let features = await source.start(previewLayer: previewView.layer) else {
            isRunning = false
            renderer.setActive(false)
            phase = .unavailable
            return
        }
        self.features = features
        phase = .live
    }

    /// The app left the screen: stops everything until it's back.
    func stop() {
        cancelSequence()
        pauseCamera()
    }

    /// The camera closed. A start still on its way (the permission prompt,
    /// finding the camera) won't turn it back on.
    func close() {
        isClosed = true
        stop()
    }

    func sceneChanged(to scenePhase: ScenePhase) {
        switch scenePhase {
        case .background:
            stop()
        case .active:
            if phase == .live { Task { await run() } }
        default:
            break
        }
    }

    private func pauseCamera() {
        guard isRunning else { return }
        isRunning = false
        renderer.setActive(false)
        source?.stop()
    }

    // MARK: Controls

    func select(_ effect: RetroEffect) {
        guard effect != self.effect else { return }
        self.effect = effect
        // Each effect starts with its own switch at its default.
        showsExtra = effect.option?.isOnByDefault ?? true
        Haptics.selection()
        renderer.update(look)
    }

    /// Swipes on the preview step through the effects.
    func step(_ offset: Int) {
        guard let index = Self.effects.firstIndex(of: effect), Self.effects.indices.contains(index + offset) else { return }
        select(Self.effects[index + offset])
    }

    func toggleExtra() {
        showsExtra.toggle()
        Haptics.selection()
        renderer.update(look)
    }

    func cycleTimer() {
        timer = PhotoBooth.nextTimer(after: timer)
        Haptics.selection()
    }

    func switchCamera() async {
        guard let source, !isShooting else { return }
        Haptics.tap()
        if let features = await source.switchCamera() {
            self.features = features
        }
    }

    // MARK: Shooting

    /// Takes a photo (after the self-timer) or runs the booth; while either
    /// is under way, the shutter stops it.
    func shutter(app: AppModel) {
        if isShooting {
            cancelSequence()
            return
        }
        guard phase == .live, isRunning, pause == nil, !isDeveloping, shot == nil else { return }
        let id = UUID()
        sequenceID = id
        isShooting = true
        sequence = Task {
            if mode == .photo {
                await takePhoto(app: app)
            } else {
                await runBooth(app: app)
            }
            guard sequenceID == id else { return }
            sequence = nil
            sequenceID = nil
            isShooting = false
            countdown = nil
        }
    }

    private func cancelSequence() {
        sequence?.cancel()
        sequence = nil
        sequenceID = nil
        isShooting = false
        countdown = nil
        boothCount = 0
    }

    private func takePhoto(app: AppModel) async {
        if timer > 0 {
            guard await count(from: timer) else { return }
        }
        guard let still = await snap(maxPixel: 4096, app: app) else { return }
        let effect = effect
        let options = RetroEffect.Options(extra: showsExtra)
        isDeveloping = true
        let developed = await Task.detached(priority: .userInitiated) { effect.apply(to: still, options: options) }.value
        isDeveloping = false
        guard !Task.isCancelled else { return }
        present(RetroCamShot(content: .photo(developed), effect: effect))
    }

    /// Four shots with 3-2-1 before each; the effect is graded into every
    /// frame (date stamps and frames are left to the print).
    private func runBooth(app: AppModel) async {
        boothCount = 0
        var frames: [UIImage] = []
        for seconds in PhotoBooth.countdowns(timer: timer) {
            guard await count(from: seconds), let still = await snap(maxPixel: 2048, app: app) else { return }
            let effect = effect
            let graded = await Task.detached(priority: .userInitiated) { Self.grade(still, with: effect) }.value
            guard !Task.isCancelled else { return }
            frames.append(graded)
            boothCount = frames.count
        }
        Haptics.success()
        present(RetroCamShot(content: .booth(frames), effect: effect))
        boothCount = 0
    }

    /// Counts down with a tick each second; false when stopped.
    private func count(from seconds: Int) async -> Bool {
        for value in stride(from: seconds, through: 1, by: -1) {
            countdown = value
            Haptics.selection()
            AccessibilityNotification.Announcement("\(value)").post()
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return false }
        }
        countdown = nil
        return true
    }

    private func snap(maxPixel: Int, app: AppModel) async -> UIImage? {
        guard let source else { return nil }
        shutterCount += 1
        Haptics.tap()
        do {
            return try await source.capture(flash: isFlashOn && features.hasFlash, maxPixel: maxPixel)
        } catch {
            app.showToast("Couldn't take the photo. Please try again.", style: .error)
            return nil
        }
    }

    nonisolated private static func grade(_ still: UIImage, with effect: RetroEffect) -> UIImage {
        guard let input = ImageFilters.ciImage(still) else { return still }
        return ImageFilters.render(effect.grade(input).cropped(to: input.extent), extent: input.extent) ?? still
    }

    /// The camera rests while she looks at the shot.
    private func present(_ shot: RetroCamShot) {
        self.shot = shot
        pauseCamera()
    }

    func retake() async {
        shot = nil
        await run()
    }

    #if DEBUG
    /// Screenshots: `-GLEffect <effect>`, `-GLCameraMode booth`,
    /// `-GLCameraTimer 3|10` and `-GLCameraAction shoot|booth`, which presses
    /// the shutter once the preview runs.
    func applyScreenshotOptions(app: AppModel) async {
        guard ScreenshotScene.current != nil else { return }
        let defaults = UserDefaults.standard
        if let effect = defaults.string(forKey: "GLEffect").flatMap(RetroEffect.init(rawValue:)), Self.effects.contains(effect) {
            select(effect)
        }
        if defaults.string(forKey: "GLCameraMode") == "booth" { mode = .booth }
        let timer = defaults.integer(forKey: "GLCameraTimer")
        if PhotoBooth.timerChoices.contains(timer) { self.timer = timer }
        guard let action = defaults.string(forKey: "GLCameraAction"), action == "shoot" || action == "booth" else { return }
        mode = action == "booth" ? .booth : .photo
        try? await Task.sleep(for: .seconds(1.5))
        shutter(app: app)
    }
    #endif
}
