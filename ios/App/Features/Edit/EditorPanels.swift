import SwiftUI
import AppCore

/// "Describe your edit" — prompt-based editing with quick suggestions.
struct MagicEditPanel: View {
    @Binding var prompt: String
    let cost: Int
    /// Off while "Ideas for this photo" shows its own chips above.
    var showsExamples = true
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.editorPanelPlacement) private var placement

    private let suggestions = [
        String(localized: "Golden hour light", comment: "Example Magic Edit request on a chip; tapping it fills the prompt"),
        String(localized: "Give me pink hair", comment: "Example Magic Edit request on a chip; tapping it fills the prompt"),
        String(localized: "Add soft glam makeup", comment: "Example Magic Edit request on a chip; tapping it fills the prompt"),
        String(localized: "Put me in a pink dress", comment: "Example Magic Edit request on a chip; tapping it fills the prompt"),
        String(localized: "Add cherry blossoms", comment: "Example Magic Edit request on a chip; tapping it fills the prompt"),
        String(localized: "Add sparkles everywhere", comment: "Example Magic Edit request on a chip; tapping it fills the prompt"),
        String(localized: "Make it a watercolor", comment: "Example Magic Edit request on a chip; tapping it fills the prompt"),
        String(localized: "Make it snow", comment: "Example Magic Edit request on a chip; tapping it fills the prompt"),
        String(localized: "Add a rainbow", comment: "Example Magic Edit request on a chip; tapping it fills the prompt"),
        String(localized: "Turn it into anime", comment: "Example Magic Edit request on a chip; tapping it fills the prompt"),
        String(localized: "Add fairy lights", comment: "Example Magic Edit request on a chip; tapping it fills the prompt"),
        String(localized: "Remove the people behind me", comment: "Example Magic Edit request on a chip; tapping it fills the prompt"),
    ]

    private var canSubmit: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        isFocused = false
        onSubmit()
    }

    var body: some View {
        VStack(spacing: 12) {
            if showsExamples && placement == .bar {
                examples
                    .transition(.opacity)
            }

            promptRow
            Text("\(cost) credit per edit · failed edits are refunded")
                .font(.legibleCaption2)
                .foregroundStyle(Palette.textTertiary)

            if showsExamples && placement == .inspector {
                examples
                    .padding(.top, 4)
                    .transition(.opacity)
            }
        }
    }

    private var examples: some View {
        ChipRow {
            ForEach(suggestions, id: \.self) { suggestion in
                SelectableChip(title: LocalizedStringKey(suggestion), isSelected: prompt == suggestion) {
                    prompt = suggestion
                    Haptics.selection()
                }
            }
        }
    }

    private var promptRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Describe your edit…", text: $prompt, axis: .vertical)
                .lineLimit(1...3)
                .focused($isFocused)
                .submitLabel(.go)
                // A multi-line field turns Go (Return) into a newline
                // instead of submitting, so a trailing one sends.
                .onChange(of: prompt) { _, text in
                    guard text.contains("\n") else { return }
                    let pressedGo = text.hasSuffix("\n")
                    prompt = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                    if pressedGo { submit() }
                }
                .onSubmit(submit)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Palette.surface, in: .card)
                .overlay(
                    RoundedRectangle.card
                        .strokeBorder(isFocused ? Palette.accent : Palette.strokeStrong, lineWidth: isFocused ? 1.5 : 1)
                )
            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(canSubmit ? Palette.onAccent : Palette.textTertiary)
                    .frame(width: 46, height: 46)
                    .background(canSubmit ? Palette.accent : Palette.strokeStrong, in: Circle())
            }
            .disabled(!canSubmit)
            .accessibilityLabel("Apply edit")
            .macHelp("Apply edit")
        }
    }
}

/// One-tap templates inside the editor.
struct StylesPanel: View {
    let isPro: Bool
    /// Her region's seasons lead the looks while they're on.
    var audience: SeasonAudience = .everyone
    let onSelect: (PhotoTemplate) -> Void

    @Environment(\.editorPanelPlacement) private var placement

