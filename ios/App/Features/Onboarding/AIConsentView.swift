import SwiftUI

/// Explicit permission before any photo or prompt leaves the device for
/// third-party AI processing (App Store Review Guideline 5.1.2(i), GDPR).
struct AIConsentView: View {
    let providerName: String
    /// "an hour", "24 hours"…
    let retention: String
    /// Her age range asks for a parent or guardian to read this with her.
    var asksGuardian = false
    /// Called with her answer to "A parent or guardian said yes".
    let onAccept: (_ guardianConfirmed: Bool) -> Void
    let onDecline: () -> Void

    @State private var legalDocument: LegalDocument?
    @State private var guardianSaidYes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Capsule()
                .fill(Palette.strokeStrong)
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 68, height: 68)
                .background(Palette.blush, in: Circle())
                .floating(distance: 3)

            Text(styled: "Your photos, *your call*", size: 28)
                .foregroundStyle(Palette.textPrimary)

            Text("To create and edit images with AI, we send the photo and text you choose to our servers and to \(providerName), who process them on our behalf.")
                .font(.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                ConsentPoint(symbol: "trash", text: "Deleted from our servers within \(retention)")
                ConsentPoint(symbol: "brain", text: "Never used to train AI models")
                ConsentPoint(symbol: "eye.slash", text: "Never sold or shared for advertising")
                ConsentPoint(symbol: Platform.isMac ? "laptopcomputer" : "lock.shield", text: "Background removal always stays on your device")
            }

            Button("Read our Privacy Policy") {
                legalDocument = .privacy
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.accent)
            .underline()

            if asksGuardian {
                guardianStep
            }

            Spacer(minLength: 0)

            Button("Allow AI processing") { onAccept(asksGuardian && guardianSaidYes) }
                .buttonStyle(.primary)
                .disabled(asksGuardian && !guardianSaidYes)
            Button("Not now", action: onDecline)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity)
            Text("You can change this anytime in Settings.")
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .legalSheet($legalDocument)
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
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ConsentPoint: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 32, height: 32)
                .background(Palette.blush, in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
