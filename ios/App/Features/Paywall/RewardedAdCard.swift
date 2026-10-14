import SwiftUI
import AppCore

/// "Watch a short ad · +1 credit": the optional way to one more credit when a
/// free member is out of credits, at most two a day. In the paywall that
/// opened because she ran out, and in the credits sheet; never for Pro, under
/// 13 or on the Mac (`AdCoordinator.offersRewardedAd` decides).
struct RewardedAdCard: View {
    /// Runs once the credit has landed, e.g. to close the sheet.
    var onCredit: () -> Void = {}

    @Environment(AppModel.self) private var app

    private var ads: AdCoordinator { app.ads }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: watch) {
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
                            .font(.caption)
                            .foregroundStyle(isNotice ? Palette.warning : Palette.textSecondary)
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if isTappable {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
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
            .accessibilityHint(isTappable ? Text("Plays a short video ad. When it ends, you get 1 credit.") : Text(verbatim: ""))
            Text("Optional. Ads come from Google and are never personalized.")
                .font(.caption2)
                .foregroundStyle(Palette.textTertiary)
                .padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { await ads.refreshRewardOverview() }
        .onChange(of: ads.rewardsLanded) { _, _ in onCredit() }
        .animation(.snappy, value: ads.rewardState)
    }

    private func watch() {
        Haptics.tap()
        Task { await ads.watchRewardedAd() }
    }

    private var isTappable: Bool {
        switch ads.rewardState {
        case .available, .notice: return true
        case .loading, .pending, .capped: return false
        }
    }

    private var isNotice: Bool {
        if case .notice = ads.rewardState { return true }
        return false
    }

    @ViewBuilder
    private var leading: some View {
        switch ads.rewardState {
        case .loading, .pending:
            ProgressView()
                .controlSize(.small)
                .tint(Palette.ink)
        case .capped:
            Image(systemName: "moon.stars.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink)
        case .available, .notice:
            Image(systemName: "play.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink)
        }
    }

    private var title: Text {
        switch ads.rewardState {
        case .available, .notice: return Text("Watch a short ad · +1 credit")
        case .loading: return Text("Getting your ad…")
        case .pending: return Text("Your credit is on its way")
        case .capped: return Text("You've watched today's ads")
        }
    }

    private var subtitle: Text {
        switch ads.rewardState {
        case .available(let remaining?):
            return Text("\(remaining) left today")
        case .available(.none), .loading:
            return Text("Up to \(ads.dailyCap) a day")
        case .pending:
            return Text("Google confirms the ad, then it's yours. It usually takes a few seconds.")
        case .capped:
            return Text("More tomorrow. Free credits are back in \(Text(app.credits.nextFreeRefill, style: .relative))")
        case .notice(.offline):
            return Text("You're offline. Connect to watch an ad.")
        case .notice(.noFill):
            return Text("No ads right now. Try again in a little while.")
        case .notice(.consent):
            return Text("Your ad privacy choice didn't load. Try again.")
        case .notice(.closedEarly):
            return Text("The ad closed early, so no credit this time.")
        case .notice(.delayed):
            return Text("Still on its way. It shows up in your balance once Google confirms the ad.")
        case .notice(.failed):
            return Text("Couldn't show the ad. Please try again.")
        }
    }
}
