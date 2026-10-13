import SwiftUI

/// Ink capsule with blush lettering; flips to blush-on-ink over dark artwork.
struct ProBadge: View {
    var onDark = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "crown.fill").font(.system(size: 9, weight: .bold))
            Text("PRO").font(.system(size: 10, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(onDark ? Palette.ink : Palette.blush)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(onDark ? Palette.blush : Palette.ink, in: Capsule())
        .accessibilityLabel("Pro")
    }
}

struct NewBadge: View {
    var onDark = false

    var body: some View {
        Text("NEW")
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(onDark ? Palette.ink : Palette.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(onDark ? Palette.white : Palette.ink, in: Capsule())
    }
}

/// Shows remaining credits (or Pro status); tapping opens the paywall.
struct CreditPill: View {
    let balance: Int
    let isPro: Bool
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isPro ? "crown.fill" : "bolt.fill")
                    .symbolEffect(.bounce, value: balance)
                Text(isPro ? "PRO" : "\(balance)")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(balance)))
            }
            .animation(Motion.bouncy, value: balance)
            .foregroundStyle(Palette.onAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Palette.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPro ? "Pro member" : "\(balance) credits left")
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.sectionTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.accent)
            }
        }
    }
}
