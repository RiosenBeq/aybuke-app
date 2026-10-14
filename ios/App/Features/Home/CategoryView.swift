import SwiftUI
import AppCore

/// A whole collection on one page, opened from "See all" on Explore: an
/// editorial, lookbook-style grid of numbered, sharp-edged cards.
struct CategoryView: View {
    let category: TemplateCategory

    @Environment(AppModel.self) private var app

    private var templates: [PhotoTemplate] { TemplateCatalog.templates(in: category, on: AppClock.now) }
    /// Two columns on iPhone, up to eight on a big iPad in landscape.
    private let columns = [GridItem(.adaptive(minimum: 136), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                    .reveal(0)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(templates.enumerated()), id: \.element) { index, template in
                        Button {
                            Haptics.tap()
                            app.startEditing(tool: .styles, template: template)
                        } label: {
                            GeometryReader { proxy in
                                TemplateCard(template: template, width: proxy.size.width, height: proxy.size.height, number: index + 1)
                            }
                            .aspectRatio(3 / 4, contentMode: .fit)
                        }
                        .buttonStyle(.pressable)
                        .reveal(1 + min(index, 7))
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(AuroraBackground(intensity: 0.35))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Collection · \(templates.count) looks")
                .eyebrowStyle()
            Text(styled: category.styledTitle, size: 36)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(category.blurb)
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
            Rectangle()
                .fill(Palette.accent)
                .frame(width: 44, height: 3)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
        .padding(.top, 4)
    }
}

extension TemplateCategory {
    /// "Glow-up *looks*": the last word in the italic accent.
    var styledTitle: String {
        let title = L10n.core(self.title(on: AppClock.now))
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
        case .dreamy: return String(localized: "Soft, magical portraits.")
        case .seasonal:
            // No scarcity talk: seasonal looks stay in the editor all year.
            switch SeasonalTheme.current(on: AppClock.now) {
            case .halloween: return String(localized: "Cute and a little spooky.")
            case .winter: return String(localized: "Snow, sweaters and New Year sparkle.")
            case .galentines: return String(localized: "Pink brunches and photo booths with your besties.")
            case nil: return String(localized: "Looks for this time of year.")
            }
        case .art: return String(localized: "Turn any photo into art.")
        case .pets: return String(localized: "Your pet, starring in their own photoshoot.")
        case .business: return String(localized: "Polished photos for work and your shop.")
        }
    }
}
