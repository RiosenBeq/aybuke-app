import SwiftUI
import PhotosUI
import AppCore

/// Two value pages → the neutral age step → personalization → "try it on
/// your photo" (Digicam '04, a free on-device effect: the "aha" before any
/// paywall). Her result opens in the editor or saves to My Works; the soft
/// paywall (adults only) follows that first success.
/// Data-sharing consent is asked in context, the first time a cloud feature
/// is used (App Store Review Guideline 5.1.2(i)).
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var page = 0
    @State private var interests: Set<String> = []
    @State private var legalDocument: LegalDocument?
    /// "Skip" goes from the value pages straight to the try-it page (through
    /// the age step when it's still needed).
    @State private var skippedIntro = false
    @State private var tryItem: PhotosPickerItem?
    @State private var tryPhoto: TryItPhoto?
    @State private var isTrying = false
    @State private var isSaving = false

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
            body: String(localized: "Doll box, Y2K, ballet core, fairy princess and more — one tap each."),
            tone: .ink
        ),
    ]

    /// Outside the swipeable pages, so it can't be swiped past.
    private var agePage: Int { pages.count }
    private var interestPage: Int { pages.count + 1 }
    private var tryItPage: Int { pages.count + 2 }
    private var isLastPage: Bool { page == tryItPage }

    var body: some View {
        ZStack {
            AuroraBackground(intensity: 0.9)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if page < agePage {
                        Button("Skip") {
                            skippedIntro = true
                            withAnimation(.snappy) { page = app.needsAgeStep ? agePage : tryItPage }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                    }
                }
                .frame(minHeight: 44)
                .padding(.horizontal, Metrics.gutter)

                if page == agePage {
                    AgeStepView(mode: .onboarding) { record in
                        let accepted = app.recordAge(record)
                        if accepted { withAnimation(.snappy) { page = skippedIntro ? tryItPage : interestPage } }
                        return accepted
                    }
                    .transition(.opacity)
                } else {
                    TabView(selection: $page) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                            OnboardingPageView(page: item).tag(index)
                        }
                        // Reachable only once the age step is answered.
                        if !app.needsAgeStep {
                            InterestPicker(selection: $interests).tag(interestPage)
                            TryItPage(photo: tryPhoto, isWorking: isTrying, item: $tryItem) {
                                // At accessibility sizes the terms scroll with the page.
                                if typeSize.isAccessibilitySize { legalCaption }
                            }
                            .tag(tryItPage)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.snappy, value: page)
                    // Scrolled text stays above the dots and buttons.
                    .clipped()
                }

                PageDots(count: pages.count + 3, current: page)
                    // A gap, so scrolled content never meets the dots.
                    .padding(.top, 8)
                    .padding(.bottom, 20)

                if isLastPage {
                    tryItButtons
                        .padding(.horizontal, Metrics.gutter)
                } else if page != agePage {
                    Button(action: advance) {
                        Text("Continue")
                    }
                    .buttonStyle(.primary)
                    .padding(.horizontal, Metrics.gutter)
                }

                // Every try-it button finishes onboarding, so the terms stay in view there.
                if isLastPage && !typeSize.isAccessibilitySize {
                    legalCaption
                } else {
                    Color.clear.frame(height: 12)
                }
            }
            .readableWidth(Metrics.compactWidth, alignment: .center)
        }
        .legalSheet($legalDocument)
        .onChange(of: tryItem) { _, newItem in
            guard let newItem else { return }
            Task { await tryLook(on: newItem) }
        }
        #if DEBUG
        .task { applyScreenshotPage() }
        #endif
    }

    private var legalCaption: some View {
        Text(consentText)
            .font(.caption2)
            .foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.center)
            .finePrintBacking()
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .environment(\.openURL, OpenURLAction { url in
                legalDocument = LegalDocument(link: url)
                return .handled
            })
    }

    /// Choose a photo or skip; with a result, keep editing or save it.
    @ViewBuilder
    private var tryItButtons: some View {
        VStack(spacing: 10) {
            if let tryPhoto {
                Button("Keep editing") { keepEditing(tryPhoto) }
                    .buttonStyle(.primary)
                Button("Save to My Works") { Task { await save(tryPhoto) } }
                    .buttonStyle(.secondaryFull)
                    .disabled(isSaving)
            } else {
                PhotosPicker(selection: $tryItem, matching: .images) {
                    Text("Start with your photo")
                }
                .buttonStyle(.primary)
                .disabled(isTrying)
                Button("Skip for now", action: finishWithoutPhoto)
                    .buttonStyle(.secondaryFull)
                    .disabled(isTrying)
            }
        }
    }

    private var consentText: AttributedString {
        let markdown = String(localized: "By continuing you agree to our [Terms of Use](\(LegalDocument.linkScheme)://terms) and [Privacy Policy](\(LegalDocument.linkScheme)://privacy).")
        var text = (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
        for run in text.runs where run.link != nil {
            text[run.range].foregroundColor = Palette.textPrimary
            text[run.range].underlineStyle = .single
        }
        return text
    }

    private func advance() {
        Haptics.tap()
        if page + 1 == agePage && !app.needsAgeStep {
            withAnimation(.snappy) { page = interestPage }
        } else {
            withAnimation(.snappy) { page += 1 }
        }
    }

    // MARK: Try it

    /// Decodes like the editor does (editing size, RAW developed), then applies
    /// Digicam '04 on the device.
    private func tryLook(on item: PhotosPickerItem) async {
        isTrying = true
        defer {
            isTrying = false
            // Picking the same photo again must still trigger onChange.
            tryItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let decoded = await PhotoDecoder.decode(data) else {
            Haptics.error()
            app.showToast("Couldn't open that photo. Try another one.", style: .error)
            return
        }
        let image = decoded.image
        let look = await Task.detached(priority: .userInitiated) {
            TryItPhoto.effect.apply(to: image, options: TryItPhoto.options)
        }.value
        withAnimation(.snappy) {
            tryPhoto = TryItPhoto(original: image, result: look, sourceType: decoded.sourceType)
        }
        Haptics.success()
    }

    /// The editor opens on Effects with the same look previewed; the paywall
    /// waits until she closes it.
    private func keepEditing(_ photo: TryItPhoto) {
        Haptics.tap()
        app.completeOnboarding(interests: interests)
        app.deferOnboardingPaywall()
        app.openEditor(with: photo.original, tool: .effects, provenance: photo.provenance, previewEffect: TryItPhoto.effect)
    }

    /// An on-device effect: no mark and no AI claim (`operation: nil`).
    private func save(_ photo: TryItPhoto) async {
        guard !isSaving else { return }
        isSaving = true
        await app.saveToLibrary([photo.result], operation: nil, title: TryItPhoto.effect.title, prompt: nil,
                                inheritedSourceType: photo.provenance.storedSourceType)
        Haptics.success()
        app.showToast("Saved to My Works ✨", style: .success)
        app.completeOnboarding(interests: interests)
        app.offerOnboardingPaywall()
    }

    private func finishWithoutPhoto() {
        Haptics.tap()
        app.completeOnboarding(interests: interests)
        app.offerOnboardingPaywall()
    }

    #if DEBUG
    /// `-GLOnboardingPage tryit|result|interests|1` for screenshots of a later page.
    private func applyScreenshotPage() {
        guard ScreenshotScene.current == .onboarding, !app.needsAgeStep,
              let target = UserDefaults.standard.string(forKey: "GLOnboardingPage") else { return }
        // `interests` and `1` (the second value page) for layout QA.
        page = target == "interests" ? interestPage : Int(target) ?? tryItPage
        if target == "result" {
            let image = ScreenshotFixtures.goldenLandscape
            tryPhoto = TryItPhoto(original: image, result: TryItPhoto.effect.apply(to: image, options: TryItPhoto.options),
                                  sourceType: nil)
        }
    }
    #endif
}

/// The try-it photo, before and after the free look.
private struct TryItPhoto {
    /// A retro camera look, not a face "glow-up": it never reshapes or retouches.
    static let effect = RetroEffect.digicam
    static var options: RetroEffect.Options { RetroEffect.Options(extra: effect.option?.isOnByDefault ?? true) }

    let original: UIImage
    let result: UIImage
    /// The AI marking the file already carried, kept through saving.
    let sourceType: DigitalSourceType?

    var provenance: Provenance { Provenance(inheritedSourceType: sourceType) }
}

/// Scrolls when the text is too large for the screen and stays centered
/// when it isn't.
private struct OnboardingScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingScroll {
            VStack(spacing: 28) {
                // Decorative; at accessibility sizes the words get the room.
                if !typeSize.isAccessibilitySize {
                    art
                }

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
                .padding(.horizontal, typeSize.isAccessibilitySize ? Metrics.gutter : 0)
            }
            .padding(.vertical, 12)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appeared = true }
        }
    }

    private var art: some View {
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
                .rotationEffect(.degrees(appeared && !reduceMotion ? 4 : 0))
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
    }
}

