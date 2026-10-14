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
    @State private var zoom = CanvasZoom()
    @State private var isZoomed = false
    @State private var ideasDismissed = false

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
                    if showsIdeas {
                        EditorIdeasRow(model: model) {
                            withAnimation(.snappy) { ideasDismissed = true }
                        }
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.bottom, 6)
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
        .task {
            model.stampsDemoResults = app.isDemoMode
            await model.checkForOtherPeople()
        }
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

    /// Ideas stay out of the way: hidden under a fresh cloud result or the
    /// kindness note, and in the hands-on Crop and Erase. (Kept, disabled,
    /// while a job runs, so "Surprise me" remembers where it was.)
    private var showsIdeas: Bool {
        !ideasDismissed && model.lastRequestID == nil && !model.showsKindnessNote
            && model.activeTool != .crop && model.activeTool != .erase
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            if isCropPending {
                closeButton.background {
                    // Mac: Esc drops the crop first, then closes the editor.
                    Button("Reset") { model.resetCrop() }
                        .macKeyboardShortcut(.cancelAction)
                        .opacity(0)
                        .accessibilityHidden(true)
                }
            } else {
                closeButton.macKeyboardShortcut(.cancelAction)
            }

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
            .disabled(!canCompare)
            .opacity(canCompare ? 1 : 0.4)
            .accessibilityLabel("Compare with original")

            Spacer(minLength: 0)

            Button { share() } label: { Image(systemName: "paperplane.fill") }
                .buttonStyle(.icon)
                .accessibilityLabel("Share")

            Button { save() } label: {
                HStack(spacing: 6) {
                    if isSaving { ProgressView().tint(Palette.onAccent) }
                    Text("Save")
                        .lineLimit(1)
                        .fixedSize()
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
            .macKeyboardShortcut(KeyboardShortcut("s"))
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 6)
    }

    private var closeButton: some View {
        Button {
            if model.hasUnsavedWork { showDiscardAlert = true } else { dismiss() }
        } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(.icon)
        .accessibilityLabel("Close editor")
    }

    private var isCropPending: Bool {
        if case .crop? = model.pendingPreview { return true }
        return false
    }

    /// Crop shows the whole photo under its box, so there's nothing to compare.
    private var canCompare: Bool { model.hasChanges && model.activeTool != .crop }

    // MARK: Canvas

    @ViewBuilder
    private var canvas: some View {
        if model.activeTool == .erase {
            MaskCanvas(image: model.current, strokes: $model.strokes, brushSize: model.brushSize)
        } else if model.activeTool == .crop, let proxy = model.cropProxy {
            CropCanvas(image: proxy, geometry: $model.crop, aspect: model.cropAspect, sourceSize: model.cropSourceSize)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Palette.shadow, radius: 16, y: 8)
        } else if model.isComparing && canCompare {
            BeforeAfterSlider(before: model.before, after: model.current, showsTransparencyGrid: model.hasTransparency)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Palette.shadow, radius: 16, y: 8)
        } else {
            ZStack {
                if model.hasTransparency && !model.isHoldingOriginal {
                    CheckerboardBackground()
                }
                ZoomableImage(
                    image: model.displayImage,
                    zoom: zoom,
                    onHold: { pressing in
                        if model.hasChanges { model.isHoldingOriginal = pressing }
                    },
                    onZoomChange: { isZoomed = $0 }
                )
                // A fresh canvas (fit) for every tool and every step.
                .id("\(model.activeTool?.rawValue ?? "")-\(model.historyVersion)")
                .surpriseReveal(id: model.revealVersion == model.historyVersion ? model.revealID : nil)
                .onDisappear { isZoomed = false }
            }
            .aspectRatio(model.displayImage.size.width / max(model.displayImage.size.height, 1), contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Palette.shadow, radius: 16, y: 8)
            .overlay(alignment: .bottom) {
                if model.hasChanges && !model.isHoldingOriginal && !isZoomed {
                    Text("Hold to see original")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Palette.ink.opacity(0.45), in: Capsule())
                        .padding(10)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.isHoldingOriginal ? "Original photo" : "Edited photo")
            .accessibilityAddTraits(.isImage)
            .accessibilityZoomAction { action in
                zoom.step(zoomIn: action.direction == .zoomIn)
            }
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
                Text(emphasised || model.likeness == .stillYou || !model.retryIsAboutLikeness ? "Retry free" : "Doesn't look like you? Retry free")
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
                message: "Runs privately on your device. Always free.",
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
        case .crop?:
            CropPanel(
                aspect: model.cropAspect,
                angle: $model.crop.angle,
                canApply: !model.crop.isIdentity,
                onAspect: { model.setCropAspect($0) },
                onRotate: { model.rotateCropLeft() },
                onFlip: { model.flipCrop() },
                onReset: { withAnimation(.snappy) { model.resetCrop() } },
                onApply: { Task { await model.applyCrop() } }
            )
        case .effects?:
            EffectsPanel(
                thumbnails: model.effectThumbnails,
                selected: model.effect,
                showsExtra: Binding(
                    get: { model.effectExtra },
                    set: { value in
                        model.effectExtra = value
                        if let effect = model.effect { model.previewEffect(effect) }
                    }
                ),
                subtitle: Binding(
                    get: { model.effectSubtitle },
                    set: { value in
                        model.effectSubtitle = String(value.prefix(FilmSubtitle.maxLength))
                        model.subtitleChanged(app: app)
                    }
                ),
                onSelect: { model.previewEffect($0) },
                onReset: { model.clearEffect() },
                onApply: {
                    guard model.commitSubtitle(app: app) else { return }
                    Task { await model.applyEffect() }
                }
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
                            .minimumScaleFactor(0.6)
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
        // Cmd+S on the Mac fires even under the processing overlay.
        guard !isSaving, !model.isProcessing else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            await model.commitPending()
            do {
                // Free tools never add a mark; free cloud AI results carry a small one.
                let usedCloudAI = model.appliedOperation.map { !$0.runsOnDevice } ?? false
                try await PhotoLibrarySaver.save(model.current, operation: model.appliedOperation, watermark: !app.purchases.isPro && usedCloudAI)
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
        guard !model.isProcessing else { return }
        Haptics.tap()
        Task {
            await model.commitPending()
            app.share(SharePayload(
                image: model.current,
                original: model.hasChanges ? model.before : nil,
                operation: model.appliedOperation,
                prompt: nil
            ))
        }
    }
}
