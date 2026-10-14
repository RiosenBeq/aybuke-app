import SwiftUI
import StoreKit

/// Honest paywall ("Fair-Price Promise", docs/03-product-spec.md):
/// annual pre-selected with an eligibility-based free trial, monthly without
/// trial, no weekly plan, no fake timers. The billed amount is always the most
/// prominent price (App Store Review Guideline 3.1.2).
struct PaywallView: View {
    let source: String

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID = StoreProducts.yearly
    @State private var trialEligible = false
    @State private var monthlyIntroEligible = false
    @State private var errorMessage: String?
    @State private var errorTitle = String(localized: "Purchase failed")
    @State private var showPacks = false
    @State private var legalDocument: LegalDocument?
    @State private var showSignIn = false
    @State private var isRestoring = false

    private var purchases: PurchaseManager { app.purchases }

    private var selectedProduct: Product? {
        purchases.products.first { $0.id == selectedID }
    }

    private var showsTrial: Bool {
        selectedID == StoreProducts.yearly && trialEligible && purchases.yearly?.freeTrialDays != nil
    }

    /// DEBUG screenshots run without a StoreKit configuration, so show the
    /// planned price points instead of an empty loading state.
    private var isScreenshotPreview: Bool {
        #if DEBUG
        return purchases.products.isEmpty && ScreenshotScene.current != nil
        #else
        return false
        #endif
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AuroraBackground(intensity: 0.7)

            ScrollView {
                VStack(spacing: 22) {
                    header
                    benefits
                    plans
                    if showsTrial, let yearly = purchases.yearly {
                        TrialTimeline(days: yearly.freeTrialDays ?? 7, price: yearly.displayPrice)
                    } else if isScreenshotPreview {
                        TrialTimeline(days: 7, price: "$39.99")
                    }
                    if purchases.isSubscriptionPending {
                        PendingApprovalCard(text: "Waiting for approval. If it's approved, Pro turns on automatically.")
                    }
                    VStack(spacing: 10) {
                        purchaseButton
                        if let billedTerms {
                            // The billed amount stays as prominent as the button (Guideline 3.1.2).
                            Text(billedTerms)
                                .font(.display(17, weight: .regular, relativeTo: .headline))
                                .foregroundStyle(Palette.textPrimary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    packsLink
                    freeCreditsReminder
                    footer
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 56)
                .padding(.bottom, 24)
                .readableWidth(Metrics.compactWidth, alignment: .center)
            }
            .scrollIndicators(.hidden)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.icon)
            .padding(Metrics.gutter)
            .accessibilityLabel("Close")
        }
        .task { await purchases.loadProducts() }
        // Products can arrive late (after "Try again"), so check eligibility then.
        .task(id: purchases.products.count) {
            if let yearly = purchases.yearly {
                trialEligible = await purchases.isEligibleForTrial(yearly)
            }
            if let monthly = purchases.monthly {
                monthlyIntroEligible = await purchases.isEligibleForTrial(monthly)
            }
        }
        .sheet(isPresented: $showSignIn) {
            AccountPromptSheet()
                .environment(app)
        }
        .sheet(isPresented: $showPacks) {
            CreditPacksView()
                .environment(app)
                .presentationDetents([.medium, .large])
                .presentationBackground(Palette.background)
        }
        .legalSheet($legalDocument)
        .alert(errorTitle, isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 76, height: 76)
                .background(Palette.blush, in: Circle())
                .overlay(Circle().strokeBorder(Palette.white.opacity(0.7), lineWidth: 3))
                .shadow(color: Palette.blush.opacity(0.8), radius: 18, y: 8)
                .symbolEffect(.pulse)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .twinkle()
                        .offset(x: 12, y: -6)
                }
                .floating(distance: 4)
            Text(styled: "Your photos,\nin their *best light*", size: 34)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.textPrimary)
            Text("\(Brand.name) Pro unlocks every tool and trend.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 14) {
            Benefit(symbol: "bolt.fill", title: "\(app.credits.policy.proMonthlyAllowance) credits every month", detail: "Unused credits roll over to next month")
            Benefit(symbol: "sparkles", title: "Every look & style", detail: "Including the Pro-only looks and styles")
            Benefit(symbol: "photo.badge.checkmark", title: "Our best-quality AI, no watermark", detail: "Up to 4 images at once")
            Benefit(symbol: "arrow.uturn.backward.circle", title: "Failed edits are always refunded", detail: "Plus a free retry if it doesn't look like you")
        }
        .padding(18)
        .cardStyle()
    }

    private var plans: some View {
        VStack(spacing: 12) {
            if let yearly = purchases.yearly {
                PlanCard(
                    title: "Yearly",
                    price: "\(yearly.displayPrice) / year",
                    detail: yearlyDetail(yearly),
                    badge: "BEST VALUE",
                    isSelected: selectedID == yearly.id
                ) { selectedID = yearly.id }
            }
            if let monthly = purchases.monthly {
                PlanCard(
                    title: "Monthly",
                    price: "\(monthly.displayPrice) / month",
                    detail: monthlyDetail(monthly),
                    badge: monthlyIntroEligible && monthly.introOfferText != nil ? "TRY IT" : nil,
                    isSelected: selectedID == monthly.id
                ) { selectedID = monthly.id }
            }
            if isScreenshotPreview {
                PlanCard(title: "Yearly", price: "$39.99 / year",
                         detail: String(localized: "7 days free, then $39.99/year · just $3.33/month"),
                         badge: "BEST VALUE", isSelected: true) {}
                PlanCard(title: "Monthly", price: "$5.99 / month", detail: String(localized: "First month $1.99 · cancel anytime"),
                         badge: "TRY IT", isSelected: false) {}
            }
            if purchases.yearly != nil || purchases.monthly != nil || isScreenshotPreview {
                Label("No weekly plans, ever.", systemImage: "heart.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            if !isScreenshotPreview {
                StoreStatusView(purchases: purchases, showsSpinner: purchases.yearly == nil && purchases.monthly == nil,
                                unavailableText: "Subscriptions are unavailable right now.")
            }
        }
    }

    private func yearlyDetail(_ product: Product) -> String {
        var parts: [String] = []
        if trialEligible, let days = product.freeTrialDays {
            parts.append(String(localized: "\(days) days free, then \(product.displayPrice)/year"))
        }
        if let monthly = product.monthlyEquivalentPrice {
            parts.append(String(localized: "just \(monthly)/month"))
        }
        return parts.joined(separator: " · ")
    }

    private func monthlyDetail(_ product: Product) -> String {
        if monthlyIntroEligible, let intro = product.introOfferText {
            return String(localized: "\(intro), then \(product.displayPrice)/month · cancel anytime")
        }
        return String(localized: "Cancel anytime")
    }

    private var purchaseButton: some View {
        Button {
            Task { await buy() }
        } label: {
            if purchases.isPurchasing {
                ProgressView().tint(Palette.onAccent)
            } else if purchases.isSubscriptionPending {
                Text("Waiting for approval")
            } else {
                Text(ctaTitle)
            }
        }
        .buttonStyle(.primary)
        .disabled((selectedProduct == nil && !isScreenshotPreview) || purchases.isPurchasing
                  || purchases.isSubscriptionPending || !purchases.canBuy)
    }

    /// With a trial or an intro price the button stays neutral and the line
    /// under it states what will be billed.
    private var ctaTitle: String {
        if isScreenshotPreview { return String(localized: "Continue") }
        guard let product = selectedProduct, billedTerms == nil else { return String(localized: "Continue") }
        switch product.periodLabel {
        case "year": return String(localized: "Continue — \(product.displayPrice)/year")
        case "week": return String(localized: "Continue — \(product.displayPrice)/week")
        default: return String(localized: "Continue — \(product.displayPrice)/month")
        }
    }

    /// "7 days free, then **$39.99**/year": the trial or intro terms with the
    /// billed price in bold, reusing the plan cards' sentences.
    private var billedTerms: AttributedString? {
        if isScreenshotPreview {
            return Self.emphasizing("$39.99", in: String(localized: "\(7) days free, then \("$39.99")/year"))
        }
        guard let product = selectedProduct else { return nil }
        if showsTrial, let days = product.freeTrialDays {
            return Self.emphasizing(product.displayPrice, in: String(localized: "\(days) days free, then \(product.displayPrice)/year"))
        }
        if product.id == StoreProducts.monthly, monthlyIntroEligible, let intro = product.introOfferText {
            return Self.emphasizing(product.displayPrice,
                                    in: String(localized: "\(intro), then \(product.displayPrice)/month · cancel anytime"))
        }
        return nil
    }

    private static func emphasizing(_ price: String, in sentence: String) -> AttributedString {
        var text = AttributedString(sentence)
        // The last match is the recurring price ("First month $1.99, then $5.99/month").
        if let range = text.range(of: price, options: .backwards) {
            text[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return text
    }

    private var packsLink: some View {
        Button {
            showPacks = true
        } label: {
            Text("Not ready to subscribe? **Get a credit pack**")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    /// Out of free credits? Paying is optional: offer a reminder instead.
    @ViewBuilder
    private var freeCreditsReminder: some View {
        if source == "out_of_credits", !purchases.isPro {
            if app.notifier.preferences.creditsBack, app.notifier.isAllowedBySystem {
                Label("We'll remind you when your free credits are back", systemImage: "bell.badge")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            } else {
                Button {
                    Task {
                        if await app.notifier.set(.creditsBack, on: true) {
                            app.syncReminders()
                            Haptics.success()
                            app.showToast("We'll remind you when your free credits are back ✨", style: .success)
                            dismiss()
                        } else {
                            app.showToast(Platform.isMac
                                ? "Turn on notifications for \(Brand.name) in System Settings to get reminders."
                                : "Turn on notifications for \(Brand.name) in Settings to get reminders.", style: .info)
                        }
                    }
                } label: {
                    Text("Or wait for your free daily credits. **Remind me when they're back**")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                Button {
                    Task { await restore() }
                } label: {
                    if isRestoring {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Restore")
                    }
                }
                .disabled(isRestoring)
                if app.canUseAccounts, !app.isSignedIn {
                    Button("Sign in") { showSignIn = true }
                }
                Button("Terms") { legalDocument = .terms }
                Button("Privacy") { legalDocument = .privacy }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.textSecondary)

            Text("Payment is charged to your Apple Account. Subscriptions renew automatically at the price shown unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in Settings › Apple Account › Subscriptions.")
                .font(.caption2)
                .foregroundStyle(Palette.textTertiary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Purchase

    private func buy() async {
        guard let product = selectedProduct else { return }
        let startsTrial = showsTrial
        do {
            let token = await app.appAccountToken()
            guard try await purchases.purchase(product, appAccountToken: token) == .purchased else { return }
            app.credits.refresh(isPro: purchases.isPro)
            if startsTrial, let days = product.freeTrialDays,
               let billingDate = Calendar.current.date(byAdding: .day, value: days, to: Date()) {
                await TrialReminder.schedule(billingDate: billingDate, price: product.displayPrice, mayAsk: true)
            }
            Haptics.success()
            app.showToast("Welcome to \(Brand.name) Pro ✦", style: .success)
            dismiss()
            app.offerAccountAfterPurchase()
        } catch {
            guard !AppModel.isCancellation(error) else { return }
            errorTitle = String(localized: "Purchase failed")
            errorMessage = AppModel.localizedMessage(for: error)
        }
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await purchases.restore()
        } catch {
            guard !AppModel.isCancellation(error) else { return }
            errorTitle = String(localized: "Restore failed")
            errorMessage = AppModel.localizedMessage(for: error)
            return
        }
        if purchases.isPro {
            app.credits.refresh(isPro: true)
            dismiss()
        } else {
            errorTitle = String(localized: "Nothing to restore")
            errorMessage = String(localized: "No active subscription found for this Apple Account.")
        }
    }
}

/// "Waiting for approval": status only. StoreKit doesn't say who approves,
/// and the copy never asks anyone to buy (UCPD Annex I No. 28).
struct PendingApprovalCard: View {
    let text: LocalizedStringKey

    var body: some View {
        Label {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "hourglass")
                .foregroundStyle(Palette.ink)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(radius: 18)
    }
}

/// Loading, "can't reach the App Store" with Try again, and turned-off
/// purchases (Screen Time or device management), shared by the paywall and the packs.
struct StoreStatusView: View {
    let purchases: PurchaseManager
    /// None of this view's products are on screen yet.
    var showsSpinner = true
    /// What to say when the App Store answered without these products.
    var unavailableText: LocalizedStringKey

    var body: some View {
        VStack(spacing: 10) {
            if purchases.isClosedForPreview {
                Label("Purchases open when \(Brand.name) launches. This is a preview build.", systemImage: "testtube.2")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            } else if !purchases.canMakePayments {
                Label("Purchases are turned off on this device.", systemImage: "lock.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            switch purchases.loadState {
            case .idle, .loading:
                if showsSpinner {
                    ProgressView().tint(Palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
            case .unavailable where !showsSpinner:
                // The products shown here did load; others are missing.
                EmptyView()
            case .unreachable, .unavailable:
                Text(purchases.loadState == .unreachable ? "Couldn't reach the App Store. Check your connection." : unavailableText)
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Try again") {
                    Task { await purchases.loadProducts() }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
            case .loaded:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Pieces

private struct Benefit: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 30, height: 30)
                .background(Palette.blush, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }
}

private struct PlanCard: View {
    let title: LocalizedStringKey
    let price: LocalizedStringKey
    /// Already localized.
    let detail: String
    let badge: LocalizedStringKey?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Palette.accent : Palette.textTertiary)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.textSecondary)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundStyle(Palette.onPrimary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Palette.primary, in: Capsule())
                        }
                    }
                    // The billed amount is the most prominent price element.
                    Text(price)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Palette.textPrimary)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                Spacer()
            }
            .padding(16)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Palette.accent : Palette.stroke, lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: Palette.shadow, radius: isSelected ? 14 : 8, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// "How your free trial works" — shown by ~3% of paywalls; builds trust.
private struct TrialTimeline: View {
    let days: Int
    let price: String

    private var chargeDate: String {
        let date = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How your free trial works")
                .font(.cardTitle)
                .foregroundStyle(Palette.textPrimary)
                .padding(.bottom, 14)
            Step(symbol: "lock.open.fill", title: "Today", detail: "Unlock everything. No charge today.", isLast: false)
            Step(symbol: "bell.fill", title: "Day \(max(1, days - 1))", detail: "We'll remind you before your trial ends.", isLast: false)
            Step(symbol: "creditcard.fill", title: "Day \(days)", detail: "You'll be charged \(price) on \(chargeDate) unless you cancel before.", isLast: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private struct Step: View {
        let symbol: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
        let isLast: Bool

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    Image(systemName: symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.onPrimary)
                        .frame(width: 28, height: 28)
                        .background(Palette.primary, in: Circle())
                    if !isLast {
                        Rectangle()
                            .fill(Palette.primary)
                            .frame(width: 2, height: 26)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
        }
    }
}

/// One-off credit packs — for occasional users who don't want a subscription.
struct CreditPacksView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Credit packs")
                    .font(.screenTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.top, 24)
                Text("Pay once. Credits never expire. 1 credit = 1 creation or edit.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                CreditPackList { dismiss() }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// The pack rows with their loading, error and approval states; used by the
/// packs sheet and the out-of-credits sheet.
struct CreditPackList: View {
    /// Called after credits were added (typically to dismiss the sheet).
    var onPurchased: () -> Void = {}

    @Environment(AppModel.self) private var app
    @State private var errorMessage: String?

    private var purchases: PurchaseManager { app.purchases }

    private var hasPendingPack: Bool {
        purchases.pendingProductIDs.contains { StoreProducts.creditPacks[$0] != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasPendingPack {
                PendingApprovalCard(text: "Waiting for approval. If it's approved, your credits are added automatically.")
            }
            ForEach(purchases.creditPacks, id: \.id) { product in
                row(for: product)
            }
            StoreStatusView(purchases: purchases, showsSpinner: purchases.creditPacks.isEmpty,
                            unavailableText: "Credit packs are unavailable right now.")
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            }
        }
        .task { await purchases.loadProducts() }
    }

    private func row(for product: Product) -> some View {
        let isPending = purchases.pendingProductIDs.contains(product.id)
        return Button {
            Task { await buy(product) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(product.description)
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                    if let perCredit = product.perCreditPrice {
                        Text("≈ \(perCredit) per credit")
                            .font(.caption2)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                Spacer()
                Group {
                    if isPending {
                        Text("Waiting for approval")
                            .font(.footnote.weight(.semibold))
                    } else {
                        Text(product.displayPrice)
                            .font(.headline)
                    }
                }
                .foregroundStyle(Palette.onAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Palette.accent, in: Capsule())
            }
            .padding(14)
            .cardStyle(radius: 18)
        }
        .buttonStyle(.plain)
        .disabled(purchases.isPurchasing || isPending || !purchases.canBuy)
    }

    private func buy(_ product: Product) async {
        errorMessage = nil
        do {
            let token = await app.appAccountToken()
            guard try await purchases.purchase(product, appAccountToken: token) == .purchased else { return }
            Haptics.success()
            app.showToast("Credits added ✦", style: .success)
            onPurchased()
            app.offerAccountAfterPurchase()
        } catch {
            guard !AppModel.isCancellation(error) else { return }
            errorMessage = AppModel.localizedMessage(for: error)
        }
    }
}
