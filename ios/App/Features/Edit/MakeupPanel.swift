import SwiftUI
import AppCore

/// Makeup Studio: one-tap looks, then a few simple choices (lips, eyes,
/// cheeks, extras, hair color and how strong), tried on her photo as a Magic
/// Edit with the same gates, credits, Likeness Lock and free retry
/// (`EditorViewModel.run(.makeup, …)`). Makeup is play: a look only adds
/// color, shine and sparkle, and her face, skin and features stay hers.
struct MakeupPanel: View {
    @Binding var recipe: MakeupRecipe
    let cost: Int
    let onTry: () -> Void

    @State private var isCustomizing: Bool
    @State private var area: Area
    @Environment(\.editorPanelPlacement) private var placement

    init(recipe: Binding<MakeupRecipe>, cost: Int, onTry: @escaping () -> Void) {
        _recipe = recipe
        self.cost = cost
        self.onTry = onTry
        var customizing = false
        var startArea = Area.lips
        #if DEBUG
        // Screenshot QA: -GLMakeupCustomize lips|eyes|cheeks|extras|hair opens that row.
        if ScreenshotScene.current != nil,
           let name = UserDefaults.standard.string(forKey: "GLMakeupCustomize"), let picked = Area(rawValue: name) {
            customizing = true
            startArea = picked
        }
        #endif
        _isCustomizing = State(initialValue: customizing)
        _area = State(initialValue: startArea)
    }