    var body: some View {
        if placement == .inspector {
            // Two big cards a row in the Mac's inspector.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                cards(fillingWidth: true)
            }
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    cards(fillingWidth: false)
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private func cards(fillingWidth: Bool) -> some View {
        ForEach(TemplateCatalog.editorOrder(on: AppClock.now, for: audience)) { template in
            Button {
                select(template)
            } label: {
                if fillingWidth {
                    GeometryReader { proxy in
                        TemplateCard(template: template, width: proxy.size.width, height: proxy.size.height, showsLock: template.isPro && !isPro)
                    }
                    .aspectRatio(3 / 4, contentMode: .fit)
                } else {
                    TemplateCard(template: template, width: 104, height: 136, showsLock: template.isPro && !isPro)
                }
            }
            .buttonStyle(.pressable)
            .macHoverLift(scale: 1.03)
            .macTryLookMenu { select(template) }
        }
    }

    private func select(_ template: PhotoTemplate) {
        Haptics.tap()
        onSelect(template)
    }
}

/// Explanation + single action for Enhance and Remove Background.
struct OneTapPanel: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let buttonTitle: LocalizedStringKey
    let cost: Int
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text(message)
                    .font(.legibleFootnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            Button(action: action) {
                CostLabel(title: buttonTitle, cost: cost)
            }
            .buttonStyle(.primary)
        }
    }
}

struct ErasePanel: View {
    @Binding var brushSize: CGFloat
    let hasStrokes: Bool
    /// "Pick a person": a tap adds a person or thing to the erase area.
    let isPicking: Bool
    /// Vision is still looking for people and things.
    let isFindingSubjects: Bool
    let cost: Int
    let onTogglePicking: () -> Void
    let onUndoStroke: () -> Void
    let onClear: () -> Void
    let onErase: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                SelectableChip(title: "Pick a person", symbolName: "person.crop.circle.badge.minus", isSelected: isPicking,
                               action: onTogglePicking)
                if isPicking {
                    Image(systemName: isFindingSubjects ? "hourglass" : "hand.tap")
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                    Group {
                        if isFindingSubjects {
                            Text("Finding people and things…", comment: "Erase: shown while the device looks for people and things she can tap to remove")
                        } else {
                            Text(MaskCanvas.pickHint)
                        }
                    }
                    .font(.legibleFootnote.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .animation(.snappy, value: isPicking)
            HStack(spacing: 12) {
                Image(systemName: "circle.fill").font(.system(size: 8))
                    .foregroundStyle(Palette.textSecondary)
                Slider(value: $brushSize, in: 0.02...0.16)
                    .tint(Palette.accent)
                    .accessibilityLabel("Brush size")
                Image(systemName: "circle.fill").font(.system(size: 20))
                    .foregroundStyle(Palette.textSecondary)
                Button(action: onUndoStroke) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.icon)
                .disabled(!hasStrokes)
                .accessibilityLabel("Undo stroke")
                .macHelp("Undo stroke")
                Button(action: onClear) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.icon)
                .disabled(!hasStrokes)
                .accessibilityLabel("Clear brush")
                .macHelp("Clear brush")
            }
            Button(action: onErase) {
                CostLabel(title: hasStrokes ? "Erase selection" : "Brush over an object", cost: hasStrokes ? cost : 0)
            }
            .buttonStyle(.primary)
            .disabled(!hasStrokes)
        }
    }
}

/// Light, colour and vibe sliders with one-tap vibes above them, rendered on
/// the device for free. A vibe only sets sliders, so she can tweak it.
struct AdjustPanel: View {
    @Binding var settings: AdjustmentSettings
    /// The vibe she picked, if any; its values are on the sliders.
    let vibe: AdjustVibe?
    /// Her saved filters ("My filters"), shown before the vibes.
    let myFilters: MyFiltersStore
    let onMyFilter: (MyFilter) -> Void
    let onAuto: () -> Void
    let onVibe: (AdjustVibe) -> Void
    let onChange: () -> Void
    let onReset: () -> Void
    let onApply: () -> Void

