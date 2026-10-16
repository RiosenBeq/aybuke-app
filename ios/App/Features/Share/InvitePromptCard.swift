import SwiftUI

/// "Loving Aybuke? Invite a friend": a small card that may follow a finished
/// save or share at a natural break (`InviteCardPacing`, decided in
/// `AppModel.noteFinishedExport`), above the tab bar. It opens the invite
/// (Glow together), goes away by itself after a while, and "Don't show again"
/// stops it for good. Brand art only: her photos are never in the invite.
struct InvitePromptCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "heart.circle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    LinearGradient(colors: [Palette.auraMint, Palette.auraLilac, Palette.auraPink, Palette.auraPeach],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .control
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Loving \(Brand.name)?")
                        .font(.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Invite a bestie to glow with you.")
                        .font(.legibleFootnote)
                        .foregroundStyle(Palette.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                // Side by side when they fit; stacked for long translations and large text.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        inviteButton(oneLine: true)
                        dontShowButton(oneLine: true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        inviteButton(oneLine: false)
                        dontShowButton(oneLine: false)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            closeButton
        }
        .padding(.leading, 14)
        .padding(.vertical, 14)
        .padding(.trailing, 6)
        .cardStyle()
        .shadow(color: Palette.ink.opacity(0.08), radius: 20, y: 10)
        .padding(.horizontal, Metrics.gutter)
        .readableWidth(Metrics.compactWidth, alignment: .center)
        .task {
            #if DEBUG
            if ScreenshotScene.current != nil { return }
            #endif
            // Not a nag: it leaves by itself if she carries on.
            try? await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning ? 30 : 14))
            if !Task.isCancelled { app.dismissInviteCard(forGood: false) }
        }
    }

    /// `oneLine`: side by side, each label keeps to one line (so the row is
    /// only used where both fit); stacked, they may wrap.
    private func inviteButton(oneLine: Bool) -> some View {
        Button {
            Haptics.tap()
            app.openInviteFromCard()
        } label: {
            Text("Invite a friend")
                .fixedSize(horizontal: oneLine, vertical: false)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Palette.onAccent)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(Palette.accent, in: .pill)
        }
        .buttonStyle(.pressable)
    }

    private func dontShowButton(oneLine: Bool) -> some View {
        Button {
            app.dismissInviteCard(forGood: true)
        } label: {
            Text("Don't show again")
                .fixedSize(horizontal: oneLine, vertical: false)
                .font(.legibleFootnote.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(minHeight: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    private var closeButton: some View {
        Button {
            app.dismissInviteCard(forGood: false)
        } label: {
            Image(systemName: "xmark")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 28, height: 28)
                .background(Palette.surfaceRaised, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Close")
        .padding(.top, -8)
    }
}

/// Where the invite card shows: at the bottom of a section, above the tab bar
/// (each tab, and the Mac's sections, carry the slot; one shows at a time).
private struct InviteCardSlot: ViewModifier {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if app.isInviteCardVisible {
                InvitePromptCard()
                    .padding(.bottom, 12)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

extension View {
    func inviteCardSlot() -> some View { modifier(InviteCardSlot()) }
}
