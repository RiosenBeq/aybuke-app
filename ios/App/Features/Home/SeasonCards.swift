import SwiftUI
import AppCore

/// Explore while a season is on, above its row: the season's banner. It goes
/// when the season ends (`SeasonalTheme.current`), and there's no countdown
/// or "last chance": the looks stay in the editor all year. Seasons with
/// examples show them as instant prints, so the looks read at a glance; the
/// local seasons show their drawn art (`SeasonArt`) along the trailing edge.
struct SeasonHeroBanner: View {
    let theme: SeasonalTheme
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The local seasons' art runs the banner's full height at the trailing edge.
    private var artWidth: CGFloat { sizeClass == .regular ? 280 : 150 }
    private var showsArtAlongside: Bool { theme.isLocal && !typeSize.isAccessibilitySize }

    var body: some View {
        let palette = theme.bannerPalette
        Button(action: action) {
            content(palette)
                .padding(20)
                .background {
                    // Overlays, so the fixed-size glow and art can't change the banner's size.
                    AuraFill(palette: palette)
                        .overlay(alignment: .topTrailing) {
                            Circle()
                                .fill(Palette.white.opacity(palette.isDark ? 0.12 : 0.45))
                                .frame(width: 220, height: 220)
                                .blur(radius: 44)
                                .offset(x: 50, y: -70)
                        }
                        .overlay(alignment: .trailing) {
                            if showsArtAlongside {
                                SeasonArt(theme: theme)
                                    .frame(width: artWidth)
                                    // Flags, strings and the Milky Way fade in behind the words.
                                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18)],
                                                         startPoint: .leading, endPoint: .trailing))
                            }
                        }
                }
                .clipShape(.card)
                .overlay(RoundedRectangle.card.strokeBorder(Palette.stroke, lineWidth: 1))
                .shadow(color: palette.colors[1].opacity(0.45), radius: 20, y: 10)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
    }

    @ViewBuilder
    private func content(_ palette: AuraPalette) -> some View {
        let examples = theme.examples
        if theme.isLocal {
            if showsArtAlongside {
                VStack(alignment: .leading, spacing: 8) {
                    headline(palette)
                    seeTheLooks(palette)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
                .padding(.trailing, artWidth - 16)
            } else {
                // The words get the whole width; the art goes above them.
                VStack(alignment: .leading, spacing: 14) {
                    SeasonArt(theme: theme)
                        .frame(height: 130)
                        .frame(maxWidth: .infinity)
                    headline(palette)
                    seeTheLooks(palette)
                }
            }
        } else if examples.isEmpty {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    headline(palette)
                    seeTheLooks(palette)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SeasonPrints(theme: theme, print: CGSize(width: 54, height: 72))
            }
        } else if typeSize.isAccessibilitySize {
            // The words get the whole width; the prints keep their size above them.
            VStack(alignment: .leading, spacing: 16) {
                prints(examples, palette: palette)
                    .frame(maxWidth: .infinity)
                headline(palette)
                seeTheLooks(palette)
            }
        } else {
            // The button gets a row of its own, so a long label never
            // squeezes beside the prints on a small phone.
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    headline(palette)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    prints(examples, palette: palette)
                }
                seeTheLooks(palette)
            }
        }
    }

    private func headline(_ palette: AuraPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(styled: theme.bannerHeadline, size: 24)
                .foregroundStyle(palette.foreground)
                .multilineTextAlignment(.leading)
            Text(theme.blurb)
                .font(.subheadline)
                .foregroundStyle(palette.foreground.opacity(0.82))
                .multilineTextAlignment(.leading)
        }
    }

    private func seeTheLooks(_ palette: AuraPalette) -> some View {
        HStack(spacing: 6) {
            Text("See the looks", comment: "Button on Explore's seasonal banner: opens the season's looks")
            Image(systemName: "arrow.right")
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(palette.isDark ? Palette.ink : Palette.blush)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(palette.isDark ? Palette.blush : Palette.ink, in: .pill)
    }

    private func prints(_ examples: [String], palette: AuraPalette) -> some View {
        // Bigger on iPad and the Mac, where the banner runs much wider.
        let photo = sizeClass == .regular ? CGSize(width: 108, height: 144) : CGSize(width: 66, height: 88)
        return VStack(spacing: 6) {
            SeasonExamplePrints(assets: examples, photo: photo, spread: 0.78)
            SeasonExampleCaption(color: palette.foreground.opacity(0.78))
        }
    }
}

