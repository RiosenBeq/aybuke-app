import SwiftUI

/// Ink tag with blush lettering; flips to blush-on-ink over dark artwork.
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
        .background(onDark ? Palette.blush : Palette.ink, in: .tag)
        .accessibilityLabel("Pro")
    }
}

/// A card title with the NEW badge after it; when they don't fit on one
/// line (large text, long translations), the badge goes under the title
/// instead of squeezing it into a mid-word break.
struct TitleWithNewBadge: View {
    let title: LocalizedStringKey

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                text.lineLimit(1)
                NewBadge()
            }
            VStack(alignment: .leading, spacing: 4) {
                text
                NewBadge()
            }
        }
    }

    private var text: some View {
        Text(title)
            .font(.cardTitle)
            .foregroundStyle(Palette.textPrimary)
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
            .background(onDark ? Palette.white : Palette.ink, in: .tag)
    }
}

/// Shows remaining credits, with a crown for Pro (a balance, never "unlimited").
struct CreditPill: View {
    let balance: Int
    let isPro: Bool
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isPro ? "crown.fill" : "bolt.fill")
                    .symbolEffect(.bounce, value: balance)
                Text("\(balance)")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(balance)))
            }
            .animation(Motion.bouncy, value: balance)
            .foregroundStyle(Palette.onAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Palette.accent, in: .pill)
            // The pill stays small; the touch target doesn't.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(balance) credits left")
        .accessibilityValue(isPro ? Text("\(Brand.name) Pro") : Text(verbatim: ""))
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.sectionTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.legibleFootnote).foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .padding(.leading, 8)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.accent)
            }
        }
    }
}
