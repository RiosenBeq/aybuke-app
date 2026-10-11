import SwiftUI

/// Explicit permission before any photo or prompt leaves the device for
/// third-party AI processing (App Store Review Guideline 5.1.2(i), GDPR).
struct AIConsentView: View {
    let providerName: String
    let retentionHours: Int
    let onAccept: () -> Void
    let onDecline: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Capsule()
                .fill(Palette.strokeStrong)
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(Palette.brandGradient)

            Text("Your photos, your call")
                .font(.screenTitle)
                .foregroundStyle(Palette.textPrimary)

            Text("To create and edit images with AI, we send the photo and text you choose to our servers and to \(providerName), who process them on our behalf.")
                .font(.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                ConsentPoint(symbol: "trash", text: "Deleted from our servers within \(retentionHours) hours")
                ConsentPoint(symbol: "brain", text: "Never used to train AI models")
                ConsentPoint(symbol: "eye.slash", text: "Never sold or shared for advertising")
                ConsentPoint(symbol: "iphone", text: "Background removal always stays on your iPhone")
            }

            Button("Read our Privacy Policy") {
                openURL(app.config.privacyPolicyURL)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.primary)

            Spacer(minLength: 0)

            Button("Allow AI processing", action: onAccept)
                .buttonStyle(.primary)
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
    }
}

private struct ConsentPoint: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.primary)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Palette.textPrimary)
        }
    }
}
