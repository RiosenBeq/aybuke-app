import SwiftUI
import StoreKit
import AppCore

struct EditorView: View {
    let launch: EditorLaunch

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @State private var model: EditorViewModel
    @State private var showDiscardAlert = false
    @State private var showReport = false
    @State private var isSaving = false

    init(launch: EditorLaunch) {
        self.launch = launch
        _model = State(initialValue: EditorViewModel(launch: launch))
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                canvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay { SparkleBurst(trigger: model.celebration) }
                Group {
                    if model.showsKindnessNote && !model.isProcessing {
                        kindnessNote
                    }
                    if model.lastRequestID != nil && !model.isProcessing {
                        resultActions
                    }
                    toolPanel
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.bottom, 8)
                }
                .readableWidth(Metrics.compactWidth, alignment: .center)
                toolBar
            }

            if model.isProcessing {
                GeneratingOverlay(title: model.processingTitle, offersReadyPing: model.isProcessingInCloud, onCancel: { model.cancelProcessing() })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.isProcessing)
        .animation(.snappy, value: model.activeTool)
        .task { await model.checkForOtherPeople() }
        .animation(.snappy, value: model.showsKindnessNote)
        .task {
            // Launched from a template card: run it right away (one-tap).
            if let template = launch.template {
                model.run(.styles, template: template, app: app)
            }
        }
        .alert("Discard your edits?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Save to Photos first if you want to keep them.")
        }
        .reportDialog(isPresented: $showReport, requestID: model.lastRequestID)
        .modifier(AppPresentations(isActive: true))
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                if model.hasChanges { showDiscardAlert = true } else { dismiss() }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.icon)
            .accessibilityLabel("Close editor")

            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.icon)
                .disabled(!model.canUndo)
                .opacity(model.canUndo ? 1 : 0.4)
                .accessibilityLabel("Undo")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(.icon)
                .disabled(!model.canRedo)
                .opacity(model.canRedo ? 1 : 0.4)
                .accessibilityLabel("Redo")
            Button { model.isComparing.toggle() } label: {
                Image(systemName: model.isComparing ? "square.split.2x1.fill" : "square.split.2x1")
            }
            .buttonStyle(.icon)
            .disabled(!model.hasChanges)
            .opacity(model.hasChanges ? 1 : 0.4)
            .accessibilityLabel("Compare with original")

            Spacer(minLength: 0)

            Button { share() } label: { Image(systemName: "paperplane.fill") }
                .buttonStyle(.icon)
                .accessibilityLabel("Share")

            Button { save() } label: {
                HStack(spacing: 6) {
                    if isSaving { ProgressView().tint(Palette.onAccent) }
                    Text("Save")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Palette.onAccent)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Palette.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .accessibilityLabel("Save to Photos")
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 6)
    }

    // MARK: Canvas

    @ViewBuilder
    private var canvas: some View {
        if model.activeTool == .erase {
            MaskCanvas(image: model.current, strokes: $model.strokes, brushSize: model.brushSize)
        } else if model.isComparing && model.hasChanges {
            BeforeAfterSlider(before: model.original, after: model.current, showsTransparencyGrid: model.hasTransparency)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Palette.shadow, radius: 16, y: 8)
        } else {
            ZStack {
                if model.hasTransparency && !model.isHoldingOriginal {
                    CheckerboardBackground()
                }
                Image(uiImage: model.displayImage)
                    .resizable()
                    .scaledToFit()
            }
            .aspectRatio(model.displayImage.size.width / max(model.displayImage.size.height, 1), contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Palette.shadow, radius: 16, y: 8)
            .onLongPressGesture(minimumDuration: 0.15, maximumDistance: 40, perform: {}, onPressingChanged: { pressing in
                if model.hasChanges { model.isHoldingOriginal = pressing }
            })
            .overlay(alignment: .bottom) {
                if model.hasChanges && !model.isHoldingOriginal {
                    Text("Hold to see original")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Palette.ink.opacity(0.45), in: Capsule())
                        .padding(10)
                }
            }
            .accessibilityLabel(model.isHoldingOriginal ? "Original photo" : "Edited photo")
        }
    }

    /// Under a fresh cloud result: Likeness Lock's free retry (people edits)
    /// and reporting. The on-device likeness check speaks up first when the
    /// result drifted from her.
    private var resultActions: some View {
        VStack(spacing: 8) {
            if let likeness = model.likeness, likeness.needsAttention, model.canRetryFree {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.title3)
                        .foregroundStyle(Palette.accent)
                    Text(likeness.message)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Palette.blush.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, Metrics.gutter)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 8) {
                if model.likeness == .stillYou {
                    Label("Still you", systemImage: "checkmark.seal.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Palette.blush, in: Capsule())
                        .accessibilityLabel("Likeness check: still looks like you")
                        .transition(.scale.combined(with: .opacity))
                }
                if model.canRetryFree {
                    retryButton(emphasised: model.likeness?.needsAttention == true)
                }
                reportButton
            }
        }
        .padding(.bottom, 6)
        .transition(.opacity)
    }

    private func retryButton(emphasised: Bool) -> some View {
        Button {
            app.registerSetback()
            model.retryFree(app: app)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text(emphasised ? "Retry free" : model.likeness == .stillYou ? "Retry free" : "Doesn't look like you? Retry free")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(emphasised ? Palette.onAccent : Palette.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(emphasised ? Palette.accent : Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(emphasised ? Color.clear : Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }

    /// Kindness check: friends in the photo get a say. Skippable, once per photo.
    private var kindnessNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(Palette.accent)
                Text("Friends in this photo? Ask them before you edit them 💗")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button("Only edit me") { model.editOnlyMe() }
                    .buttonStyle(.pressable)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Palette.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Palette.accent, in: Capsule())
                Button("They're OK with it") { model.dismissKindnessNote() }
                    .buttonStyle(.pressable)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Palette.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.stroke, lineWidth: 1))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.stroke, lineWidth: 1))
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var reportButton: some View {
        Button {
            showReport = true
        } label: {
            Image(systemName: "flag")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 34, height: 34)
                .background(Palette.surface, in: Circle())
                .overlay(Circle().strokeBorder(Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Report this result")
    }

    // MARK: Tool panel

    @ViewBuilder
    private var toolPanel: some View {
        switch model.activeTool {
        case .magicEdit?:
            MagicEditPanel(prompt: $model.magicPrompt, cost: app.credits.cost(of: .magicEdit)) {
                model.run(.magicEdit, app: app)
            }
        case .styles?:
            StylesPanel(isPro: app.purchases.isPro) { template in
                model.run(.styles, template: template, app: app)
            }
        case .enhance?:
            OneTapPanel(
                title: "AI Enhance",
                message: "Unblur, sharpen details and restore faces in one tap.",
                buttonTitle: "Enhance",
                cost: app.credits.cost(of: .enhance)
            ) {
                model.run(.enhance, app: app)
            }
        case .removeBackground?:
            OneTapPanel(
                title: "Remove background",
                message: "Runs privately on your iPhone. Always free.",
                buttonTitle: "Remove background",
                cost: 0
            ) {
                model.run(.removeBackground, app: app)
            }
        case .erase?:
            ErasePanel(
                brushSize: $model.brushSize,
                hasStrokes: !model.strokes.isEmpty,
                cost: app.credits.cost(of: .eraseObject),
                onUndoStroke: { model.undoStroke() },
                onClear: { model.clearMask() },
                onErase: { model.run(.erase, app: app) }
            )
        case .adjust?:
            AdjustPanel(
                settings: $model.adjustments,
                onAuto: { model.autoAdjust() },
                onChange: { model.updateAdjustPreview() },
                onReset: { model.resetAdjustments() },
                onApply: { Task { await model.applyAdjustments() } }
            )
        case .effects?:
            EffectsPanel(
                thumbnails: model.effectThumbnails,
                selected: model.effect,
                dateStamp: Binding(
                    get: { model.effectDateStamp },
                    set: { value in
                        model.effectDateStamp = value
                        if let effect = model.effect { model.previewEffect(effect) }
                    }
                ),
                onSelect: { model.previewEffect($0) },
                onReset: { model.clearEffect() },
                onApply: { Task { await model.applyEffect() } }
            )
            .task(id: model.historyVersion) { await model.loadEffectThumbnails() }
        case nil:
            EmptyView()
        }
    }

    // MARK: Tool bar

    /// Every tool in one row on any iPhone or iPad (no scrolling), on a
    /// floating Liquid Glass bar.
    private var toolBar: some View {
        HStack(spacing: 2) {
            ForEach(EditorTool.allCases) { tool in
                let isActive = model.activeTool == tool
                Button {
                    model.select(tool)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tool.symbolName)
                            .font(.system(size: 18, weight: .semibold))
                            .symbolEffect(.bounce, value: isActive)
                        Text(tool.shortTitle)
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(isActive ? Palette.onPrimary : Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(isActive ? Palette.primary : Color.clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tool.title)
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .padding(5)
        .liquidGlass(in: Capsule(), tint: Palette.white.opacity(0.4))
        .frame(maxWidth: 560)
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
        .shadow(color: Palette.shadow, radius: 14, y: 6)
        .animation(.snappy, value: model.activeTool)
    }

    // MARK: Export

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await PhotoLibrarySaver.save(model.current, operation: model.appliedOperation, watermark: !app.purchases.isPro)
                await app.saveToLibrary([model.current], operation: model.appliedOperation, title: model.libraryTitle, prompt: nil)
                app.showToast("Saved to Photos", style: .success)
                Haptics.success()
                if app.registerHappyMoment() {
                    requestReview()
                }
            } catch {
                app.handle(error)
            }
        }
    }

    private func share() {
        Haptics.tap()
        app.share(SharePayload(
            image: model.current,
            original: model.hasChanges ? model.original : nil,
            operation: model.appliedOperation,
            prompt: nil
        ))
    }
}