    @State private var selected: AdjustmentParameter
    /// Naming a new filter, or renaming one of hers.
    @State private var naming: Naming?
    @State private var name = ""
    @State private var showsFullShelf = false
    @Environment(\.editorPanelPlacement) private var placement

    private enum Naming: Equatable {
        case new
        case rename(MyFilter)
    }

    init(settings: Binding<AdjustmentSettings>, vibe: AdjustVibe?, myFilters: MyFiltersStore, onMyFilter: @escaping (MyFilter) -> Void,
         onAuto: @escaping () -> Void, onVibe: @escaping (AdjustVibe) -> Void, onChange: @escaping () -> Void,
         onReset: @escaping () -> Void, onApply: @escaping () -> Void) {
        _settings = settings
        self.vibe = vibe
        self.myFilters = myFilters
        self.onMyFilter = onMyFilter
        self.onAuto = onAuto
        self.onVibe = onVibe
        self.onChange = onChange
        self.onReset = onReset
        self.onApply = onApply
        var first = vibe?.lead ?? .brightness
        #if DEBUG
        // Screenshot QA: -GLAdjustParameter <slider> (e.g. tint) shows that slider.
        if ScreenshotScene.current != nil, let name = UserDefaults.standard.string(forKey: "GLAdjustParameter"),
           let parameter = AdjustmentParameter(rawValue: name) {
            first = parameter
        }
        #endif
        _selected = State(initialValue: first)
    }

