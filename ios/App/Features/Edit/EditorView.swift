import SwiftUI
import StoreKit
import AppCore

struct EditorView: View {
    let launch: EditorLaunch

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @State private var model: EditorViewModel
    @State private var shareItem: ShareItem?
    @State private var showDiscardAlert = false
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
                if model.canRetryFree {
                    likenessRetry
                }
                toolPanel
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 8)
                toolBar
            }

            if model.isProcessing {
                GeneratingOverlay(title: model.processingTitle, onCancel: { model.cancelProcessing() })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.isProcessing)
        .animation(.snappy, value: model.activeTool)
        .task {
            // Launched from a template card: run it right away (one-tap).
            if let template = launch.template {
                model.run(.styles, template: template, app: app)
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
                .presentationDetents([.medium, .large])
        }
        .alert("Discard your edits?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Save to Photos first if you want to keep them.")
        }
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

            Spacer()

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

            Spacer()

            Menu {
                Button { save() } label: { Label("Save to Photos", systemImage: "square.and.arrow.down") }
                Button { share() } label: { Label("Share", systemImage: "square.and.arrow.up") }
            } label: {
                HStack(spacing: 6) {
                    if isSaving { ProgressView().tint(Palette.onPrimary) }
                    Text("Save")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Palette.onPrimary)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Palette.brandGradient, in: Capsule())
            }
            .disabled(isSaving)
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
            .onLongPressGesture(minimumDuration: 0.15, maximumDistance: 40, perform: {}, onPressingChanged: { pressing in
                if model.hasChanges { model.isHoldingOriginal = pressing }
            })
            .overlay(alignment: .bottom) {
                if model.hasChanges && !model.isHoldingOriginal {
                    Text("Hold to see original")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.4), in: Capsule())
                        .padding(10)
                }
            }
            .accessibilityLabel(model.isHoldingOriginal ? "Original photo" : "Edited photo")
        }
    }

    /// Likeness Lock: if a people edit doesn't look like the user, retry for free.
    private var likenessRetry: some View {
        Button {
            model.retryFree(app: app)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("Doesn't look like you? Retry free")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Palette.surfaceRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
        .transition(.opacity)
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
                onChange: { model.updateAdjustPreview() },
                onReset: { model.resetAdjustments() },
                onApply: { Task { await model.applyAdjustments() } }
            )
        case nil:
            EmptyView()
        }
    }

    // MARK: Tool bar

    private var toolBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(EditorTool.allCases) { tool in
                    let isActive = model.activeTool == tool
                    Button {
                        model.select(tool)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: tool.symbolName)
                                .font(.system(size: 19, weight: .semibold))
                            Text(tool.title)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(isActive ? Palette.textPrimary : Palette.textTertiary)
                        .frame(width: 72, height: 58)
                        .background(isActive ? Palette.surfaceRaised : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.hidden)
        .padding(.vertical, 8)
        .background(Palette.surface.ignoresSafeArea(edges: .bottom))
    }

    // MARK: Export

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await PhotoLibrarySaver.save(model.current, operation: model.appliedOperation, watermark: !app.purchases.isPro)
                await app.save([model.current], for: AIJob(operation: model.appliedOperation ?? .enhance))
                app.showToast("Saved to Photos", style: .success)
                Haptics.success()
                if app.registerSuccessfulSave() {
                    requestReview()
                }
            } catch {
                app.handle(error)
            }
        }
    }

    private func share() {
        do {
            let url = try ImageExporter.temporaryFile(for: model.current, operation: model.appliedOperation, watermark: !app.purchases.isPro)
            shareItem = ShareItem(url: url)
        } catch {
            app.handle(error)
        }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}
