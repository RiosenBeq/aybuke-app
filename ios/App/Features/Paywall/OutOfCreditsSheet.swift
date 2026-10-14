import SwiftUI

/// A Pro member tried an AI action without enough credits.
struct OutOfCreditsRequest: Identifiable {
    let id = UUID()
    /// What the action costs, when known (the server's 402 doesn't say).
    var needed: Int?
    var available: Int?
}

/// Pro only (free members get the paywall, with its "remind me" option):
/// when the monthly credits come back, the packs, and what stays free.
/// Shown only after she tries an AI action, never on its own.
struct OutOfCreditsSheet: View {
    let request: OutOfCreditsRequest

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    /// "This needs 4 credits. You have 2." (several images in Create).
    private var shortfall: (needed: Int, available: Int)? {
        guard let needed = request.needed, let available = request.available, available > 0, needed > available else { return nil }
        return (needed, available)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "bolt.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 48, height: 48)
                        .background(Palette.blush, in: Circle())
                    if let shortfall {
                        Text(styled: "Not quite *enough*", size: 28)
                            .foregroundStyle(Palette.textPrimary)
                        Text("This needs \(shortfall.needed) credits. You have \(shortfall.available). Choose fewer images, or add a credit pack.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                    } else {
                        Text(styled: "You've used this month's *credits*", size: 28)
                            .foregroundStyle(Palette.textPrimary)
                    }
                    refillLine
                    CreditPackList { dismiss() }
                    Label("Free tools still work: 80s & 90s effects, Cut out, Adjust and the video editor.", systemImage: "wand.and.stars")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 28)
                .padding(.bottom, 24)
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
    }

    /// Monthly credits are granted from when Pro started, not on the billing
    /// date (yearly plans bill once a year), so name a date only when known.
    @ViewBuilder
    private var refillLine: some View {
        Group {
            if let date = app.credits.nextSubscriptionGrant {
                Label("Next refill: \(date.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
            } else {
                Label("Your monthly credits come back within a month.", systemImage: "calendar")
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Palette.textPrimary)
    }
}
