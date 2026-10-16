import SwiftUI
import AppCore

/// Card for a one-tap template. Uses the remote thumbnail when available, then
/// a real example of the look (`exampleImageName`), and illustrated aura art
/// (the template's symbol as a sticker) otherwise.
/// Sharp-edged, like a print. Equatable, so the forty cards on Explore aren't
/// redrawn each time something else there changes.
struct TemplateCard: View, Equatable {
    let template: PhotoTemplate
    var width: CGFloat = 148
    var height: CGFloat = 196
    var showsLock = false
    /// Lookbook number ("N°03") shown on collection pages.
    var number: Int?

    private var palette: AuraPalette { template.cardPalette }

    /// Photos get a dark scrim, so their labels are always light.
    private var hasPhoto: Bool { template.thumbnailURL != nil || template.exampleImageName != nil }
    private var isOnDark: Bool { hasPhoto || palette.isDark }
    private var labelColor: Color { hasPhoto ? Palette.white : palette.foreground }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.core(template.title))
                    .font(.cardTitle)
                    .foregroundStyle(labelColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(L10n.core(template.subtitle))
                    .font(.legibleCaption)
                    .foregroundStyle(labelColor.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            // A fixed-size print: its words stop growing at the first
            // accessibility size (VoiceOver reads the full label).
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(12)
        }
        .frame(width: width, height: height)
        .clipShape(.print)
        .overlay(
            RoundedRectangle.print
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
                    .font(.legibleCaption.weight(.bold))
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
        .accessibilityLabel("\(L10n.core(template.title)). \(L10n.core(template.subtitle))\(template.isPro ? ". Pro" : "")")
        // The badge shows Pro first, so "New" is only spoken when it's visible.
        .accessibilityValue(!template.isPro && template.isNew ? Text("NEW") : Text(verbatim: ""))
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
        } else if let example = template.exampleImageName {
            // Fills the card without setting its size: the card's frame does.
            Color.clear
                .overlay {
                    Image(example)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .overlay(LinearGradient(colors: [.clear, Palette.ink.opacity(0.7)], startPoint: .center, endPoint: .bottom))
        } else {
            TemplateArt(symbolName: template.symbolName, palette: palette, seed: template.id)
        }
    }
}

extension PhotoTemplate {
    /// The card's aura: neighbours in the catalog never share one.
    var cardPalette: AuraPalette {
        AuraPalette.at(TemplateCatalog.all.firstIndex(of: self) ?? 0)
    }
}