/// Explore in the two weeks before a season (`SeasonalTheme.upcoming`): a
/// small Coming soon card. The looks already work in the editor, so a tap
/// shows them now; on the season's first day its banner and row take over.
struct SeasonTeaserCard: View {
    let upcoming: UpcomingSeason
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            prints
                            Spacer(minLength: 0)
                            chevron
                        }
                        words
                    }
                } else {
                    HStack(spacing: 14) {
                        prints
                        words
                        Spacer(minLength: 0)
                        chevron
                    }
                }
            }
            .padding(14)
            .cardStyle()
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
    }

    @ViewBuilder
    private var prints: some View {
        let examples = upcoming.theme.examples
        if upcoming.theme.isLocal {
            SeasonArtTile(theme: upcoming.theme)
        } else if examples.isEmpty {
            SeasonPrints(theme: upcoming.theme, print: CGSize(width: 38, height: 50), count: 2)
        } else {
            VStack(spacing: 4) {
                SeasonExamplePrints(assets: Array(examples.prefix(2)), photo: CGSize(width: 48, height: 64), spread: 0.85)
                SeasonExampleCaption(color: Palette.textSecondary)
            }
        }
    }

    private var words: some View {
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
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .foregroundStyle(Palette.textTertiary)
    }

    private var countdown: Text {
        upcoming.daysLeft == 1
            ? Text("Looks arrive tomorrow", comment: "Under a season's name on Explore's Coming soon card: its looks reach Explore tomorrow")
            : Text("Looks arrive in \(upcoming.daysLeft) days",
                   comment: "Under a season's name on Explore's Coming soon card: days until its looks reach Explore (2 to 14)")
    }
}

/// Real results of a season's looks as a little fan of instant prints: the
/// first one in front, the others tucked behind it to the left and right.
struct SeasonExamplePrints: View {
    let assets: [String]
    let photo: CGSize
    /// How far the back prints reach out, as a share of the photo's width:
    /// far enough that every face shows.
    var spread: CGFloat = 0.78

    private var border: CGFloat { (photo.width * 0.06).rounded() }

    var body: some View {
        let prints = Array(assets.prefix(3))
        let reach = prints.count > 1 ? photo.width * spread : 0
        ZStack {
            ForEach(Array(prints.enumerated()), id: \.element) { index, asset in
                let place = Self.place(index, of: prints.count)
                InstantPrint(asset: asset, photo: photo, border: border)
                    .scaleEffect(index == 0 ? 1 : 0.92)
                    .rotationEffect(.degrees(place.angle))
                    .offset(x: place.side * reach, y: abs(place.side) * photo.height * 0.05)
                    .zIndex(place.depth)
            }
        }
        // Room for the back prints and their turn, so nothing spills over the words.
        .frame(width: photo.width + border * 2 + reach * (prints.count > 2 ? 2 : 1) + photo.width * 0.16,
               height: photo.height + border * 4.2 + photo.height * 0.12)
        .accessibilityHidden(true)
    }

    /// The front print stands nearly straight; the back ones, a little smaller, lean outwards.
    private static func place(_ index: Int, of count: Int) -> (side: CGFloat, angle: Double, depth: Double) {
        switch (count, index) {
        case (2, 0): return (0.5, 5, 2)
        case (2, 1): return (-0.5, -8, 1)
        case (_, 1): return (-1, -10, 1)
        case (_, 2): return (1, 9, 0)
        default: return (0, -2, 3)
        }
    }
}

/// One print: the photo on white paper with the deeper bottom edge of an instant print.
private struct InstantPrint: View {
    let asset: String
    let photo: CGSize
    let border: CGFloat

    var body: some View {
        Color.clear
            .frame(width: photo.width, height: photo.height)
            .overlay {
                Image(asset)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .padding([.top, .horizontal], border)
            .padding(.bottom, border * 3.2)
            .background(Palette.white)
            .shadow(color: Palette.ink.opacity(0.3), radius: 8, y: 4)
    }
}

/// Under the examples: they're real results of the season's looks.
private struct SeasonExampleCaption: View {
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
            Text("Made with \(Brand.name)",
                 comment: "Tiny caption under the example photos on Explore's season banner and Coming soon card: they are real results of the season's looks, made with the app. The placeholder is the app's name.")
        }
        .font(.legibleCaption2.weight(.semibold))
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        // It labels fixed-size prints: past the first accessibility size it would outgrow them.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityHidden(true)
    }
}

