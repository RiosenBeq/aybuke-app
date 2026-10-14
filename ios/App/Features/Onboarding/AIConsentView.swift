import SwiftUI

/// Explicit permission before any photo or prompt leaves the device for
/// third-party AI processing (App Store Review Guideline 5.1.2(i), GDPR).
struct AIConsentView: View {
    let providerName: String
    /// "an hour", "24 hours"…
    let retention: String
    let onAccept: () -> Void
    let onDecline: () -> Void

    @State private var legalDocument: LegalDocument?

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

            Spacer(minLength: 0)

            Button("Allow AI processing", action: onAccept)
                .buttonStyle(.primary)
            Button("Not now", action: onDecline)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity)
            Text("Under 16? Check with a parent or guardian first. You can change this anytime in Settings.")
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .legalSheet($legalDocument)
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
