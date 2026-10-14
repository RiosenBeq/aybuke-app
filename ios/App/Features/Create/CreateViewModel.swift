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
    /// Text Apple's on-device model wrote, so the field can say so.
    private(set) var modelWrittenPrompt: String?
    /// Unused model ideas from the last request, served before asking again.
    @ObservationIgnored private var queuedIdeas: [String] = []
    @ObservationIgnored private var lastIdea: String?
    @ObservationIgnored private var undoTask: Task<Void, Never>?

    var isPromptFromModel: Bool { modelWrittenPrompt != nil && modelWrittenPrompt == prompt }

    /// "Inspire me": model ideas when the on-device writer is available,
    /// otherwise hand-written seasonal ones; never the same idea twice in a row.
    func inspire(writer: OnDeviceWriter) {
        guard !isWriting else { return }
        Haptics.selection()
        if let next = queuedIdeas.popLast() {
            show(idea: next, fromModel: true)
            return
        }
        let context = OnDeviceWriter.IdeaContext.create(season: .current)
        guard writer.isAvailable else {
            showCurated(context)
            return
        }
        isWriting = true
        Task {
            defer { isWriting = false }
            let ideas = await writer.ideas(context).filter { $0 != lastIdea }
            if let first = ideas.first {
                queuedIdeas = Array(ideas.dropFirst())
                show(idea: first, fromModel: true)
            } else {
                showCurated(context)
            }
        }
    }

    /// "Make it magic" with the on-device model, or the offline enhancer.
    func enhancePrompt(writer: OnDeviceWriter) {
        guard !isWriting, !PromptBuilder.sanitize(prompt).isEmpty else { return }
        let original = prompt
        guard writer.isAvailable else {
            apply(PromptBuilder.enhance(original), replacing: original, fromModel: false)
            return
        }
        isWriting = true
        Task {
            defer { isWriting = false }
            let upgraded = await writer.enhance(prompt: original, style: style)
            // She may have kept typing while the model worked.
            guard prompt == original else { return }
            if let upgraded {
                apply(upgraded, replacing: original, fromModel: true)
            } else {
                apply(PromptBuilder.enhance(original), replacing: original, fromModel: false)
            }
        }
    }

    /// A recent prompt chip: her own words, so no "written by" note.
    func useRecent(_ recent: String) {
        Haptics.selection()
        prompt = recent
        modelWrittenPrompt = nil
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
            show(idea: idea, fromModel: false)
        }
    }

    private func show(idea: String, fromModel: Bool) {
        lastIdea = idea
        prompt = idea
        modelWrittenPrompt = fromModel ? idea : nil
        undoPrompt = nil
    }

    private func apply(_ upgraded: String, replacing original: String, fromModel: Bool) {
        guard upgraded != original else { return }
        prompt = upgraded
        modelWrittenPrompt = fromModel ? upgraded : nil
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
