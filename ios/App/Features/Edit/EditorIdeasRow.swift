import SwiftUI
import AppCore

/// "Ideas for this photo": a compact row under the canvas with looks that fit
/// what's in the picture, found on device (`PhotoInsightsService`) and ranked
/// by `LookSuggester`. Effects apply instantly and free; a look asks first and
/// then goes through the usual gates; a Magic Edit idea fills the prompt.
struct EditorIdeasRow: View {
    let model: EditorViewModel
    /// Called once the row has something to show (it starts empty).
    var onShown: () -> Void = {}
    let onDismiss: () -> Void

    @Environment(AppModel.self) private var app
    @State private var insight: PhotoInsight?
    /// A Magic Edit idea from the on-device writer, when it answers in time.
    @State private var writerIdea: String?
    @State private var surpriseCount = 0
    @State private var confirmTemplate: PhotoTemplate?

    private static let freeEffects = RetroEffect.allCases.map(\.rawValue)
    /// Past this, a late model idea would swap a chip under her finger.
    private static let writerBudget: Duration = .seconds(2)

    var body: some View {
        // A VStack, not a Group: modifiers on an empty Group never run, and
        // the row is empty until the photo has been looked at.
        VStack(spacing: 0) {
            if let insight {
                content(suggestions(for: insight, rotation: 0))
                    .transition(.opacity)
            }
        }
        .task { await load() }
        .onChange(of: insight != nil) { _, shown in
            if shown { onShown() }
        }
        .confirmationDialog(
            confirmTemplate.map { Text("Try \(L10n.core($0.title))?") } ?? Text(verbatim: ""),
            isPresented: Binding(get: { confirmTemplate != nil }, set: { if !$0 { confirmTemplate = nil } }),
            titleVisibility: .visible,
            presenting: confirmTemplate
        ) { template in
            Button("Try this look") { tryLook(template) }
            Button("Cancel", role: .cancel) {}
        } message: { template in
            if template.isPro && !app.purchases.isPro {
                Text("This look is part of Pro.")
            } else {
                Text("\(app.credits.cost(of: .restyle)) credit per edit · failed edits are refunded")
            }
        }
    }

    private func content(_ suggestions: [LookSuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Ideas for this photo")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 32, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide ideas")
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    surpriseChip
                    // Up to three ideas next to "Surprise me".
                    ForEach(suggestions.prefix(3), id: \.self) { suggestion in
                        chip(for: suggestion)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .disabled(model.isProcessing)
        .accessibilityElement(children: .contain)
    }

    // MARK: Chips

    private var surpriseChip: some View {
        IdeaChip(title: String(localized: "Surprise me"), symbolName: "sparkles", isPrimary: true) {
            surprise()
        }
        .accessibilityHint("Applies a free effect that suits this photo. Tap again for another.")
    }

    @ViewBuilder
    private func chip(for suggestion: LookSuggestion) -> some View {
        switch suggestion {
        case .effect(let id):
            if let effect = RetroEffect(rawValue: id) {
                IdeaChip(title: effect.title, symbolName: "camera.filters") {
                    Task { await model.applySuggestedEffect(effect) }
                }
                .accessibilityLabel("Add the \(effect.title) effect")
                .accessibilityHint("Free, on your device. Undo takes it back.")
            }
        case .template(let id):
            if let template = TemplateCatalog.template(id: id) {
                IdeaChip(title: L10n.core(template.title), symbolName: template.symbolName, isLocked: template.isPro && !app.purchases.isPro) {
                    Haptics.tap()
                    confirmTemplate = template
                }
                .accessibilityLabel("Try the \(L10n.core(template.title)) look")
            }
        case .magicEdit(let prompt):
            let text = writerIdea ?? L10n.core(prompt)
            IdeaChip(title: text, symbolName: "wand.and.stars", maxWidth: 240) {
                Haptics.tap()
                model.magicPrompt = text
                model.select(.magicEdit)
            }
            .accessibilityLabel("Magic Edit idea: \(text)")
            .accessibilityHint("Puts this idea in the Magic Edit box.")
        }
    }

    // MARK: Actions

    private func suggestions(for insight: PhotoInsight, rotation: Int) -> [LookSuggestion] {
        let all = LookSuggester.suggest(for: insight, date: AppClock.now, freeEffects: Self.freeEffects, rotation: rotation)
        // Under 13 only the free on-device tools are offered, so no looks or
        // Magic Edit ideas (see AgeDefaults).
        guard !app.allowsCloudAI else { return all }
        return all.filter { if case .effect = $0 { return true } else { return false } }
    }

    /// Applies the next free effect that suits the photo. Never anything
    /// that costs a credit, so it needs no confirmation.
    private func surprise() {
        guard let insight else { return }
        let effect = suggestions(for: insight, rotation: surpriseCount).lazy.compactMap { suggestion -> RetroEffect? in
            if case .effect(let id) = suggestion { return RetroEffect(rawValue: id) }
            return nil
        }.first
        surpriseCount += 1
        guard let effect else { return }
        Task { await model.applySuggestedEffect(effect, surprise: true) }
    }

    private func tryLook(_ template: PhotoTemplate) {
        Task {
            // An effect or adjustment still on the canvas becomes the look's input.
            await model.commitPending()
            model.run(.styles, template: template, app: app)
        }
    }

    private func load() async {
        #if DEBUG
        // Deterministic ideas for screenshots: the demo landscape, no model.
        if ScreenshotScene.current == .ideas {
            withAnimation { insight = PhotoInsight(labels: ["sky", "lake", "mountain", "outdoor"]) }
            // QA: `-GLIdeasAction surprise` taps "Surprise me" once.
            if UserDefaults.standard.string(forKey: "GLIdeasAction") == "surprise" {
                try? await Task.sleep(for: .seconds(1))
                surprise()
            }
            return
        }
        #endif
        let found = await PhotoInsightsService.insight(for: model.original)
        withAnimation(.easeOut(duration: 0.25)) { insight = found }

        guard app.allowsCloudAI else { return }
        app.writer.refreshAvailability()
        guard app.writer.isAvailable else { return }
        let labels = found.labels + [found.animalKind].compactMap { $0 }
        let start = ContinuousClock.now
        let idea = await app.writer.ideas(.magicEdit(labels: labels, peopleCount: found.faceCount), count: 1).first
        if let idea, start.duration(to: .now) <= Self.writerBudget {
            writerIdea = idea
        }
    }
}

/// Capsule chip for an idea. The primary one ("Surprise me") is blush.
private struct IdeaChip: View {
    let title: String
    let symbolName: String
    var isPrimary = false
    var isLocked = false
    var maxWidth: CGFloat?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbolName).font(.footnote.weight(.semibold))
                Text(verbatim: title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if isLocked {
                    Image(systemName: "lock.fill").font(.caption2).accessibilityLabel("Pro")
                }
            }
            .frame(maxWidth: maxWidth)
            .fixedSize(horizontal: maxWidth == nil, vertical: false)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isPrimary ? Palette.onPrimary : Palette.textPrimary)
            .background(isPrimary ? Palette.primary : Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(isPrimary ? Palette.ink.opacity(0.12) : Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
}

extension View {
    /// The develop reveal for a "Surprise me" step; other steps show as is.
    @ViewBuilder
    func surpriseReveal(id: UUID?) -> some View {
        if let id {
            developReveal(id: id, haptic: false)
        } else {
            self
        }
    }
}
