import SwiftUI

/// Shown on Home and Create while cloud AI can't be reached. Only free
/// on-device tools are named, because only they work offline.
struct OfflineNotice: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.subheadline.weight(.semibold))
                .accessibilityHidden(true)
            Text("You're offline. Effects, Adjust, Cut out and Video still work.")
                .font(.legibleFootnote.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Palette.textPrimary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .card)
        .overlay(RoundedRectangle.card.strokeBorder(Palette.strokeStrong))
        .accessibilityElement(children: .combine)
    }
}