    var body: some View {
        VStack(spacing: 12) {
            vibesRow
            parametersRow
            slider

            ButtonRow {
                Button("Reset", action: onReset)
                    .buttonStyle(.secondary)
                    .disabled(settings.isNeutral)
            } primary: {
                Button("Apply", action: onApply)
                    .buttonStyle(.primary)
                    .disabled(settings.isNeutral)
            }
        }
        // A vibe turns to the slider it's about.
        .onChange(of: vibe) { _, picked in
            guard let picked else { return }
            withAnimation(.snappy) { selected = picked.lead }
        }
        .alert(naming == .new ? Text("Name your filter") : Text("Rename filter"), isPresented: Binding(
            get: { naming != nil },
            set: { if !$0 { naming = nil } }
        )) {
            TextField("Filter name", text: $name)
            Button("Save") { finishNaming() }
            Button("Cancel", role: .cancel) { naming = nil }
        } message: {
            if naming == .new {
                Text("Use it on any photo, any time. It stays on this device.")
            }
        }
        .alert("Your filters are full", isPresented: $showsFullShelf) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can keep up to \(MyFilterShelf.limit) filters. Delete one to save a new one.")
        }
    }

    // MARK: Auto and vibes

    private var vibesRow: some View {
        ChipRow {
            Button(action: onAuto) {
                Label("Auto", systemImage: "wand.and.sparkles")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.onAccent)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Palette.accent, in: .pill)
            }
            .buttonStyle(.pressable)
            .accessibilityHint("Picks the best light and colour for this photo")
            if canSave {
                saveChip
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            ForEach(myFilters.filters) { filter in
                myFilterChip(filter)
            }
            ForEach(AdjustVibes.all) { item in
                SelectableChip(title: LocalizedStringKey(L10n.core(item.name)), symbolName: item.symbolName, isSelected: vibe == item) {
                    onVibe(item)
                }
                .accessibilityHint(Text("Sets several sliders at once. Tap it again to take it off.",
                                        comment: "Accessibility hint of a one-tap vibe (Dreamy, Analog…) in the editor's Adjust tool"))
            }
        }
    }

    // MARK: My filters

    /// Something to save that isn't saved yet.
    private var canSave: Bool {
        !settings.isNeutral && myFilters.shelf.filter(matching: settings) == nil
    }

    private var saveChip: some View {
        Button {
            guard !myFilters.shelf.isFull else {
                showsFullShelf = true
                return
            }
            name = myFilters.shelf.suggestedName(base: String(localized: "My filter", comment: "Suggested name of a saved Adjust filter, followed by a number"))
            naming = .new
        } label: {
            Label("Save as my filter", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Palette.surface.opacity(0.6), in: .chip)
                .overlay(RoundedRectangle.chip.strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
        .buttonStyle(.pressable)
        .accessibilityHint(Text("Saves these sliders under a name, to put on any photo with one tap",
                                comment: "Accessibility hint of Save as my filter in the editor's Adjust tool"))
    }

    private func myFilterChip(_ filter: MyFilter) -> some View {
        SelectableChip(verbatim: filter.name, symbolName: "heart", isSelected: settings == filter.settings) {
            onMyFilter(filter)
        }
        .contextMenu {
            Button { beginRenaming(filter) } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) { delete(filter) } label: { Label("Delete", systemImage: "trash") }
        }
        .accessibilityHint(Text("Your saved filter. Tap it again to take it off.",
                                comment: "Accessibility hint of one of her saved filters in the editor's Adjust tool"))
        .accessibilityAction(named: Text("Rename")) { beginRenaming(filter) }
        .accessibilityAction(named: Text("Delete")) { delete(filter) }
    }

    private func beginRenaming(_ filter: MyFilter) {
        name = filter.name
        naming = .rename(filter)
    }

    private func delete(_ filter: MyFilter) {
        withAnimation(.snappy) { myFilters.delete(filter) }
        Haptics.selection()
    }

    private func finishNaming() {
        defer { naming = nil }
        switch naming {
        case .new?:
            // Left empty: the suggested name.
            let chosen = MyFilterShelf.cleanName(name)
                ?? myFilters.shelf.suggestedName(base: String(localized: "My filter", comment: "Suggested name of a saved Adjust filter, followed by a number"))
            let result = withAnimation(.snappy) {
                myFilters.save(name: chosen, settings: settings, vibe: vibe)
            }
            switch result {
            case .saved: Haptics.success()
            case .full: showsFullShelf = true
            case .emptyName, .duplicate, .neutral: break
            }
        case .rename(let filter)?:
            withAnimation(.snappy) { _ = myFilters.rename(filter, to: name) }
        case nil:
            break
        }
    }

    // MARK: Sliders

    @ViewBuilder
    private var parametersRow: some View {
        if placement == .inspector {
            FlowLayout {
                parameterChips
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        parameterChips
                    }
                }
                .scrollIndicators(.hidden)
                .onAppear { proxy.scrollTo(selected, anchor: .center) }
                .onChange(of: selected) { _, parameter in
                    withAnimation(.snappy) { proxy.scrollTo(parameter, anchor: .center) }
                }
            }
        }
    }

    private var parameterChips: some View {
        ForEach(AdjustmentParameter.allCases) { parameter in
            SelectableChip(title: LocalizedStringKey(parameter.title), symbolName: parameter.symbol, isSelected: selected == parameter) {
                selected = parameter
                Haptics.selection()
            }
            .id(parameter)
        }
    }

    private var slider: some View {
        let value = Binding(
            get: { settings[selected] },
            set: { newValue in
                settings[selected] = newValue
                onChange()
            }
        )
        return Group {
            if selected == .tint {
                // The two ends are colours: pink on the left, lilac on the right.
                Slider(value: value, in: selected.range) {
                    Text(selected.title)
                } minimumValueLabel: {
                    tintDot(Color(hex: 0xE58BA8))
                } maximumValueLabel: {
                    tintDot(Color(hex: 0xB49BE0))
                }
                .accessibilityHint(Text("Left is pinker, right is more lilac.",
                                        comment: "Accessibility hint of the Tint slider in the editor's Adjust tool"))
            } else {
                Slider(value: value, in: selected.range)
            }
        }
        .tint(Palette.accent)
        .accessibilityLabel(selected.title)
    }

    private func tintDot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .overlay(Circle().stroke(Palette.ink.opacity(0.12), lineWidth: 0.5))
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)
    }
}