/// A season's looks as a little fan of prints, each with its card's own art.
/// For seasons without examples (`SeasonalTheme.examples`).
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
        case .eidAlFitr:
            return LocalizedStringResource("Happy *Eid*",
                                           comment: "Explore's banner during Eid al-Fitr (Ramazan Bayramı in Türkiye, Lebaran in Indonesia), shown there only. Use the greeting people use in your language. Keep one word between the asterisks: it's set in the accent font.")
        case .eidAlAdha:
            return LocalizedStringResource("Happy *Eid* al-Adha",
                                           comment: "Explore's banner during Eid al-Adha (Kurban Bayramı in Türkiye, Iduladha in Indonesia), shown there only. Use the greeting people use in your language. Keep one word between the asterisks: it's set in the accent font.")
        case .lunarNewYear:
            return LocalizedStringResource("Happy *Lunar* New Year",
                                           comment: "Explore's banner during Lunar New Year (Seollal in Korea, Spring Festival for Chinese speakers), shown there only. Keep one word between the asterisks: it's set in the accent font.")
        case .chuseok:
            return LocalizedStringResource("Happy *Chuseok*",
                                           comment: "Explore's banner during Chuseok, Korea's autumn harvest holiday, shown in Korea only. Keep one word between the asterisks: it's set in the accent font.")
        case .hanami:
            return LocalizedStringResource("It's *hanami* season",
                                           comment: "Explore's banner during cherry blossom season (hanami: picnics under the blossoms), shown in Japan only. Keep one word between the asterisks: it's set in the accent font.")
        case .tanabata:
            return LocalizedStringResource("Make a *wish*",
                                           comment: "Explore's banner for Tanabata, Japan's star festival on July 7, when people write wishes on paper strips. Shown in Japan only. Keep one word between the asterisks: it's set in the accent font.")
        case .carnaval:
            return LocalizedStringResource("It's *Carnaval*",
                                           comment: "Explore's banner during Carnaval, shown in Brazil only. Keep one word between the asterisks: it's set in the accent font.")
        case .festaJunina:
            return LocalizedStringResource("Festa *Junina* is here",
                                           comment: "Explore's banner in June, for Brazil's festas juninas (paper flags, bonfires, sweets), shown in Brazil only. Keep one word between the asterisks: it's set in the accent font.")
        case .diaDeMuertos:
            return LocalizedStringResource("Día de *Muertos*",
                                           comment: "Explore's banner on Día de Muertos (October 31 to November 2), shown in Mexico and Latin America. Use the festival's name; keep one word between the asterisks: it's set in the accent font.")
        }
    }

    /// One of the template cards' auras; the local seasons have their own.
    var bannerPalette: AuraPalette {
        switch self {
        case .halloween: return .nightGlam
        case .winter: return .mint
        case .galentines: return .bubblegum
        case .eidAlFitr: return .eidNight
        case .eidAlAdha: return .eidDay
        case .lunarNewYear: return .lunarRed
        case .chuseok: return .harvestNight
        case .hanami: return .sakura
        case .tanabata: return .starNight
        case .carnaval: return .carnaval
        case .festaJunina: return .arraia
        case .diaDeMuertos: return .muertos
        }
    }

    /// The local seasons' looks wear the season's colours on their cards.
    var cardPalettes: [AuraPalette]? {
        switch self {
        case .halloween, .winter, .galentines: return nil
        case .eidAlFitr: return [.eidNight, .eidDay]
        case .eidAlAdha: return [.eidDay, .eidNight]
        case .lunarNewYear: return [.lunarRed, .lunarGold]
        case .chuseok: return [.harvestNight, .persimmonDay]
        case .hanami: return [.sakura, .sakuraNight]
        case .tanabata: return [.starNight, .tanzaku]
        case .carnaval: return [.carnaval, .carnavalSun]
        case .festaJunina: return [.arraia, .junina]
        case .diaDeMuertos: return [.muertos, .cempasuchil]
        }
    }

    /// Real results of the season's looks, made with the looks themselves on
    /// the fictional sample people (docs/marketing/seasonal-examples), as
    /// asset names; the first is the front print. Galentine's has none yet,
    /// so its banner and card keep the drawn art.
    var examples: [String] {
        switch self {
        case .halloween: return ["SeasonExampleHalloween1", "SeasonExampleHalloween2", "SeasonExampleHalloween3"]
        case .winter: return ["SeasonExampleWinter1", "SeasonExampleWinter2", "SeasonExampleWinter3"]
        default: return []
        }
    }
}

extension PhotoTemplate {
    /// A real result of this look, shown on its card in place of the drawn
    /// art (asset name; nil for looks without one).
    var exampleImageName: String? {
        switch id {
        case "witchy": return "SeasonExampleHalloween1"
        case "spooky": return "SeasonExampleHalloween2"
        case "snow-globe": return "SeasonExampleWinter1"
        case "cozy-sweater": return "SeasonExampleWinter2"
        case "new-year": return "SeasonExampleWinter3"
        default: return nil
        }
    }
}