    enum Area: String, CaseIterable, Identifiable {
        case lips, eyes, cheeks, extras, hair

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .lips: return "Lips"
            case .eyes: return "Eyes"
            case .cheeks: return "Cheeks"
            case .extras: return "Extras"
            case .hair: return "Hair color"
            }
        }

        var symbolName: String {
            switch self {
            case .lips: return "mouth"
            case .eyes: return "eye"
            case .cheeks: return "heart"
            case .extras: return "sparkles"
            case .hair: return "paintpalette"
            }
        }
    }

    /// The look she picked, unless she has changed it since.
    private var look: MakeupPreset? { MakeupStudio.preset(matching: recipe) }

    var body: some View {
        VStack(spacing: 12) {
            looksRow

            DisclosureGroup(isExpanded: $isCustomizing.animation(.snappy)) {
                VStack(spacing: 10) {
                    areaRow
                    choicesRow
                    intensityRow
                }
                .padding(.top, 10)
            } label: {
                Label("Customize", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .tint(Palette.accent)

            Text("Makeup is play. Your face, skin and features stay yours.")
                .font(.legibleCaption)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onTry) {
                CostLabel(title: recipe.isEmpty ? "Pick a look" : "Try it", cost: recipe.isEmpty ? 0 : cost)
            }
            .buttonStyle(.primary)
            .disabled(recipe.isEmpty)
        }
    }

    // MARK: Looks

    private var looksRow: some View {
        Group {
            if placement == .inspector {
                FlowLayout {
                    lookChips
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            lookChips
                        }
                    }
                    .scrollIndicators(.hidden)
                    .onAppear {
                        if let look { proxy.scrollTo(look.id, anchor: .center) }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Makeup looks")
    }

    private var lookChips: some View {
        ForEach(MakeupStudio.presets) { preset in
            MakeupChip(title: L10n.core(preset.name), swatches: preset.swatches, isSelected: look == preset) {
                // Her hair color choice stays when she switches looks.
                withAnimation(.snappy) { recipe = preset.recipe.withHair(recipe.hair) }
                Haptics.selection()
            }
            .id(preset.id)
        }
    }

    // MARK: Customize

    private var areaRow: some View {
        ChipRow {
            ForEach(Area.allCases) { item in
                SelectableChip(title: item.title, symbolName: item.symbolName, isSelected: area == item) {
                    withAnimation(.snappy) { area = item }
                    Haptics.selection()
                }
            }
        }
    }

    @ViewBuilder
    private var choicesRow: some View {
        switch area {
        case .lips: choices(MakeupLips.allCases, selected: recipe.lips) { recipe.lips = $0 }
        case .eyes: choices(MakeupEyes.allCases, selected: recipe.eyes) { recipe.eyes = $0 }
        case .cheeks: choices(MakeupCheeks.allCases, selected: recipe.cheeks) { recipe.cheeks = $0 }
        case .extras: extrasRow
        case .hair: choices(MakeupHair.allCases, selected: recipe.hair) { recipe.hair = $0 }
        }
    }

    /// One choice per row ("As is" first), scrolled to the one she has.
    @ViewBuilder
    private func choices<Choice: MakeupChoice>(_ all: [Choice], selected: Choice, select: @escaping (Choice) -> Void) -> some View {
        let chips = ForEach(all) { choice in
            MakeupChip(title: L10n.core(choice.name), swatches: choice.swatch.map { [$0] } ?? [],
                       isSelected: choice == selected) {
                select(choice)
                Haptics.selection()
            }
            .id(choice.id)
        }
        if placement == .inspector {
            FlowLayout {
                chips
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        chips
                    }
                }
                .scrollIndicators(.hidden)
                .onAppear { proxy.scrollTo(selected.id, anchor: .center) }
            }
        }
    }

    /// Any number of extras.
    private var extrasRow: some View {
        ChipRow {
            ForEach(MakeupExtra.allCases) { extra in
                MakeupChip(title: L10n.core(extra.name), swatches: extra.swatch.map { [$0] } ?? [],
                           isSelected: recipe.extras.contains(extra), isToggle: true) {
                    recipe.toggle(extra)
                    Haptics.selection()
                }
            }
        }
    }

    /// The label sits beside the control when both fit, above it otherwise.
    private var intensityRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                intensityLabel
                intensityPicker
            }
            VStack(alignment: .leading, spacing: 6) {
                intensityLabel
                intensityPicker
            }
        }
    }

    private var intensityLabel: some View {
        Text("Intensity")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.textSecondary)
            .fixedSize()
            .accessibilityHidden(true)
    }

    private var intensityPicker: some View {
        Picker("Intensity", selection: $recipe.intensity) {
            ForEach(MakeupIntensity.allCases) { level in
                Text(L10n.core(level.name)).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// A choice with its color dots: white when idle, blush with an ink edge when
/// picked, like `SelectableChip`.
private struct MakeupChip: View {
    /// Already in her language.
    let title: String
    /// "#RRGGBB"; none shows an empty ring ("As is").
    let swatches: [String]
    let isSelected: Bool
    /// Extras: any number can be on, so a check or a plus says which.
    var isToggle = false
    let action: () -> Void

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // VoiceOver hears the selected trait instead.
                if isToggle {
                    Image(systemName: isSelected ? "checkmark" : "plus")
                        .font(.footnote.weight(.bold))
                        .accessibilityHidden(true)
                } else if isSelected && differentiateWithoutColor {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .accessibilityHidden(true)
                }
                SwatchDots(hexes: swatches, ring: isSelected ? Palette.primary : Palette.surface)
                Text(title)
                    .font(.subheadline.weight(isSelected ? .bold : .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .foregroundStyle(isSelected ? Palette.onPrimary : Palette.textPrimary)
            .background(isSelected ? Palette.primary : Palette.surface, in: .chip)
            // Blush on white is too faint to show selection alone (see SelectableChip).
            .overlay(RoundedRectangle.chip.strokeBorder(isSelected ? Palette.ink : Palette.stroke, lineWidth: isSelected ? 1.5 : 1))
            .animation(Motion.press, value: isSelected)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Overlapping color dots, ringed in the chip's own color so they stay apart.
private struct SwatchDots: View {
    let hexes: [String]
    let ring: Color

    var body: some View {
        HStack(spacing: -5) {
            if hexes.isEmpty {
                Circle()
                    .strokeBorder(Palette.textTertiary, lineWidth: 1.5)
                    .frame(width: 14, height: 14)
            }
            ForEach(Array(hexes.enumerated()), id: \.offset) { _, hex in
                Circle()
                    .fill(Color(uiColor: UIColor(hexString: hex) ?? .clear))
                    .overlay(Circle().stroke(Palette.ink.opacity(0.12), lineWidth: 0.5))
                    .frame(width: 14, height: 14)
                    .padding(1.5)
                    .background(ring, in: Circle())
            }
        }
        .accessibilityHidden(true)
    }
}