private struct InterestPicker: View {
    @Binding var selection: Set<String>
    @Environment(\.dynamicTypeSize) private var typeSize

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

    private var columns: [GridItem] {
        typeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        OnboardingScroll {
            VStack(alignment: .leading, spacing: 18) {
                Text(styled: "What are you\n*here for?*", size: 34)
                    .foregroundStyle(Palette.textPrimary)
                Text("Pick as many as you like — we'll put them near the top of Explore.")
                    .font(.body)
                    .foregroundStyle(Palette.textSecondary)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(options) { option in
                        tile(option)
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 8)
        }
    }

    private func tile(_ option: Option) -> some View {
        let isSelected = selection.contains(option.id)
        return Button {
            Haptics.selection()
            if isSelected { selection.remove(option.id) } else { selection.insert(option.id) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // A fixed circle can't hold an accessibility-size symbol; the words are enough.
                if !typeSize.isAccessibilitySize {
                    Image(systemName: option.symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 40, height: 40)
                        .background(isSelected ? Palette.blush : Palette.paper, in: Circle())
                }
                Text(option.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .padding(.trailing, typeSize.isAccessibilitySize ? 28 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: typeSize.isAccessibilitySize ? 0 : 84, alignment: .leading)
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

/// Free, private, instant: Digicam '04 on her own photo, shown with the
/// signature before/after slider. The buttons live in OnboardingView.
private struct TryItPage<Footer: View>: View {
    let photo: TryItPhoto?
    let isWorking: Bool
    @Binding var item: PhotosPickerItem?
    @ViewBuilder var footer: Footer
    /// The photo takes the room the words leave on the page, so it's never cut
    /// off under the page dots on short screens, with long translations or
    /// large text (the page scrolls when even the smallest size doesn't fit).
    @State private var pageHeight: CGFloat = 0
    @State private var wordsHeight: CGFloat = 0

    var body: some View {
        OnboardingScroll {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(styled: "Try *Digicam '04*\non your photo", size: 34)
                        .foregroundStyle(Palette.textPrimary)
                    Text("A free Y2K camera look, made right on your device. Nothing is uploaded.")
                        .font(.body)
                        .foregroundStyle(Palette.textSecondary)
                }
                // Never squeezed to make room for the photo; the page scrolls instead.
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { wordsHeight = $0 }

                if let photo {
                    BeforeAfterSlider(before: photo.original, after: photo.result)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .frame(height: room(from: 180, upTo: 320))
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
                            Text(isWorking ? "Adding \(TryItPhoto.effect.title)…" : "Choose a photo")
                                .font(.headline)
                                .foregroundStyle(Palette.textPrimary)
                        }
                        .frame(maxWidth: .infinity, minHeight: room(from: 150, upTo: 220))
                        .glassPanel()
                    }
                    .disabled(isWorking)
                }
                footer
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 8)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
        .animation(.snappy, value: photo != nil)
    }

    /// The height left under the words (16 pt spacing and 8 pt padding above
    /// and below), between `floor` and `cap`.
    private func room(from floor: CGFloat, upTo cap: CGFloat) -> CGFloat {
        min(cap, max(floor, pageHeight - wordsHeight - 32))
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
