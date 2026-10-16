import SwiftUI
import AppCore

struct CreateView: View {
    @Environment(AppModel.self) private var app
    @State private var model: CreateViewModel
    @State private var showsCredits = false
    @FocusState private var isPromptFocused: Bool
    /// Mac: the page's width, to split it into the form and a preview.
    @State private var pageWidth: CGFloat = 0

    /// The Mac keeps one model in its window, so a draft, a running job and
    /// its results survive switching sections.
    init(model: CreateViewModel? = nil) {
        _model = State(initialValue: model ?? CreateViewModel())
    }

    /// Mac: the form on the left and the picture on the right, once the
    /// window is wide enough; a narrow window gets the single column.
    private var usesColumns: Bool {
        Platform.isMac && pageWidth >= Metrics.macColumnsWidth
    }

    var body: some View {
        NavigationStack {
            Group {
                if usesColumns {
                    macColumns
                } else {
                    singleColumn
                }
            }
            // In the preview column on a wide Mac window, pushed otherwise.
            .navigationDestination(isPresented: Binding(
                get: { model.showResults && !usesColumns },
                set: { model.showResults = $0 }
            )) {
                results(isEmbedded: false)
            }
            // Either way the layout switches, a result pushed by the old layout
            // must not come back unasked when the window is resized. iPhone
            // never switches, so its flow is unchanged.
            .onChange(of: usesColumns) { _, _ in
                model.showResults = false
            }
            .animation(.easeInOut(duration: 0.2), value: model.undoPrompt)
            .animation(.snappy, value: model.prompt.isEmpty)
            .sheet(isPresented: $showsCredits) {
                CreditsSheet()
                    .environment(app)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(Palette.background)
                    .macSheet(.form)
            }
            .onAppear {
                app.writer.prewarm()
                // Her draft survives leaving the tab (and the app).
                if model.prompt.isEmpty, !app.prompts.draft.isEmpty { model.prompt = app.prompts.draft }
            }
            .onChange(of: model.prompt) { _, prompt in app.prompts.draft = prompt }
            // File › New Creation on the Mac: the cursor goes to the prompt.
            .task(id: app.wantsPromptFocus) {
                guard app.wantsPromptFocus else { return }
                app.wantsPromptFocus = false
                try? await Task.sleep(for: .milliseconds(150))
                isPromptFocused = true
            }
            #if DEBUG
            .onAppear {
                guard let scene = ScreenshotScene.current, scene == .create || scene == .results, model.prompt.isEmpty else { return }
                // `-GLPrompt <text>`: the prompt in the screenshot's language.
                model.prompt = UserDefaults.standard.string(forKey: "GLPrompt") ?? ScreenshotFixtures.createPrompt
                model.style = StyleCatalog.style(id: "pastel")
                if scene == .results {
                    // After the first layout, so a wide Mac window shows them in
                    // its preview column instead of pushing them.
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        model.showScreenshotResults(ScreenshotFixtures.createResults)
                    }
                }
                // QA: `-GLWriterAction magic|inspire` runs a writer chip once
                // (with `-GLAssistStub YES`, the server's writing help answers).
                switch UserDefaults.standard.string(forKey: "GLWriterAction") {
                case "magic":
                    model.prompt = "a cat in the snow"
                    model.enhancePrompt(app: app)
                case "inspire": model.inspire(app: app)
                default: break
                }
            }
            #endif
        }
        .modifier(MacPageWidthReader(width: $pageWidth))
        // Over the results too, so Regenerate shows the same progress.
        .overlay {
            ZStack {
                if model.isGenerating {
                    GeneratingOverlay(title: model.count > 1 ? String(localized: "Creating \(model.count) images…") : String(localized: "Creating your image…"), offersReadyPing: true) {
                        model.cancel()
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: model.isGenerating)
        }
    }

    // MARK: Layouts

    /// iPhone, iPad and a narrow Mac window: one column with the Generate
    /// bar floating at the bottom.
    private var singleColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                header

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
            .padding(.horizontal, Metrics.pageGutter)
            .padding(.top, 12)
            .padding(.bottom, 120)
            .readableWidth(Metrics.pageWidth)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(AuroraBackground(intensity: 0.3))
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { generateBar }
    }

