import SwiftUI
import AppCore

/// Card for a one-tap template. Uses the remote thumbnail when available and a
/// flat brand-tone swatch with the template's symbol otherwise.
struct TemplateCard: View {
    let template: PhotoTemplate
    var width: CGFloat = 148
    var height: CGFloat = 196
    var showsLock = false

    private var tone: PaletteTone {
        PaletteTone.at(TemplateCatalog.all.firstIndex(of: template) ?? 0)
    }

    /// Photo thumbnails get a dark scrim, so their labels are always light.
    private var isOnDark: Bool { template.thumbnailURL != nil || tone.isDark }
    private var labelColor: Color { template.thumbnailURL != nil ? Palette.white : tone.foreground }

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
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
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
                    tone.fill
                }
            }
            .overlay(LinearGradient(colors: [.clear, Palette.ink.opacity(0.7)], startPoint: .center, endPoint: .bottom))
        } else {
            ZStack {
                tone.fill
                Circle()
                    .fill(tone.foreground.opacity(0.08))
                    .frame(width: width * 0.72, height: width * 0.72)
                    .offset(y: -height * 0.08)
                Image(systemName: template.symbolName)
                    .font(.system(size: min(52, width * 0.36), weight: .semibold))
                    .foregroundStyle(tone.foreground)
                    .offset(y: -height * 0.08)
            }
        }
    }
}
