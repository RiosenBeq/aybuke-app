import SwiftUI
import AppCore

/// Makeup Studio: one-tap looks, then a few simple choices (lips, eyes,
/// cheeks, extras, hair color and how strong), tried on her photo as a Magic
/// Edit with the same gates, credits, Likeness Lock and free retry
/// (`EditorViewModel.run(.makeup, …)`). Makeup is play: a look only adds
/// color, shine and sparkle, and her face, skin and features stay hers.
///
/// "Describe your vibe" turns her words into these choices with the
/// server's writing help (`AppModel.suggestMakeup`); she checks them on the
/// chips before Try it. It's there only while that help is on for her
/// (`describeVibe` is nil otherwise, and the panel is as before).
struct MakeupPanel: View {
    @Binding var recipe: MakeupRecipe
    let cost: Int
    var describeVibe: ((String) async -> MakeupVibeOutcome)?
    let onTry: () -> Void

    @State private var isCustomizing: Bool
    @State private var area: Area
    /// Counts the looks set from her words, so the row scrolls to each.
    @State private var suggestions = 0
    @Environment(\.editorPanelPlacement) private var placement

    init(recipe: Binding<MakeupRecipe>, cost: Int, describeVibe: ((String) async -> MakeupVibeOutcome)? = nil,
         onTry: @escaping () -> Void) {
        _recipe = recipe
        self.cost = cost
        self.describeVibe = describeVibe
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

        /// The first row a suggested look sets, to open Customize on it.
        static func first(changedIn recipe: MakeupRecipe) -> Area? {
            if recipe.lips != .none { return .lips }
            if recipe.eyes != .none { return .eyes }
            if recipe.cheeks != .none { return .cheeks }
            if !recipe.extras.isEmpty { return .extras }
            return recipe.hair != .none ? .hair : nil
        }
    }

    /// The look she picked, unless she has changed it since.
    private var look: MakeupPreset? { MakeupStudio.preset(matching: recipe) }

    var body: some View {
        VStack(spacing: 12) {
            if let describeVibe {
                MakeupVibeField(describe: describeVibe) { suggested in
                    withAnimation(.snappy) {
                        recipe = suggested
                        isCustomizing = true
                        area = Area.first(changedIn: suggested) ?? area
                    }
                    suggestions += 1
                }
                .transition(.opacity)
            }

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
                    // A look picked from her words comes into view.
                    .onChange(of: suggestions) { _, _ in
                        if let look { withAnimation(.snappy) { proxy.scrollTo(look.id, anchor: .center) } }
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
            .font(.legibleFootnote.weight(.semibold))
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

/// "Describe your vibe": a field with a small sparkle button. Her words pass
/// the content policy on the device first (`AppModel.suggestMakeup`), then
/// the picks land on the chips below with the writer's note; nothing is
/// tried, and no credit used, until she taps Try it.
private struct MakeupVibeField: View {
    let describe: (String) async -> MakeupVibeOutcome
    let onSuggested: (MakeupRecipe) -> Void

    @State private var text = ""
    @State private var isWorking = false
    @State private var status: Status?
    @FocusState private var isFocused: Bool

    private enum Status: Equatable {
        /// Picks are on the chips; the writer's line about them, if it passed.
        case suggested(note: String?)
        /// Why nothing changed, in her language.
        case message(String)
    }

    /// Long enough for a vibe, short of the server's limit.
    private static let maxLength = 200

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            field
            if let status {
                statusLine(status)
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: status)
        #if DEBUG
        // Screenshot QA: -GLMakeupVibe "<words>" types them and asks once.
        .task {
            guard ScreenshotScene.current != nil, text.isEmpty, status == nil,
                  let vibe = UserDefaults.standard.string(forKey: "GLMakeupVibe") else { return }
            text = vibe
            try? await Task.sleep(for: .milliseconds(300))
            submit()
        }
        #endif
    }

    private static let placeholder: LocalizedStringKey = "Describe your vibe, like “soft winter party glam”"

    private var field: some View {
        HStack(alignment: .center, spacing: 6) {
            ZStack(alignment: .topLeading) {
                // A field's own placeholder stays on one line and cuts the
                // example short in longer languages; this one wraps.
                if text.isEmpty {
                    Text(Self.placeholder)
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .placeholderText))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                textField
            }
            .padding(.leading, 14)
            .padding(.vertical, 11)
            sparkleButton
                .padding(.trailing, 2)
        }
        .background(Palette.surface, in: .card)
        .overlay(
            RoundedRectangle.card
                .strokeBorder(isFocused ? Palette.accent : Palette.strokeStrong, lineWidth: isFocused ? 1.5 : 1)
        )
    }

    private var textField: some View {
        TextField("", text: $text, axis: .vertical)
            .lineLimit(1...2)
            .font(.subheadline)
            .foregroundStyle(Palette.textPrimary)
            .focused($isFocused)
            .submitLabel(.go)
            .accessibilityLabel(Text(Self.placeholder))
            // A multi-line field turns Go (Return) into a newline instead of
            // submitting (see MagicEditPanel), so a trailing one sends.
            .onChange(of: text) { _, newText in
                var cleaned = newText
                let pressedGo = cleaned.hasSuffix("\n")
                if cleaned.contains("\n") {
                    cleaned = cleaned.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                }
                if cleaned.count > Self.maxLength { cleaned = String(cleaned.prefix(Self.maxLength)) }
                if cleaned != newText { text = cleaned }
                if pressedGo { submit() }
            }
            .onSubmit(submit)
    }

    private var sparkleButton: some View {
        Button(action: submit) {
            ZStack {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Palette.onAccent)
                } else {
                    Image(systemName: "sparkles")
                        .font(.subheadline.weight(.bold))
                }
            }
            .foregroundStyle(canSubmit || isWorking ? Palette.onAccent : Palette.textTertiary)
            .frame(width: 34, height: 34)
            .background(canSubmit || isWorking ? Palette.accent : Palette.strokeStrong, in: Circle())
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .disabled(!canSubmit)
        .accessibilityLabel("Find a look for my vibe")
        .macHelp("Find a look for my vibe")
    }

    @ViewBuilder
    private func statusLine(_ status: Status) -> some View {
        switch status {
        case .suggested(let note):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.legibleFootnote.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if let note {
                        Text(verbatim: note)
                            .font(.legibleFootnote.weight(.semibold))
                            .foregroundStyle(Palette.textPrimary)
                    }
                    Text("Suggested by Claude, an AI helper. Change anything, then try it.")
                        .font(.legibleCaption)
                        .foregroundStyle(Palette.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        case .message(let message):
            Label {
                Text(verbatim: message)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.circle")
            }
            .font(.legibleFootnote)
            .foregroundStyle(Palette.textSecondary)
        }
    }

    private func submit() {
        guard canSubmit else { return }
        isFocused = false
        isWorking = true
        Haptics.tap()
        let words = text
        Task {
            let outcome = await describe(words)
            isWorking = false
            switch outcome {
            case .suggested(let suggested, let note):
                onSuggested(suggested)
                status = .suggested(note: note)
                Haptics.success()
            case .blocked(let reason):
                status = .message(reason)
                Haptics.error()
            case .notFound:
                status = .message(String(localized: "Couldn't find a look for that just now. Pick one below or try other words."))
            }
        }
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
                        .font(.legibleFootnote.weight(.bold))
                        .accessibilityHidden(true)
                } else if isSelected && differentiateWithoutColor {
                    Image(systemName: "checkmark")
                        .font(.legibleFootnote.weight(.bold))
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
