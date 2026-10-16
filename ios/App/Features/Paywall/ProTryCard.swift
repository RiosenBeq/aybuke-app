#if !targetEnvironment(macCatalyst)
import SwiftUI
import AppCore

/// "Try this look once · watch a short ad": on the paywall that a Pro look or
/// style opened, the optional way to try it once, a day, for free members 13+
/// on iPhone and iPad (`AdCoordinator.offersProTry` decides). The try's job
/// costs a credit like any look, so without one the card says so, with the
/// ways to get one. Once the server has the try, the paywall closes and the
/// look or style starts (`AppModel.startProTry`). Not in the Mac app, which
/// has no ads.
struct ProTryCard: View {
    let item: ProTryItem

    @Environment(AppModel.self) private var app

    private var ads: AdCoordinator { app.ads }
    private var offer: ProTryOffer { ads.proTryOffer(for: item) }
    private var phase: AdCoordinator.TryPhase { ads.tryPhase(for: item) }
    private var cost: Int { app.credits.cost(of: item.operation) }

    private var isLook: Bool {
        if case .template = item { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: tap) {
                HStack(spacing: 12) {
                    leading
                        .frame(width: 32, height: 32)
                        .background(Palette.blush, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        title
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.textPrimary)
                        subtitle
                            .font(.legibleCaption)
                            .foregroundStyle(isNotice ? Palette.warning : Palette.textSecondary)
                        if offer == .needsCredit, phase == .idle {
                            Text("Free credits are back in \(Text(app.credits.nextFreeRefill, style: .relative))")
                                .font(.legibleCaption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if isTappable {
                        Image(systemName: "chevron.right")
                            .font(.legibleFootnote.weight(.semibold))
                            .foregroundStyle(Palette.textTertiary)
                            .accessibilityHidden(true)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isTappable)
            .cardStyle()
            .accessibilityElement(children: .combine)
            .accessibilityHint(hint)
            if showsAdNote {
                // What the try costs and where the ad comes from, before she taps.
                Text("Optional. Your try uses \(cost) credit. Ads come from Google and are never personalized.")
                    .font(.legibleCaption2)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Out of credits: the credit ad, if she likes (packs are further down).
            if offer == .needsCredit, phase == .idle, ads.offersRewardedAd {
                RewardedAdCard {
                    Task { await ads.refreshProTryOverview(force: true) }
                }
            }
        }
        // A credit from a pack, the credit ad or the new day changes what she can do.
        .onChange(of: app.credits.balance) { old, new in
            if old < cost, new >= cost { Task { await ads.refreshProTryOverview(force: true) } }
        }
        .animation(.snappy, value: phase)
        .animation(.snappy, value: offer)
    }

    private func tap() {
        Haptics.tap()
        Task { await ads.tapProTry(item) }
    }

    private var isTappable: Bool {
        switch phase {
        case .loading, .pending, .granted, .notice(.unavailable): return false
        case .notice: return offer.isAvailable || offer.isReady
        case .idle: return offer.isAvailable || offer.isReady
        }
    }

    private var isNotice: Bool {
        if case .notice = phase { return true }
        return false
    }

    /// The ad's terms belong next to the button that plays it.
    private var showsAdNote: Bool {
        switch phase {
        case .loading, .pending, .notice: return true
        case .granted: return false
        case .idle: return offer.isAvailable
        }
    }

    @ViewBuilder
    private var leading: some View {
        switch (phase, offer) {
        case (.loading, _), (.pending, _):
            ProgressView()
                .controlSize(.small)
                .tint(Palette.ink)
        case (.granted, _), (.idle, .ready):
            symbol("sparkles")
        case (.idle, .capped):
            symbol("moon.stars.fill")
        case (.idle, .needsCredit):
            symbol("bolt.fill")
        default:
            symbol("play.fill")
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.legibleFootnote.weight(.semibold))
            .foregroundStyle(Palette.ink)
    }

    private var offerTitle: Text {
        isLook ? Text("Try this look once · watch a short ad") : Text("Try this style once · watch a short ad")
    }

    private var title: Text {
        switch phase {
        case .loading: return Text("Getting your ad…")
        case .pending: return Text("Your try is on its way")
        case .granted: return Text("Your try is ready")
        case .notice: return offerTitle
        case .idle:
            switch offer {
            case .ready: return Text("Your try is ready")
            case .capped: return Text("You've had today's Pro try")
            case .needsCredit: return Text("You need a credit to try it")
            case .available, .none: return offerTitle
            }
        }
    }

    private var subtitle: Text {
        switch phase {
        case .loading:
            return remainingText
        case .pending:
            return Text("Google confirms the ad, then it starts. It usually takes a few seconds.")
        case .granted:
            return Text("Starting it now…")
        case .notice(.offline):
            return Text("You're offline. Connect to watch an ad.")
        case .notice(.noFill):
            return Text("No ads right now. Try again in a little while.")
        case .notice(.consent):
            return Text("Your ad privacy choice didn't load. Try again.")
        case .notice(.closedEarly):
            return Text("The ad closed early, so no try this time.")
        case .notice(.delayed):
            return Text("Still on its way. Tap to check again.")
        case .notice(.failed):
            return Text("Couldn't show the ad. Please try again.")
        case .notice(.unavailable):
            return Text("Trying it with an ad isn't available right now.")
        case .idle:
            switch offer {
            case .ready(let expiresAt):
                return Text("Tap to start it. It ends at \(Text(expiresAt, style: .time)).")
            case .capped:
                return Text("There's another one tomorrow.")
            case .needsCredit:
                return isLook ? Text("Trying it uses \(cost) credit, like any look.")
                    : Text("Trying it uses \(cost) credit, like any creation.")
            case .available, .none:
                return remainingText
            }
        }
    }

    private var remainingText: Text {
        if case .available(let remaining) = offer {
            return Text("\(remaining) try left today")
        }
        return Text(verbatim: "")
    }

    private var hint: Text {
        guard isTappable else { return Text(verbatim: "") }
        if offer.isReady, phase == .idle { return Text("Starts your try.") }
        if case .notice(.delayed) = phase { return Text("Checks whether Google has confirmed the ad.") }
        return Text("Plays a short video ad. When it ends, your try starts.")
    }
}

private extension ProTryOffer {
    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}
#endif
