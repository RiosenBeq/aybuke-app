import SwiftUI

/// The "aybuke" logotype: the `Wordmark` vector that
/// scripts/render-brand-assets.py draws from Poppins Bold (tightened, corners
/// rounded, the icon's sparkle after the "e"), tinted like text: ink, or light
/// in dark mode. VoiceOver reads the name.
struct BrandWordmark: View {
    var height: CGFloat
    var color: Color = Palette.textPrimary

    var body: some View {
        Image("Wordmark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .foregroundStyle(color)
            .accessibilityRemoveTraits(.isImage)
            .accessibilityLabel(Text(verbatim: Brand.name))
    }
}
