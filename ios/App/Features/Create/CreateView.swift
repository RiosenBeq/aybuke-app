import SwiftUI
import AppCore

struct CreateView: View {
    @Environment(AppModel.self) private var app
    @State private var model = CreateViewModel()
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(styled: "Create *anything*", size: 28)
                            .foregroundStyle(Palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("Describe it, pick a vibe — we'll handle the magic words.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                    }

                    if app.isCloudOffline {
                        OfflineNotice()
                    }

                    promptCard
                        .tourAnchor(.create)
                    styleSection
                    ratioSection
                    countSection
                    if #available(iOS 18.4, *) {
                        ImagePlaygroundCreateButton(prompt: model.prompt) { image in
                            model.finishPlayground(image, app: app)
                        }
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 12)
                .padding(.bottom, 120)
                .readableWidth()
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(AuroraBackground(intensity: 0.3))
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { generateBar }
            .navigationDestination(isPresented: $model.showResults) {
                ResultsView(
                    images: model.results,
                    prompt: model.resultsSource == nil ? model.prompt : nil,
                    operation: .textToImage,
                    requestID: model.requestID,
                    source: model.resultsSource
                )
            }
            .overlay {
                if model.isGenerating {
                    GeneratingOverlay(title: model.count > 1 ? String(localized: "Creating \(model.count) images…") : String(localized: "Creating your image…"), offersReadyPing: true) {
                        model.cancel()
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: model.isGenerating)
            .animation(.easeInOut(duration: 0.2), value: model.undoPrompt)
            .onAppear { app.writer.prewarm() }
            #if DEBUG
            .onAppear {
                guard let scene = ScreenshotScene.current, scene == .create || scene == .results, model.prompt.isEmpty else { return }
                model.prompt = ScreenshotFixtures.createPrompt
                model.style = StyleCatalog.style(id: "pastel")
                if scene == .results {
                    model.results = ScreenshotFixtures.generatedArt(count: 3)
                    model.showResults = true
                }
                // QA: `-GLWriterAction magic|inspire` runs a writer chip once.
                switch UserDefaults.standard.string(forKey: "GLWriterAction") {
                case "magic":
                    model.prompt = "a cat in the snow"
                    model.enhancePrompt(writer: app.writer)
                case "inspire": model.inspire(writer: app.writer)
                default: break
                }
            }
            #endif
        }
    }

    // MARK: Sections

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("A dreamy pastel bedroom with fairy lights and a canopy bed…", text: $model.prompt, axis: .vertical)
                .lineLimit(4...8)
                .focused($isPromptFocused)
                .font(.body)
                .foregroundStyle(Palette.textPrimary)

            HStack(alignment: .top, spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { writerChips }
                    VStack(alignment: .leading, spacing: 8) { writerChips }
                }
                Spacer(minLength: 0)
                // The spinner takes the clear button's slot, so the chips don't move.
                if model.isWriting {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: 32, minHeight: 32)
                        .accessibilityLabel("Writing…")
                } else if !model.prompt.isEmpty {
                    Button {
                        model.prompt = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.textTertiary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Clear prompt")
                }
            }

            if model.undoPrompt != nil || model.isPromptFromModel {
                HStack(spacing: 8) {
                    if model.isPromptFromModel {
                        Label("Written on your device by Apple Intelligence", systemImage: "sparkles")
                            .labelStyle(WriterCaptionLabelStyle())
                    }
                    Spacer(minLength: 0)
                    if model.undoPrompt != nil {
                        Button("Undo") { model.undoEnhance() }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                            .accessibilityHint("Brings back what you wrote before")
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(16)
        .cardStyle()
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(isPromptFocused ? Palette.accent : Color.clear, lineWidth: 1.5)
        )
    }

    /// "Inspire me" and the prompt upgrade. With Apple's on-device model the
    /// upgrade is "Make it magic"; without it, the offline enhancer.
    @ViewBuilder
    private var writerChips: some View {
        SelectableChip(title: "Inspire me", symbolName: "sparkles", isSelected: false) {
            model.inspire(writer: app.writer)
        }
        .accessibilityHint("Fills in a new idea for your picture")
        if app.writer.isAvailable {
            SelectableChip(title: "Make it magic", symbolName: "wand.and.stars", isSelected: false) {
                model.enhancePrompt(writer: app.writer)
            }
            .disabled(model.prompt.isEmpty)
            .accessibilityHint("Rewrites your idea with more detail. You can undo it.")
        } else {
            SelectableChip(title: "Enhance prompt", symbolName: "wand.and.stars", isSelected: false) {
                model.enhancePrompt(writer: app.writer)
            }
            .disabled(model.prompt.isEmpty)
        }
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Style")
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(StyleCatalog.all.enumerated()), id: \.element.id) { index, style in
                        StyleTile(
                            name: L10n.core(style.name),
                            symbolName: style.symbolName,
                            tone: PaletteTone.at(index),
                            isSelected: model.style == style,
                            isLocked: style.isPro && !app.purchases.isPro
                        ) {
                            Haptics.selection()
                            model.style = style
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private var ratioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Size")
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(AspectRatio.allCases) { ratio in
                        SelectableChip(title: LocalizedStringKey(L10n.core(ratio.label) + " " + ratio.rawValue), isSelected: model.aspectRatio == ratio) {
                            Haptics.selection()
                            model.aspectRatio = ratio
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var countSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Images", subtitle: "Generate up to 4 variations with Pro")
            HStack(spacing: 8) {
                ForEach(1...4, id: \.self) { number in
                    SelectableChip(
                        title: "\(number)",
                        isSelected: model.count == number,
                        isLocked: number > 1 && !app.purchases.isPro
                    ) {
                        Haptics.selection()
                        model.count = number
                    }
                }
            }
        }
    }

    private var generateBar: some View {
        Button {
            isPromptFocused = false
            model.generate(app: app)
        } label: {
            CostLabel(title: "Generate", cost: app.credits.cost(of: .textToImage, outputs: model.count), isLoading: model.isGenerating)
        }
        .buttonStyle(.primary)
        .disabled(!model.canGenerate)
        .keyboardShortcut(.return, modifiers: .command)
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .readableWidth(Metrics.compactWidth, alignment: .center)
        .background(
            LinearGradient(colors: [Palette.background.opacity(0), Palette.background], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        )
    }
}

/// The small "written by Apple Intelligence" note under the prompt.
private struct WriterCaptionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
        .font(.caption)
        .foregroundStyle(Palette.textSecondary)
    }
}
