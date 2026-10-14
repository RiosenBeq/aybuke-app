import SwiftUI
import AppCore

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var legalDocument: LegalDocument?
    @State private var openCategory: TemplateCategory?
    @State private var showInvite = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    header
                        .padding(.horizontal, Metrics.gutter)
                        .reveal(0)

                    if let banner = app.modeBanner {
                        ModeBanner(text: banner)
                            .padding(.horizontal, Metrics.gutter)
                            .reveal(1)
                    }

                    if app.allowsCloudAI && app.isCloudOffline {
                        OfflineNotice()
                            .padding(.horizontal, Metrics.gutter)
                            .transition(.opacity)
                    }

                    // Under 13 Explore shows only the free on-device tools.
                    if app.allowsCloudAI {
                        heroCard
                            .tourAnchor(.hero)
                            .padding(.horizontal, Metrics.gutter)
                            .reveal(1)
                    }

                    quickTools
                        .tourAnchor(.quickTools)
                        .reveal(2)

                    if app.allowsCloudAI {
                        ForEach(Array(orderedCategories.enumerated()), id: \.element) { index, category in
                            templateRow(category)
                                .reveal(3 + index)
                        }

                        createBanner
                            .padding(.horizontal, Metrics.gutter)
                            .reveal(8)
                    }

                    inviteBanner
                        .padding(.horizontal, Metrics.gutter)
                        .reveal(9)
                }
                .padding(.vertical, 12)
                .readableWidth()
            }
            .scrollIndicators(.hidden)
            .background(AuroraBackground(intensity: 0.55))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $openCategory) { category in
                CategoryView(category: category)
                    .environment(app)
            }
            .sheet(isPresented: $showInvite) {
                InviteView()
                    .environment(app)
                    .pageSheetSizing()
            }
            .legalSheet($legalDocument)
            #if DEBUG
            .onAppear {
                if ScreenshotScene.current == .settings || ScreenshotScene.current == .feelGood { app.isSettingsPresented = true }
                if ScreenshotScene.current == .invite { showInvite = true }
                if ScreenshotScene.current == .legal { legalDocument = .privacy }
                if ScreenshotScene.current == .collection {
                    openCategory = UserDefaults.standard.string(forKey: "GLCategory").flatMap(TemplateCategory.init(rawValue:)) ?? .seasonal
                }
            }
            #endif
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Brand.name)
                    .font(.display(30, weight: .heavy, relativeTo: .largeTitle))
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("What are we glowing up today?")
                    .font(.accent(16, relativeTo: .subheadline))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            if app.allowsCloudAI {
                CreditPill(balance: app.credits.balance, isPro: app.purchases.isPro) {
                    // Pro: Settings has the Membership and Credits sections.
                    if app.purchases.isPro {
                        app.isSettingsPresented = true
                    } else {
                        app.presentPaywall(source: "home_credits")
                    }
                }
                .tourAnchor(.credits)
            }
            Button {
                app.isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.icon)
            .accessibilityLabel("Settings")
            .tourAnchor(.settings)
        }
    }

    private var heroCard: some View {
        Button {
            Haptics.tap()
            app.startEditing(tool: .magicEdit)
        } label: {
            ZStack(alignment: .bottomLeading) {
                Palette.blush
                Circle()
                    .fill(Palette.white.opacity(0.5))
                    .frame(width: 260, height: 260)
                    .blur(radius: 40)
                    .offset(x: 170, y: -90)
                HeroSparkles()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Magic Edit")
                        .eyebrowStyle(Palette.ink.opacity(0.7))
                    Text(styled: "Say the change.\nWatch it *glow.*", size: 26)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text("Try it on your photo")
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.blush)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Palette.ink, in: Capsule())
                    .padding(.top, 6)
                }
                .padding(20)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .glowSweep()
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Palette.stroke, lineWidth: 1)
            )
            .shadow(color: Palette.blush.opacity(0.6), radius: 24, y: 12)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
        .accessibilityLabel("Magic Edit. Describe any change to your photo.")
    }

    private var quickTools: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Quick tools")
                .padding(.horizontal, Metrics.gutter)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(EditorTool.quickTools.filter { app.allowsCloudAI || !$0.usesCloudAI }.enumerated()), id: \.element) { index, tool in
                        QuickToolTile(title: LocalizedStringKey(tool.title), caption: LocalizedStringKey(tool.caption), symbolName: tool.symbolName, palette: Self.toolPalettes[index % Self.toolPalettes.count]) {
                            Haptics.tap()
                            app.startEditing(tool: tool)
                        }
                    }
                    QuickToolTile(title: "Video", caption: "Cut silences · effects", symbolName: "video.fill", palette: .sunset) {
                        Haptics.tap()
                        app.isVideoPickerPresented = true
                    }
                    QuickToolTile(title: "Best shot", caption: "Free · sorts by light", symbolName: "photo.stack", palette: .lilac) {
                        Haptics.tap()
                        app.isBestShotPresented = true
                    }
                }
                .padding(.horizontal, Metrics.gutter)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    /// Light aura palettes only: tool icons stay ink on colour.
    private static let toolPalettes: [AuraPalette] = [.bubblegum, .lilac, .mint, .sunset, .butter]

    private func templateRow(_ category: TemplateCategory) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: LocalizedStringKey(category.title(on: AppClock.now)), actionTitle: "See all") {
                Haptics.tap()
                openCategory = category
            }
            .padding(.horizontal, Metrics.gutter)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(TemplateCatalog.templates(in: category, on: AppClock.now)) { template in
                        Button {
                            Haptics.tap()
                            app.startEditing(tool: .styles, template: template)
                        } label: {
                            TemplateCard(template: template)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, Metrics.gutter)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private var createBanner: some View {
        Button {
            app.selectedTab = .create
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "text.cursor")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.blush)
                    .frame(width: 52, height: 52)
                    .background(Palette.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        .buttonStyle(PressableButtonStyle(scale: 0.97))
    }

    /// "Glow together": share the app with friends (a story card with a QR code).
    private var inviteBanner: some View {
        Button {
            Haptics.tap()
            showInvite = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "heart.circle.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(
                        LinearGradient(colors: [Palette.auraMint, Palette.auraLilac, Palette.auraPink, Palette.auraPeach],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text("Glow together")
                        .font(.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                    Text("Invite your besties with a story card")
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
        .buttonStyle(PressableButtonStyle(scale: 0.97))
    }

    /// Puts the categories that match onboarding interests first.
    private var orderedCategories: [TemplateCategory] {
        let preferred: [String: TemplateCategory] = [
            "selfies": .glowUp, "looks": .glowUp, "aesthetic": .aesthetic, "besties": .trending,
            "art": .art, "memories": .dreamy, "social": .trending, "business": .business,
        ]
        let boosted = app.interests.compactMap { preferred[$0] }
        let order = TemplateCategory.allCases
        return TemplateCatalog.categories(on: AppClock.now).sorted { lhs, rhs in
            let lhsScore = (lhs == .trending ? 2 : 0) + (boosted.contains(lhs) ? 1 : 0)
            let rhsScore = (rhs == .trending ? 2 : 0) + (boosted.contains(rhs) ? 1 : 0)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }
    }
}

private struct QuickToolTile: View {
    let title: LocalizedStringKey
    let caption: LocalizedStringKey
    let symbolName: String
    var palette: AuraPalette = .bubblegum
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.isDark ? Palette.white : Palette.ink)
                    .frame(width: 44, height: 44)
                    .background(AuraFill(palette: palette).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 128, alignment: .leading)
            .padding(14)
            .cardStyle(radius: 20)
        }
        .buttonStyle(.pressable)
    }
}

