import SwiftUI

/// Chip: white when idle, blush with ink text when selected.
struct SelectableChip: View {
    let title: LocalizedStringKey
    var symbolName: String?
    let isSelected: Bool
    var isLocked = false
    /// A name she typed (a saved filter), shown as is in place of `title`.
    var verbatimTitle: String?
    let action: () -> Void

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected && differentiateWithoutColor {
                    Image(systemName: "checkmark").font(.legibleFootnote.weight(.bold))
                } else if let symbolName {
                    Image(systemName: symbolName).font(.legibleFootnote.weight(.semibold))
                }
                // One line where the row has room (scrolling rows); where it
                // hasn't (large text, long translations), the words wrap
                // instead of pushing the screen wider than the window.
                ViewThatFits(in: .horizontal) {
                    titleText
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    titleText
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if isLocked {
                    Image(systemName: "lock.fill").font(.legibleCaption2)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .foregroundStyle(isSelected ? Palette.onPrimary : Palette.textPrimary)
            .background(isSelected ? Palette.primary : Palette.surface, in: .chip)
            // Blush on white is too faint to show selection alone, so the
            // selected chip always gets an ink edge as well.
            .overlay(RoundedRectangle.chip.strokeBorder(isSelected ? Palette.ink : Palette.stroke, lineWidth: isSelected ? 1.5 : 1))
            .animation(Motion.press, value: isSelected)
        }
        .buttonStyle(.pressable)
        .macHoverLift()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var titleText: Text {
        (verbatimTitle.map { Text(verbatim: $0) } ?? Text(title)).font(.subheadline.weight(isSelected ? .bold : .semibold))
    }
}

extension SelectableChip {
    /// A chip named by her (a saved filter): the name is never looked up in the catalog.
    init(verbatim name: String, symbolName: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.init(title: "", symbolName: symbolName, isSelected: isSelected, verbatimTitle: name, action: action)
    }
}

/// Square style tile on the Create screen: a flat brand-tone swatch with the
/// style's symbol; the selected tile gets an accent ring and a check.
struct StyleTile: View {
    let name: String
    let symbolName: String
    let tone: PaletteTone
    let isSelected: Bool
    var isLocked = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle.control
                        .fill(tone.fill)
                    Image(systemName: symbolName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(tone.foreground)
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.legibleCaption2.weight(.bold))
                            .foregroundStyle(tone.isDark ? Palette.ink : Palette.blush)
                            .padding(5)
                            .background(tone.isDark ? Palette.blush : Palette.ink, in: Circle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(6)
                    }
                }
                .frame(width: 72, height: 72)
                .overlay(
                    RoundedRectangle.control
                        .strokeBorder(Palette.stroke, lineWidth: 1)
                )
                .padding(3)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.controlRadius + 3, style: .continuous)
                        .strokeBorder(isSelected ? Palette.accent : Color.clear, lineWidth: 2.5)
                )
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Palette.onAccent, Palette.accent)
                            .offset(x: 3, y: 3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(name)
                    .font(.legibleCaption.weight(isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: Platform.isMac ? 92 : 80)
            .animation(.snappy, value: isSelected)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
