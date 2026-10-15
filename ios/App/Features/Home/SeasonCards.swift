import SwiftUI
import AppCore

/// Explore while a season is on, above its row: the season's banner. It goes
/// when the season ends (`SeasonalTheme.current`), and there's no countdown
/// or "last chance": the looks stay in the editor all year.
struct SeasonHeroBanner: View {
    let theme: SeasonalTheme
    let action: () -> Void

    var body: some View {
        let palette = theme.bannerPalette
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(styled: theme.bannerHeadline, size: 24)
                        .foregroundStyle(palette.foreground)
                        .multilineTextAlignment(.leading)
                    Text(theme.blurb)
                        .font(.subheadline)
                        .foregroundStyle(palette.foreground.opacity(0.82))
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text("See the looks", comment: "Button on Explore's seasonal banner: opens the season's looks")
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.isDark ? Palette.ink : Palette.blush)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(palette.isDark ? Palette.blush : Palette.ink, in: .chip)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SeasonPrints(theme: theme, print: CGSize(width: 54, height: 72))
            }
            .padding(20)
            .background {
                // Overlays, so the fixed-size glow can't change the banner's size.
                AuraFill(palette: palette)
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(Palette.white.opacity(palette.isDark ? 0.12 : 0.45))
                            .frame(width: 220, height: 220)
                            .blur(radius: 44)
                            .offset(x: 50, y: -70)
                    }
            }
            .clipShape(.card)
            .overlay(RoundedRectangle.card.strokeBorder(Palette.stroke, lineWidth: 1))
            .shadow(color: palette.colors[1].opacity(0.45), radius: 20, y: 10)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
    }
}

/// Explore in the two weeks before a season (`SeasonalTheme.upcoming`): a
/// small Coming soon card. The looks already work in the editor, so a tap
/// shows them now; on the season's first day its banner and row take over.
struct SeasonTeaserCard: View {
    let upcoming: UpcomingSeason
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                SeasonPrints(theme: upcoming.theme, print: CGSize(width: 38, height: 50), count: 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Coming soon", comment: "Small heading on Explore's card for a season that starts in the next two weeks")
                        .eyebrowStyle()
                    Text(styled: upcoming.theme.styledTitle, size: 20)
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.leading)
                    countdown
                        .font(.legibleFootnote)
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(14)
            .cardStyle()
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
    }

    private var countdown: Text {
        upcoming.daysLeft == 1
            ? Text("Looks arrive tomorrow", comment: "Under a season's name on Explore's Coming soon card: its looks reach Explore tomorrow")
            : Text("Looks arrive in \(upcoming.daysLeft) days",
                   comment: "Under a season's name on Explore's Coming soon card: days until its looks reach Explore (2 to 14)")
    }
}

/// A season's looks as a little fan of prints, each with its card's own art.
struct SeasonPrints: View {
    let theme: SeasonalTheme
    var print = CGSize(width: 46, height: 60)
    var count = 3

    var body: some View {
        let looks = Array(theme.looks.prefix(count))
        ZStack {
            ForEach(Array(looks.enumerated()), id: \.element.id) { index, look in
                let turn = Self.turn(index, of: looks.count)
                TemplateArt(symbolName: look.symbolName, palette: look.cardPalette, seed: look.id)
                    .frame(width: print.width, height: print.height)
                    .padding(3)
                    .background(Palette.white)
                    .shadow(color: Palette.ink.opacity(0.18), radius: 5, y: 3)
                    .rotationEffect(.degrees(turn * 9))
                    .offset(x: turn * print.width * 0.42, y: abs(turn) * 4)
                    .zIndex(-abs(turn))
            }
        }
        .frame(width: print.width * (1 + 0.42 * CGFloat(max(looks.count - 1, 0))) + 18, height: print.height + 20)
        .accessibilityHidden(true)
    }

    /// From -1 (left) to 1 (right) across the fan; 0 in the middle, on top.
    private static func turn(_ index: Int, of count: Int) -> CGFloat {
        count > 1 ? CGFloat(index) / CGFloat(count - 1) * 2 - 1 : 0
    }
}

extension SeasonalTheme {
    /// The banner's headline, with one word in the accent font.
    var bannerHeadline: LocalizedStringResource {
        switch self {
        case .halloween:
            return LocalizedStringResource("It's *spooky* season",
                                           comment: "Explore's banner while Halloween is on. Keep one word between the asterisks: it's set in the accent font.")
        case .winter:
            return LocalizedStringResource("Cozy *winter* is here",
                                           comment: "Explore's banner from December to early January. Keep one word between the asterisks: it's set in the accent font.")
        case .galentines:
            return LocalizedStringResource("Happy *Galentine's*",
                                           comment: "Explore's banner in early February, Galentine's: a day to celebrate best friends. Keep one word between the asterisks: it's set in the accent font.")
        }
    }

    /// One of the template cards' auras.
    var bannerPalette: AuraPalette {
        switch self {
        case .halloween: return .nightGlam
        case .winter: return .mint
        case .galentines: return .bubblegum
        }
    }
}
