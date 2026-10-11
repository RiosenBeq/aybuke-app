import SwiftUI
import AppCore

/// Card for a one-tap template. Uses the remote thumbnail when available and a
/// branded gradient + symbol otherwise.
struct TemplateCard: View {
    let template: PhotoTemplate
    var width: CGFloat = 148
    var height: CGFloat = 196
    var showsLock = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.title)
                    .font(.cardTitle)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(template.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
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
        .overlay(alignment: .topTrailing) {
            Group {
                if template.isPro {
                    ProBadge()
                } else if template.isNew {
                    NewBadge()
                }
            }
            .padding(10)
        }
        .overlay(alignment: .topLeading) {
            if showsLock {
                Image(systemName: "lock.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(7)
                    .background(.black.opacity(0.4), in: Circle())
                    .padding(10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(template.title). \(template.subtitle)\(template.isPro ? ". Pro" : "")")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var artwork: some View {
        let gradient = LinearGradient(colors: template.gradient.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
        if let url = template.thumbnailURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    gradient
                }
            }
        } else {
            ZStack {
                gradient
                Image(systemName: template.symbolName)
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    .offset(y: -14)
            }
        }
    }
}
