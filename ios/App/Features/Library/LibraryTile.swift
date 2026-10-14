import SwiftUI
import AppCore

/// One square in My Works: the thumbnail with its heart, the days left in
/// Recently deleted and the select check, or a placeholder with "Remove"
/// when the image file is gone.
struct LibraryTile: View {
    let creation: Creation
    var isMissing = false
    var isSelecting = false
    var isSelected = false
    /// Recently deleted: days until it's removed for good.
    var daysLeft: Int?
    var onMissing: () -> Void = {}
    var onRemove: () -> Void = {}

    private let shape = RoundedRectangle.control

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if isMissing {
                    missingPlaceholder
                } else {
                    ThumbnailView(fileName: creation.imageFileName, onMissing: onMissing)
                }
            }
            .clipShape(shape)
            .overlay(alignment: .topTrailing) {
                if creation.isFavorite && !isMissing {
                    Image(systemName: "heart.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.blush)
                        .padding(6)
                        .background(Palette.ink.opacity(0.55), in: Circle())
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let daysLeft {
                    Text(daysLeft == 1 ? "1 day" : "\(daysLeft) days")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.white)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Palette.ink.opacity(0.6), in: .tag)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isSelecting { checkmark }
            }
            .overlay {
                if isSelected { shape.strokeBorder(Palette.accent, lineWidth: 3) }
            }
            .contentShape(shape)
            .animation(.snappy(duration: 0.2), value: isSelected)
    }

    private var checkmark: some View {
        ZStack {
            Circle().fill(isSelected ? Palette.accent : Palette.ink.opacity(0.25))
            Circle().strokeBorder(Palette.white, lineWidth: 1.5)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Palette.onAccent)
            }
        }
        .frame(width: 24, height: 24)
        .shadow(color: Palette.ink.opacity(0.2), radius: 2, y: 1)
        .padding(6)
        .accessibilityHidden(true)
    }

    private var missingPlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.textTertiary)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.danger)
                        .background(Circle().fill(Palette.surface))
                        .offset(x: 6, y: 4)
                }
            Text("Image missing")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if !isSelecting {
                Button(action: onRemove) {
                    Text("Remove")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.onAccent)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 28)
                        .background(Palette.accent, in: .chip)
                        // A 44 pt target around the small button.
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityHint("Takes the missing image out of My Works")
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface)
        .overlay(shape.strokeBorder(Palette.strokeStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}
