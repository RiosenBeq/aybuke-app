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
    @State private var errorMessage: String?
    @State private var errorTitle = "Purchase failed"
    @State private var showPacks = false
    @State private var legalDocument: LegalDocument?

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
                        TrialTimeline(days: 7, price: "$59.99")
                    }
                    purchaseButton
                    packsLink
                    footer
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 56)
                .padding(.bottom, 24)
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
        .task {
            await purchases.loadProducts()
            if let yearly = purchases.yearly {
                trialEligible = await purchases.isEligibleForTrial(yearly)
            }
        }
        .sheet(isPresented: $showPacks) {
            CreditPacksView()
                .environment(app)
                .presentationDetents([.medium])
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
            Benefit(symbol: "sparkles", title: "Every trend & style, first", detail: "New templates within 48 hours of a trend")
            Benefit(symbol: "photo.badge.checkmark", title: "HD exports, no watermark", detail: "Up to 4 images at once")
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
                    detail: "Cancel anytime",
                    badge: nil,
                    isSelected: selectedID == monthly.id
                ) { selectedID = monthly.id }
            }
            if isScreenshotPreview {
                PlanCard(title: "Yearly", price: "$59.99 / year", detail: "7 days free, then $59.99/year · ≈ $1.15/week",
                         badge: "BEST VALUE", isSelected: true) {}
                PlanCard(title: "Monthly", price: "$9.99 / month", detail: "Cancel anytime", badge: nil, isSelected: false) {}
            } else if purchases.products.isEmpty {
                VStack(spacing: 8) {
                    ProgressView().tint(Palette.textSecondary)
                    if let error = purchases.loadError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
    }

    private func yearlyDetail(_ product: Product) -> String {
        var parts: [String] = []
        if trialEligible, let days = product.freeTrialDays {
            parts.append("\(days) days free, then \(product.displayPrice)/year")
        }
        if let weekly = product.weeklyEquivalentPrice {
            parts.append("≈ \(weekly)/week")
        }
        return parts.joined(separator: " · ")
    }

    private var purchaseButton: some View {
        Button {
            Task { await buy() }
        } label: {
            if purchases.isPurchasing {
                ProgressView().tint(Palette.onAccent)
            } else {
                Text(ctaTitle)
            }
        }
        .buttonStyle(.primary)
        .disabled((selectedProduct == nil && !isScreenshotPreview) || purchases.isPurchasing)
    }

    private var ctaTitle: String {
        if isScreenshotPreview { return "Start my 7-day free trial" }
        guard let product = selectedProduct else { return "Continue" }
        if showsTrial, let days = product.freeTrialDays {
            return "Start my \(days)-day free trial"
        }
        return "Continue — \(product.displayPrice)/\(product.periodLabel)"
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

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                Button("Restore") {
                    Task {
                        await purchases.restore()
                        if purchases.isPro {
                            app.credits.refresh(isPro: true)
                            dismiss()
                        } else {
                            errorTitle = "Nothing to restore"
                            errorMessage = "No active subscription found for this Apple Account."
                        }
                    }
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
            let success = try await purchases.purchase(product, appAccountToken: token)
            guard success else { return }
            app.credits.refresh(isPro: purchases.isPro)
            if startsTrial, let days = product.freeTrialDays {
                await TrialReminder.schedule(trialDays: days, price: product.displayPrice)
            }
            Haptics.success()
            app.showToast("Welcome to \(Brand.name) Pro ✦", style: .success)
            dismiss()
        } catch {
            errorTitle = "Purchase failed"
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Pieces

private struct Benefit: View {
    let symbol: String
    let title: String
    let detail: String

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
    let title: String
    let price: String
    let detail: String
    let badge: String?
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
        let title: String
        let detail: String
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
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Credit packs")
                .font(.screenTitle)
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, 24)
            Text("Pay once. Credits never expire. 1 credit = 1 creation or edit.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)

            ForEach(app.purchases.creditPacks, id: \.id) { product in
                Button {
                    Task {
                        do {
                            let token = await app.appAccountToken()
                            if try await app.purchases.purchase(product, appAccountToken: token) {
                                Haptics.success()
                                app.showToast("Credits added ✦", style: .success)
                                dismiss()
                            }
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.textPrimary)
                            Text(product.description)
                                .font(.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        Spacer()
                        Text(product.displayPrice)
                            .font(.headline)
                            .foregroundStyle(Palette.onAccent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Palette.accent, in: Capsule())
                    }
                    .padding(14)
                    .cardStyle(radius: 18)
                }
                .buttonStyle(.plain)
                .disabled(app.purchases.isPurchasing)
            }
            if app.purchases.creditPacks.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            }
            Spacer()
        }
        .padding(.horizontal, Metrics.gutter)
        .task { await app.purchases.loadProducts() }
    }
}
