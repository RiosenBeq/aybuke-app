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
        var inheritedSourceType: DigitalSourceType?
    }

    let original: UIImage
    private(set) var current: UIImage
    /// The original with every applied crop and turn, so before/after views
    /// line up with the edited photo.
    private(set) var before: UIImage
    /// Strongest AI operation applied so far — drives the provenance label on export.
    /// Starts at the source's own operation when re-editing an AI result.
    private(set) var appliedOperation: AIOperation?
    /// The AI marking the opened file already carried (imported file, Image
    /// Playground), or that a pasted cut-out sticker brought along.
    private(set) var inheritedSourceType: DigitalSourceType?
    /// A cut-out was placed on another photo (IPTC "composite" on export).
    private(set) var isComposite = false

    /// Export markings for the current image.
    var provenance: Provenance {
        Provenance(operation: appliedOperation, inheritedSourceType: inheritedSourceType, isComposite: isComposite)
    }

    var activeTool: EditorTool?
    var magicPrompt = ""
    /// Makeup Studio's look; a fresh editor starts on the first one.
    var makeup = MakeupStudio.defaultPreset.recipe
    /// The step a makeup look made and the photo it was made from: trying
    /// another look on that step starts again from the photo.
    @ObservationIgnored private var makeupBase: (version: Int, photo: UIImage)?
    var adjustments = AdjustmentSettings()
    /// The vibe picked above the sliders, if any (its values are on them).
    private(set) var adjustVibe: AdjustVibe?
    private(set) var adjustPreview: UIImage?
    /// Adjust's Soft skin (0…1), only for adults: the editor sets
    /// `allowsSoftSkin` from her age range, and without it the value is
    /// never rendered. Off for every new step.
    var softSkin = SoftSkin.defaultAmount
    private(set) var allowsSoftSkin = false
    private(set) var softSkinState: SoftSkinState = .idle
    enum SoftSkinState { case idle, finding, ready, noFace }
    /// The skin mask of a step (nil: no face found), and the one being made.
    @ObservationIgnored private var skinMask: (version: Int, mask: CIImage?)?
    @ObservationIgnored private var skinMaskJob: (version: Int, task: Task<CIImage?, Never>)?

    // Enhance: the free Quick fix (previewed like an effect) or an AI fix.
    private(set) var enhanceOption: EnhanceOption?
    var enhanceAddsColor = false
    var enhanceUpscales = false
    private(set) var enhancePreview: UIImage?
    /// The fix that suits the photo on the canvas ("Suggested" in the panel).
    private(set) var enhanceSuggested: EnhanceOption?
    /// Quick fix's inputs for a step: Auto's light and colour, and the photo's measures.
    @ObservationIgnored private var enhanceInputs: (version: Int, light: AutoAdjustment, quality: PhotoQuality)?
    @ObservationIgnored private var enhanceTask: Task<Void, Never>?
    private(set) var strokes: [MaskStroke] = []
    /// People and things she picked to erase ("Pick a person").
    private(set) var eraseRegions: [EraseRegion] = []
    /// What she added to the erase area, in order, so Undo takes the last off.
    @ObservationIgnored private var eraseMarks: [EraseMark] = []
    private enum EraseMark: Equatable { case stroke, region(Int) }
    /// "Pick a person": a tap on the canvas picks instead of painting.
    private(set) var isPickingToErase = false
    /// "Pick a person" waits for Vision (the panel shows an hourglass).
    var isFindingSubjects: Bool { isPickingToErase && eraseSubjects == nil && isAnalyzingSubjects }
    /// What she can pick in Erase, once Vision has looked.
    private(set) var eraseSubjects: SubjectMasks?
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
    /// DSLR '12's lens; it stays as she left it for the next photo step.
    var effectLens = DSLRLens.standard
    /// The subtitle that passed the content policy; only this one is drawn.
    @ObservationIgnored private var approvedSubtitle = ""
    @ObservationIgnored private var subtitleTask: Task<Void, Never>?
    private(set) var effectPreview: UIImage?
    private(set) var effectThumbnails: [RetroEffect: UIImage] = [:]
    /// The step DSLR '12's tile was drawn for with Vision's answer; before
    /// that it shows the centre-weighted blur.
    @ObservationIgnored private var dslrTileVersion: Int?
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
    // Text & Stickers (on-device, free)
    let overlays = OverlaySession()

    @ObservationIgnored private var undoStack: [Step] = []
    @ObservationIgnored private var redoStack: [Step] = []
    @ObservationIgnored private var jobTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var previewSource: (source: UIImage, proxy: UIImage)?
    /// The preview copy being made in the background, and for which image.
    @ObservationIgnored private var proxyJob: (source: UIImage, task: Task<UIImage, Never>)?
    @ObservationIgnored private var lastJob: AIJob?
    /// Vision's subjects of the photo on the canvas, found once per step and
    /// shared by DSLR '12, Cut out and Erase's "Pick a person".
    @ObservationIgnored private var subjectJob: (version: Int, task: Task<Result<SubjectMasks, Error>, Never>)?
    /// Vision's answer for a step: what it found, or nil for nobody and nothing.
    @ObservationIgnored private var answeredSubjects: (version: Int, masks: SubjectMasks?)?
    /// Vision is looking at this step's photo (Erase's hourglass, DSLR '12's tile).
    private(set) var isAnalyzingSubjects = false
    @ObservationIgnored private var memoryWatcher: Task<Void, Never>?
    private(set) var historyVersion = 0
    /// Moves when memory pressure drops redo, so Redo updates without
    /// starting a new step (work for the photo on the canvas stays valid).
    private(set) var redoRevision = 0
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
        prepareProxy()
        if activeTool == .enhance {
            prepareEnhance()
            if let option = launch.enhanceOption { selectEnhance(option, haptic: false) }
        }
        #if DEBUG
        // Screenshot QA: -GLOverlayMode text|stickers|doodle picks the panel.
        if ScreenshotScene.current == .textStickers {
            let mode = UserDefaults.standard.string(forKey: "GLOverlayMode").flatMap(OverlaySession.Mode.init(rawValue:))
            overlays.loadScreenshotFixture(mode: mode ?? .stickers)
        }
        if ScreenshotScene.current == .erase {
            strokes = ScreenshotFixtures.eraseStrokes
            eraseMarks = strokes.map { _ in .stroke }
        }
        // Screenshot QA: -GLDSLRLens portrait85|standard50|wide35 picks DSLR '12's lens.
        if ScreenshotScene.current != nil, let lens = UserDefaults.standard.string(forKey: "GLDSLRLens").flatMap(DSLRLens.init(rawValue:)) {
            effectLens = lens
            if let effect { previewEffect(effect, haptic: false) }
        }
        // Screenshot QA: -GLMakeupPreset <id> picks a Makeup Studio look.
        if ScreenshotScene.current != nil, let id = UserDefaults.standard.string(forKey: "GLMakeupPreset"),
           let preset = MakeupStudio.preset(id: id) {
            makeup = preset.recipe
        }
        // Screenshot QA: -GLAdjustVibe dreamy|analog|moody|golden picks a vibe in Adjust.
        if ScreenshotScene.current != nil, activeTool == .adjust, let id = UserDefaults.standard.string(forKey: "GLAdjustVibe"),
           let vibe = AdjustVibes.preset(id: id) {
            adjustments = vibe.applied(to: .neutral, replacing: nil)
            adjustVibe = vibe
            updateAdjustPreview()
        }
        // Screenshot QA: -GLSoftSkin <0…1> moves Soft skin (shown with -GLAgeBand adult).
        if ScreenshotScene.current != nil, activeTool == .adjust, UserDefaults.standard.object(forKey: "GLSoftSkin") != nil {
            softSkin = min(1, max(0, UserDefaults.standard.double(forKey: "GLSoftSkin")))
        }
        // Screenshot QA: -GLEnhanceMode <EnhanceOption> picks a fix; -GLEnhanceColor YES turns on Add color.
        if ScreenshotScene.current != nil, activeTool == .enhance {
            enhanceAddsColor = UserDefaults.standard.bool(forKey: "GLEnhanceColor")
            if let option = UserDefaults.standard.string(forKey: "GLEnhanceMode").flatMap(EnhanceOption.init(rawValue:)) {
                selectEnhance(option, haptic: false)
            }
        }
        #endif
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
            redoRevision += 1
        }
        previewSource = nil
        if activeTool != .effects {
            effectThumbnails = [:]
            effectPreview = nil
        }
        if activeTool != .adjust { adjustPreview = nil }
        if activeTool != .enhance { enhancePreview = nil }
    }

    var canUndo: Bool { historyVersion >= 0 && !undoStack.isEmpty }
    var canRedo: Bool { historyVersion >= 0 && redoRevision >= 0 && !redoStack.isEmpty }
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
        case overlays
        case quickFix
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
            return adjustments.isNeutral && effectiveSoftSkin == 0 ? nil : .adjust(adjustments)
        case .enhance?:
            return enhanceOption == .quickFix ? .quickFix : nil
        case .crop?:
            return crop.isIdentity ? nil : .crop(crop, cropAspect)
        case .hideFaces?:
            return faceHider.hasSelection ? .hideFaces : nil
        case .removeBackground?:
            return cutout.isActive ? .cutout : nil
        case .textStickers?:
            return overlays.hasContent ? .overlays : nil
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
        if activeTool == .enhance, enhanceOption == .quickFix, let enhancePreview { return enhancePreview }
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
        if activeTool == .erase {
            clearMask()
            isPickingToErase = false
        }
        if activeTool == .crop {
            crop = CropGeometry()
            cropAspect = .original
        }
        if activeTool == .hideFaces { faceHider.reset() }
        if activeTool == .removeBackground { cutout.reset() }
        if activeTool == .textStickers { overlays.reset() }
        if activeTool == .enhance { clearEnhance() }
        isComparing = false
        activeTool = tool
        refreshCropProxy()
        if tool == .hideFaces { startHidingFaces(preselect: true) }
        if tool == .enhance { prepareEnhance() }
        Haptics.selection()
    }

    // MARK: History

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(currentStep)
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(currentStep)
        restore(next)
    }

    private var currentStep: Step {
        Step(image: current, operation: appliedOperation, before: before, isComposite: isComposite, inheritedSourceType: inheritedSourceType)
    }

    private func restore(_ step: Step) {
        current = step.image
        appliedOperation = step.operation
        before = step.before
        isComposite = step.isComposite
        inheritedSourceType = step.inheritedSourceType
        afterHistoryChange()
    }

    /// `marking`: AI that came in with the step's content (a pasted sticker
    /// of an AI edit), kept like an imported file's.
    private func commit(_ image: UIImage, operation: AIOperation?, before newBefore: UIImage? = nil, composite: Bool = false,
                        marking: DigitalSourceType? = nil) {
        undoStack.append(currentStep)
        // Each step holds up to two 2048-px bitmaps (about 16 MB each).
        if undoStack.count > Self.historyLimit { undoStack.removeFirst() }
        redoStack.removeAll()
        current = image
        if let newBefore { before = newBefore }
        if composite { isComposite = true }
        if let marking { inheritedSourceType = DigitalSourceType.strongest(inheritedSourceType, marking) }
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
        clearMask()
        eraseSubjects = nil
        isPickingToErase = false
        // The old photo's search may still run, but nothing waits for it.
        subjectJob = nil
        answeredSubjects = nil
        isAnalyzingSubjects = false
        adjustments = .neutral
        adjustVibe = nil
        adjustPreview = nil
        softSkin = SoftSkin.defaultAmount
        skinMask = nil
        skinMaskJob = nil
        softSkinState = .idle
        previewSource = nil
        prepareProxy()
        // The fixes belong to the photo they were measured on.
        enhancePreview = nil
        enhanceSuggested = nil
        if activeTool == .enhance {
            prepareEnhance()
            if enhanceOption == .quickFix { updateQuickFixPreview() }
        }
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
        // The history step a new makeup look replaces, if any.
        var replacedStep: Int?
        // Erase's mask, drawn full size off the main actor once she's through the gates.
        var eraseMask: MaskRenderer.Drawing?

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
            job.prompt = editsOnlyMainPerson ? PromptBuilder.onlyMainPerson(prompt) : prompt
        case .makeup:
            // A Magic Edit whose words the app writes from her picks, through
            // the same gates, guard, credits, Likeness Lock and retry.
            guard !makeup.isEmpty else {
                app.showToast("Pick a look first.")
                return
            }
            let instruction = MakeupStudio.instruction(for: makeup)
            if case .blocked(let reason, _) = ContentPolicy.evaluate(instruction, operation: .magicEdit) {
                app.showToast(verbatim: L10n.core(reason), style: .error)
                Haptics.error()
                return
            }
            job.prompt = editsOnlyMainPerson ? PromptBuilder.onlyMainPerson(instruction) : instruction
            job.makeup = makeup
            // Another look straight after one starts again from her photo and
            // takes its place, so looks never pile up on an AI result.
            if let base = makeupBase, base.version == historyVersion {
                job.sourceImage = base.photo
                replacedStep = historyVersion
            }
        case .styles:
            guard let template else { return }
            job.template = template
        case .enhance:
            // Only the fix's name goes out: the server writes its instruction.
            job.enhanceMode = enhanceOption?.mode(addingColor: enhanceAddsColor) ?? .unblur
        case .erase:
            guard hasEraseMask else {
                app.showToast("Brush over what you want to remove.")
                return
            }
            let size = ImageUtilities.pixelSize(of: current)
            eraseMask = MaskRenderer.Drawing(strokes: strokes, regions: eraseRegions,
                                             size: CGSize(width: size.width, height: size.height))
        case .removeBackground, .adjust, .effects, .textStickers, .crop, .hideFaces:
            break
        }

        app.requestAccess(for: operation, requiresPro: template?.isPro ?? false,
                          proSource: template.map { "template_\($0.id)" } ?? "pro_content") { [weak self] in
            self?.execute(job, app: app, replacing: replacedStep, eraseMask: eraseMask)
        }
    }

    /// `replacing`: the history step (a makeup look) this result takes the
    /// place of, when it's still the one on the canvas. `eraseMask`: Erase's
    /// strokes and picks as she left them at Try, drawn into the job's mask
    /// here, off the main actor.
    private func execute(_ job: AIJob, app: AppModel, replacing replacedStep: Int? = nil,
                         eraseMask: MaskRenderer.Drawing? = nil) {
        processingTitle = Self.progressTitle(for: job)
        isProcessingInCloud = !job.operation.runsOnDevice
        isProcessing = true
        jobTask = Task {
            defer { isProcessing = false }
            var job = job
            do {
                if let eraseMask {
                    job.mask = await Task.detached(priority: .userInitiated) { MaskRenderer.render(eraseMask) }.value
                    try Task.checkCancellation()
                }
                let result = try await app.run(job, saveToLibrary: false)
                guard let image = result.images.first else { return }
                var edited = ImageUtilities.normalized(image)
                // An AI fix never comes back smaller than her photo (HD: up to twice it).
                if job.operation == .enhance, let source = job.sourceImage {
                    let mode = job.enhanceMode ?? .unblur
                    let result = edited
                    edited = await Task.detached(priority: .userInitiated) { Self.sizedEnhanceResult(result, source: source, mode: mode) }.value
                }
                // One Undo still goes back to her photo, not through every look.
                if let replacedStep, replacedStep == historyVersion, let previous = undoStack.popLast() {
                    restore(previous)
                }
                commit(edited, operation: job.operation)
                if job.makeup != nil, let photo = job.sourceImage {
                    makeupBase = (historyVersion, photo)
                }
                checkLikeness(of: job, edited: edited)
                lastRequestID = result.requestID
                lastStepTitle = job.title
                celebration += 1
                // Her typed request is done; a makeup look stays picked for another photo or tweak.
                if job.operation == .magicEdit, job.makeup == nil { magicPrompt = "" }
                isComparing = job.operation != .removeBackground
                announceResult(comparing: isComparing)
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

    /// VoiceOver hears the result instead of silence when the overlay goes.
    /// High priority, so the overlay's removal doesn't cut it off. (Errors
    /// are already spoken by their toast.)
    private func announceResult(comparing: Bool) {
        var text = AttributedString(comparing
            ? String(localized: "Your edit is ready. Showing before and after.")
            : String(localized: "Your edit is ready."))
        text.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(text).post()
    }

    /// A failed retry keeps the paid result and its Retry button, except when
    /// the server has used the retry up: it said so, or the user cancelled a
    /// retry it had already started.
    private func endsFreeRetry(_ error: Error, app: AppModel) -> Bool {
        if case AIServiceError.server(code: "retry_unavailable", _) = error { return true }
        // Today's free retries are used (a few a day, still one per result).
        if case AIServiceError.retryLimit = error { return true }
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
        // Blush and lip color sit where skin tone is usually read, so a
        // makeup look is read on the chin instead.
        let skinSample: FaceAnalysis.SkinSample = job.makeup == nil ? .cheeks : .chin
        likenessTask = Task {
            let result = await FaceAnalysis.likeness(original: source, edited: edited, skinSample: skinSample)
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
        case .magicEdit where job.makeup != nil: return String(localized: "Applying your makeup…")
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

    // MARK: Subjects (on-device, Vision)

    /// The photo's subjects, found once per step off the main actor. Only an
    /// answer is kept for the step (what Vision found, or that it found nobody
    /// and nothing): a failure may pass, so the next try looks again.
    private func subjectAnalysis() async -> Result<SubjectMasks, Error> {
        if let subjectJob, subjectJob.version == historyVersion { return await subjectJob.task.value }
        let source = current
        let version = historyVersion
        let task = Task.detached(priority: .userInitiated) { () -> Result<SubjectMasks, Error> in
            #if DEBUG
            // The Cut out scene's cartoon stands in for Vision unless -GLCutoutPhoto picks a sample.
            if ScreenshotScene.current == .cutout, UserDefaults.standard.string(forKey: "GLCutoutPhoto") == nil,
               let fixture = ScreenshotFixtures.cutoutAnalysis(for: source) {
                return .success(fixture)
            }
            #endif
            return Result { try SubjectMasks.analyze(source) }
        }
        subjectJob = (version, task)
        isAnalyzingSubjects = true
        let result = await task.value
        // Undo, Redo or a new step cleared it (or started another) meanwhile.
        guard subjectJob?.task == task else { return result }
        isAnalyzingSubjects = false
        switch result {
        case .success(let masks): answeredSubjects = (version, masks)
        case .failure(AIServiceError.noSubjectFound): answeredSubjects = (version, nil)
        case .failure: subjectJob = nil
        }
        return result
    }

    // MARK: Erase

    var hasEraseMask: Bool { !strokes.isEmpty || !eraseRegions.isEmpty }

    func addEraseStroke(_ stroke: MaskStroke) {
        strokes.append(stroke)
        eraseMarks.append(.stroke)
    }

    /// Takes off what she added last: a stroke or a picked person or thing.
    func undoStroke() {
        switch eraseMarks.popLast() {
        case .region(let id)?: eraseRegions.removeAll { $0.id == id }
        case .stroke?, nil: _ = strokes.popLast()
        }
    }

    func clearMask() {
        strokes.removeAll()
        eraseRegions.removeAll()
        eraseMarks.removeAll()
    }

    /// "Pick a person" on or off. The first time on a step, Vision looks
    /// for people and things (on the device, free).
    func toggleErasePicking(app: AppModel) {
        isPickingToErase.toggle()
        Haptics.selection()
        // A search already running (Cut out's, DSLR '12's or an earlier tap's)
        // is shared: this tap waits for its answer too.
        guard isPickingToErase, eraseSubjects == nil else { return }
        let version = historyVersion
        Task {
            let result = await subjectAnalysis()
            // Undo or Redo meanwhile turned picking off (and the hourglass with
            // it); turned off by hand, it waits for the next time.
            guard version == historyVersion, isPickingToErase, eraseSubjects == nil else { return }
            if case .success(let masks) = result, !masks.subjects.isEmpty {
                eraseSubjects = masks
            } else {
                isPickingToErase = false
                app.showToast(LocalizedStringResource("No people or things found. Brush over what to remove.",
                                                      comment: "Erase: Pick a person found nobody and nothing to pick in this photo"))
            }
        }
    }

    /// A tap while picking: adds the person or thing under it to the erase
    /// area, or takes it off again.
    func pickToErase(at point: CGPoint, app: AppModel) {
        guard let masks = eraseSubjects, isPickingToErase else { return }
        guard let id = masks.subject(atNormalized: point) else {
            app.showToast(LocalizedStringResource("Nothing to pick there.", comment: "Erase: she tapped the background while picking people and things to remove"))
            return
        }
        pickToErase(subject: id)
    }

    func pickToErase(subject id: Int) {
        guard let masks = eraseSubjects, isPickingToErase else { return }
        if eraseRegions.contains(where: { $0.id == id }) {
            eraseRegions.removeAll { $0.id == id }
            eraseMarks.removeAll { $0 == .region(id) }
            Haptics.selection()
            return
        }
        let version = historyVersion
        Task {
            let region = await Task.detached(priority: .userInitiated) { EraseRegion.make(id: id, from: masks) }.value
            guard version == historyVersion, let region, !eraseRegions.contains(region) else { return }
            eraseRegions.append(region)
            eraseMarks.append(.region(id))
            Haptics.tap()
        }
    }

    // MARK: Adjust (on-device, free)

    func updateAdjustPreview() {
        previewTask?.cancel()
        let settings = adjustments
        let amount = effectiveSoftSkin
        previewTask = Task {
            let proxy = await previewProxy()
            let mask = amount > 0 ? await skinMaskForCurrentStep() : nil
            guard !Task.isCancelled else { return }
            let rendered = await Task.detached(priority: .userInitiated) {
                OnDeviceImageService.adjust(proxy, with: settings, softSkin: mask.map { ($0, amount) })
            }.value
            guard !Task.isCancelled else { return }
            adjustPreview = rendered
        }
    }

    /// "Auto": the best light and colour for this photo, on the sliders. The
    /// vibe sliders stay as she has them, with her vibe still on top.
    func autoAdjust() {
        Task {
            let proxy = await previewProxy()
            let plan = await Task.detached(priority: .userInitiated) { AutoDevelop.plan(for: proxy) }.value
            withAnimation(.snappy) { adjustments = adjustments.applyingAuto(plan, vibe: adjustVibe) }
            updateAdjustPreview()
            Haptics.success()
        }
    }

    /// A vibe sets its sliders and nudges her contrast, saturation and
    /// warmth; another one takes its place, and the same one again takes it
    /// off. Every value lands on the sliders, so she can tweak it.
    func pickVibe(_ vibe: AdjustVibe) {
        withAnimation(.snappy) {
            if adjustVibe == vibe {
                adjustments = vibe.removed(from: adjustments)
                adjustVibe = nil
            } else {
                adjustments = vibe.applied(to: adjustments, replacing: adjustVibe)
                adjustVibe = vibe
            }
        }
        updateAdjustPreview()
        Haptics.selection()
    }

    /// One of her saved filters: every slider and the vibe it was built on;
    /// the same one again takes it off, like a vibe.
    func applyMyFilter(_ filter: MyFilter) {
        withAnimation(.snappy) {
            if adjustments == filter.settings {
                adjustments = .neutral
                adjustVibe = nil
            } else {
                adjustments = filter.settings
                adjustVibe = filter.vibe
            }
        }
        updateAdjustPreview()
        Haptics.selection()
    }

    // MARK: Effects (on-device)

    /// Every tile without Vision's subject pass: DSLR '12's uses what Vision
    /// already found for this step, else its centre-weighted blur, and is
    /// drawn again once a tap on it has found her (`finishDSLRTile`).
    func loadEffectThumbnails() async {
        let image = current
        let version = historyVersion
        if effectThumbnails.isEmpty {
            let answered = answeredSubjects?.version == version ? answeredSubjects : nil
            let thumbnails = await Task.detached(priority: .userInitiated) {
                RetroEffect.thumbnails(of: image, subjects: .known(answered?.masks))
            }.value
            // A step taken meanwhile brings its own thumbnails.
            guard version == historyVersion else { return }
            effectThumbnails = thumbnails
            dslrTileVersion = answered == nil ? nil : version
        }
        finishDSLRTile()
    }

    /// DSLR '12's tile with what Vision found, once it has answered for this step.
    private func finishDSLRTile() {
        let version = historyVersion
        guard dslrTileVersion != version, effectThumbnails[.dslr12] != nil,
              let answered = answeredSubjects, answered.version == version else { return }
        dslrTileVersion = version
        // Nobody and nothing found: the centre-weighted tile is already right.
        guard let masks = answered.masks else { return }
        let image = current
        Task {
            let tile = await Task.detached(priority: .utility) {
                RetroEffect.thumbnails(of: image, effects: [.dslr12], subjects: .known(masks))
            }.value
            guard version == historyVersion else { return }
            effectThumbnails.merge(tile) { _, new in new }
        }
    }

    private var effectOptions: RetroEffect.Options {
        RetroEffect.Options(extra: effectExtra, subtitle: effect?.takesSubtitle == true ? approvedSubtitle : "", lens: effectLens)
    }

    /// What DSLR '12 needs from Vision; nothing for the other effects.
    private func subjects(for effect: RetroEffect) async -> RetroEffect.Subjects {
        guard effect == .dslr12 else { return .known(nil) }
        return .known(try? await subjectAnalysis().get())
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
        let options = effectOptions
        effectTask = Task {
            let proxy = await previewProxy()
            // DSLR '12's first tap on a step runs Vision (its tile shows progress).
            let subjects = await subjects(for: effect)
            if effect == .dslr12 { finishDSLRTile() }
            guard !Task.isCancelled else { return }
            let rendered = await Task.detached(priority: .userInitiated) { effect.apply(to: proxy, options: options, subjects: subjects) }.value
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
        let subjects = await subjects(for: effect)
        let output = await Task.detached(priority: .userInitiated) { effect.apply(to: source, options: options, subjects: subjects) }.value
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
        adjustVibe = nil
        adjustPreview = nil
        softSkin = SoftSkin.defaultAmount
    }

    func applyAdjustments() async {
        let amount = effectiveSoftSkin
        guard !adjustments.isNeutral || amount > 0, !isProcessing else { return }
        let settings = adjustments
        let source = current
        processingTitle = String(localized: "Applying adjustments…")
        isProcessingInCloud = false
        isProcessing = true
        let mask = amount > 0 ? await skinMaskForCurrentStep() : nil
        let output = await Task.detached(priority: .userInitiated) {
            OnDeviceImageService.adjust(source, with: settings, softSkin: mask.map { ($0, amount) })
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
        case .overlays?: await applyOverlays()
        case .quickFix?: await applyQuickFix()
        case nil: break
        }
    }

    // MARK: Soft skin (Adjust, adults only, on-device)

    /// What's rendered: nothing unless her age range allows the slider.
    private var effectiveSoftSkin: Double { allowsSoftSkin ? softSkin : 0 }

    /// The editor sets this from her age range (`AgeDefaults.allowsSoftSkin`).
    func setSoftSkinAllowed(_ allowed: Bool) {
        guard allowed != allowsSoftSkin else { return }
        allowsSoftSkin = allowed
        if !allowed { softSkin = SoftSkin.defaultAmount }
        if activeTool == .adjust, softSkin > 0 || !allowed { updateAdjustPreview() }
    }

    func softSkinChanged() {
        softSkin = min(1, max(0, softSkin))
        updateAdjustPreview()
    }

    /// The step's skin mask, made once off the main actor (nil: no face).
    private func skinMaskForCurrentStep() async -> CIImage? {
        let version = historyVersion
        if let skinMask, skinMask.version == version { return skinMask.mask }
        let task: Task<CIImage?, Never>
        if let skinMaskJob, skinMaskJob.version == version {
            task = skinMaskJob.task
        } else {
            let source = current
            task = Task.detached(priority: .userInitiated) { SkinMask.make(for: source) }
            skinMaskJob = (version, task)
            softSkinState = .finding
        }
        let mask = await task.value
        guard version == historyVersion else { return nil }
        if skinMask?.version != version {
            skinMask = (version, mask)
            softSkinState = mask == nil ? .noFace : .ready
        }
        return mask
    }

    // MARK: Enhance

    /// Quick fix can make this photo bigger (it's under the editor's size).
    var canUpscale: Bool {
        let size = ImageUtilities.pixelSize(of: current)
        return EnhanceSizing.canUpscale(longEdge: Double(max(size.width, size.height)))
    }

    /// Measures the photo once per step, for Quick fix and the "Suggested" mark.
    func prepareEnhance() {
        Task {
            guard let inputs = await enhanceMeasures() else { return }
            enhanceSuggested = EnhanceAdvisor.suggestion(for: inputs.quality, cloudAI: true)?.option
        }
    }

    private func enhanceMeasures() async -> (light: AutoAdjustment, quality: PhotoQuality)? {
        let version = historyVersion
        if let enhanceInputs, enhanceInputs.version == version { return (enhanceInputs.light, enhanceInputs.quality) }
        let proxy = await previewProxy()
        let measured = await Task.detached(priority: .userInitiated) {
            (AutoDevelop.plan(for: proxy), PhotoQuality.measure(proxy) ?? PhotoQuality())
        }.value
        guard version == historyVersion else { return nil }
        enhanceInputs = (version, measured.0, measured.1)
        return measured
    }

    /// A tap on a fix: Quick fix shows on the photo at once; an AI fix waits
    /// for its button. The same one again puts it down.
    func selectEnhance(_ option: EnhanceOption, haptic: Bool = true) {
        if enhanceOption == option {
            clearEnhance()
        } else {
            enhanceOption = option
            if option == .quickFix {
                updateQuickFixPreview()
            } else {
                enhanceTask?.cancel()
                enhancePreview = nil
            }
        }
        if haptic { Haptics.selection() }
    }

    /// From a hint or an idea: Enhance with this fix picked.
    func openEnhance(_ option: EnhanceOption) {
        guard !isProcessing else { return }
        Task {
            if activeTool != .enhance {
                await commitPending()
                switchTool(to: .enhance)
            }
            if enhanceOption != option { selectEnhance(option) }
        }
    }

    func clearEnhance() {
        enhanceTask?.cancel()
        enhanceOption = nil
        enhancePreview = nil
    }

    private func updateQuickFixPreview() {
        enhanceTask?.cancel()
        enhanceTask = Task {
            guard let inputs = await enhanceMeasures() else { return }
            let proxy = await previewProxy()
            guard !Task.isCancelled, enhanceOption == .quickFix else { return }
            let size = ImageUtilities.pixelSize(of: proxy)
            let plan = QuickFix.plan(light: inputs.light, noise: inputs.quality.noise, longEdge: Double(max(size.width, size.height)))
            let rendered = await Task.detached(priority: .userInitiated) { OnDeviceImageService.quickFix(proxy, plan: plan) }.value
            guard !Task.isCancelled, enhanceOption == .quickFix else { return }
            enhancePreview = rendered
        }
    }

    /// Quick fix at full size: free, on the device, one Undo takes it back.
    func applyQuickFix() async {
        guard enhanceOption == .quickFix, !isProcessing, let inputs = await enhanceMeasures() else { return }
        let source = current
        let size = ImageUtilities.pixelSize(of: source)
        let plan = QuickFix.plan(light: inputs.light, noise: inputs.quality.noise, longEdge: Double(max(size.width, size.height)),
                                 upscale: enhanceUpscales && canUpscale)
        processingTitle = String(localized: "Fixing your photo…", comment: "While Enhance's free Quick fix runs")
        isProcessingInCloud = false
        isProcessing = true
        let output = await Task.detached(priority: .userInitiated) { OnDeviceImageService.quickFix(source, plan: plan) }.value
        isProcessing = false
        clearEnhance()
        commit(output, operation: nil)
        lastStepTitle = EnhanceOption.quickFix.title
        isComparing = true
        celebration += 1
        announceResult(comparing: true)
        Haptics.success()
    }

    /// An AI fix at the size `EnhanceSizing` asks for (Lanczos, edges clamped).
    nonisolated private static func sizedEnhanceResult(_ result: UIImage, source: UIImage, mode: EnhanceMode) -> UIImage {
        let resultSize = ImageUtilities.pixelSize(of: result), sourceSize = ImageUtilities.pixelSize(of: source)
        let resultLong = Double(max(resultSize.width, resultSize.height))
        let target = EnhanceSizing.resultLongEdge(source: Double(max(sourceSize.width, sourceSize.height)), result: resultLong, mode: mode)
        guard resultLong > 0, target > resultLong + 1, let input = ImageFilters.ciImage(result) else { return result }
        let factor = target / resultLong
        let rect = CGRect(x: 0, y: 0, width: (input.extent.width * factor).rounded(), height: (input.extent.height * factor).rounded())
        let scaled = ImageFilters.upscale(input.clampedToExtent(), factor: Float(factor)).cropped(to: rect).settingAlphaOne(in: rect)
        return ImageFilters.render(scaled, extent: rect) ?? result
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
                let analysis = try await subjectAnalysis().get()
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
                    if let refine = defaults.string(forKey: "GLCutoutRefine") {
                        for fixture in ScreenshotFixtures.refineStrokes {
                            cutout.setRefineMode(fixture.keeps ? .keepMore : .keepLess)
                            cutout.addRefineStroke(fixture.stroke)
                        }
                        // The brush she'd be holding.
                        let mode: CutoutSession.RefineMode = refine == "less" ? .keepLess : .keepMore
                        if cutout.refineMode != mode { cutout.setRefineMode(mode) }
                    }
                    if defaults.bool(forKey: "GLCutoutShadow") { cutout.toggleShadow() }
                    if defaults.object(forKey: "GLCutoutEdge") != nil { cutout.setEdge(defaults.double(forKey: "GLCutoutEdge")) }
                }
                #endif
                Haptics.success()
            } catch {
                app.handle(error)
            }
        }
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

    // MARK: Text & Stickers (on-device, free)

    /// Draws the text, stickers and doodle into the photo at full size, as
    /// one step. Manual edits: the photo's AI marking stays as it was, except
    /// that a pasted cut-out makes it a composite (with AI, if the sticker
    /// came from an AI edit).
    func applyOverlays() async {
        guard overlays.hasContent, !isProcessing else { return }
        let snapshot = overlays.snapshot()
        guard !snapshot.isEmpty else {
            overlays.reset()
            return
        }
        let source = current
        let layers = snapshot.layers
        let doodle = snapshot.doodle
        processingTitle = String(localized: "Adding text and stickers…")
        isProcessingInCloud = false
        isProcessing = true
        let output = await Task.detached(priority: .userInitiated) {
            OverlayRenderer.flatten(source, layers: layers, doodle: doodle)
        }.value
        isProcessing = false
        overlays.reset()
        commit(output, operation: nil, composite: snapshot.hasPasted, marking: snapshot.pastedAIMarking)
        lastStepTitle = String(localized: "Text & Stickers")
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

    /// Downscaled copy of the current image for live previews. Crop and Hide
    /// faces need it at once; it's usually ready from `prepareProxy`.
    private func adjustProxy() -> UIImage {
        if let previewSource, previewSource.source === current {
            return previewSource.proxy
        }
        let proxy = ImageUtilities.normalized(current, maxLongEdge: 1200)
        previewSource = (current, proxy)
        return proxy
    }

    /// The same copy, made off the main actor (once per step, shared by
    /// every preview that asks meanwhile).
    private func previewProxy() async -> UIImage {
        let source = current
        if let previewSource, previewSource.source === source { return previewSource.proxy }
        let task: Task<UIImage, Never>
        if let proxyJob, proxyJob.source === source {
            task = proxyJob.task
        } else {
            task = Task.detached(priority: .userInitiated) { ImageUtilities.normalized(source, maxLongEdge: 1200) }
            proxyJob = (source, task)
        }
        let proxy = await task.value
        if source === current, previewSource?.source !== source { previewSource = (source, proxy) }
        return proxy
    }

    /// Starts the copy for a new photo or step in the background, so the
    /// tool she opens next doesn't make it on the main actor.
    private func prepareProxy() {
        Task { _ = await previewProxy() }
    }
}
