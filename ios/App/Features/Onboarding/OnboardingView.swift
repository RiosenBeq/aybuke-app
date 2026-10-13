import SwiftUI
import PhotosUI
import AppCore

/// Three value pages → personalization → "try it on your photo" (a free,
/// on-device enhance: the "aha" before any paywall) → soft paywall.
/// Data-sharing consent is asked in context, the first time a cloud feature
/// is used (App Store Review Guideline 5.1.2(i)).
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @State private var page = 0
    @State private var interests: Set<String> = []
    @State private var legalDocument: LegalDocument?

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            symbol: "wand.and.stars",
            title: String(localized: "Your glow-up,\n*just by saying it*"),
            body: String(localized: "“Give me pink hair.” “Add soft glam.” Describe any change and watch it happen."),
            tone: .blush
        ),
        OnboardingPage(
            symbol: "heart.text.square",
            title: String(localized: "One tap.\nA whole new *aesthetic*"),
            body: String(localized: "Doll box, Y2K, ballet core, fairy princess — and fresh trends every week."),
            tone: .ink
        ),
        OnboardingPage(
            symbol: "sparkles",
            title: String(localized: "Dream it.\n*See it.*"),
            body: String(localized: "Type an idea, pick a style and get gorgeous images in seconds — no prompt skills needed."),
            tone: .charcoal
        ),
    ]

    private var interestPage: Int { pages.count }
    private var tryItPage: Int { pages.count + 1 }
    private var isLastPage: Bool { page == tryItPage }

    var body: some View {
        ZStack {
            AuroraBackground(intensity: 0.9)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if page < interestPage {
                        Button("Skip") { withAnimation(.snappy) { page = interestPage } }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .frame(height: 44)
                .padding(.horizontal, Metrics.gutter)

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        OnboardingPageView(page: item).tag(index)
                    }
                    InterestPicker(selection: $interests).tag(interestPage)
                    TryItPage().tag(tryItPage)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.snappy, value: page)

                PageDots(count: pages.count + 2, current: page)
                    .padding(.bottom, 20)

                Button(action: advance) {
                    Text(isLastPage ? "Start creating" : "Continue")
                }
                .buttonStyle(.primary)
                .padding(.horizontal, Metrics.gutter)

                Text(consentText)
                    .font(.caption2)
                    .foregroundStyle(Palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .opacity(isLastPage ? 1 : 0)
                    .environment(\.openURL, OpenURLAction { url in
                        legalDocument = LegalDocument(link: url)
                        return .handled
                    })
            }
            .readableWidth(Metrics.compactWidth, alignment: .center)
        }
        .legalSheet($legalDocument)
    }

    private var consentText: AttributedString {
        let markdown = String(localized: "By continuing you confirm you're at least 13 and agree to our [Terms of Use](\(LegalDocument.linkScheme)://terms) and [Privacy Policy](\(LegalDocument.linkScheme)://privacy).")
        var text = (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
        for run in text.runs where run.link != nil {
            text[run.range].foregroundColor = Palette.textPrimary
            text[run.range].underlineStyle = .single
        }
        return text
    }

    private func advance() {
        Haptics.tap()
        if isLastPage {
            app.completeOnboarding(interests: interests)
            // Soft paywall right after onboarding: the highest-converting placement.
            if !app.purchases.isPro {
                app.presentPaywall(source: "onboarding")
            }
        } else {
            withAnimation(.snappy) { page += 1 }
        }
    }
}

private struct OnboardingPage {
    let symbol: String
    let title: String
    let body: String
    let tone: PaletteTone
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)
            ZStack {
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(page.tone.fill)
                    .frame(width: 250, height: 310)
                    .rotationEffect(.degrees(appeared ? -7 : 0))
                    .shadow(color: Palette.ink.opacity(0.16), radius: 30, y: 18)
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(Palette.white)
                    .frame(width: 250, height: 310)
                    .overlay(
                        RoundedRectangle(cornerRadius: 40, style: .continuous)
                            .strokeBorder(Palette.ink.opacity(0.06), lineWidth: 1)
                    )
                    .overlay(
                        ZStack {
                            Circle()
                                .fill(Palette.blush)
                                .frame(width: 168, height: 168)
                            Image(systemName: page.symbol)
                                .font(.system(size: 80, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .symbolEffect(.bounce, value: appeared)
                        }
                    )
                    .rotationEffect(.degrees(appeared ? 4 : 0))
                    .shadow(color: Palette.ink.opacity(0.10), radius: 24, y: 12)
                Image(systemName: "sparkle")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Palette.white)
                    .shadow(color: Palette.ink.opacity(0.15), radius: 6, y: 2)
                    .twinkle()
                    .offset(x: 118, y: -150)
                Image(systemName: "heart.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .twinkle(phase: 0.6)
                    .offset(x: -122, y: 128)
            }
            .floating()
            .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text(styled: page.title, size: 34)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.textPrimary)
                Text(page.body)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 28)
            }
            Spacer(minLength: 12)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appeared = true }
        }
    }
}