private extension AdjustmentParameter {
    var title: String {
        switch self {
        case .brightness: return String(localized: "Brightness")
        case .contrast: return String(localized: "Contrast")
        case .highlights: return String(localized: "Highlights", comment: "Adjust slider: makes the brightest parts of the photo lighter or darker")
        case .shadows: return String(localized: "Shadows", comment: "Adjust slider: makes the darkest parts of the photo lighter or darker")
        case .saturation: return String(localized: "Saturation")
        case .warmth: return String(localized: "Warmth")
        case .tint: return String(localized: "Tint", comment: "Adjust slider: a pink or lilac color cast over the photo")
        case .glow: return String(localized: "Glow", comment: "Adjust slider: soft light that glows from the bright parts of the photo")
        case .fade: return String(localized: "Fade", comment: "Adjust slider: lifts the blacks for a faded, matte film look")
        case .grain: return String(localized: "Grain", comment: "Adjust slider: film grain texture")
        case .vignette: return String(localized: "Vignette")
        case .sharpness: return String(localized: "Sharpness")
        }
    }

    var symbol: String {
        switch self {
        case .brightness: return "sun.max"
        case .contrast: return "circle.lefthalf.filled"
        case .highlights: return "sun.max.circle"
        case .shadows: return "moon.circle"
        case .saturation: return "drop"
        case .warmth: return "thermometer.medium"
        case .tint: return "swatchpalette"
        case .glow: return "sun.haze"
        case .fade: return "camera.filters"
        case .grain: return "aqi.medium"
        case .vignette: return "circle.dashed"
        case .sharpness: return "triangle"
        }
    }
}

/// Retro effects: live thumbnails of her own photo, the effect's one switch
/// (date stamp, border, letterbox or camera info), Film Still's subtitle,
/// DSLR '12's lens, and Apply.
struct EffectsPanel: View {
    let thumbnails: [RetroEffect: UIImage]
    let selected: RetroEffect?
    /// An effect still getting ready on the photo (DSLR '12 while Vision
    /// looks for her): its tile shows progress.
    var working: RetroEffect?
    @Binding var showsExtra: Bool
    @Binding var subtitle: String
    @Binding var lens: DSLRLens
    let onSelect: (RetroEffect) -> Void
    let onReset: () -> Void
    let onApply: () -> Void

    @Environment(\.editorPanelPlacement) private var placement

    var body: some View {
        VStack(spacing: 12) {
            if placement == .inspector {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8, alignment: .top)], spacing: 12) {
                    ForEach(RetroEffect.allCases) { effect in
                        effectButton(effect)
                    }
                }
            } else {
                effectsRow
            }

            if let option = selected?.option {
                Toggle(isOn: $showsExtra) {
                    Label { Text(option.label) } icon: { Image(systemName: option.symbolName) }
                        .font(.subheadline.weight(.semibold))
                }
                .tint(Palette.accent)
            }

            if selected?.takesLens == true {
                lensRow
            }

            if selected?.takesSubtitle == true {
                TextField(text: $subtitle) {
                    Text("Add a subtitle (optional)", comment: "Placeholder of the Film Still effect's one-line subtitle field")
                }
                .accessibilityLabel(Text("Subtitle", comment: "Accessibility label of the Film Still effect's subtitle field"))
                .submitLabel(.done)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Palette.petal, in: .control)
            }

            ButtonRow {
                Button("Reset", action: onReset)
                    .buttonStyle(.secondary)
                    .disabled(selected == nil)
            } primary: {
                Button("Apply", action: onApply)
                    .buttonStyle(.primary)
                    .disabled(selected == nil)
            }
            Text("Free for everyone · on your device · no credits")
                .font(.legibleCaption2)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    /// 85 mm blurs the background most, 35 mm least.
    private var lensRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.aperture")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)
            ForEach(DSLRLens.allCases) { option in
                SelectableChip(title: "\(option.focalLength) mm", isSelected: lens == option) {
                    guard lens != option else { return }
                    lens = option
                    Haptics.selection()
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Lens", comment: "Label of DSLR '12's lens choice (85, 50 or 35 mm) in the editor's Effects"))
    }

    private var effectsRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(RetroEffect.allCases) { effect in
                        effectButton(effect)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            // An effect picked elsewhere (an idea, a deep link) may sit past the edge.
            .onAppear {
                if let selected { proxy.scrollTo(selected, anchor: .center) }
            }
            .onChange(of: selected) { _, effect in
                guard let effect else { return }
                withAnimation(.snappy) { proxy.scrollTo(effect, anchor: .center) }
            }
        }
    }

    private func effectButton(_ effect: RetroEffect) -> some View {
        Button {
            onSelect(effect)
        } label: {
            EffectTile(effect: effect, thumbnail: thumbnails[effect], isSelected: selected == effect, isWorking: working == effect)
        }
        .buttonStyle(.pressable)
        .macHoverLift(scale: 1.04)
        .id(effect)
    }
}

