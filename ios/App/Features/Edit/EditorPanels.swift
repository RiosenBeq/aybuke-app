import SwiftUI
import AppCore

/// "Describe your edit" — prompt-based editing with quick suggestions.
struct MagicEditPanel: View {
    @Binding var prompt: String
    let cost: Int
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool

    private let suggestions = [
        "Golden hour light",
        "Give me pink hair",
        "Add soft glam makeup",
        "Put me in a pink dress",
        "Add cherry blossoms",
        "Add sparkles everywhere",
        "Make it a watercolor",
        "Remove the people behind me",
    ]

    private var canSubmit: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        SelectableChip(title: suggestion, isSelected: prompt == suggestion) {
                            prompt = suggestion
                            Haptics.selection()
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Describe your edit…", text: $prompt, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($isFocused)
                    .submitLabel(.go)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(isFocused ? Palette.accent : Palette.strokeStrong, lineWidth: isFocused ? 1.5 : 1)
                    )
                Button {
                    isFocused = false
                    onSubmit()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(canSubmit ? Palette.onAccent : Palette.textTertiary)
                        .frame(width: 46, height: 46)
                        .background(canSubmit ? Palette.accent : Palette.strokeStrong, in: Circle())
                }
                .disabled(!canSubmit)
                .accessibilityLabel("Apply edit")
            }
            Text("\(cost) credit per edit · failed edits are refunded")
                .font(.caption2)
                .foregroundStyle(Palette.textTertiary)
        }
    }
}

/// One-tap templates inside the editor.
struct StylesPanel: View {
    let isPro: Bool
    let onSelect: (PhotoTemplate) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(TemplateCatalog.all) { template in
                    Button {
                        Haptics.tap()
                        onSelect(template)
                    } label: {
                        TemplateCard(template: template, width: 104, height: 136, showsLock: template.isPro && !isPro)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

/// Explanation + single action for Enhance and Remove Background.
struct OneTapPanel: View {
    let title: String
    let message: String
    let buttonTitle: String
    let cost: Int
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text(message)
                    .font(.footnote)
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
                Button(action: onClear) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.icon)
                .disabled(!hasStrokes)
                .accessibilityLabel("Clear brush")
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
    let onChange: () -> Void
    let onReset: () -> Void
    let onApply: () -> Void

    @State private var selected: Parameter = .brightness

    enum Parameter: String, CaseIterable, Identifiable {
        case brightness, contrast, saturation, warmth, sharpness, vignette

        var id: String { rawValue }

        var title: String { rawValue.capitalized }

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
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Parameter.allCases) { parameter in
                        SelectableChip(title: parameter.title, symbolName: parameter.symbol, isSelected: selected == parameter) {
                            selected = parameter
                            Haptics.selection()
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

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

            HStack(spacing: 12) {
                Button("Reset", action: onReset)
                    .buttonStyle(.secondary)
                    .disabled(settings.isNeutral)
                Button("Apply", action: onApply)
                    .buttonStyle(.primary)
                    .disabled(settings.isNeutral)
            }
        }
    }
}
