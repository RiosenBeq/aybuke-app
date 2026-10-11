import SwiftUI

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
                Text(title).font(.subheadline.weight(.semibold))
                if isLocked {
                    Image(systemName: "lock.fill").font(.caption2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? Palette.onPrimary : Palette.textPrimary)
            .background {
                if isSelected {
                    Capsule().fill(Palette.brandGradient)
                } else {
                    Capsule().fill(Palette.surfaceRaised)
                }
            }
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Style chip with a color swatch preview, used on the Create screen.
struct StyleSwatchChip: View {
    let name: String
    let colors: [Color]
    let symbolName: String
    let isSelected: Bool
    var isLocked = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: symbolName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.black.opacity(0.45), in: Circle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(6)
                    }
                }
                .frame(width: 72, height: 72)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(isSelected ? Palette.primary : Color.clear, lineWidth: 2.5)
                )
                Text(name)
                    .font(.caption.weight(isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 76)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
