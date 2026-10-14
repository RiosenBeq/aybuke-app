import SwiftUI
import Observation
import AppCore

@MainActor
@Observable
final class EditorViewModel {
    struct Step {
        let image: UIImage
        let operation: AIOperation?
    }

    let original: UIImage
    private(set) var current: UIImage
    /// Strongest AI operation applied so far — drives the provenance label on export.
    private(set) var appliedOperation: AIOperation?

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

    // Effects (on-device, 80s / 90s / Y2K)
    private(set) var effect: RetroEffect?
    var effectDateStamp = true
    private(set) var effectPreview: UIImage?
    private(set) var effectThumbnails: [RetroEffect: UIImage] = [:]
    @ObservationIgnored private var effectTask: Task<Void, Never>?

    @ObservationIgnored private var undoStack: [Step] = []
    @ObservationIgnored private var redoStack: [Step] = []
    @ObservationIgnored private var jobTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var previewSource: (source: UIImage, proxy: UIImage)?
    @ObservationIgnored private var lastJob: AIJob?
    private(set) var historyVersion = 0

    init(launch: EditorLaunch) {
        original = launch.image
        current = launch.image
        activeTool = launch.tool ?? .magicEdit
        magicPrompt = launch.prompt ?? ""
        if let previewResult = launch.previewResult {
            commit(previewResult, operation: .magicEdit)
            isComparing = true
        }
        if let effect = launch.previewEffect {
            previewEffect(effect)
        }
    }

    var canUndo: Bool { historyVersion >= 0 && !undoStack.isEmpty }
    var canRedo: Bool { historyVersion >= 0 && !redoStack.isEmpty }
    var hasChanges: Bool { canUndo }
    var hasTransparency: Bool { ImageUtilities.hasAlpha(current) }
    var canRetryFree: Bool { retryRequestID != nil && !isProcessing && Date.now < retryDeadline }

    /// On-device work shown on the canvas but not applied yet.
    enum PendingPreview {
        case effect(RetroEffect, dateStamp: Bool)
        case adjust(AdjustmentSettings)
    }

    /// Read from the settings rather than the preview images: the first effect
    /// render may still be running, and sliders moved back to zero leave a
    /// preview behind that changes nothing.
    var pendingPreview: PendingPreview? {
        switch activeTool {
        case .effects?:
            guard let effect else { return nil }
            return .effect(effect, dateStamp: effectDateStamp)
        case .adjust?:
            return adjustments.isNeutral ? nil : .adjust(adjustments)
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
        if isHoldingOriginal { return original }
        if activeTool == .adjust, let adjustPreview { return adjustPreview }
        if activeTool == .effects, let effectPreview { return effectPreview }
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
        isComparing = false
        activeTool = tool
        Haptics.selection()
    }

    // MARK: History

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(Step(image: current, operation: appliedOperation))
        current = previous.image
        appliedOperation = previous.operation
        afterHistoryChange()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Step(image: current, operation: appliedOperation))
        current = next.image
        appliedOperation = next.operation
        afterHistoryChange()
    }

    private func commit(_ image: UIImage, operation: AIOperation?) {
        undoStack.append(Step(image: current, operation: appliedOperation))
        if undoStack.count > 20 { undoStack.removeFirst() }
        redoStack.removeAll()
        current = image
        if let operation {
            appliedOperation = Self.stronger(appliedOperation, operation)
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
        // A chosen effect follows the photo it will be applied to (after Undo, say).
        if let effect {
            effectPreview = nil
            previewEffect(effect, haptic: false)
        }
    }

    private static func stronger(_ lhs: AIOperation?, _ rhs: AIOperation) -> AIOperation {
        func rank(_ operation: AIOperation) -> Int {
            switch operation.digitalSourceType {
            case .trainedAlgorithmicMedia: return 3
            case .compositeWithTrainedAlgorithmicMedia: return 2
            case .algorithmicallyEnhanced: return 1
            }
        }
        guard let lhs else { return rhs }
        return rank(rhs) >= rank(lhs) ? rhs : lhs
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
        case .enhance, .removeBackground, .adjust, .effects:
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

    /// Edits meant to keep the person (not stylised ones like anime or a
    /// figurine) are compared with the photo she started from.
    private func checkLikeness(of job: AIJob, edited: UIImage) {
        let keepsPerson: Bool
        switch job.operation {
        case .magicEdit: keepsPerson = true
        case .restyle: keepsPerson = [.glowUp, .aesthetic, .dreamy, .business].contains(job.template?.category)
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
            Dictionary(uniqueKeysWithValues: RetroEffect.allCases.map { ($0, $0.apply(to: source)) })
        }.value
        effectThumbnails = thumbnails
    }

    func previewEffect(_ effect: RetroEffect, haptic: Bool = true) {
        self.effect = effect
        effectTask?.cancel()
        let proxy = adjustProxy()
        let stamp = effectDateStamp
        if haptic { Haptics.selection() }
        effectTask = Task {
            let rendered = await Task.detached(priority: .userInitiated) { effect.apply(to: proxy, dateStamp: stamp) }.value
            guard !Task.isCancelled else { return }
            effectPreview = rendered
        }
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
        let stamp = effectDateStamp
        processingTitle = String(localized: "Adding \(effect.title)…")
        isProcessingInCloud = false
        isProcessing = true
        let output = await Task.detached(priority: .userInitiated) { effect.apply(to: source, dateStamp: stamp) }.value
        isProcessing = false
        clearEffect()
        commit(output, operation: nil)
        lastStepTitle = effect.title
        celebration += 1
        Haptics.success()
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
        case nil: break
        }
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
