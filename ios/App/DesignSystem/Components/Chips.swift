import SwiftUI

/// Capsule chip: white when idle, blush with ink text when selected.
struct SelectableChip: View {
    let title: String
    var symbolName: String?
    let isSelected: Bool
    var isLocked = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbolName {
                    Image(systemName: symbolName).font(.footnote.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if isLocked {
                    Image(systemName: "lock.fill").font(.caption2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? Palette.onPrimary : Palette.textPrimary)
            .background(isSelected ? Palette.primary : Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Palette.ink.opacity(0.12) : Palette.stroke, lineWidth: 1))
            .animation(Motion.press, value: isSelected)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(tone.fill)
                    Image(systemName: symbolName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(tone.foreground)
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(tone.isDark ? Palette.ink : Palette.blush)
                            .padding(5)
                            .background(tone.isDark ? Palette.blush : Palette.ink, in: Circle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(6)
                    }
                }
                .frame(width: 72, height: 72)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Palette.stroke, lineWidth: 1)
                )
                .padding(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
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
                    .font(.caption.weight(isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 80)
            .animation(.snappy, value: isSelected)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
