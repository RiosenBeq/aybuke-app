import SwiftUI
import Observation
import AppCore

@MainActor
@Observable
final class EditorViewModel {
    struct Step {
        let image: UIImage
        let operation: AIOperation?
        let before: UIImage
        var isComposite = false
    }

    let original: UIImage
    private(set) var current: UIImage
    /// The original with every applied crop and turn, so before/after views
    /// line up with the edited photo.
    private(set) var before: UIImage
    /// Strongest AI operation applied so far — drives the provenance label on export.
    /// Starts at the source's own operation when re-editing an AI result.
    private(set) var appliedOperation: AIOperation?
    /// The AI marking the opened file already carried (imported file, Image Playground).
    let inheritedSourceType: DigitalSourceType?
    /// A cut-out was placed on another photo (IPTC "composite" on export).
    private(set) var isComposite = false

    /// Export markings for the current image.
    var provenance: Provenance {
        Provenance(operation: appliedOperation, inheritedSourceType: inheritedSourceType, isComposite: isComposite)
    }

    var activeTool: EditorTool?
    var magicPrompt = ""
    var adjustments = AdjustmentSettings()
    private(set) var adjustPreview: UIImage?
    var strokes: [MaskStroke] = []
    var brushSize: CGFloat = 0.07
    var isComparing = false
    var isHoldingOriginal = false
    private(set) var isProcessing = false
    private(set) var processingTitle = ""
    /// Cloud jobs take a while, so the overlay offers a "ready" notification.
    private(set) var isProcessingInCloud = false
    /// Request id of the latest people edit that can still be re-rolled for free.
    private(set) var retryRequestID: String?
    /// The server honours a free retry for 15 minutes (FREE_RETRY_WINDOW_MINUTES).
    @ObservationIgnored private var retryDeadline = Date.distantPast
    /// Request id of the cloud result on screen, attached to reports.
    private(set) var lastRequestID: String?
    /// Title of the latest AI step, used when saving to the library.
    private var lastStepTitle: String?
    /// Bumped after each finished AI step to play the sparkle burst.
    private(set) var celebration = 0
    /// On-device likeness check of the latest people edit (nil: not checked).
    private(set) var likeness: LikenessResult?
    /// Kindness check: other people are in the photo.
    private(set) var showsKindnessNote = false
    /// "Only edit me": Magic Edit leaves everyone else as they are.
    private(set) var editsOnlyMainPerson = false
    @ObservationIgnored private var likenessTask: Task<Void, Never>?

    // Effects (on-device, 80s to 2010s)
    private(set) var effect: RetroEffect?
    /// The effect's switch (date stamp, border, letterbox or camera info).
    var effectExtra = true
    /// Film Still's subtitle as she types it.
    var effectSubtitle = ""
    /// The subtitle that passed the content policy; only this one is drawn.
    @ObservationIgnored private var approvedSubtitle = ""
    @ObservationIgnored private var subtitleTask: Task<Void, Never>?
    private(set) var effectPreview: UIImage?
    private(set) var effectThumbnails: [RetroEffect: UIImage] = [:]
    @ObservationIgnored private var effectTask: Task<Void, Never>?

    // Crop (on-device geometry)
    var crop = CropGeometry()
    private(set) var cropAspect: CropAspect = .original
    /// The preview photo with the session's turns and mirror, under the crop box.
    private(set) var cropProxy: UIImage?
    /// Demo results carry a "DEMO PREVIEW" mark in a corner that a crop can cut off.
    var stampsDemoResults = false

    // Hide faces and Cut out (on-device, free)
    let faceHider = FaceHider()
    let cutout = CutoutSession()

    @ObservationIgnored private var undoStack: [Step] = []
    @ObservationIgnored private var redoStack: [Step] = []
    @ObservationIgnored private var jobTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var previewSource: (source: UIImage, proxy: UIImage)?
    @ObservationIgnored private var lastJob: AIJob?
    @ObservationIgnored private var memoryWatcher: Task<Void, Never>?
    private(set) var historyVersion = 0
    static let historyLimit = 8

