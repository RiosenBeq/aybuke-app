import SwiftUI
import AppCore

/// One square in My Works: the thumbnail with its heart, the days left in
/// Recently deleted and, in select mode, the select badge; or a placeholder
/// with "Remove" when the image file is gone. A selected picture steps in
/// from a blush ring (its corner concentric with the tile's) under a light
/// blush veil, with a filled check.
struct LibraryTile: View {
    let creation: Creation
    var isMissing = false
    var isSelecting = false
    var isSelected = false
    /// Recently deleted: days until it's removed for good.
    var daysLeft: Int?
    var onMissing: () -> Void = {}
    var onRemove: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let ringWidth: CGFloat = 3
    /// Between the ring and the picture.
    private static let ringGap: CGFloat = 2.5
    private static let badgeSize: CGFloat = 24

    /// How far a selected picture steps in. With Reduce Motion it stays put
    /// and the ring, veil and check only fade in.
    private var inset: CGFloat {
        isSelected && !reduceMotion ? Self.ringWidth + Self.ringGap : 0
    }

    /// The picture's corner, concentric with the tile's at any inset.
    private var pictureShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: max(Metrics.controlRadius - inset, 0), style: .continuous)
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                picture
                    .padding(inset)
            }
            .overlay {
                if isSelected {
                    ring
                        .transition(.opacity)
                }
            }
            .contentShape(RoundedRectangle.control)
            .animation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.press, value: isSelected)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.reveal, value: isSelecting)
    }

    private var picture: some View {
        Color.clear
            .overlay {
                if isMissing {
                    missingPlaceholder
                } else {
                    ThumbnailView(fileName: creation.imageFileName, onMissing: onMissing)
                }
            }
            .overlay {
                // Only while picked, never in what she saves or shares.
                if isSelected {
                    Palette.blush.opacity(0.2)
                        .transition(.opacity)
                }
            }
            .clipShape(pictureShape)
            .overlay(alignment: .topTrailing) {
                if creation.isFavorite && !isMissing { heart }
            }
            .overlay(alignment: .bottomLeading) {
                if let daysLeft { daysTag(daysLeft) }
            }
            .overlay(alignment: .bottomTrailing) {
                if isSelecting {
                    badge
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                }
            }
    }

    /// Blush, with a crisp accent edge where it meets the page: blush alone
    /// fades into the petal canvas (in dark mode both are blush).
    private var ring: some View {
        RoundedRectangle.control
            .strokeBorder(Palette.blush, lineWidth: Self.ringWidth)
            .overlay(RoundedRectangle.control.strokeBorder(Palette.accent, lineWidth: 1))
            .allowsHitTesting(false)
    }

    /// An empty ring in select mode, filled with a check once picked.
    private var badge: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Palette.accent : Palette.ink.opacity(0.22))
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Palette.onAccent)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.3).combined(with: .opacity))
            }
            Circle()
                .strokeBorder(Palette.white, lineWidth: 1.75)
        }
        .frame(width: Self.badgeSize, height: Self.badgeSize)
        .shadow(color: Palette.ink.opacity(0.25), radius: 2, y: 1)
        .padding(5)
        .accessibilityHidden(true)
    }

    private var heart: some View {
        Image(systemName: "heart.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(Palette.blush)
            .padding(6)
            .background(Palette.ink.opacity(0.55), in: Circle())
            .padding(5)
            // A badge on a fixed-size tile grows with the text only so far.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func daysTag(_ days: Int) -> some View {
        Text(days == 1 ? "1 day" : "\(days) days")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Palette.white)
            .lineLimit(1)
            // Shrinks to fit rather than cutting a word (small iPad tiles in
            // select mode, at the largest size it takes).
            .minimumScaleFactor(0.4)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Palette.ink.opacity(0.6), in: .tag)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(5)
            // Leaves room for the select badge beside it.
            .padding(.trailing, isSelecting ? Self.badgeSize + 6 : 0)
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
                .minimumScaleFactor(0.5)
            if !isSelecting {
                Button(action: onRemove) {
                    Text("Remove")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.onAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
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
        // It has to fit the tile; VoiceOver reads it in full.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface)
        .overlay(pictureShape.strokeBorder(Palette.strokeStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}
