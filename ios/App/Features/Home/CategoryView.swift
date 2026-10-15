import SwiftUI
import AppCore

/// A whole collection on one page, opened from "See all" on Explore: an
/// editorial, lookbook-style grid of numbered, sharp-edged cards.
struct CategoryView: View {
    let category: TemplateCategory
    /// A season's looks before it starts, from Explore's Coming soon card:
    /// they already work (the editor keeps them all year). Nil: the
    /// collection as it is today.
    var season: SeasonalTheme?

    @Environment(AppModel.self) private var app

    private var templates: [PhotoTemplate] {
        season?.looks ?? TemplateCatalog.templates(in: category, on: AppClock.now)
    }
    /// Two columns on iPhone, up to eight on a big iPad in landscape; on
    /// the Mac, cards about as big as on Explore.
    private let columns = [GridItem(.adaptive(minimum: Platform.isMac ? 176 : 136), spacing: Platform.isMac ? 14 : 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                    .reveal(0)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(templates.enumerated()), id: \.element) { index, template in
                        Button {
                            tryLook(template)
                        } label: {
                            GeometryReader { proxy in
                                TemplateCard(template: template, width: proxy.size.width, height: proxy.size.height, number: index + 1)
                            }
                            .aspectRatio(3 / 4, contentMode: .fit)
                        }
                        .buttonStyle(.pressable)
                        .macHoverLift()
                        .macTryLookMenu { tryLook(template) }
                        .accessibilityHint(template.lookHint(isPro: app.purchases.isPro))
                        .reveal(1 + min(index, 7))
                    }
                }
            }
            .padding(.horizontal, Metrics.pageGutter)
            .padding(.bottom, 32)
            .macPageWidth()
        }
        .scrollIndicators(.hidden)
        .background(AuroraBackground(intensity: 0.35))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func tryLook(_ template: PhotoTemplate) {
        Haptics.tap()
        app.startEditing(tool: .styles, template: template)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Collection · \(templates.count) looks")
                .eyebrowStyle()
            Text(styled: season?.styledTitle ?? category.styledTitle, size: 31)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(season?.blurb ?? category.blurb)
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
            // A tap on a look runs it on her photo right away, so the price
            // is said here, before the credit is spent.
            Label("\(app.credits.cost(of: .restyle)) credit per look · failed looks are refunded", systemImage: "bolt.fill")
                .font(.legibleCaption.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 2)
            Rectangle()
                .fill(Palette.accent)
                .frame(width: 44, height: 3)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
        .padding(.top, 4)
    }
}

extension View {
    /// Mac: a right-click on a look's card offers it, with the same action as
    /// a click (so the same gates). iPhone and iPad are unchanged.
    @ViewBuilder
    func macTryLookMenu(_ action: @escaping () -> Void) -> some View {
        if Platform.isMac {
            contextMenu {
                Button("Try this look", action: action)
            }
        } else {
            self
        }
    }
}

extension PhotoTemplate {
    /// VoiceOver: what a tap on the look's card on Explore does next.
    func lookHint(isPro: Bool) -> Text {
        self.isPro && !isPro ? Text("Upgrade to \(Brand.name) Pro") : Text("Choose a photo to try this look")
    }
}

extension TemplateCategory {
    /// "Glow-up *looks*": the last word in the italic accent.
    var styledTitle: String { Self.accentingLastWord(L10n.core(title(on: AppClock.now))) }

    static func accentingLastWord(_ title: String) -> String {
        var words = title.split(separator: " ").map(String.init)
        // Languages written without spaces (Japanese, Chinese) keep it plain.
        guard words.count > 1, let last = words.popLast() else { return title }
        return (words + ["*\(last)*"]).joined(separator: " ")
    }

    var blurb: String {
        switch self {
        case .trending: return String(localized: "Looks inspired by what's trending.")
        case .glowUp: return String(localized: "Hair, makeup and glam, and still 100% you.")
        case .aesthetic: return String(localized: "Moods, places and colours for your feed.")
        case .besties: return String(localized: "Sleepovers, concerts and matching fits with your besties.")
        case .dreamy: return String(localized: "Soft, magical portraits.")
        case .seasonal:
            return SeasonalTheme.current(on: AppClock.now)?.blurb ?? String(localized: "Looks for this time of year.")
        case .art: return String(localized: "Turn any photo into art.")
        case .pets: return String(localized: "Your pet, starring in their own photoshoot.")
        case .business: return String(localized: "Polished photos for work and your shop.")
        }
    }
}

extension SeasonalTheme {
    /// Every look of the season, in catalog order.
    var looks: [PhotoTemplate] { TemplateCatalog.all.filter { $0.season == self } }

    /// "Cozy *winter*": its row's heading, styled like a collection's.
    var styledTitle: String { TemplateCategory.accentingLastWord(L10n.core(rowTitle)) }

    /// No scarcity talk: seasonal looks stay in the editor all year.
    var blurb: String {
        switch self {
        case .halloween: return String(localized: "Cute and a little spooky.")
        case .winter: return String(localized: "Snow, sweaters and New Year sparkle.")
        case .galentines: return String(localized: "Pink brunches and photo booths with your besties.")
        }
    }
}
