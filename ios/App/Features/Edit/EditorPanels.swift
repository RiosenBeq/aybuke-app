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
        ForEach(TemplateCatalog.editorOrder(on: AppClock.now)) { template in
            Button {
                Haptics.tap()
                onSelect(template)
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
            .buttonStyle(.plain)
            .macHoverLift(scale: 1.03)
        }
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
    let cost: Int
    let onUndoStroke: () -> Void
    let onClear: () -> Void
    let onErase: () -> Void

    var body: some View {
        VStack(spacing: 12) {
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

/// Classic manual adjustments, rendered on device for free.
struct AdjustPanel: View {
    @Binding var settings: AdjustmentSettings
    let onAuto: () -> Void
    let onChange: () -> Void
    let onReset: () -> Void
    let onApply: () -> Void

    @State private var selected: Parameter = .brightness

    enum Parameter: String, CaseIterable, Identifiable {
        case brightness, contrast, saturation, warmth, sharpness, vignette

        var id: String { rawValue }

        var title: String {
            switch self {
            case .brightness: return String(localized: "Brightness")
            case .contrast: return String(localized: "Contrast")
            case .saturation: return String(localized: "Saturation")
            case .warmth: return String(localized: "Warmth")
            case .sharpness: return String(localized: "Sharpness")
            case .vignette: return String(localized: "Vignette")
            }
        }

        var symbol: String {
            switch self {
            case .brightness: return "sun.max"
            case .contrast: return "circle.lefthalf.filled"
            case .saturation: return "drop"
            case .warmth: return "thermometer.medium"
            case .sharpness: return "triangle"
            case .vignette: return "circle.dashed"
            }
        }

        var range: ClosedRange<Double> {
            switch self {
            case .brightness: return -0.3...0.3
            case .contrast: return 0.7...1.4
            case .saturation: return 0...2
            case .warmth: return -1...1
            case .sharpness: return 0...1
            case .vignette: return 0...1
            }
        }

        var keyPath: WritableKeyPath<AdjustmentSettings, Double> {
            switch self {
            case .brightness: return \.brightness
            case .contrast: return \.contrast
            case .saturation: return \.saturation
            case .warmth: return \.warmth
            case .sharpness: return \.sharpness
            case .vignette: return \.vignette
            }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            ChipRow {
                    Button(action: onAuto) {
                        Label("Auto", systemImage: "wand.and.sparkles")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Palette.onAccent)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(Palette.accent, in: .chip)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityHint("Picks the best light and colour for this photo")
                    ForEach(Parameter.allCases) { parameter in
                        SelectableChip(title: LocalizedStringKey(parameter.title), symbolName: parameter.symbol, isSelected: selected == parameter) {
                            selected = parameter
                            Haptics.selection()
                        }
                    }
            }

            Slider(
                value: Binding(
                    get: { settings[keyPath: selected.keyPath] },
                    set: { newValue in
                        settings[keyPath: selected.keyPath] = newValue
                        onChange()
                    }
                ),
                in: selected.range
            )
            .tint(Palette.accent)
            .accessibilityLabel(selected.title)

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
    }
}

/// Retro effects: live thumbnails of her own photo, the effect's one switch
/// (date stamp, border, letterbox or camera info), Film Still's subtitle,
/// and Apply.
struct EffectsPanel: View {
    let thumbnails: [RetroEffect: UIImage]
    let selected: RetroEffect?
    @Binding var showsExtra: Bool
    @Binding var subtitle: String
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
            EffectTile(effect: effect, thumbnail: thumbnails[effect], isSelected: selected == effect)
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

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Palette.petal
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView().tint(Palette.accent)
                }
            }
            .frame(width: 76, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.printRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.printRadius)
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
                .font(.caption2.weight(isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 80)
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
                    .font(.footnote.weight(.semibold).monospacedDigit())
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
