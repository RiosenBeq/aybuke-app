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

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            symbol: "wand.and.stars",
            title: "Edit photos by\njust saying it",
            body: "“Make it golden hour.” “Put me in a suit.” Describe any change and watch it happen.",
            colors: [Palette.primary, Palette.gradientEnd]
        ),
        OnboardingPage(
            symbol: "theatermask.and.paintbrush",
            title: "One tap.\nTotally new you.",
            body: "Figurines, pro headshots, anime, old-photo restore and fresh trends every week.",
            colors: [Palette.gradientEnd, Palette.secondary]
        ),
        OnboardingPage(
            symbol: "sparkles",
            title: "Create anything\nyou can imagine",
            body: "Type an idea, pick a style and get stunning images in seconds — no prompt skills needed.",
            colors: [Palette.secondary, Palette.primary]
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

                Text("By continuing you agree to our Terms and Privacy Policy.")
                    .font(.caption2)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .opacity(isLastPage ? 1 : 0)
            }
        }
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
    let colors: [Color]
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)
            ZStack {
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(LinearGradient(colors: page.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 250, height: 310)
                    .rotationEffect(.degrees(appeared ? -6 : 0))
                    .shadow(color: page.colors[0].opacity(0.45), radius: 40, y: 20)
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(width: 250, height: 310)
                    .rotationEffect(.degrees(appeared ? 5 : 0))
                    .overlay(
                        Image(systemName: page.symbol)
                            .font(.system(size: 92, weight: .semibold))
                            .foregroundStyle(.white)
                            .symbolEffect(.bounce, value: appeared)
                            .rotationEffect(.degrees(appeared ? 5 : 0))
                    )
            }
            .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text(page.title)
                    .font(.heroTitle)
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
        Option(id: "selfies", title: "Better selfies", symbol: "person.crop.circle"),
        Option(id: "art", title: "AI art & ideas", symbol: "paintpalette"),
        Option(id: "social", title: "Content for social", symbol: "heart.text.square"),
        Option(id: "memories", title: "Restore old photos", symbol: "clock.arrow.circlepath"),
        Option(id: "business", title: "Product photos", symbol: "bag"),
        Option(id: "fun", title: "Just for fun", symbol: "face.smiling"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 8)
            Text("What will you\ncreate first?")
                .font(.heroTitle)
                .foregroundStyle(Palette.textPrimary)
            Text("Pick any — we'll tailor your home screen.")
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
                                .font(.title2)
                                .foregroundStyle(isSelected ? AnyShapeStyle(Palette.brandGradient) : AnyShapeStyle(Palette.textSecondary))
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
                                .strokeBorder(isSelected ? Palette.primary : Palette.stroke, lineWidth: isSelected ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
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
            Text("See the glow on\nyour own photo")
                .font(.heroTitle)
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
                            ProgressView().tint(Palette.primary)
                        } else {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 40, weight: .semibold))
                                .foregroundStyle(Palette.brandGradient)
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
                    .fill(index == current ? AnyShapeStyle(Palette.brandGradient) : AnyShapeStyle(Palette.strokeStrong))
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}
