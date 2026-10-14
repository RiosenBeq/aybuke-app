import SwiftUI
import StoreKit
import UniformTypeIdentifiers
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
    @State private var ideasShown = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(launch: EditorLaunch) {
        self.launch = launch
        _model = State(initialValue: EditorViewModel(launch: launch))
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .disabled(model.isProcessing)
                    // Typing covers it; only its Esc shortcut stays.
                    .opacity(isTypingOverlayText ? 0 : 1)
                    .background { applyShortcut }
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
                        EditorIdeasRow(model: model, onShown: { ideasShown = true }) {
                            withAnimation(.snappy) { ideasDismissed = true }
                        }
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.bottom, 6)
                    }
                    toolPanel
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.bottom, 8)
                        .disabled(model.isProcessing)
                }
                .readableWidth(Metrics.compactWidth, alignment: .center)
                toolBar
                    .disabled(model.isProcessing)
            }
            // The typing screen brings its own room above the keyboard.
            .ignoresSafeArea(.keyboard, edges: isTypingOverlayText ? .bottom : [])

            if isTypingOverlayText {
                OverlayTextEditor(session: model.overlays)
                    .transition(.opacity)
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
            #if DEBUG
            if ScreenshotScene.current == .cutout { model.startCutout(app: app) }
            // Screenshot QA of the full-size render: -GLOverlayApply YES.
            if ScreenshotScene.current == .textStickers, UserDefaults.standard.bool(forKey: "GLOverlayApply") {
                try? await Task.sleep(for: .seconds(1.5))
                await model.applyOverlays()
            }
            #endif
            await model.checkForOtherPeople()
        }
        .animation(.snappy, value: model.showsKindnessNote)
        .animation(.easeInOut(duration: 0.2), value: isTypingOverlayText)
        .onChange(of: model.overlays.notice) { _, notice in
            guard let notice else { return }
            app.showToast(verbatim: notice, style: .error)
            model.overlays.notice = nil
        }
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
    /// kindness note, and in the hands-on Crop, Erase, Hide faces and Cut out
    /// (an effect from the row would commit their preview mid-task). Kept,
    /// disabled, while a job runs, so "Surprise me" remembers where it was.
    private var showsIdeas: Bool {
        guard !ideasDismissed, model.lastRequestID == nil, !model.showsKindnessNote else { return false }
        switch model.activeTool {
        case .crop?, .erase?, .hideFaces?, .removeBackground?, .textStickers?: return false
        default: return true
        }
    }

    private var isTypingOverlayText: Bool {
        model.activeTool == .textStickers && model.overlays.isEditingText
    }

    // MARK: Top bar

    private var topBar: some View {
        // 6 pt spacing keeps five 44 pt targets plus Save within today's width.
        HStack(spacing: 6) {
            if isCropPending {
                closeButton.background {
                    // Esc drops the crop first, then closes the editor.
                    Button("Reset") { model.resetCrop() }
                        .keyboardShortcut(.cancelAction)
                        .opacity(0)
                        .accessibilityHidden(true)
                }
            } else if model.activeTool == .textStickers && model.overlays.hasFocus {
                closeButton.background {
                    // Esc finishes typing, then lets go of the picked item.
                    Button("Done") { model.overlays.dismissFocus() }
                        .keyboardShortcut(.cancelAction)
                        .opacity(0)
                        .accessibilityHidden(true)
                }
            } else {
                closeButton.keyboardShortcut(.cancelAction)
            }

            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.icon)
                .disabled(!model.canUndo)
                .opacity(model.canUndo ? 1 : 0.4)
                .accessibilityLabel("Undo")
                .padKeyboardShortcut("z")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(.icon)
                .disabled(!model.canRedo)
                .opacity(model.canRedo ? 1 : 0.4)
                .accessibilityLabel("Redo")
                .padKeyboardShortcut("z", modifiers: [.command, .shift])
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
                .padKeyboardShortcut("e")

            Button { save() } label: {
                // A long "Save" (French, Russian) falls back to the icon
                // rather than pushing the bar off narrow screens.
                ViewThatFits(in: .horizontal) {
                    saveLabel(showsText: true)
                    saveLabel(showsText: false)
                }
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .disabled(isSaving)
            .accessibilityLabel("Save to Photos")
            .accessibilityInputLabels(["Save", "Save to Photos"])
            .keyboardShortcut("s")
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 6)
    }

    private func saveLabel(showsText: Bool) -> some View {
        HStack(spacing: 6) {
            if isSaving {
                ProgressView().tint(Palette.onAccent)
            } else if !showsText {
                Image(systemName: "square.and.arrow.down")
            }
            if showsText {
                Text("Save")
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(Palette.onAccent)
        .padding(.horizontal, showsText ? 16 : 0)
        .frame(minWidth: 44, minHeight: 44)
        .background(Palette.accent, in: Capsule())
        .fixedSize()
    }

    /// ⌘Return: sends the Magic Edit prompt, or applies the previewed
    /// effect, adjustment or crop. Hidden; the visible buttons do the same.
    private var applyShortcut: some View {
        Button("Apply") {
            if model.activeTool == .magicEdit {
                guard !model.magicPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                model.run(.magicEdit, app: app)
            } else if model.pendingPreview != nil {
                Task { await model.commitPending() }
            }
        }
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(model.isProcessing)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var closeButton: some View {
        Button {
            // A typed but unsent prompt counts too, so Esc can't lose it.
            let hasTypedPrompt = model.activeTool == .magicEdit && !model.magicPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if model.hasUnsavedWork || hasTypedPrompt { showDiscardAlert = true } else { dismiss() }
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

    /// Crop shows the whole photo under its box, so there's nothing to
    /// compare; Text & Stickers needs the canvas for its own gestures.
    private var canCompare: Bool { model.hasChanges && model.activeTool != .crop && model.activeTool != .textStickers }

    // MARK: Canvas

    @ViewBuilder
    private var canvas: some View {
        if model.activeTool == .erase {
            MaskCanvas(image: model.current, strokes: $model.strokes, brushSize: model.brushSize)
        } else if model.activeTool == .hideFaces {
            HideFacesCanvas(image: model.displayImage, hider: model.faceHider)
        } else if model.activeTool == .removeBackground && model.cutout.isActive {
            CutoutCanvas(session: model.cutout, fallback: model.current)
        } else if model.activeTool == .textStickers {
            TextStickersCanvas(image: model.current, session: model.overlays)
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
                        .background(Palette.ink.opacity(reduceTransparency ? 0.9 : 0.65), in: Capsule())
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
            .frame(minHeight: 44)
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
            // Three buttons don't fit in one row in every language on a small iPhone.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { kindnessButtons }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        onlyMeButton
                        hideFacesButton
                    }
                    okButton
                }
                VStack(alignment: .leading, spacing: 8) { kindnessButtons }
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

    @ViewBuilder
    private var kindnessButtons: some View {
        onlyMeButton
        hideFacesButton
        okButton
    }

    private var onlyMeButton: some View {
        kindnessButton("Only edit me", foreground: Palette.onAccent, background: Palette.accent) { model.editOnlyMe() }
    }

    private var hideFacesButton: some View {
        kindnessButton("Hide their faces", foreground: Palette.textPrimary, background: Palette.blush) { model.hideTheirFaces() }
    }

    private var okButton: some View {
        kindnessButton("They're OK with it", foreground: Palette.textPrimary, background: Palette.surface, outlined: true) {
            model.dismissKindnessNote()
        }
    }

    /// The whole 44 pt capsule is the button, not just its text.
    private func kindnessButton(_ title: LocalizedStringKey, foreground: Color, background: Color, outlined: Bool = false,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.bold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(background, in: Capsule())
                .overlay(Capsule().strokeBorder(outlined ? Palette.stroke : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .fixedSize()
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
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Report this result")
    }

    // MARK: Tool panel

    @ViewBuilder
    private var toolPanel: some View {
        switch model.activeTool {
        case .magicEdit?:
            // One row of chips at a time: the photo's own ideas replace the examples.
            MagicEditPanel(prompt: $model.magicPrompt, cost: app.credits.cost(of: .magicEdit),
                           showsExamples: !(showsIdeas && ideasShown)) {
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
            CutoutPanel(
                session: model.cutout,
                onStart: { model.startCutout(app: app) },
                onApply: { Task { await model.applyCutout() } },
                onCopySticker: { copySticker() },
                onSaveSticker: { saveSticker() }
            )
        case .hideFaces?:
            HideFacesPanel(hider: model.faceHider) {
                Task { await model.applyHideFaces() }
            }
        case .textStickers?:
            TextStickersPanel(session: model.overlays) {
                Task { await model.applyOverlays() }
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

    /// One row on iPad and the Mac, a scrolling one on iPhone (see `EditorToolBar`).
    private var toolBar: some View {
        EditorToolBar(tools: EditorTool.available(cloudAI: app.allowsCloudAI), activeTool: model.activeTool) { tool in
            model.select(tool)
        }
        // Room for all ten tools in one row on iPad and the Mac in most languages.
        .frame(maxWidth: Metrics.readableWidth)
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
                // Free tools never add a mark; free cloud AI results carry a
                // small one, also after a re-edit of a Create or Library result.
                let provenance = model.provenance
                try await PhotoLibrarySaver.save(model.current, sourceType: provenance.sourceType,
                                                 watermark: provenance.showsMark(isPro: app.purchases.isPro))
                await app.saveToLibrary([model.current], operation: model.appliedOperation, title: model.libraryTitle, prompt: nil,
                                        inheritedSourceType: provenance.storedSourceType)
                app.showToast("Saved to Photos", style: .success)
                Haptics.success()
                if app.registerHappyMoment() {
                    requestReview()
                }
            } catch {
                app.handleSaveError(error, shareInstead: sharePayload)
            }
        }
    }

    private func share() {
        guard !model.isProcessing else { return }
        Haptics.tap()
        Task {
            await model.commitPending()
            app.share(sharePayload)
        }
    }

    private var sharePayload: SharePayload {
        SharePayload(
            image: model.current,
            original: model.hasChanges ? model.before : nil,
            operation: model.appliedOperation,
            prompt: nil,
            isComposite: model.isComposite,
            inheritedSourceType: model.inheritedSourceType
        )
    }

    // MARK: Stickers

    private func copySticker() {
        Task {
            guard let sticker = await model.cutoutSticker(isPro: app.purchases.isPro) else { return }
            UIPasteboard.general.setData(sticker.data, forPasteboardType: UTType.png.identifier)
            Haptics.success()
            app.showToast("Copied, paste it in a chat", style: .success)
        }
    }

    private func saveSticker() {
        Task {
            guard let sticker = await model.cutoutSticker(isPro: app.purchases.isPro) else { return }
            do {
                try await PhotoLibrarySaver.save(data: sticker.data)
                Haptics.success()
                app.showToast("Saved to Photos", style: .success)
            } catch {
                app.handle(error)
            }
        }
    }
}
