import SwiftUI
import Observation
import AppCore

@MainActor
@Observable
final class CreateViewModel {
    var prompt = ""
    var style: ImageStyle = StyleCatalog.auto
    var aspectRatio: AspectRatio = .portrait
    var count = 1
    private(set) var isGenerating = false
    var results: [UIImage] = []
    /// Server request id of the latest results, attached to reports.
    private(set) var requestID: String?
    var showResults = false
    /// `Creation.imagePlaygroundSource` when the results came from Apple's sheet.
    private(set) var resultsSource: String?
    /// The job behind the results on screen, so Regenerate can run it again.
    private(set) var resultsJob: AIJob?
    @ObservationIgnored private var task: Task<Void, Never>?

    var canGenerate: Bool {
        !PromptBuilder.sanitize(prompt).isEmpty && !isGenerating
    }

    /// The writer is busy with "Inspire me" or "Make it magic".
    private(set) var isWriting = false
    /// The prompt before the last upgrade, offered as "Undo" for a few seconds.
    private(set) var undoPrompt: String?
    /// Text a model wrote, and which one, so the field can say so.
    private(set) var modelWrittenPrompt: String?
    private(set) var modelWriter: WrittenBy?
    /// Unused model ideas from the last request, served before asking again.
    @ObservationIgnored private var queuedIdeas: [String] = []
    @ObservationIgnored private var queuedWriter: WrittenBy = .device
    @ObservationIgnored private var lastIdea: String?
    @ObservationIgnored private var undoTask: Task<Void, Never>?

    var isPromptFromModel: Bool { modelWrittenPrompt != nil && modelWrittenPrompt == prompt }

    /// The writer of the text in the field, while it's unchanged.
    var promptWriter: WrittenBy? { isPromptFromModel ? modelWriter : nil }

    /// "Inspire me": the server's writing help when it's on for her (see
    /// `AppModel.usesCloudWriter`), else Apple's on-device model when
    /// available, else hand-written seasonal ideas; never the same idea
    /// twice in a row.
    func inspire(app: AppModel) {
        guard !isWriting else { return }
        Haptics.selection()
        if let next = queuedIdeas.popLast() {
            show(idea: next, writtenBy: queuedWriter)
            return
        }
        let context = OnDeviceWriter.IdeaContext.create(season: .current)
        let writer = app.writer
        let usesCloud = app.usesCloudWriter
        guard usesCloud || writer.isAvailable else {
            showCurated(context)
            return
        }
        isWriting = true
        let picked = style
        Task {
            defer { isWriting = false }
            if usesCloud {
                let ideas = await app.cloudIdeas(style: picked).filter { $0 != lastIdea }
                if let first = ideas.first {
                    queue(Array(ideas.dropFirst()), writtenBy: .cloud)
                    show(idea: first, writtenBy: .cloud)
                    return
                }
            }
            if writer.isAvailable {
                let ideas = await writer.ideas(context).filter { $0 != lastIdea }
                if let first = ideas.first {
                    queue(Array(ideas.dropFirst()), writtenBy: .device)
                    show(idea: first, writtenBy: .device)
                    return
                }
            }
            showCurated(context)
        }
    }

    /// "Make it magic": the server's writing help, else Apple's on-device
    /// model, else the offline enhancer.
    func enhancePrompt(app: AppModel) {
        guard !isWriting, !PromptBuilder.sanitize(prompt).isEmpty else { return }
        let original = prompt
        let writer = app.writer
        let usesCloud = app.usesCloudWriter
        guard usesCloud || writer.isAvailable else {
            apply(PromptBuilder.enhance(original), replacing: original, writtenBy: nil)
            return
        }
        isWriting = true
        let picked = style
        Task {
            defer { isWriting = false }
            var upgraded: (text: String, writer: WrittenBy)?
            if usesCloud, let text = await app.cloudPromptUpgrade(original, style: picked) {
                upgraded = (text, .cloud)
            } else if writer.isAvailable, let text = await writer.enhance(prompt: original, style: picked) {
                upgraded = (text, .device)
            }
            // She may have kept typing while the model worked.
            guard prompt == original else { return }
            if let upgraded {
                apply(upgraded.text, replacing: original, writtenBy: upgraded.writer)
            } else {
                apply(PromptBuilder.enhance(original), replacing: original, writtenBy: nil)
            }
        }
    }

