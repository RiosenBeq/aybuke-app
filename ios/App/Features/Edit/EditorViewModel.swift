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
    /// Request id of the latest people edit that can still be re-rolled for free.
    private(set) var retryRequestID: String?

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
    }

    var canUndo: Bool { historyVersion >= 0 && !undoStack.isEmpty }
    var canRedo: Bool { historyVersion >= 0 && !redoStack.isEmpty }
    var hasChanges: Bool { canUndo }
    var hasTransparency: Bool { ImageUtilities.hasAlpha(current) }
    var canRetryFree: Bool { retryRequestID != nil && !isProcessing }

    /// What the canvas shows right now.
    var displayImage: UIImage {
        if isHoldingOriginal { return original }
        if activeTool == .adjust, let adjustPreview { return adjustPreview }
        return current
    }

    // MARK: Tool selection

    func select(_ tool: EditorTool) {
        guard tool != activeTool else { return }
        if activeTool == .adjust { resetAdjustments() }
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
        retryRequestID = nil
        strokes.removeAll()
        adjustments = .neutral
        adjustPreview = nil
        previewSource = nil
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
            job.prompt = prompt
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
        case .enhance, .removeBackground, .adjust:
            break
        }

        app.requestAccess(for: operation, requiresPro: template?.isPro ?? false) { [weak self] in
            self?.execute(job, app: app)
        }
    }

    private func execute(_ job: AIJob, app: AppModel) {
        processingTitle = Self.progressTitle(for: job)
        isProcessing = true
        jobTask = Task {
            defer { isProcessing = false }
            do {
                let result = try await app.run(job, saveToLibrary: false)
                guard let image = result.images.first else { return }
                commit(ImageUtilities.normalized(image), operation: job.operation)
                if job.operation == .magicEdit { magicPrompt = "" }
                isComparing = job.operation != .removeBackground
                // Likeness Lock: one free re-roll for edits that involve people.
                if job.retryOf == nil, job.operation == .restyle || job.operation == .magicEdit {
                    lastJob = job
                    retryRequestID = result.requestID ?? UUID().uuidString
                }
            } catch {
                app.handle(error)
            }
        }
    }

    func cancelProcessing() {
        jobTask?.cancel()
    }

    /// Reverts the unsatisfying result and runs the same job again at no cost.
    func retryFree(app: AppModel) {
        guard var job = lastJob, let requestID = retryRequestID, !isProcessing else { return }
        undo()
        redoStack.removeAll()
        job.sourceImage = current
        job.retryOf = requestID
        Haptics.tap()
        execute(job, app: app)
    }

    private static func progressTitle(for job: AIJob) -> String {
        switch job.operation {
        case .magicEdit: return "Applying your edit…"
        case .restyle: return "Styling \(job.template?.title ?? "your photo")…"
        case .enhance: return "Enhancing details…"
        case .removeBackground: return "Cutting out the subject…"
        case .eraseObject: return "Erasing…"
        case .textToImage: return "Creating magic…"
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

    func resetAdjustments() {
        previewTask?.cancel()
        adjustments = .neutral
        adjustPreview = nil
    }

    func applyAdjustments() async {
        guard !adjustments.isNeutral, !isProcessing else { return }
        let settings = adjustments
        let source = current
        processingTitle = "Applying adjustments…"
        isProcessing = true
        let output = await Task.detached(priority: .userInitiated) {
            OnDeviceImageService.adjust(source, with: settings)
        }.value
        isProcessing = false
        commit(output, operation: nil)
        Haptics.success()
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
