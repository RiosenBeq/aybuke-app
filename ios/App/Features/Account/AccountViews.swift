import SwiftUI
import AuthenticationServices
import CryptoKit

/// Sign in with Apple, offered (never required) so Pro and credits follow
/// her to other iPhones. Asks only for an email, which she can hide.
struct AppleSignInButton: View {
    var onSignedIn: (() -> Void)?

    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    @State private var nonce = AppleSignInNonce.make()
    @State private var isWorking = false

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            nonce = AppleSignInNonce.make()
            request.requestedScopes = [.email]
            request.nonce = AppleSignInNonce.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                let nonce = nonce
                isWorking = true
                Task {
                    await app.signInWithApple(credential, nonce: nonce)
                    isWorking = false
                    if app.isSignedIn { onSignedIn?() }
                }
            case .failure(let error):
                if (error as? ASAuthorizationError)?.code == .canceled { return }
                app.showToast("Couldn't sign in with Apple. Please try again.", style: .error)
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 52)
        .clipShape(Capsule())
        .overlay {
            if isWorking {
                ProgressView().tint(colorScheme == .dark ? Palette.ink : Palette.white)
            }
        }
        .disabled(!app.canUseAccounts || isWorking)
        .opacity(app.canUseAccounts ? 1 : 0.45)
    }
}

/// "Keep your glow on every iPhone", shown after a purchase or from the
/// paywall's "Sign in". "Not now" is as easy to tap as signing in.
struct AccountPromptSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: Platform.isMac ? "macbook.and.iphone" : "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 72, height: 72)
                .background(Palette.blush, in: Circle())
                .padding(.top, 28)

            VStack(spacing: 8) {
                Text(styled: Platform.isMac ? "Keep your glow on *every device*" : "Keep your glow on *every iPhone*", size: 26)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.textPrimary)
                Text(Platform.isMac
                     ? "Sign in with Apple and Pro and your credits come with you when you switch or add a device."
                     : "Sign in with Apple and Pro and your credits come with you when you switch or add a phone.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.textSecondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                AccountPoint(symbol: "crown.fill", text: Platform.isMac ? "Pro on all your devices" : "Pro on all your iPhones")
                AccountPoint(symbol: "bolt.fill", text: Platform.isMac ? "Credits never get stuck on an old device" : "Credits never get stuck on an old phone")
                AccountPoint(symbol: "eye.slash.fill", text: "Hide your email if you like")
                AccountPoint(symbol: "photo.on.rectangle", text: Platform.isMac ? "Your photos stay on this Mac" : "Your photos stay on this iPhone")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .cardStyle()

            VStack(spacing: 10) {
                AppleSignInButton { dismiss() }
                Button("Not now") { dismiss() }
                    .buttonStyle(.secondary)
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 16)
        .background(AuroraBackground(intensity: 0.4).ignoresSafeArea())
        .presentationDetents([.large])
    }
}

private struct AccountPoint: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        Label {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Palette.accent)
        }
    }
}

/// The nonce Apple signs into the identity token; the server checks it.
enum AppleSignInNonce {
    static func make(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        if SecRandomCopyBytes(kSecRandomDefault, length, &bytes) != errSecSuccess {
            return UUID().uuidString + UUID().uuidString
        }
        return String(bytes.map { characters[Int($0) % characters.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
