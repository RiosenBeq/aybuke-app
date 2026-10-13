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

                    promptCard
                        .tourAnchor(.create)
                    styleSection
                    ratioSection
                    countSection
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
                ResultsView(images: model.results, prompt: model.prompt, operation: .textToImage, requestID: model.requestID)
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
            #if DEBUG
            .onAppear {
                guard let scene = ScreenshotScene.current, scene == .create || scene == .results, model.prompt.isEmpty else { return }
                model.prompt = ScreenshotFixtures.createPrompt
                model.style = StyleCatalog.style(id: "pastel")
                if scene == .results {
                    model.results = ScreenshotFixtures.generatedArt(count: 3)
                    model.showResults = true
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

            HStack(spacing: 8) {
                SelectableChip(title: "Inspire me", symbolName: "sparkles", isSelected: false) {
                    model.surpriseMe()
                }
                SelectableChip(title: "Enhance prompt", symbolName: "wand.and.stars", isSelected: false) {
                    model.enhancePrompt()
                }
                .disabled(model.prompt.isEmpty)
                Spacer()
                if !model.prompt.isEmpty {
                    Button {
                        model.prompt = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .accessibilityLabel("Clear prompt")
                }
            }
        }
        .padding(16)
        .cardStyle()
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(isPromptFocused ? Palette.accent : Color.clear, lineWidth: 1.5)
        )
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