    /// A recent prompt chip: her own words, so no "written by" note.
    func useRecent(_ recent: String) {
        Haptics.selection()
        prompt = recent
        modelWrittenPrompt = nil
        modelWriter = nil
        undoPrompt = nil
    }

    func undoEnhance() {
        guard let undoPrompt else { return }
        prompt = undoPrompt
        self.undoPrompt = nil
        undoTask?.cancel()
        Haptics.selection()
    }

    private func showCurated(_ context: OnDeviceWriter.IdeaContext) {
        var generator = SystemRandomNumberGenerator()
        if let idea = PromptBuilder.pickIdea(from: CuratedIdeas.for(context), avoiding: lastIdea, using: &generator) {
            show(idea: idea, writtenBy: nil)
        }
    }

    private func queue(_ ideas: [String], writtenBy writer: WrittenBy) {
        queuedIdeas = ideas
        queuedWriter = writer
    }

    /// `writtenBy`: the model that wrote it; nil for hand-written ideas.
    private func show(idea: String, writtenBy writer: WrittenBy?) {
        lastIdea = idea
        prompt = idea
        modelWrittenPrompt = writer == nil ? nil : idea
        modelWriter = writer
        undoPrompt = nil
    }

    private func apply(_ upgraded: String, replacing original: String, writtenBy writer: WrittenBy?) {
        guard upgraded != original else { return }
        prompt = upgraded
        modelWrittenPrompt = writer == nil ? nil : upgraded
        modelWriter = writer
        undoPrompt = original
        Haptics.success()
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.undoPrompt = nil
        }
    }

    func generate(app: AppModel) {
        submit(AIJob(operation: .textToImage, prompt: prompt, style: style, aspectRatio: aspectRatio, numOutputs: count), app: app)
    }

    /// Results' "Regenerate": the same prompt, style, size and count, through
    /// the same safety check, consent, Pro and credit gates as Generate.
    func regenerate(app: AppModel) {
        guard let resultsJob, !isGenerating else { return }
        submit(resultsJob, app: app)
    }

    private func submit(_ job: AIJob, app: AppModel) {
        let verdict = ContentPolicy.evaluate(job.prompt ?? "", operation: .textToImage)
        if case .blocked(let reason, _) = verdict {
            app.showToast(verbatim: L10n.core(reason), style: .error)
            Haptics.error()
            return
        }
        app.requestAccess(for: .textToImage, outputs: job.numOutputs, requiresPro: job.isProOnly,
                          proSource: Self.paywallSource(for: job)) { [weak self] in
            self?.start(job, app: app)
        }
    }

    /// What made the job Pro, so the paywall can say so: the style first,
    /// then the number of images.
    private static func paywallSource(for job: AIJob) -> String {
        if let style = job.style, style.isPro { return "style_\(style.id)" }
        return job.numOutputs > 1 ? "create_count" : "pro_content"
    }

    /// A picture from Apple's Image Playground sheet: no credits, kept in My
    /// Works and marked as AI-made on export. Her starting prompt isn't stored,
    /// because she may have changed the description inside Apple's sheet.
    func finishPlayground(_ image: UIImage, app: AppModel) {
        results = [image]
        requestID = nil
        resultsSource = Creation.imagePlaygroundSource
        resultsJob = nil
        showResults = true
        Task {
            await app.saveToLibrary([image], operation: .textToImage, title: "Image Playground", prompt: nil, source: Creation.imagePlaygroundSource)
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func start(_ job: AIJob, app: AppModel) {
        // Every gate passed: kept for the recent prompt chips (this device only).
        if let prompt = job.prompt { app.prompts.record(prompt) }
        isGenerating = true
        task = Task {
            defer { isGenerating = false }
            do {
                let result = try await app.run(job, saveToLibrary: true)
                results = result.images
                requestID = result.requestID
                resultsSource = nil
                resultsJob = job
                showResults = true
            } catch {
                app.handle(error)
            }
        }
    }

    #if DEBUG
    /// The `results` screenshot scene, with Regenerate available.
    func showScreenshotResults(_ images: [UIImage]) {
        results = images
        resultsJob = AIJob(operation: .textToImage, prompt: prompt, style: style, aspectRatio: aspectRatio, numOutputs: images.count)
        showResults = true
    }
    #endif
}