    init(launch: EditorLaunch) {
        original = launch.image
        current = launch.image
        before = launch.image
        appliedOperation = launch.provenance.operation
        inheritedSourceType = launch.provenance.inheritedSourceType
        activeTool = launch.tool ?? .magicEdit
        magicPrompt = launch.prompt ?? ""
        if let previewResult = launch.previewResult {
            commit(previewResult, operation: .magicEdit)
            isComparing = true
        }
        if let effect = launch.previewEffect {
            #if DEBUG
            // Screenshot QA of subtitles in every script: -GLSubtitle "…"
            // (fixed test text, so the policy check is skipped here).
            if ScreenshotScene.current != nil, let subtitle = UserDefaults.standard.string(forKey: "GLSubtitle") {
                effectSubtitle = subtitle
                approvedSubtitle = FilmSubtitle.clean(subtitle)
            }
            #endif
            previewEffect(effect)
        }
        if activeTool == .crop {
            refreshCropProxy()
            if let aspect = launch.cropAspect { setCropAspect(aspect) }
            crop.angle = launch.cropAngle
        }
        if activeTool == .hideFaces { startHidingFaces(preselect: true) }
        // Holds self weakly, so it ends at the first warning after the editor closes.
        memoryWatcher = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didReceiveMemoryWarningNotification) {
                guard let self else { return }
                self.releaseRebuildableImages()
            }
        }
    }

    /// Under memory pressure, drops what can be rendered again (and redo,
    /// which only exists right after an undo). Undo history and the preview
    /// on screen stay.
    private func releaseRebuildableImages() {
        if !redoStack.isEmpty {
            redoStack.removeAll()
            historyVersion += 1
        }
        previewSource = nil
        if activeTool != .effects {
            effectThumbnails = [:]
            effectPreview = nil
        }
        if activeTool != .adjust { adjustPreview = nil }
    }

    var canUndo: Bool { historyVersion >= 0 && !undoStack.isEmpty }
    var canRedo: Bool { historyVersion >= 0 && !redoStack.isEmpty }
    var hasChanges: Bool { canUndo }
    var hasTransparency: Bool { ImageUtilities.hasAlpha(current) }
    var canRetryFree: Bool { retryRequestID != nil && !isProcessing && Date.now < retryDeadline }
    /// Pet looks restyle the animal, so "doesn't look like you" would be odd.
    var retryIsAboutLikeness: Bool { lastJob?.template?.category != .pets }

    /// On-device work shown on the canvas but not applied yet.
    enum PendingPreview {
        case effect(RetroEffect, RetroEffect.Options)
        case adjust(AdjustmentSettings)
        case crop(CropGeometry, CropAspect)
        case hideFaces
        case cutout
    }

    /// Read from the settings rather than the preview images: the first effect
    /// render may still be running, and sliders moved back to zero leave a
    /// preview behind that changes nothing.
    var pendingPreview: PendingPreview? {
        switch activeTool {
        case .effects?:
            guard let effect else { return nil }
            return .effect(effect, effectOptions)
        case .adjust?:
            return adjustments.isNeutral ? nil : .adjust(adjustments)
        case .crop?:
            return crop.isIdentity ? nil : .crop(crop, cropAspect)
        case .hideFaces?:
            return faceHider.hasSelection ? .hideFaces : nil
        case .removeBackground?:
            return cutout.isActive ? .cutout : nil
        default:
            return nil
        }
    }

    /// Anything Close would throw away.
    var hasUnsavedWork: Bool { canUndo || pendingPreview != nil }

    /// Library title: the latest AI step, or the tool that was used.
    var libraryTitle: String {
        lastStepTitle ?? appliedOperation.map { L10n.core($0.displayName) } ?? String(localized: "Adjusted photo")
    }

    /// What the canvas shows right now.
    var displayImage: UIImage {
        if isHoldingOriginal { return before }
        if activeTool == .adjust, let adjustPreview { return adjustPreview }
        if activeTool == .effects, let effectPreview { return effectPreview }
        if activeTool == .hideFaces, let preview = faceHider.preview { return preview }
        return current
    }

    // MARK: Tool selection

    /// Leaving Effects or Adjust applies what's on the canvas (one Undo takes
    /// it back), so switching tools never silently drops work.
    func select(_ tool: EditorTool) {
        guard tool != activeTool, !isProcessing else { return }
        if pendingPreview != nil {
            Task {
                await commitPending()
                switchTool(to: tool)
            }
        } else {
            switchTool(to: tool)
        }
    }

    private func switchTool(to tool: EditorTool) {
        guard tool != activeTool else { return }
        if activeTool == .adjust { resetAdjustments() }
        if activeTool == .effects { clearEffect() }
        if activeTool == .erase { strokes.removeAll() }
        if activeTool == .crop {
            crop = CropGeometry()
            cropAspect = .original
        }
        if activeTool == .hideFaces { faceHider.reset() }
        if activeTool == .removeBackground { cutout.reset() }
        isComparing = false
        activeTool = tool
        refreshCropProxy()
        if tool == .hideFaces { startHidingFaces(preselect: true) }
        Haptics.selection()
    }

    // MARK: History

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(Step(image: current, operation: appliedOperation, before: before, isComposite: isComposite))
        current = previous.image
        appliedOperation = previous.operation
        before = previous.before
        isComposite = previous.isComposite
        afterHistoryChange()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Step(image: current, operation: appliedOperation, before: before, isComposite: isComposite))
        current = next.image
        appliedOperation = next.operation
        before = next.before
        isComposite = next.isComposite
        afterHistoryChange()
    }

    private func commit(_ image: UIImage, operation: AIOperation?, before newBefore: UIImage? = nil, composite: Bool = false) {
        undoStack.append(Step(image: current, operation: appliedOperation, before: before, isComposite: isComposite))
        // Each step holds up to two 2048-px bitmaps (about 16 MB each).
        if undoStack.count > Self.historyLimit { undoStack.removeFirst() }
        redoStack.removeAll()
        current = image
        if let newBefore { before = newBefore }
        if composite { isComposite = true }
        if let operation {
            appliedOperation = AIOperation.stronger(appliedOperation, operation)
        }
        afterHistoryChange()
    }

    private func afterHistoryChange() {
        historyVersion += 1
        likenessTask?.cancel()
        likeness = nil
        effectThumbnails = [:]
        retryRequestID = nil
        lastRequestID = nil
        strokes.removeAll()
        adjustments = .neutral
        adjustPreview = nil
        previewSource = nil
        crop = CropGeometry()
        cropAspect = .original
        if activeTool == .crop { refreshCropProxy() }
        // Face boxes and subject masks belong to the photo they came from.
        cutout.reset()
        if activeTool == .hideFaces { startHidingFaces(preselect: false) }
        // A chosen effect follows the photo it will be applied to (after Undo, say).
        if let effect {
            effectPreview = nil
            previewEffect(effect, haptic: false)
        }
    }

    // MARK: AI tools

    func run(_ tool: EditorTool, template: PhotoTemplate? = nil, app: AppModel) {
        guard let operation = tool.operation, !isProcessing else { return }
        var job = AIJob(operation: operation, sourceImage: current)

        switch tool {
        case .magicEdit:
            let prompt = magicPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else {
                app.showToast("Describe the change you want first.")
                return
            }
            // Refuse before the consent sheet or paywall opens, so a blocked
            // idea never looks like it needs credits.
            if case .blocked(let reason, _) = ContentPolicy.evaluate(prompt, operation: .magicEdit) {
                app.showToast(verbatim: L10n.core(reason), style: .error)
                Haptics.error()
                return
            }
            job.prompt = editsOnlyMainPerson
                ? prompt + ". Only change the main person in front; keep everyone else exactly as they are."
                : prompt
        case .styles:
            guard let template else { return }
            job.template = template
        case .erase:
            guard !strokes.isEmpty else {
                app.showToast("Brush over what you want to remove.")
                return
            }
            let size = ImageUtilities.pixelSize(of: current)
            job.mask = MaskRenderer.render(strokes, size: CGSize(width: size.width, height: size.height))
        case .enhance, .removeBackground, .adjust, .effects, .crop, .hideFaces:
            break
        }

        app.requestAccess(for: operation, requiresPro: template?.isPro ?? false) { [weak self] in
            self?.execute(job, app: app)
        }
    }

    private func execute(_ job: AIJob, app: AppModel) {
        processingTitle = Self.progressTitle(for: job)
        isProcessingInCloud = !job.operation.runsOnDevice
        isProcessing = true
        jobTask = Task {
            defer { isProcessing = false }
            do {
                let result = try await app.run(job, saveToLibrary: false)
                guard let image = result.images.first else { return }
                let edited = ImageUtilities.normalized(image)
                commit(edited, operation: job.operation)
                checkLikeness(of: job, edited: edited)
                lastRequestID = result.requestID
                lastStepTitle = job.title
                celebration += 1
                if job.operation == .magicEdit { magicPrompt = "" }
                isComparing = job.operation != .removeBackground
                // Likeness Lock: one free re-roll for edits that involve people.
                if job.retryOf == nil, job.operation == .restyle || job.operation == .magicEdit {
                    lastJob = job
                    retryRequestID = result.requestID ?? UUID().uuidString
                    retryDeadline = .now.addingTimeInterval(15 * 60)
                }
            } catch {
                if job.retryOf != nil, endsFreeRetry(error, app: app) { retryRequestID = nil }
                app.handle(error)
            }
        }
    }

    /// A failed retry keeps the paid result and its Retry button, except when
    /// the server has used the retry up: it said so, or the user cancelled a
    /// retry it had already started.
    private func endsFreeRetry(_ error: Error, app: AppModel) -> Bool {
        if case AIServiceError.server(code: "retry_unavailable", _) = error { return true }
        return AppModel.isCancellation(error) && app.config.backend != nil
    }

    func cancelProcessing() {
        jobTask?.cancel()
    }

    // MARK: Kindness and likeness checks (on-device)

    /// Other people in the photo? A gentle, skippable reminder to ask first.
    func checkForOtherPeople() async {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "GLKindnessNote") {
            showsKindnessNote = true
            return
        }
        #endif
        guard await FaceAnalysis.faceCount(in: original) >= 2 else { return }
        showsKindnessNote = true
    }

    func editOnlyMe() {
        editsOnlyMainPerson = true
        showsKindnessNote = false
        Haptics.selection()
    }

    func dismissKindnessNote() {
        showsKindnessNote = false
    }

    /// "Hide their faces": opens Hide faces with everyone but her selected.
    func hideTheirFaces() {
        showsKindnessNote = false
        select(.hideFaces)
    }

    /// Edits meant to keep the person (not stylised ones like anime or a
    /// figurine) are compared with the photo she started from.
    private func checkLikeness(of job: AIJob, edited: UIImage) {
        let keepsPerson: Bool
        switch job.operation {
        case .magicEdit: keepsPerson = true
        case .restyle: keepsPerson = job.template?.keepsLikeness == true
        default: keepsPerson = false
        }
        guard keepsPerson, let source = job.sourceImage else { return }
        likenessTask = Task {
            let result = await FaceAnalysis.likeness(original: source, edited: edited)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { likeness = result }
        }
    }

    /// Runs the same job again at no cost, on the photo the first try started
    /// from. The paid result stays on the canvas until the retry succeeds and
    /// stays one Undo away afterwards.
    func retryFree(app: AppModel) {
        guard var job = lastJob, let requestID = retryRequestID, canRetryFree else { return }
        job.retryOf = requestID
        Haptics.tap()
        execute(job, app: app)
    }

    private static func progressTitle(for job: AIJob) -> String {
        switch job.operation {
        case .magicEdit: return String(localized: "Applying your edit…")
        case .restyle:
            guard let title = job.template?.title else { return String(localized: "Styling your photo…") }
            return String(localized: "Styling \(L10n.core(title))…")
        case .enhance: return String(localized: "Enhancing details…")
        case .removeBackground: return String(localized: "Cutting out the subject…")
        case .eraseObject: return String(localized: "Erasing…")
        case .textToImage: return String(localized: "Creating magic…")
        }
    }

    // MARK: Erase

    func undoStroke() {
        _ = strokes.popLast()
    }

    func clearMask() {
        strokes.removeAll()
    }

    // MARK: Adjust (on-device, free)

    func updateAdjustPreview() {
        previewTask?.cancel()
        let settings = adjustments
        let proxy = adjustProxy()
        previewTask = Task {
            let rendered = await Task.detached(priority: .userInitiated) {
                OnDeviceImageService.adjust(proxy, with: settings)
            }.value
            guard !Task.isCancelled else { return }
            adjustPreview = rendered
        }
    }

    /// "Auto": the best light and colour for this photo, on the sliders.
    func autoAdjust() {
        let proxy = adjustProxy()
        Task {
            let settings = await Task.detached(priority: .userInitiated) { AutoDevelop.settings(for: proxy) }.value
            withAnimation(.snappy) { adjustments = settings }
            updateAdjustPreview()
            Haptics.success()
        }
    }

    // MARK: Effects (on-device)

    func loadEffectThumbnails() async {
        guard effectThumbnails.isEmpty else { return }
        let source = ImageUtilities.normalized(current, maxLongEdge: 240)
        let thumbnails = await Task.detached(priority: .userInitiated) {
            Dictionary(uniqueKeysWithValues: RetroEffect.allCases.map {
                ($0, $0.apply(to: source, options: RetroEffect.Options(extra: $0.option?.isOnByDefault ?? true)))
            })
        }.value
        effectThumbnails = thumbnails
    }

    private var effectOptions: RetroEffect.Options {
        RetroEffect.Options(extra: effectExtra, subtitle: effect?.takesSubtitle == true ? approvedSubtitle : "")
    }

    /// `haptic: false` re-renders quietly, as after Undo or Redo.
    func previewEffect(_ effect: RetroEffect, haptic: Bool = true) {
        if effect != self.effect {
            // Each effect starts with its own switch at its default.
            effectExtra = effect.option?.isOnByDefault ?? true
            if haptic { Haptics.selection() }
        }
        self.effect = effect
        effectTask?.cancel()
        let proxy = adjustProxy()
        let options = effectOptions
        effectTask = Task {
            let rendered = await Task.detached(priority: .userInitiated) { effect.apply(to: proxy, options: options) }.value
            guard !Task.isCancelled else { return }
            effectPreview = rendered
        }
    }

    /// Re-renders a moment after she stops typing, not on every key.
    func subtitleChanged(app: AppModel) {
        subtitleTask?.cancel()
        subtitleTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            commitSubtitle(app: app)
        }
    }

    /// Checks the subtitle with the content policy before it is drawn. A
    /// blocked one shows why and isn't drawn. False when blocked.
    @discardableResult
    func commitSubtitle(app: AppModel) -> Bool {
        subtitleTask?.cancel()
        let text = FilmSubtitle.clean(effectSubtitle)
        var allowed = true
        var approved = text
        // Text drawn over the photo, not an edit instruction: the text rules apply.
        if case .blocked(let reason, _) = ContentPolicy.evaluate(text, operation: .textToImage) {
            app.showToast(verbatim: L10n.core(reason), style: .error)
            Haptics.error()
            approved = ""
            allowed = false
        }
        if approved != approvedSubtitle {
            approvedSubtitle = approved
            if let effect, effect.takesSubtitle { previewEffect(effect) }
        }
        return allowed
    }

    func clearEffect() {
        effectTask?.cancel()
        effect = nil
        effectPreview = nil
    }

    /// Applies the chosen effect at full size. Effects are free for everyone.
    func applyEffect() async {
        guard let effect, !isProcessing else { return }
        let source = current
        let options = effectOptions
        processingTitle = String(localized: "Adding \(effect.title)…")
        isProcessingInCloud = false
        isProcessing = true
        let output = await Task.detached(priority: .userInitiated) { effect.apply(to: source, options: options) }.value
        isProcessing = false
        clearEffect()
        commit(output, operation: nil)
        lastStepTitle = effect.title
        celebration += 1
        Haptics.success()
    }

    // MARK: Ideas for this photo (on-device, free)

    /// The step the last "Surprise me" made, so the next tap swaps its effect
    /// instead of stacking a second one on top.
    @ObservationIgnored private var surpriseVersion: Int?
    /// The canvas plays the develop reveal for this step.
    private(set) var revealID: UUID?
    private(set) var revealVersion: Int?

    /// Applies a suggested free effect straight away, through the same path
    /// as the Effects panel (one Undo takes it back).
    func applySuggestedEffect(_ suggested: RetroEffect, surprise: Bool = false) async {
        guard !isProcessing else { return }
        await commitPending()
        if surprise, surpriseVersion == historyVersion { undo() }
        effectTask?.cancel()
        effect = suggested
        effectExtra = suggested.option?.isOnByDefault ?? true
        await applyEffect()
        surpriseVersion = surprise ? historyVersion : nil
        if surprise {
            revealID = UUID()
            revealVersion = historyVersion
        }
    }

    func resetAdjustments() {
        previewTask?.cancel()
        adjustments = .neutral
        adjustPreview = nil
    }

    func applyAdjustments() async {
        guard !adjustments.isNeutral, !isProcessing else { return }
        let settings = adjustments
        let source = current
        processingTitle = String(localized: "Applying adjustments…")
        isProcessingInCloud = false
        isProcessing = true
        let output = await Task.detached(priority: .userInitiated) {
            OnDeviceImageService.adjust(source, with: settings)
        }.value
        isProcessing = false
        commit(output, operation: nil)
        Haptics.success()
    }

    /// Applies the effect or adjustments on the canvas at full size, so Save
    /// and Share export what the user sees. Both apply paths clear the pending
    /// state, so nothing is applied twice.
    func commitPending() async {
        switch pendingPreview {
        case .effect?: await applyEffect()
        case .adjust?: await applyAdjustments()
        case .crop?: await applyCrop()
        case .hideFaces?: await applyHideFaces()
        case .cutout?: await applyCutout()
        case nil: break
        }
    }

    // MARK: Crop (on-device, free)

    /// Full-size pixels of the photo being cropped.
    var cropSourceSize: CropSize {
        let pixels = ImageUtilities.pixelSize(of: current)
        return CropSize(width: Double(pixels.width), height: Double(pixels.height))
    }

    func setCropAspect(_ aspect: CropAspect) {
        cropAspect = aspect
        if aspect != .free {
            let size = crop.orientedSize(of: cropSourceSize)
            withAnimation(.snappy) {
                crop.rect = CropGeometry.largestRect(ratio: aspect.widthOverHeight(for: size), in: size)
            }
        }
        Haptics.selection()
    }

    func rotateCropLeft() {
        crop.rotateLeft(aspect: cropAspect, source: cropSourceSize)
        refreshCropProxy()
        Haptics.selection()
    }

    func flipCrop() {
        crop.flip()
        refreshCropProxy()
        Haptics.selection()
    }

    func resetCrop() {
        crop = CropGeometry()
        cropAspect = .original
        refreshCropProxy()
    }

    private func refreshCropProxy() {
        guard activeTool == .crop else {
            cropProxy = nil
            return
        }
        cropProxy = CropRenderer.oriented(adjustProxy(), geometry: crop)
    }

    /// Crops, turns and straightens at full size; the before/after original
    /// gets the same geometry so comparisons keep lining up.
    func applyCrop() async {
        guard !crop.isIdentity, !isProcessing else { return }
        let geometry = crop
        let aspect = cropAspect
        let source = current
        let sourceBefore = before
        let restamp = stampsDemoResults && appliedOperation.map { !$0.runsOnDevice } == true
        processingTitle = String(localized: "Cropping…")
        isProcessingInCloud = false
        isProcessing = true
        let (output, newBefore) = await Task.detached(priority: .userInitiated) {
            let cropped = CropRenderer.render(source, geometry: geometry, aspect: aspect)
            return (restamp ? DemoArt.stamp(cropped) : cropped, CropRenderer.render(sourceBefore, geometry: geometry, aspect: aspect))
        }.value
        isProcessing = false
        commit(output, operation: nil, before: newBefore)
        Haptics.success()
    }

    // MARK: Hide faces (on-device, free)

    private func startHidingFaces(preselect: Bool) {
        faceHider.start(source: current, proxy: adjustProxy(), preselect: preselect)
    }

    /// Covers the chosen faces at full size. The before photo gets the same
    /// covers, because Before/After, Photo strip and Which vibe? share it.
    func applyHideFaces() async {
        let faces = faceHider.hiddenRects
        let cover = faceHider.cover
        guard !faces.isEmpty, !isProcessing else { return }
        let source = current
        let sourceBefore = before
        processingTitle = String(localized: "Hiding faces…")
        isProcessingInCloud = false
        isProcessing = true
        let (output, newBefore) = await Task.detached(priority: .userInitiated) {
            let hidden = FaceHiding.render(source, faces: faces, cover: cover)
            // Same shape: the boxes line up. Otherwise never share an unhidden before.
            let hiddenBefore = FaceHiding.sameShape(sourceBefore, source)
                ? FaceHiding.render(sourceBefore, faces: faces, cover: cover)
                : hidden
            return (hidden, hiddenBefore)
        }.value
        isProcessing = false
        // On-device and not generative: no AI provenance for this step.
        commit(output, operation: nil, before: newBefore)
        lastStepTitle = String(localized: "Hide faces")
        Haptics.success()
    }

    // MARK: Cut out (on-device, free)

    /// Finds the subjects with Vision and shows the cut-out without applying it.
    func startCutout(app: AppModel) {
        guard !isProcessing, !cutout.isActive else { return }
        let source = current
        let version = historyVersion
        let onlyMe = editsOnlyMainPerson
        processingTitle = String(localized: "Cutting out the subject…")
        isProcessingInCloud = false
        isProcessing = true
        Task {
            defer { isProcessing = false }
            do {
                let analysis = try await Self.analyzeCutout(source)
                guard version == historyVersion, activeTool == .removeBackground else { return }
                // "Only edit me": start with the subject under her face.
                var keep: Int?
                if onlyMe, let face = await FaceAnalysis.faceRects(in: source).max(by: { $0.width * $0.height < $1.width * $1.height }) {
                    keep = analysis.subject(atNormalized: CGPoint(x: face.midX, y: face.midY))
                }
                cutout.begin(analysis, keeping: keep)
                #if DEBUG
                // Screenshot QA: -GLCutoutKeep <subject from the left> -GLBackdrop blur|<gradient>
                if ScreenshotScene.current == .cutout {
                    let defaults = UserDefaults.standard
                    if defaults.object(forKey: "GLCutoutKeep") != nil, case let index = defaults.integer(forKey: "GLCutoutKeep"), analysis.subjects.indices.contains(index) {
                        cutout.keepOnly(analysis.subjects[index].id)
                    }
                    switch defaults.string(forKey: "GLBackdrop") {
                    case "blur"?: cutout.setBackdrop(.blurOriginal)
                    case let name?: CutoutGradient(rawValue: name).map { cutout.setBackdrop(.gradient($0)) }
                    case nil: break
                    }
                }
                #endif
                Haptics.success()
            } catch {
                app.handle(error)
            }
        }
    }

    private static func analyzeCutout(_ source: UIImage) async throws -> CutoutAnalysis {
        #if DEBUG
        if ScreenshotScene.current == .cutout, let fixture = ScreenshotFixtures.cutoutAnalysis(for: source) {
            return fixture
        }
        #endif
        return try await Task.detached(priority: .userInitiated) { try CutoutAnalysis.analyze(source) }.value
    }

    func applyCutout() async {
        guard cutout.isActive, !isProcessing else { return }
        processingTitle = String(localized: "Cutting out the subject…")
        isProcessingInCloud = false
        isProcessing = true
        let output = await cutout.renderFinal()
        isProcessing = false
        guard let output else { return }
        let composite = cutout.isComposite
        commit(output, operation: .removeBackground, composite: composite)
        lastStepTitle = String(localized: "Cut out")
        celebration += 1
        Haptics.success()
    }

    /// Stickers follow Save's rules: AI provenance from the photo's steps,
    /// and the small mark only when cloud AI made it and she isn't Pro.
    func cutoutSticker(isPro: Bool) async -> (data: Data, fileExtension: String)? {
        guard let sticker = await cutout.renderSticker() else { return nil }
        // The sticker is only her subject, so it's never a composite, but it
        // keeps the photo's AI and inherited markings.
        let provenance = Provenance(operation: AIOperation.stronger(appliedOperation, .removeBackground), inheritedSourceType: inheritedSourceType)
        return ImageExporter.encode(sticker, sourceType: provenance.sourceType, watermark: provenance.showsMark(isPro: isPro))
    }

    /// Downscaled copy of the current image for live slider previews.
    private func adjustProxy() -> UIImage {
        if let previewSource, previewSource.source === current {
            return previewSource.proxy
        }
        let proxy = ImageUtilities.normalized(current, maxLongEdge: 1200)
        previewSource = (current, proxy)
        return proxy
    }
}
