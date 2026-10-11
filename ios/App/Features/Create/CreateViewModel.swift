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
    var showResults = false
    @ObservationIgnored private var task: Task<Void, Never>?

    var canGenerate: Bool {
        !PromptBuilder.sanitize(prompt).isEmpty && !isGenerating
    }

    func surpriseMe() {
        prompt = PromptBuilder.surprisePrompt()
        Haptics.selection()
    }

    func enhancePrompt() {
        let enhanced = PromptBuilder.enhance(prompt)
        guard enhanced != prompt else { return }
        prompt = enhanced
        Haptics.success()
    }

    func generate(app: AppModel) {
        let verdict = ContentPolicy.evaluate(prompt)
        if case .blocked(let reason) = verdict {
            app.showToast(reason, style: .error)
            Haptics.error()
            return
        }
        let job = AIJob(operation: .textToImage, prompt: prompt, style: style, aspectRatio: aspectRatio, numOutputs: count)
        app.requestAccess(for: .textToImage, outputs: count, requiresPro: job.isProOnly) { [weak self] in
            self?.start(job, app: app)
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func start(_ job: AIJob, app: AppModel) {
        isGenerating = true
        task = Task {
            defer { isGenerating = false }
            do {
                let result = try await app.run(job, saveToLibrary: true)
                results = result.images
                showResults = true
            } catch {
                app.handle(error)
            }
        }
    }
}