private struct InterestPicker: View {
    @Binding var selection: Set<String>

    private struct Option: Identifiable {
        let id: String
        let title: String
        let symbol: String
    }

    private let options: [Option] = [
        Option(id: "selfies", title: String(localized: "Selfie glow-ups"), symbol: "camera.fill"),
        Option(id: "looks", title: String(localized: "Makeup & hair looks"), symbol: "sparkles"),
        Option(id: "aesthetic", title: String(localized: "Aesthetic edits"), symbol: "heart.fill"),
        Option(id: "besties", title: String(localized: "Bestie pics"), symbol: "person.2.fill"),
        Option(id: "art", title: String(localized: "Dreamy AI art"), symbol: "paintpalette.fill"),
        Option(id: "social", title: String(localized: "Content for my socials"), symbol: "heart.text.square.fill"),
        Option(id: "memories", title: String(localized: "Restore family photos"), symbol: "clock.arrow.circlepath"),
        Option(id: "business", title: String(localized: "Shots for my shop"), symbol: "bag.fill"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 8)
            Text(styled: "What are you\n*here for?*", size: 34)
                .foregroundStyle(Palette.textPrimary)
            Text("Pick as many as you like — we'll tailor your feed.")
                .font(.body)
                .foregroundStyle(Palette.textSecondary)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(options) { option in
                    let isSelected = selection.contains(option.id)
                    Button {
                        Haptics.selection()
                        if isSelected { selection.remove(option.id) } else { selection.insert(option.id) }
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: option.symbol)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                                .frame(width: 40, height: 40)
                                .background(isSelected ? Palette.blush : Palette.paper, in: Circle())
                            Text(option.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.textPrimary)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
                        .padding(14)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(isSelected ? Palette.accent : Palette.stroke, lineWidth: isSelected ? 2 : 1)
                        )
                        .overlay(alignment: .topTrailing) {
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Palette.onAccent, Palette.accent)
                                    .padding(10)
                            }
                        }
                        .shadow(color: Palette.shadow, radius: 10, y: 4)
                        .animation(Motion.bouncy, value: isSelected)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, Metrics.gutter)
    }
}

/// Free, private, instant: Core Image auto-enhance plus a warm "glow" grade,
/// shown with the signature before/after slider.
private struct TryItPage: View {
    @State private var item: PhotosPickerItem?
    @State private var original: UIImage?
    @State private var enhanced: UIImage?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 8)
            Text(styled: "See the *glow*\non your own photo", size: 34)
                .foregroundStyle(Palette.textPrimary)
            Text("A free enhance that runs on your iPhone — nothing is uploaded.")
                .font(.body)
                .foregroundStyle(Palette.textSecondary)

            if let original, let enhanced {
                BeforeAfterSlider(before: original, after: enhanced)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .frame(maxHeight: 380)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                PhotosPicker(selection: $item, matching: .images) {
                    VStack(spacing: 12) {
                        if isWorking {
                            ProgressView().tint(Palette.accent)
                        } else {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .frame(width: 76, height: 76)
                                .background(Palette.blush, in: Circle())
                        }
                        Text(isWorking ? "Adding the glow…" : "Choose a photo")
                            .font(.headline)
                            .foregroundStyle(Palette.textPrimary)
                        Text("Optional — you can skip this")
                            .font(.caption)
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .glassPanel()
                }
                .disabled(isWorking)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, Metrics.gutter)
        .animation(.snappy, value: enhanced != nil)
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            isWorking = true
            Task {
                defer { isWorking = false }
                guard let data = try? await newItem.loadTransferable(type: Data.self),
                      let picked = UIImage(data: data) else { return }
                let (before, after) = await Task.detached(priority: .userInitiated) { () -> (UIImage, UIImage) in
                    let normalized = ImageUtilities.normalized(picked, maxLongEdge: 1600)
                    return (normalized, OnDeviceImageService.quickGlow(normalized))
                }.value
                original = before
                enhanced = after
                Haptics.success()
            }
        }
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Palette.accent : Palette.strokeStrong)
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}
