import SwiftUI
import AppCore

/// Card for a one-tap template. Uses the remote thumbnail when available and
/// illustrated aura art (the template's symbol as a sticker) otherwise.
/// Sharp-edged, like a print.
struct TemplateCard: View {
    let template: PhotoTemplate
    var width: CGFloat = 148
    var height: CGFloat = 196
    var showsLock = false
    /// Lookbook number ("N°03") shown on collection pages.
    var number: Int?

    private var palette: AuraPalette {
        AuraPalette.at(TemplateCatalog.all.firstIndex(of: template) ?? 0)
    }

    /// Photo thumbnails get a dark scrim, so their labels are always light.
    private var isOnDark: Bool { template.thumbnailURL != nil || palette.isDark }
    private var labelColor: Color { template.thumbnailURL != nil ? Palette.white : palette.foreground }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(template.title)
                    .font(.cardTitle)
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                Text(template.subtitle)
                    .font(.caption)
                    .foregroundStyle(labelColor.opacity(0.75))
                    .lineLimit(1)
            }
            .padding(12)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.printRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.printRadius)
                .strokeBorder(Palette.stroke, lineWidth: 1)
        )
        .shadow(color: Palette.shadow, radius: 12, y: 6)
        .overlay(alignment: .topTrailing) {
            Group {
                if template.isPro {
                    ProBadge(onDark: isOnDark)
                } else if template.isNew {
                    NewBadge(onDark: isOnDark)
                }
            }
            .padding(10)
        }
        .overlay(alignment: .topLeading) {
            if showsLock {
                Image(systemName: "lock.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isOnDark ? Palette.ink : Palette.blush)
                    .padding(7)
                    .background(isOnDark ? Palette.blush : Palette.ink, in: Circle())
                    .padding(10)
            } else if let number {
                Text(String(format: "N°%02d", number))
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(labelColor.opacity(0.7))
                    .padding(12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(template.title). \(template.subtitle)\(template.isPro ? ". Pro" : "")")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = template.thumbnailURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    AuraFill(palette: palette)
                }
            }
            .overlay(LinearGradient(colors: [.clear, Palette.ink.opacity(0.7)], startPoint: .center, endPoint: .bottom))
        } else {
            TemplateArt(symbolName: template.symbolName, palette: palette, seed: template.id)
        }
    }
}