private struct EffectTile: View {
    let effect: RetroEffect
    let thumbnail: UIImage?
    let isSelected: Bool
    var isWorking = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Palette.petal
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                }
                if thumbnail == nil || isWorking {
                    if thumbnail != nil { Palette.white.opacity(0.45) }
                    ProgressView().tint(Palette.accent)
                }
            }
            .frame(width: 76, height: 96)
            .clipShape(.print)
            .overlay(
                RoundedRectangle.print
                    .strokeBorder(isSelected ? Palette.accent : Palette.stroke, lineWidth: isSelected ? 3 : 1)
            )
            .overlay(alignment: .topLeading) {
                Text(effect.era)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Palette.ink.opacity(0.7))
                    .padding(4)
            }
            .shadow(color: Palette.shadow, radius: 6, y: 3)
            Text(effect.title)
                .font(.legibleCaption2.weight(isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 80)
        .animation(Motion.select, value: isSelected)
        .selectionPop(isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(effect.title), \(effect.era)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Crop: posting shapes, a quarter turn left, mirror and straighten. Free,
/// on-device geometry only (uniform scaling, never a stretch).
struct CropPanel: View {
    let aspect: CropAspect
    @Binding var angle: Double
    let canApply: Bool
    let onAspect: (CropAspect) -> Void
    let onRotate: () -> Void
    let onFlip: () -> Void
    let onReset: () -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ChipRow {
                ForEach(CropAspect.allCases) { option in
                    SelectableChip(title: title(of: option), symbolName: symbol(of: option), isSelected: aspect == option) {
                        onAspect(option)
                    }
                }
            }

            HStack(spacing: 10) {
                Button(action: onRotate) { Image(systemName: "rotate.left") }
                    .buttonStyle(.icon)
                    .accessibilityLabel("Rotate left")
                    .macHelp("Rotate left")
                Button(action: onFlip) { Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                    .buttonStyle(.icon)
                    .accessibilityLabel("Flip horizontally")
                    .macHelp("Flip horizontally")
                Slider(
                    value: Binding(
                        get: { angle },
                        set: { angle = CropGeometry.snappedAngle($0) }
                    ),
                    in: -CropGeometry.maxAngle...CropGeometry.maxAngle
                )
                .tint(Palette.accent)
                .accessibilityLabel("Straighten")
                .accessibilityValue(Text("\(Int(angle.rounded())) degrees"))
                .sensoryFeedback(.alignment, trigger: angle == 0) { _, isLevel in isLevel }
                Text(verbatim: "\(Int(angle.rounded()))°")
                    .font(.legibleFootnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 36, alignment: .trailing)
                    .accessibilityHidden(true)
            }

            ButtonRow {
                Button("Reset", action: onReset)
                    .buttonStyle(.secondary)
                    .disabled(!canApply)
            } primary: {
                Button("Apply", action: onApply)
                    .buttonStyle(.primary)
                    .disabled(!canApply)
            }
        }
    }

    private func title(of option: CropAspect) -> LocalizedStringKey {
        switch option {
        case .original: return "Original"
        // The crop shape, not the price.
        case .free: return "Freeform"
        default:
            guard let ratio = option.ratio else { return "" }
            return LocalizedStringKey(String("\(ratio.width):\(ratio.height)"))
        }
    }

    private func symbol(of option: CropAspect) -> String {
        switch option {
        case .original: return "photo"
        case .free: return "crop"
        case .square: return "square"
        case .portrait: return "rectangle.portrait"
        case .story: return "rectangle.ratio.9.to.16"
        case .landscape: return "rectangle.ratio.16.to.9"
        }
    }
}
