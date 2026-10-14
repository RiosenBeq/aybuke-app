import SwiftUI
import AppCore

/// "Your credits": what the balance means, when free credits come back, what
/// uses a credit and what never does. Opened from the credit pill on Explore
/// and the balance under Create's Generate button, so tapping a number
/// explains it instead of opening a paywall. Buying stays one calm step away.
struct CreditsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showsPacks = false

    private var isPro: Bool { app.purchases.isPro }
    private var policy: CreditPolicy { app.credits.policy }
    private var balance: Int { app.credits.balance }

    /// Some of today's free credits are used. Only the local wallet knows
    /// the daily part; with the server's total, a short balance says so.
    private var awaitsFreeRefill: Bool {
        if let daily = app.credits.breakdown?.daily { return daily < policy.freeDailyAllowance }
        return balance < policy.freeDailyAllowance
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: isPro ? "crown.fill" : "bolt.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 48, height: 48)
                        .background(Palette.blush, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(styled: "Your *credits*", size: 25)
                            .foregroundStyle(Palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("\(balance) credits left")
                            .font(.display(22, weight: .bold, relativeTo: .title2))
                            .foregroundStyle(Palette.textPrimary)
                            .contentTransition(.numericText(value: Double(balance)))
                            .animation(Motion.bouncy, value: balance)
                        refillLine
                    }
                    rules
                    // Never under 13 (no credits there either); teens and
                    // adults get one quiet way to more, never a pick made for them.
                    if app.allowsPurchases {
                        Button(action: getMore) {
                            Text("Get more credits")
                        }
                        .buttonStyle(.secondaryFull)
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 28)
                .padding(.bottom, 24)
                .readableWidth(Metrics.compactWidth)
            }
            .scrollBounceBehavior(.basedOnSize)

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
            // The day may have turned since the pill last counted.
            app.credits.refresh(isPro: isPro)
            await app.refreshServerBalance()
        }
        .sheet(isPresented: $showsPacks) {
            CreditPacksView()
                .environment(app)
                .presentationDetents([.medium, .large])
                .presentationBackground(Palette.background)
        }
    }

    /// When credits come back. Free: only once some are used, since a full
    /// day's credits have nothing to wait for. Pro: the next monthly grant,
    /// when the app knows it (the server's month can start elsewhere).
    @ViewBuilder
    private var refillLine: some View {
        Group {
            if isPro {
                if let date = app.credits.nextSubscriptionGrant {
                    Label("Next refill: \(date.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
                }
            } else if awaitsFreeRefill {
                Label {
                    Text("Free credits are back in \(Text(app.credits.nextFreeRefill, style: .relative))")
                } icon: {
                    Image(systemName: "clock")
                }
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Palette.textSecondary)
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                if isPro {
                    Text("Pro gives you \(policy.proMonthlyAllowance) credits every month. Free tools never use credits, and failed edits are always refunded.")
                } else {
                    Text("You get \(policy.freeDailyAllowance) free credits every day. Free tools never use credits, and failed edits are always refunded.")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Palette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            rule("bolt.fill", "AI tools use 1 credit per picture: Magic Edit, looks, Enhance, Erase and Create.")
            rule("gift.fill", "Always free: effects, Retro Cam, Cut out, Adjust, Crop, Hide faces, Text & Stickers, collages and videos.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func rule(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // A fixed circle can't hold an accessibility-size symbol.
            if !typeSize.isAccessibilitySize {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 26, height: 26)
                    .background(Palette.blush, in: Circle())
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Pro members get the packs; everyone else the plans (with the packs
    /// one link below), opened once this sheet is gone.
    private func getMore() {
        Haptics.tap()
        if isPro {
            showsPacks = true
            return
        }
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            app.presentPaywall(source: "credits")
        }
    }
}
