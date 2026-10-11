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
                        Text("Create")
                            .font(.screenTitle)
                            .foregroundStyle(Palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("Describe anything. We'll handle the magic words.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                    }

                    promptCard
                    styleSection
                    ratioSection
                    countSection
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(AuroraBackground(intensity: 0.3))
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { generateBar }
            .navigationDestination(isPresented: $model.showResults) {
                ResultsView(images: model.results, prompt: model.prompt, operation: .textToImage)
            }
            .overlay {
                if model.isGenerating {
                    GeneratingOverlay(title: "Creating \(model.count > 1 ? "\(model.count) images" : "your image")…") {
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
                model.style = StyleCatalog.style(id: "cinematic")
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
            TextField("A cozy cabin in a snowy forest at dusk, warm lights in the windows…", text: $model.prompt, axis: .vertical)
                .lineLimit(4...8)
                .focused($isPromptFocused)
                .font(.body)
                .foregroundStyle(Palette.textPrimary)

            HStack(spacing: 8) {
                SelectableChip(title: "Surprise me", symbolName: "dice", isSelected: false) {
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
                .strokeBorder(isPromptFocused ? Palette.primary.opacity(0.6) : Color.clear, lineWidth: 1.5)
        )
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Style")
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(StyleCatalog.all) { style in
                        StyleSwatchChip(
                            name: style.name,
                            colors: style.swatch.gradientColors,
                            symbolName: style.symbolName,
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
        }
    }

    private var ratioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Size")
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(AspectRatio.allCases) { ratio in
                        SelectableChip(title: "\(ratio.label) \(ratio.rawValue)", isSelected: model.aspectRatio == ratio) {
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
        .background(
            LinearGradient(colors: [Palette.background.opacity(0), Palette.background], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        )
    }
}
