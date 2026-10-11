import SwiftUI
import AppCore

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    header
                        .padding(.horizontal, Metrics.gutter)

                    if app.isDemoMode {
                        DemoModeBanner()
                            .padding(.horizontal, Metrics.gutter)
                    }

                    heroCard
                        .padding(.horizontal, Metrics.gutter)

                    quickTools

                    ForEach(orderedCategories) { category in
                        templateRow(category)
                    }

                    createBanner
                        .padding(.horizontal, Metrics.gutter)
                }
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .background(AuroraBackground(intensity: 0.4))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environment(app)
            }
            #if DEBUG
            .onAppear {
                if ScreenshotScene.current == .settings { showSettings = true }
            }
            #endif
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 12) {
            Text(Brand.name)
                .font(.display(30, weight: .heavy, relativeTo: .largeTitle))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            CreditPill(balance: app.credits.balance, isPro: app.purchases.isPro) {
                if !app.purchases.isPro { app.presentPaywall(source: "home_credits") }
            }
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.icon)
            .accessibilityLabel("Settings")
        }
    }

    private var heroCard: some View {
        Button {
            Haptics.tap()
            app.startEditing(tool: .magicEdit)
        } label: {
            ZStack(alignment: .bottomLeading) {
                Palette.brandGradient
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 120, weight: .bold))
                    .foregroundStyle(Palette.onPrimary.opacity(0.12))
                    .rotationEffect(.degrees(-12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .offset(x: 18, y: -6)
                VStack(alignment: .leading, spacing: 8) {
                    Text("MAGIC EDIT")
                        .font(.caption.weight(.heavy))
                        .tracking(1.2)
                        .foregroundStyle(Palette.onPrimary.opacity(0.75))
                    Text("Describe any change.\nWatch it happen.")
                        .font(.display(26, weight: .bold))
                        .foregroundStyle(Palette.onPrimary)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text("Try it on your photo")
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Palette.onPrimary, in: Capsule())
                    .padding(.top, 6)
                }
                .padding(20)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .shadow(color: Palette.primary.opacity(0.3), radius: 24, y: 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Magic Edit. Describe any change to your photo.")
    }

    private var quickTools: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Quick tools")
                .padding(.horizontal, Metrics.gutter)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(EditorTool.quickTools) { tool in
                        QuickToolTile(tool: tool) {
                            Haptics.tap()
                            app.startEditing(tool: tool)
                        }
                    }
                }
                .padding(.horizontal, Metrics.gutter)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func templateRow(_ category: TemplateCategory) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: category.title)
                .padding(.horizontal, Metrics.gutter)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(TemplateCatalog.templates(in: category)) { template in
                        Button {
                            Haptics.tap()
                            app.startEditing(tool: .styles, template: template)
                        } label: {
                            TemplateCard(template: template)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Metrics.gutter)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var createBanner: some View {
        Button {
            app.selectedTab = .create
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "text.cursor")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.brandGradient)
                    .frame(width: 52, height: 52)
                    .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Create from text")
                        .font(.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                    Text("Turn any idea into an image")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(14)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    /// Puts the categories that match onboarding interests first.
    private var orderedCategories: [TemplateCategory] {
        let preferred: [String: TemplateCategory] = [
            "selfies": .portrait, "memories": .portrait, "business": .business,
            "art": .art, "fun": .fun, "social": .trending,
        ]
        let boosted = app.interests.compactMap { preferred[$0] }
        return TemplateCatalog.categories.sorted { lhs, rhs in
            let lhsScore = (lhs == .trending ? 2 : 0) + (boosted.contains(lhs) ? 1 : 0)
            let rhsScore = (rhs == .trending ? 2 : 0) + (boosted.contains(rhs) ? 1 : 0)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return TemplateCategory.allCases.firstIndex(of: lhs)! < TemplateCategory.allCases.firstIndex(of: rhs)!
        }
    }
}

private struct QuickToolTile: View {
    let tool: EditorTool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: tool.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.onPrimary)
                    .frame(width: 44, height: 44)
                    .background(Palette.brandGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(tool.caption)
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 128, alignment: .leading)
            .padding(14)
            .cardStyle(radius: 20)
        }
        .buttonStyle(.plain)
    }
}

struct DemoModeBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "testtube.2")
                .foregroundStyle(Palette.warning)
            Text("Demo mode — AI results are simulated on device. Add your backend URL in AppConfig.json to enable real AI.")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(radius: 16, fill: Palette.warning.opacity(0.08))
    }
}
