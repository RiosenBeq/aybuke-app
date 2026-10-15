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
    /// The "2×" badge's number while it shows (nil at fit).
    @State private var zoomBadge: Double?
    @State private var showsZoomBadge = false
    /// Focus mode: one tap on the photo hides the bars, another brings them back.
    @State private var isFocused = false
    @State private var ideasDismissed = false
    @State private var ideasShown = false
    /// Mac: the window's width, for the inspector beside the photo.
    @State private var editorWidth: CGFloat = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(launch: EditorLaunch) {
        self.launch = launch
        _model = State(initialValue: EditorViewModel(launch: launch))
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            Group {
                if usesInspector {
                    inspectorLayout
                } else {
                    stackedLayout
                }
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
        .modifier(MacPageWidthReader(width: $editorWidth))
        .animation(.easeInOut(duration: 0.25), value: model.isProcessing)
        .animation(.snappy, value: model.activeTool)
        .task {
            model.stampsDemoResults = app.isDemoMode
            #if DEBUG
            if ScreenshotScene.current == .cutout { model.startCutout(app: app) }
            // Screenshot QA of "Pick a person": -GLErasePick x,y (normalized).
            if ScreenshotScene.current == .erase, let pick = UserDefaults.standard.string(forKey: "GLErasePick") {
                let parts = pick.split(separator: ",").compactMap { Double($0) }
                model.clearMask()
                model.toggleErasePicking(app: app)
                for _ in 0..<100 where model.eraseSubjects == nil && model.isPickingToErase {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                if parts.count == 2 { model.pickToErase(at: CGPoint(x: parts[0], y: parts[1]), app: app) }
            }
            // Screenshot QA of the full-size render: -GLOverlayApply YES.
            if ScreenshotScene.current == .textStickers, UserDefaults.standard.bool(forKey: "GLOverlayApply") {
                try? await Task.sleep(for: .seconds(1.5))
                await model.applyOverlays()
            }
            // Screenshot QA: -GLFocusMode YES hides the bars, -GLHoldOriginal YES
            // shows the original as a held finger would.
            if ScreenshotScene.current != nil {
                if UserDefaults.standard.bool(forKey: "GLFocusMode") { isFocused = true }
                if UserDefaults.standard.bool(forKey: "GLHoldOriginal") {
                    try? await Task.sleep(for: .seconds(1))
                    model.isHoldingOriginal = true
                }
            }
            #endif
            await model.checkForOtherPeople()
        }
        #if DEBUG || GL_PERF
        .onAppear { PerfProbe.editorAppeared() }
        #endif
        // Edit › Undo and Redo on the Mac reach this editor's history, File ›
        // Save (⌘S) saves it, and File › Close (⌘W) asks like its close button.
        .onAppear {
            app.activeEditor = model
            app.saveActiveCover = { save() }
            registerClose()
        }
        .onChange(of: isUnderAppSheet) { _, _ in registerClose() }
        // A new tool starts at fit, with every bar in view.
        .onChange(of: model.activeTool) { _, _ in
            isFocused = false
            zoomBadge = nil
            showsZoomBadge = false
        }
        .onChange(of: model.isProcessing) { _, processing in
            if processing { isFocused = false }
        }
        .task(id: zoomBadge) {
            // The badge says the zoom, then fades.
            guard zoomBadge != nil else { return }
            #if DEBUG
            if ScreenshotScene.current != nil, UserDefaults.standard.double(forKey: "GLCanvasZoom") > 1 { return }
            #endif
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { showsZoomBadge = false }
        }
        .onDisappear {
            if app.activeEditor === model {
                app.activeEditor = nil
                app.saveActiveCover = nil
                app.closeActiveCover = nil
            }
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

    // MARK: Layouts

    /// A wide Mac window: the tool's panel in an inspector beside the photo.
    private var usesInspector: Bool {
        Platform.isMac && editorWidth >= Self.inspectorMinimumWidth
    }

    /// Room for the photo and the whole tool bar in one row beside it.
    private static let inspectorMinimumWidth: CGFloat = 1180
    private static let inspectorWidth: CGFloat = 380

    /// iPhone, iPad and a narrow Mac window: the photo, then the tool's
    /// panel and the tool bar under it.
    private var stackedLayout: some View {
        VStack(spacing: 0) {
            topBar
                .disabled(model.isProcessing)
                // Typing covers it, and so does focus mode; only its
                // shortcuts (Esc, ⌘S) stay.
                .opacity(isTypingOverlayText || isFocused ? 0 : 1)
                .allowsHitTesting(!isFocused)
                .background { applyShortcut }
            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay { SparkleBurst(trigger: model.celebration) }
            if !isFocused {
                stackedPanels
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: isFocused)
    }

    /// Under the photo: the kindness note, a result's retry, ideas, the
    /// tool's panel and the tool bar. Focus mode hides them all.
    private var stackedPanels: some View {
        VStack(spacing: 0) {
            Group {
                if model.showsKindnessNote && !model.isProcessing {
                    kindnessNote
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if model.lastRequestID != nil && !model.isProcessing {
                    resultActions
                }
                if showsIdeas {
                    ideasRow
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.bottom, 6)
                }
                toolPanel
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 8)
                    .disabled(model.isProcessing)
            }
            // The panels keep their full height (large text grows them);
            // the photo above gives up the room instead of squeezing them.
            .fixedSize(horizontal: false, vertical: true)
            .readableWidth(Metrics.compactWidth, alignment: .center)
            toolBar
                .disabled(model.isProcessing)
        }
    }

    /// One tap on the photo hides the bars (iPhone, iPad and a narrow Mac
    /// window); tools that use taps themselves keep them.
    private func toggleFocus() {
        guard !usesInspector, !model.isProcessing else { return }
        isFocused.toggle()
        Haptics.tap()
    }

    /// A wide Mac window: the photo keeps the middle with the tool bar under
    /// it, and the tool's panel (with ideas, the kindness note and a result's
    /// retry) sits in an inspector on the right, like the Mac's own editors.
    private var inspectorLayout: some View {
        VStack(spacing: 0) {
            topBar
                .disabled(model.isProcessing)
                .opacity(isTypingOverlayText ? 0 : 1)
                .background { applyShortcut }
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    canvas
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .overlay { SparkleBurst(trigger: model.celebration) }
                    toolBar
                        .disabled(model.isProcessing)
                }
                inspector
                    .frame(width: Self.inspectorWidth)
                    .padding(.top, 8)
                    .padding(.trailing, Metrics.gutter)
                    .padding(.bottom, 12)
            }
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let tool = model.activeTool {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.title)
                        .font(.sectionTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(tool.caption)
                        .font(.legibleFootnote)
                        .foregroundStyle(Palette.textSecondary)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 10)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.showsKindnessNote && !model.isProcessing {
                        kindnessNote
                            .transition(.opacity)
                    }
                    if model.lastRequestID != nil && !model.isProcessing {
                        resultActions
                    }
                    if showsIdeas {
                        ideasRow
                    }
                    toolPanel
                        .disabled(model.isProcessing)
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.automatic)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.surface.opacity(0.7), in: .card)
        .overlay(RoundedRectangle.card.strokeBorder(Palette.stroke, lineWidth: 1))
        .shadow(color: Palette.shadow, radius: 14, y: 6)
        .environment(\.editorPanelPlacement, .inspector)
    }

    private var ideasRow: some View {
        EditorIdeasRow(model: model, onShown: { ideasShown = true }) {
            withAnimation(.snappy) { ideasDismissed = true }
        }
    }

    /// Ideas stay out of the way: hidden under a fresh cloud result or the
    /// kindness note, and in the hands-on Crop, Erase, Hide faces and Cut out
    /// (an effect from the row would commit their preview mid-task). Makeup
    /// Studio brings its own looks. Kept, disabled, while a job runs, so
    /// "Surprise me" remembers where it was.
    private var showsIdeas: Bool {
        guard !ideasDismissed, model.lastRequestID == nil, !model.showsKindnessNote else { return false }
        switch model.activeTool {
        case .crop?, .erase?, .hideFaces?, .removeBackground?, .textStickers?, .makeup?: return false
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
                .macHelp("Undo")
                .padKeyboardShortcut("z")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(.icon)
                .disabled(!model.canRedo)
                .opacity(model.canRedo ? 1 : 0.4)
                .accessibilityLabel("Redo")
                .macHelp("Redo")
                .padKeyboardShortcut("z", modifiers: [.command, .shift])
            Button { model.isComparing.toggle() } label: {
                Image(systemName: model.isComparing ? "square.split.2x1.fill" : "square.split.2x1")
            }
            .buttonStyle(.icon)
            .disabled(!canCompare)
            .opacity(canCompare ? 1 : 0.4)
            .accessibilityLabel("Compare with original")
            .macHelp("Compare with original")

            Spacer(minLength: 0)

            Button { share() } label: { Image(systemName: "paperplane.fill") }
                .buttonStyle(.icon)
                .accessibilityLabel("Share")
                .macHelp("Share")
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
            .padKeyboardShortcut("s")
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
        .background(Palette.accent, in: .chip)
        .fixedSize()
    }

    /// ⌘Return: sends the Magic Edit prompt or the makeup look, or applies the
    /// previewed effect, adjustment or crop. Hidden; the visible buttons do the same.
    private var applyShortcut: some View {
        Button("Apply") {
            if model.activeTool == .magicEdit {
                guard !model.magicPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                model.run(.magicEdit, app: app)
            } else if model.activeTool == .makeup {
                guard !model.makeup.isEmpty else { return }
                model.run(.makeup, app: app)
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
            requestClose()
        } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(.icon)
        .accessibilityLabel("Close editor")
        .macHelp("Close editor")
    }

    private func requestClose() {
        // A typed but unsent prompt counts too, so Esc can't lose it.
        let hasTypedPrompt = model.activeTool == .magicEdit && !model.magicPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if model.hasUnsavedWork || hasTypedPrompt { showDiscardAlert = true } else { dismiss() }
    }

    /// One of the app's sheets is over the editor. ⌘W then leaves the editor
    /// alone: with the paywall up it still closes the paywall, as before.
    private var isUnderAppSheet: Bool {
        app.isPaywallPresented || app.outOfCredits != nil || app.consentRequest != nil
            || app.shareRequest != nil || app.isAccountPromptPresented || app.isBestShotPresented
    }

    private func registerClose() {
        app.closeActiveCover = isUnderAppSheet ? nil : { requestClose() }
    }

    private var isCropPending: Bool {
        if case .crop? = model.pendingPreview { return true }
        return false
    }

    /// Crop shows the whole photo under its box, so there's nothing to
    /// compare; Text & Stickers needs the canvas for its own gestures.
    private var canCompare: Bool { model.hasChanges && model.activeTool != .crop && model.activeTool != .textStickers }

    /// Holding the photo shows the original once anything changed, a
    /// previewed effect or adjustment included.
    private var canHoldForOriginal: Bool { model.hasChanges || model.pendingPreview != nil }

    // MARK: Canvas

    @ViewBuilder
    private var canvas: some View {
        if model.activeTool == .erase {
            MaskCanvas(
                image: model.current, strokes: model.strokes, regions: model.eraseRegions, brushSize: model.brushSize,
                subjects: model.eraseSubjects?.subjects ?? [],
                onPick: model.isPickingToErase ? { point in model.pickToErase(at: point, app: app) } : nil,
                onPickSubject: { model.pickToErase(subject: $0) }
            ) { stroke in
                model.addEraseStroke(stroke)
            }
        } else if model.activeTool == .hideFaces {
            HideFacesCanvas(image: model.displayImage, hider: model.faceHider)
        } else if model.activeTool == .removeBackground && model.cutout.isActive {
            CutoutCanvas(session: model.cutout, fallback: model.current)
        } else if model.activeTool == .textStickers {
            TextStickersCanvas(image: model.current, session: model.overlays)
        } else if model.activeTool == .crop, let proxy = model.cropProxy {
            CropCanvas(image: proxy, geometry: $model.crop, aspect: model.cropAspect, sourceSize: model.cropSourceSize)
                .clipShape(.control)
                .shadow(color: Palette.shadow, radius: 16, y: 8)
        } else if model.isComparing && canCompare {
            BeforeAfterSlider(before: model.before, after: model.current, showsTransparencyGrid: model.hasTransparency)
                .clipShape(.control)
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
                        if canHoldForOriginal || !pressing { model.isHoldingOriginal = pressing }
                    },
                    onZoomChange: { isZoomed = $0 },
                    onScale: { scale in
                        let value = CanvasZoomMath.badgeValue(for: Double(scale))
                        guard value != zoomBadge else { return }
                        zoomBadge = value
                        withAnimation(.easeOut(duration: 0.15)) { showsZoomBadge = value != nil }
                    },
                    onTap: usesInspector ? nil : { toggleFocus() }
                )
                // A fresh canvas (fit) for every tool and every step.
                .id("\(model.activeTool?.rawValue ?? "")-\(model.historyVersion)")
                .surpriseReveal(id: model.revealVersion == model.historyVersion ? model.revealID : nil)
                .onDisappear { isZoomed = false }
            }
            .aspectRatio(model.displayImage.size.width / max(model.displayImage.size.height, 1), contentMode: .fit)
            .clipShape(.control)
            .shadow(color: Palette.shadow, radius: 16, y: 8)
            .overlay(alignment: .bottom) {
                if canHoldForOriginal && !model.isHoldingOriginal && !isZoomed && !isFocused {
                    canvasPill(Text("Hold to see original"))
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .top) {
                if model.isHoldingOriginal {
                    canvasPill(Text("Original"))
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .topTrailing) {
                if showsZoomBadge, let zoomBadge {
                    canvasPill(Text(verbatim: zoomBadge.formatted(.number.precision(.fractionLength(0...1))) + "×"))
                        .monospacedDigit()
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .animation(.easeOut(duration: 0.15), value: model.isHoldingOriginal)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.isHoldingOriginal ? "Original photo" : "Edited photo")
            .accessibilityAddTraits(.isImage)
            .accessibilityZoomAction { action in
                zoom.step(zoomIn: action.direction == .zoomIn)
            }
            .accessibilityAction(named: isFocused ? Text("Show tools", comment: "VoiceOver action on the editor's photo: brings back the bars focus mode hid")
                                                  : Text("Hide tools", comment: "VoiceOver action on the editor's photo: focus mode, only the photo on screen")) {
                toggleFocus()
            }
        }
    }

    /// A small dark label on the photo ("Hold to see original", "Original", "2×").
    private func canvasPill(_ text: Text) -> some View {
        text
            .font(.legibleCaption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Palette.ink.opacity(reduceTransparency ? 0.9 : 0.65), in: .tag)
            .padding(10)
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
                        .font(.legibleFootnote.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Palette.blush.opacity(0.55), in: .control)
                .padding(.horizontal, Metrics.gutter)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 8) {
                if model.likeness == .stillYou {
                    Label("Still you", systemImage: "checkmark.seal.fill")
                        .font(.legibleFootnote.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Palette.blush, in: .chip)
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
            .font(.legibleFootnote.weight(.semibold))
            .foregroundStyle(emphasised ? Palette.onAccent : Palette.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(emphasised ? Palette.accent : Palette.surface, in: .chip)
            .overlay(RoundedRectangle.chip.strokeBorder(emphasised ? Color.clear : Palette.stroke, lineWidth: 1))
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
                    .font(.legibleFootnote.weight(.semibold))
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
        .background(Palette.surface, in: .card)
        .overlay(RoundedRectangle.card.strokeBorder(Palette.stroke, lineWidth: 1))
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
                .font(.legibleFootnote.weight(.bold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(background, in: .chip)
                .overlay(RoundedRectangle.chip.strokeBorder(outlined ? Palette.stroke : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .fixedSize()
    }

    private var reportButton: some View {
        Button {
            showReport = true
        } label: {
            Image(systemName: "flag")
                .font(.legibleFootnote.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 34, height: 34)
                .background(Palette.surface, in: Circle())
                .overlay(Circle().strokeBorder(Palette.stroke, lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Report this result")
        .macHelp("Report this result")
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
        case .makeup?:
            // A Magic Edit underneath, so it costs what one does. "Describe
            // your vibe" only while the server's writing help is on for her.
            MakeupPanel(
                recipe: $model.makeup,
                cost: app.credits.cost(of: .magicEdit),
                describeVibe: app.usesCloudWriter ? { [model] vibe in await app.suggestMakeup(for: vibe, current: model.makeup) } : nil
            ) {
                model.run(.makeup, app: app)
            }
        case .styles?:
            StylesPanel(isPro: app.purchases.isPro) { template in
                model.run(.styles, template: template, app: app)
            }
        case .enhance?:
            OneTapPanel(
                title: "AI Enhance",
                message: Platform.isMac ? "Unblur, sharpen details and restore faces in one click." : "Unblur, sharpen details and restore faces in one tap.",
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
                hasStrokes: model.hasEraseMask,
                isPicking: model.isPickingToErase,
                isFindingSubjects: model.isFindingSubjects,
                cost: app.credits.cost(of: .eraseObject),
                onTogglePicking: { model.toggleErasePicking(app: app) },
                onUndoStroke: { model.undoStroke() },
                onClear: { model.clearMask() },
                onErase: { model.run(.erase, app: app) }
            )
        case .adjust?:
            AdjustPanel(
                settings: $model.adjustments,
                vibe: model.adjustVibe,
                myFilters: app.myFilters,
                onMyFilter: { model.applyMyFilter($0) },
                onAuto: { model.autoAdjust() },
                onVibe: { model.pickVibe($0) },
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
                lens: Binding(
                    get: { model.effectLens },
                    set: { lens in
                        model.effectLens = lens
                        if let effect = model.effect { model.previewEffect(effect) }
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
        // Room for all eleven tools in one row on iPad and the Mac in most languages.
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
                // Free members: an ad may follow once the editor closes, never inside it.
                app.ads.noteFinishedExport()
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
