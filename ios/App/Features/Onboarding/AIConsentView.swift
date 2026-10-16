import SwiftUI

/// Explicit permission before any photo or prompt leaves the device for
/// third-party AI processing (App Store Review Guideline 5.1.2(i), GDPR).
/// "Allow" and "Not now" carry the same weight: no nudge either way.
struct AIConsentView: View {
    /// Everyone who processes what she sends. The list says what each one
    /// is; the companies are named in one small line under it (Apple asks
    /// for them before anything is shared), never in the headline copy.
    let processors: [AIProcessor]
    /// "an hour", "24 hours"…
    let retention: String
    /// Her age range asks for a parent or guardian to read this with her.
    var asksGuardian = false
    /// Called with her answer to "A parent or guardian said yes".
    let onAccept: (_ guardianConfirmed: Bool) -> Void
    let onDecline: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var legalDocument: LegalDocument?
    @State private var guardianSaidYes = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !typeSize.isAccessibilitySize {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 68, height: 68)
                        .background(Palette.blush, in: Circle())
                        .floating(distance: 3)
                        .accessibilityHidden(true)
                }

                Text(styled: "Your photos, *your call*", size: 25)
                    .foregroundStyle(Palette.textPrimary)

                // Writing help (ideas, prompts, captions, makeup picks) sends text too.
                Text("To create and edit images with AI and to help you write prompts and captions, we send the photo and text you choose to our servers and to the third-party AI providers listed below, who process them for us.")
                    .font(.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 14) {
                    ConsentPoint(symbol: "trash", text: "Deleted from our servers within \(retention)")
                    // Anthropic's API terms: deleted within 30 days, longer
                    // only for content its systems flag (privacy policy §14).
                    if processors.contains(where: { $0.role.checksSafety }) {
                        ConsentPoint(symbol: "checkmark.shield",
                                     text: "Deleted by our safety-check provider within 30 days, unless flagged for breaking its rules")
                    }
                    ConsentPoint(symbol: "brain", text: "Never used to train AI models")
                    ConsentPoint(symbol: "eye.slash", text: "Never sold or shared for advertising")
                    ConsentPoint(symbol: Platform.isMac ? "laptopcomputer" : "lock.shield",
                                 text: "Effects, Adjust, Cut out and video editing always stay on this device")
                }

                processorList

                Button("Read our Privacy Policy") {
                    legalDocument = .privacy
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.accent)
                .underline()

                if asksGuardian {
                    guardianStep
                }

                // At accessibility sizes nothing is pinned: two wrapped
                // buttons and the caption would cover the sheet.
                if typeSize.isAccessibilitySize {
                    choices
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            if !typeSize.isAccessibilitySize {
                choices
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(Palette.background)
            }
        }
        .legalSheet($legalDocument)
    }

    private var choices: some View {
        VStack(spacing: 10) {
            Button("Allow AI processing") { onAccept(asksGuardian && guardianSaidYes) }
                .buttonStyle(.primary)
                .disabled(asksGuardian && !guardianSaidYes)
            Button("Not now", action: onDecline)
                .buttonStyle(.secondaryFull)
            Text("You can change this anytime in Settings.")
                .font(.legibleCaption)
                .foregroundStyle(Palette.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    /// What each one does; Create sends text only, so not "your photo".
    /// The companies come last, in one small line.
    private var processorList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Who processes what you send")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
            ForEach(processors, id: \.self) { processor in
                VStack(alignment: .leading, spacing: 2) {
                    Text(processor.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(processor.roleText)
                        .font(.legibleCaption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            // Reviewers look for the providers by name: readable, on one line where it fits.
            Text(verbatim: AIProcessor.providersLine(processors))
                .font(.legibleFootnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .card)
    }
}

extension AIConsentView {
    /// Not a verification: we can't check it, and the copy doesn't pretend to.
    private var guardianStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ask a parent or guardian to read this with you", systemImage: "person.2.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: $guardianSaidYes) {
                Text("A parent or guardian said yes")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textPrimary)
            }
            .tint(Palette.accent)
        }
        .padding(14)
        .background(Palette.surface, in: .card)
    }
}

private struct ConsentPoint: View {
    let symbol: String
    let text: LocalizedStringKey
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 12) {
            // A fixed circle can't hold an accessibility-size symbol.
            if !typeSize.isAccessibilitySize {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 32, height: 32)
                    .background(Palette.blush, in: Circle())
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