/// Hearts and sparkles scattered over the Magic Edit hero card.
private struct HeroSparkles: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                ForEach(Array(Self.items.enumerated()), id: \.offset) { index, item in
                    Image(systemName: item.symbol)
                        .font(.system(size: item.size, weight: .bold))
                        .foregroundStyle(item.isWhite ? Palette.white : Palette.ink.opacity(0.85))
                        .rotationEffect(.degrees(item.rotation))
                        .twinkle(phase: Double(index) * 0.35)
                        .position(x: size.width * item.x, y: size.height * item.y)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private struct Item {
        let symbol: String
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let rotation: Double
        let isWhite: Bool
    }

    private static let items: [Item] = [
        Item(symbol: "sparkle", x: 0.86, y: 0.18, size: 30, rotation: 0, isWhite: true),
        Item(symbol: "heart.fill", x: 0.72, y: 0.32, size: 18, rotation: -14, isWhite: false),
        Item(symbol: "sparkle", x: 0.93, y: 0.46, size: 14, rotation: 10, isWhite: false),
        Item(symbol: "heart.fill", x: 0.62, y: 0.12, size: 12, rotation: 12, isWhite: true),
        Item(symbol: "sparkles", x: 0.80, y: 0.62, size: 22, rotation: 0, isWhite: true),
    ]
}

/// Explains that results are simulated (demo) or come from a developer API key.
struct ModeBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "testtube.2")
                .foregroundStyle(Palette.warning)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(radius: 16)
    }
}