    /// A wide Mac window: the form scrolls on the left, with Generate at its
    /// end; the picture (or where it will appear) stays in view on the right.
    private var macColumns: some View {
        HStack(alignment: .top, spacing: 36) {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    header
                    if app.isCloudOffline {
                        OfflineNotice()
                    }
                    promptCard
                        .tourAnchor(.create)
                    styleSection
                    ratioSection
                    countSection
                    VStack(spacing: 0) {
                        generateButton
                        creditsLink
                    }
                    if #available(iOS 18.4, *) {
                        ImagePlaygroundCreateButton(prompt: model.prompt) { image in
                            model.finishPlayground(image, app: app)
                        }
                    }
                }
                .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
            .frame(width: Self.macFormWidth)

            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 24)
        }
        .padding(.horizontal, Metrics.pageGutter)
        .frame(maxWidth: Metrics.pageWidth)
        .frame(maxWidth: .infinity)
        .background(AuroraBackground(intensity: 0.3))
        .toolbar(.hidden, for: .navigationBar)
    }

    private static let macFormWidth: CGFloat = 540

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(styled: "Create *anything*", size: 25)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Describe it, pick a vibe — we'll handle the magic words.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private func results(isEmbedded: Bool) -> some View {
        ResultsView(
            images: model.results,
            prompt: model.resultsSource == nil ? (model.resultsJob?.prompt ?? model.prompt) : nil,
            operation: .textToImage,
            requestID: model.requestID,
            source: model.resultsSource,
            regenerate: model.resultsJob.map { job in
                ResultsView.Regenerate(cost: app.credits.cost(of: .textToImage, outputs: job.numOutputs)) {
                    model.regenerate(app: app)
                }
            },
            isEmbedded: isEmbedded
        )
    }

    /// The latest pictures, or a frame in the chosen size where they'll appear.
    @ViewBuilder
    private var preview: some View {
        if model.results.isEmpty {
            CreatePreviewPlaceholder(ratio: model.aspectRatio, style: model.style)
        } else {
            results(isEmbedded: true)
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
                    .macHelp("Clear prompt")
                }
            }

            if model.undoPrompt != nil || model.isPromptFromModel {
                HStack(spacing: 8) {
                    switch model.promptWriter {
                    case .cloud?:
                        Label("Written by Aybik, our AI helper", systemImage: "sparkles")
                            .labelStyle(WriterCaptionLabelStyle())
                    case .device?:
                        Label("Written on your device by Apple Intelligence", systemImage: "sparkles")
                            .labelStyle(WriterCaptionLabelStyle())
                    case nil:
                        EmptyView()
                    }
                    Spacer(minLength: 0)
                    if model.undoPrompt != nil {
                        Button("Undo") { model.undoEnhance() }
                            .font(.legibleFootnote.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                            .accessibilityHint("Brings back what you wrote before")
                    }
                }
                .transition(.opacity)
            }

            if model.prompt.isEmpty && !app.prompts.recent.isEmpty {
                recentPrompts
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

    /// Her last prompts, only while the box is empty. Kept on this device only.
    private var recentPrompts: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Recent", systemImage: "clock.arrow.circlepath")
                    .labelStyle(WriterCaptionLabelStyle())
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button("Clear") {
                    Haptics.selection()
                    withAnimation(.snappy) { app.prompts.clear() }
                }
                .font(.legibleFootnote.weight(.semibold))
                .foregroundStyle(Palette.accent)
                .accessibilityLabel("Clear recent prompts")
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(app.prompts.recent, id: \.self) { recent in
                        RecentPromptChip(text: recent) { model.useRecent(recent) }
                            .contextMenu {
                                Button(role: .destructive) {
                                    withAnimation(.snappy) { app.prompts.remove(recent) }
                                } label: {
                                    Label("Remove from recent", systemImage: "xmark")
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            // Scrolls edge to edge inside the card.
            .padding(.horizontal, -16)
        }
    }

    /// "Inspire me" and the prompt upgrade. With a model to write it (the
    /// server's writing help, or Apple's on-device model) the upgrade is
    /// "Make it magic"; without one, the offline enhancer.
    @ViewBuilder
    private var writerChips: some View {
        SelectableChip(title: "Inspire me", symbolName: "sparkles", isSelected: false) {
            model.inspire(app: app)
        }
        .accessibilityHint("Fills in a new idea for your picture")
        if app.usesCloudWriter || app.writer.isAvailable {
            SelectableChip(title: "Make it magic", symbolName: "wand.and.stars", isSelected: false) {
                model.enhancePrompt(app: app)
            }
            .disabled(model.prompt.isEmpty)
            .accessibilityHint("Rewrites your idea with more detail. You can undo it.")
        } else {
            SelectableChip(title: "Enhance prompt", symbolName: "wand.and.stars", isSelected: false) {
                model.enhancePrompt(app: app)
            }
            .disabled(model.prompt.isEmpty)
        }
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Style")
            if Platform.isMac {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6, alignment: .top)], alignment: .leading, spacing: 14) {
                    styleTiles
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        styleTiles
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
    }

    private var styleTiles: some View {
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
            .macHoverLift(scale: 1.04)
        }
    }

    private var ratioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Size")
            if Platform.isMac {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ratioChips
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ratioChips
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var ratioChips: some View {
        ForEach(AspectRatio.allCases) { ratio in
            SelectableChip(title: LocalizedStringKey(L10n.core(ratio.label) + " " + ratio.rawValue), isSelected: model.aspectRatio == ratio) {
                Haptics.selection()
                model.aspectRatio = ratio
            }
        }
    }

    private var countSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Images", subtitle: "Generate up to 4 variations with Pro")
            // One row when the chips fit; with large text it scrolls instead
            // of pushing the page wider than the screen.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { countChips }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) { countChips }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private var countChips: some View {
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

    private var generateButton: some View {
        Button {
            isPromptFocused = false
            model.generate(app: app)
        } label: {
            CostLabel(title: "Generate", cost: app.credits.cost(of: .textToImage, outputs: model.count), isLoading: model.isGenerating)
        }
        .buttonStyle(.primary)
        .disabled(!model.canGenerate)
        .keyboardShortcut(.return, modifiers: .command)
    }

    private var generateBar: some View {
        VStack(spacing: 0) {
            generateButton
            creditsLink
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 10)
        .readableWidth(Metrics.compactWidth, alignment: .center)
        .background(
            // A short fade above the button, then solid behind it and the
            // balance line, so nothing scrolled shows through either.
            LinearGradient(stops: [.init(color: Palette.background.opacity(0), location: 0),
                                   .init(color: Palette.background, location: 0.16)],
                           startPoint: .top, endPoint: .bottom)
                // Down to the tab bar too, so section titles don't peek
                // through the gap between the button and the tabs.
                .padding(.bottom, -32)
                .ignoresSafeArea()
        )
    }

    /// Her balance next to the price, so she knows before she taps; a tap
    /// explains credits and when they refill.
    private var creditsLink: some View {
        Button {
            Haptics.tap()
            showsCredits = true
        } label: {
            Label("\(app.credits.balance) credits left", systemImage: app.purchases.isPro ? "crown.fill" : "bolt.fill")
                .font(.legibleCaption.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
                .contentTransition(.numericText(value: Double(app.credits.balance)))
                .animation(Motion.bouncy, value: app.credits.balance)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows your credits and how they work")
    }
}

/// Where Create's pictures will appear on a wide Mac window: a frame in the
/// chosen size with the chosen style's swatch.
private struct CreatePreviewPlaceholder: View {
    let ratio: AspectRatio
    let style: ImageStyle

    var body: some View {
        let index = StyleCatalog.all.firstIndex(of: style) ?? 0
        let tone = PaletteTone.at(index)
        VStack(spacing: 14) {
            Image(systemName: style.symbolName)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(tone.foreground)
                .frame(width: 76, height: 76)
                .background(tone.fill, in: .control)
                .overlay(RoundedRectangle.control.strokeBorder(Palette.stroke, lineWidth: 1))
            Text("Your picture appears here")
                .font(.cardTitle)
                .foregroundStyle(Palette.textPrimary)
            Text(verbatim: "\(L10n.core(style.name)) · \(L10n.core(ratio.label)) \(ratio.rawValue)")
                .font(.legibleFootnote)
                .foregroundStyle(Palette.textSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface.opacity(0.55), in: .card)
        .overlay(RoundedRectangle.card.strokeBorder(Palette.strokeStrong, style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])))
        .aspectRatio(ratio.widthOverHeight, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy, value: ratio)
        .accessibilityElement(children: .combine)
    }
}

/// Mac: reads a page's width for layouts that split into columns. Nothing
/// on iPhone and iPad. A preference rather than `onGeometryChange`, which is
/// iOS 18 while the app targets iOS 17 (macOS 14 on the Mac).
struct MacPageWidthReader: ViewModifier {
    @Binding var width: CGFloat

    func body(content: Content) -> some View {
        if Platform.isMac {
            content
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: PageWidthKey.self, value: proxy.size.width)
                    }
                }
                .onPreferenceChange(PageWidthKey.self) { width = $0 }
        } else {
            content
        }
    }
}

private struct PageWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// One of her recent prompts; long ones are cut short.
private struct RecentPromptChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: 220, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Palette.surfaceRaised, in: .chip)
                .overlay(RoundedRectangle.chip.strokeBorder(Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityHint("Puts this prompt back in the box")
    }
}

/// The small "written by" note under the prompt (Claude or Apple Intelligence).
private struct WriterCaptionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
        .font(.legibleCaption)
        .foregroundStyle(Palette.textSecondary)
    }
}
